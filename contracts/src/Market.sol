// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IPyth} from "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import {PythStructs} from "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";

/// @title Market - Parimutuel binary prediction market
/// @notice Each instance represents a single UP/DOWN prediction market with Pyth oracle resolution
/// @dev Deployed as minimal proxy clone via MarketFactory. Uses initializer pattern (no constructor).
contract Market is ReentrancyGuard, Pausable {
    // ─── Enums ───────────────────────────────────────────────────────────
    enum State {
        Open,      // Accepting bets
        Closed,    // Betting stopped, awaiting resolution
        Resolved,  // Winner determined, payouts available
        Cancelled  // Refunds available (resolution failed or one-sided/tie)
    }

    enum Side {
        Up,
        Down
    }

    // ─── Events ──────────────────────────────────────────────────────────
    event BetPlaced(address indexed user, Side side, uint256 amount, uint256 shares);
    event MarketResolved(Side winningSide, int64 resolutionPrice, address indexed resolver);
    event MarketCancelled(string reason);
    event Claimed(address indexed user, uint256 payout);
    event Refunded(address indexed user, uint256 amount);
    event EmergencyPaused(address indexed by);
    event EmergencyUnpaused(address indexed by);

    // ─── Constants ───────────────────────────────────────────────────────
    uint256 public constant MIN_BET = 0.001 ether;          // 0.001 BNB
    uint256 public constant PROTOCOL_FEE_BPS = 300;         // 3% of winnings (not total pool)
    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint256 public constant RESOLUTION_DEADLINE = 24 hours; // Auto-cancel if not resolved
    uint256 public constant PRICE_MAX_AGE = 60;             // Max staleness for Pyth price
    uint256 public constant MAX_MULTIPLIER = 2e18;           // 2x shares at market open
    uint256 public constant BASE_MULTIPLIER = 1e18;          // 1x shares at trading end

    // ─── Storage ─────────────────────────────────────────────────────────
    bool private _initialized;

    IPyth public pyth;
    bytes32 public priceId;
    address public factory;
    address public feeCollector;

    uint256 public startTime;
    uint256 public tradingEnd;       // When betting stops (halfway through duration)
    uint256 public expiryTime;

    int64 public strikePrice;
    int32 public strikePriceExpo;
    int64 public resolutionPrice;

    State public state;
    Side public winningSide;

    // Side => User => Amount (raw BNB deposited)
    mapping(Side => mapping(address => uint256)) public bets;
    // Side => User => Shares (time-weighted)
    mapping(Side => mapping(address => uint256)) public shares;
    // Side => Total
    mapping(Side => uint256) public totalBets;
    mapping(Side => uint256) public totalShares;
    uint256 public totalPool;

    uint256 public protocolFeeAmount;
    bool public protocolFeeClaimed;

    // ─── Modifiers ───────────────────────────────────────────────────────
    modifier onlyFactory() {
        require(msg.sender == factory, "Only factory");
        _;
    }

    modifier inState(State _state) {
        _checkAndTransitionState();
        require(state == _state, "Invalid state");
        _;
    }

    // ─── Initialization ──────────────────────────────────────────────────

    /// @notice Initialize a market clone. Called once by MarketFactory.
    /// @param _pyth Pyth oracle contract address
    /// @param _priceId Pyth price feed ID (e.g. BTC/USD)
    /// @param _duration Market duration in seconds
    /// @param _feeCollector Address to receive protocol fees
    /// @param _strikeUpdateData Pyth update data to capture strike price
    function initialize(
        address _pyth,
        bytes32 _priceId,
        uint256 _duration,
        address _feeCollector,
        bytes[] calldata _strikeUpdateData
    ) external payable {
        require(!_initialized, "Already initialized");
        _initialized = true;

        pyth = IPyth(_pyth);
        priceId = _priceId;
        factory = msg.sender;
        feeCollector = _feeCollector;
        startTime = block.timestamp;
        tradingEnd = block.timestamp + (_duration / 2); // Trading stops halfway
        expiryTime = block.timestamp + _duration;
        state = State.Open;

        // Capture strike price from Pyth
        uint256 fee = pyth.getUpdateFee(_strikeUpdateData);
        require(msg.value >= fee, "Insufficient Pyth fee");
        pyth.updatePriceFeeds{value: fee}(_strikeUpdateData);

        PythStructs.Price memory price = pyth.getPriceNoOlderThan(priceId, PRICE_MAX_AGE);
        strikePrice = price.price;
        strikePriceExpo = price.expo;

        // Refund excess ETH/BNB
        if (msg.value > fee) {
            (bool sent, ) = msg.sender.call{value: msg.value - fee}("");
            require(sent, "Refund failed");
        }
    }

    // ─── State transitions ───────────────────────────────────────────────

    /// @dev Automatically transitions state based on time
    function _checkAndTransitionState() internal {
        if (state == State.Open && block.timestamp >= tradingEnd) {
            state = State.Closed;
        }
        if (state == State.Closed && block.timestamp >= expiryTime + RESOLUTION_DEADLINE) {
            state = State.Cancelled;
            emit MarketCancelled("Resolution deadline passed");
        }
    }

    // ─── Betting ─────────────────────────────────────────────────────────

    /// @notice Place a bet on UP or DOWN
    /// @param side The side to bet on (Up or Down)
    function bet(Side side) external payable nonReentrant whenNotPaused inState(State.Open) {
        require(msg.value >= MIN_BET, "Below minimum bet");

        // Time-weighted shares: early bets get up to 2x shares, linear decay to 1x at tradingEnd
        uint256 elapsed = block.timestamp - startTime;
        uint256 window = tradingEnd - startTime;
        uint256 multiplier = MAX_MULTIPLIER - ((MAX_MULTIPLIER - BASE_MULTIPLIER) * elapsed) / window;
        uint256 betShares = (msg.value * multiplier) / BASE_MULTIPLIER;

        bets[side][msg.sender] += msg.value;
        shares[side][msg.sender] += betShares;
        totalBets[side] += msg.value;
        totalShares[side] += betShares;
        totalPool += msg.value;

        emit BetPlaced(msg.sender, side, msg.value, betShares);
    }

    // ─── Resolution ──────────────────────────────────────────────────────

    /// @notice Resolve the market using Pyth price data. Only callable by factory (keeper).
    /// @param pythUpdateData Pyth price update data from Hermes API
    function resolve(bytes[] calldata pythUpdateData) external payable onlyFactory nonReentrant whenNotPaused inState(State.Closed) {
        require(block.timestamp >= expiryTime, "Market not yet expired");

        // Update Pyth price
        uint256 fee = pyth.getUpdateFee(pythUpdateData);
        require(msg.value >= fee, "Insufficient Pyth fee");
        pyth.updatePriceFeeds{value: fee}(pythUpdateData);

        // Read validated price
        PythStructs.Price memory price = pyth.getPriceNoOlderThan(priceId, PRICE_MAX_AGE);
        resolutionPrice = price.price;

        // Handle edge cases: one-sided markets and exact ties
        bool oneSided = totalBets[Side.Up] == 0 || totalBets[Side.Down] == 0;
        bool exactTie = resolutionPrice == strikePrice;

        if (oneSided || exactTie) {
            state = State.Cancelled;
            string memory reason = exactTie ? "Exact price tie" : "One-sided market";
            emit MarketCancelled(reason);
        } else {
            // Determine winner
            if (resolutionPrice > strikePrice) {
                winningSide = Side.Up;
            } else {
                winningSide = Side.Down;
            }

            // Fee is % of the LOSING side only (the winnings), not total pool
            // Winners get their own bets back + loser pool minus fee
            Side losingSide = winningSide == Side.Up ? Side.Down : Side.Up;
            protocolFeeAmount = (totalBets[losingSide] * PROTOCOL_FEE_BPS) / BPS_DENOMINATOR;

            state = State.Resolved;
            emit MarketResolved(winningSide, resolutionPrice, msg.sender);
        }

        // Refund excess BNB
        if (msg.value > fee) {
            (bool sent, ) = msg.sender.call{value: msg.value - fee}("");
            require(sent, "Refund failed");
        }
    }

    // ─── Payouts ─────────────────────────────────────────────────────────

    /// @notice Claim winnings from a resolved market
    function claim() external nonReentrant inState(State.Resolved) {
        uint256 userShares = shares[winningSide][msg.sender];
        uint256 userBet = bets[winningSide][msg.sender];
        require(userShares > 0, "No winning bet");

        // Zero out before transfer (checks-effects-interactions)
        shares[winningSide][msg.sender] = 0;
        bets[winningSide][msg.sender] = 0;

        // Payout proportional to SHARES (not raw bet amount)
        // Total payout pool = winning side bets + losing side bets - fee
        Side losingSide = winningSide == Side.Up ? Side.Down : Side.Up;
        uint256 payoutPool = totalBets[winningSide] + totalBets[losingSide] - protocolFeeAmount;
        uint256 payout = (userShares * payoutPool) / totalShares[winningSide];

        (bool sent, ) = msg.sender.call{value: payout}("");
        require(sent, "Transfer failed");

        emit Claimed(msg.sender, payout);
    }

    /// @notice Claim refund from a cancelled market
    function refund() external nonReentrant inState(State.Cancelled) {
        uint256 upBet = bets[Side.Up][msg.sender];
        uint256 downBet = bets[Side.Down][msg.sender];
        uint256 total = upBet + downBet;
        require(total > 0, "No bets to refund");

        // Zero out before transfer
        bets[Side.Up][msg.sender] = 0;
        bets[Side.Down][msg.sender] = 0;

        (bool sent, ) = msg.sender.call{value: total}("");
        require(sent, "Transfer failed");

        emit Refunded(msg.sender, total);
    }

    /// @notice Collect protocol fees (only after resolution)
    function collectFees() external nonReentrant {
        require(state == State.Resolved, "Not resolved");
        require(!protocolFeeClaimed, "Fees already claimed");
        require(protocolFeeAmount > 0, "No fees");

        protocolFeeClaimed = true;

        (bool sent, ) = feeCollector.call{value: protocolFeeAmount}("");
        require(sent, "Fee transfer failed");
    }

    // ─── Emergency ───────────────────────────────────────────────────────

    /// @notice Emergency pause - only factory (owner) can call
    function emergencyPause() external onlyFactory {
        _pause();
        emit EmergencyPaused(msg.sender);
    }

    /// @notice Unpause - only factory (owner) can call
    function emergencyUnpause() external onlyFactory {
        _unpause();
        emit EmergencyUnpaused(msg.sender);
    }

    /// @notice Emergency cancel - force market to cancelled state for refunds
    function emergencyCancel() external onlyFactory {
        require(state != State.Resolved, "Already resolved");
        state = State.Cancelled;
        emit MarketCancelled("Emergency cancellation");
    }

    // ─── View functions ──────────────────────────────────────────────────

    /// @notice Get current market info
    function getMarketInfo()
        external
        view
        returns (
            State currentState,
            bytes32 _priceId,
            int64 _strikePrice,
            int32 _strikePriceExpo,
            uint256 _startTime,
            uint256 _tradingEnd,
            uint256 _expiryTime,
            uint256 upPool,
            uint256 downPool,
            uint256 _totalPool
        )
    {
        return (
            state,
            priceId,
            strikePrice,
            strikePriceExpo,
            startTime,
            tradingEnd,
            expiryTime,
            totalBets[Side.Up],
            totalBets[Side.Down],
            totalPool
        );
    }

    /// @notice Calculate estimated payout for a hypothetical bet
    /// @param side The side to bet on
    /// @param amount The bet amount
    /// @return estimatedPayout The estimated payout if this side wins
    function estimatePayout(Side side, uint256 amount) external view returns (uint256 estimatedPayout) {
        uint256 otherPool = totalBets[side == Side.Up ? Side.Down : Side.Up];
        uint256 elapsed = block.timestamp >= tradingEnd ? tradingEnd - startTime : block.timestamp - startTime;
        uint256 mult = MAX_MULTIPLIER - ((MAX_MULTIPLIER - BASE_MULTIPLIER) * elapsed) / (tradingEnd - startTime);
        uint256 betShares = (amount * mult) / BASE_MULTIPLIER;
        uint256 newShares = totalShares[side] + betShares;
        uint256 fee = (otherPool * PROTOCOL_FEE_BPS) / BPS_DENOMINATOR;
        estimatedPayout = (betShares * (totalBets[side] + amount + otherPool - fee)) / newShares;
    }

    /// @notice Get a user's bets
    function getUserBets(address user) external view returns (uint256 upBet, uint256 downBet, uint256 upShares, uint256 downShares) {
        return (bets[Side.Up][user], bets[Side.Down][user], shares[Side.Up][user], shares[Side.Down][user]);
    }

    /// @notice Check effective market state (accounts for time-based transitions)
    function getCurrentState() external view returns (State) {
        State s = state;
        if (s == State.Open && block.timestamp >= tradingEnd) {
            s = State.Closed;
        }
        if (s == State.Closed && block.timestamp >= expiryTime + RESOLUTION_DEADLINE) {
            s = State.Cancelled;
        }
        return s;
    }

    // Allow contract to receive BNB (for Pyth fee refunds)
    receive() external payable {}
}
