// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./IUSDTCreditReserve.sol";
import "./IWorldCupResolver.sol";
import "./WorldCupWinnerTypes.sol";

/// @title WorldCupWinnerMarket
/// @notice Bespoke 42-outcome USDT/credit parimutuel market for named World Cup teams.
contract WorldCupWinnerMarket is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct BuyQuote {
        uint256 feeAmount;
        uint256 principalAdded;
        uint256 rewardSharesOut;
    }

    struct ClaimAmounts {
        uint256 realPayout;
        uint256 creditPayout;
        uint256 winningCreditPrincipal;
        uint256 unsettledLosingCreditPrincipal;
    }

    struct RefundAmounts {
        uint256 realRefund;
        uint256 creditRefund;
    }

    struct SettlementSnapshot {
        bool initialized;
        uint256 totalWinningRewardShares;
    }

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    uint8 public constant OUTCOME_COUNT = 42;
    uint8 public constant FLAP_OTHER_INDEX = 42;
    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint256 public constant MIN_BUY_AMOUNT_IN = 0.01e18;

    IERC20 public immutable usdt;
    IUSDTCreditReserve public immutable creditReserve;
    IWorldCupResolver public worldCupResolver;
    uint256 public immutable creditEventId;

    address public feeRecipient;
    uint16 public feeBps;
    uint256 public accruedRealFees;
    uint256 public totalPrincipal;
    WorldCupWinnerMarketState public state;
    WorldCupRound public currentRound;
    uint8 public winningOutcomeId;
    bool public hasWinner;

    mapping(WorldCupRound => uint16) public roundMultiplierBps;
    mapping(uint8 => WorldCupOutcomePool) internal _outcomePools;
    mapping(address => mapping(uint8 => WorldCupPosition)) internal _realPositions;
    mapping(address => mapping(uint8 => WorldCupPosition)) internal _creditPositions;
    mapping(address => bool) public losingCreditSettled;
    SettlementSnapshot internal _settlementSnapshot;

    event ResolverUpdated(address indexed resolver);
    event FeeRecipientUpdated(address indexed feeRecipient);
    event FeesWithdrawn(address indexed recipient, uint256 amount);
    event RoundMultiplierUpdated(WorldCupRound indexed round, uint16 multiplierBps);
    event WorldCupRoundUpdated(WorldCupRound indexed oldRound, WorldCupRound indexed newRound, uint16 multiplierBps);
    event BettingClosed();
    event BoughtWithUsdt(
        address indexed user,
        uint8 indexed outcomeId,
        uint256 amountIn,
        uint256 feeAmount,
        uint256 principalAdded,
        uint256 rewardSharesOut
    );
    event BoughtWithCredit(
        address indexed user,
        uint8 indexed outcomeId,
        uint256 creditAmount,
        uint256 feeAmount,
        uint256 principalAdded,
        uint256 rewardSharesOut
    );
    event LosingCreditSettled(address indexed user, uint256 consumedCredit);
    event WorldCupResolved(uint8 indexed winningOutcomeId, bool adminFallback, string reason);
    event WorldCupInvalidated(string reason);
    event Claimed(address indexed user, uint256 realPayout, uint256 creditPayout);
    event Refunded(address indexed user, uint256 realRefund, uint256 creditRefund);

    error ZeroAddress();
    error ZeroAmount();
    error BelowMinimumBuy();
    error MarketNotOpen();
    error MarketNotClosed();
    error MarketNotResolved();
    error MarketNotRefundable();
    error InvalidOutcome();
    error EliminatedOutcome();
    error FlaggedOutcome();
    error Slippage();
    error TransferShortfall();
    error CreditFeesUnsupported();
    error NoClearWinner();
    error OtherWinner();
    error AlreadySettled();
    error NothingToClaim();
    error NothingToRefund();
    error EmptyOutcomes();
    error DuplicateOutcome();
    error InvalidRoundTransition();

    constructor(
        address admin,
        address usdt_,
        address creditReserve_,
        address worldCupResolver_,
        uint256 creditEventId_,
        address feeRecipient_,
        uint16 feeBps_
    ) {
        if (
            admin == address(0) || usdt_ == address(0) || creditReserve_ == address(0)
                || worldCupResolver_ == address(0) || feeRecipient_ == address(0)
        ) revert ZeroAddress();
        if (feeBps_ > BPS_DENOMINATOR) revert ZeroAmount();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);

        usdt = IERC20(usdt_);
        creditReserve = IUSDTCreditReserve(creditReserve_);
        worldCupResolver = IWorldCupResolver(worldCupResolver_);
        creditEventId = creditEventId_;
        feeRecipient = feeRecipient_;
        feeBps = feeBps_;
        state = WorldCupWinnerMarketState.Open;

        roundMultiplierBps[WorldCupRound.PreTournament] = 40_000;
        roundMultiplierBps[WorldCupRound.EarlyGroupStage] = 25_000;
        roundMultiplierBps[WorldCupRound.LateGroupStage] = 16_000;
        roundMultiplierBps[WorldCupRound.RoundOf32] = 10_000;
        roundMultiplierBps[WorldCupRound.RoundOf16] = 7_000;
        roundMultiplierBps[WorldCupRound.QuarterFinal] = 4_500;
        roundMultiplierBps[WorldCupRound.SemiFinal] = 3_000;
        roundMultiplierBps[WorldCupRound.FinalBuildUp] = 2_000;
    }

    function setResolver(address resolver) external onlyRole(ADMIN_ROLE) {
        if (resolver == address(0)) revert ZeroAddress();
        worldCupResolver = IWorldCupResolver(resolver);
        emit ResolverUpdated(resolver);
    }

    function setFeeRecipient(address feeRecipient_) external onlyRole(ADMIN_ROLE) {
        if (feeRecipient_ == address(0)) revert ZeroAddress();
        feeRecipient = feeRecipient_;
        emit FeeRecipientUpdated(feeRecipient_);
    }

    function setRoundMultiplier(WorldCupRound round, uint16 multiplierBps) external onlyRole(ADMIN_ROLE) {
        if (multiplierBps == 0) revert ZeroAmount();
        roundMultiplierBps[round] = multiplierBps;
        emit RoundMultiplierUpdated(round, multiplierBps);
    }

    function setRound(WorldCupRound newRound) external onlyRole(ADMIN_ROLE) {
        WorldCupRound oldRound = currentRound;
        if (uint8(newRound) < uint8(oldRound)) revert InvalidRoundTransition();
        currentRound = newRound;
        emit WorldCupRoundUpdated(oldRound, newRound, roundMultiplierBps[newRound]);
    }

    function closeBetting() external onlyRole(ADMIN_ROLE) {
        if (state != WorldCupWinnerMarketState.Open) revert MarketNotOpen();
        state = WorldCupWinnerMarketState.Closed;
        emit BettingClosed();
    }

    function withdrawFees(uint256 amount) external onlyRole(ADMIN_ROLE) nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (amount > accruedRealFees) revert NothingToRefund();
        accruedRealFees -= amount;
        usdt.safeTransfer(feeRecipient, amount);
        emit FeesWithdrawn(feeRecipient, amount);
    }

    function quoteBuy(uint8 outcomeId, uint256 amountIn)
        external
        view
        returns (uint256 feeAmount, uint256 principalAdded, uint256 rewardSharesOut)
    {
        _requireOpenActiveOutcome(outcomeId);
        BuyQuote memory quote = _quoteBuy(amountIn, _outcomePools[outcomeId].principal);
        return (quote.feeAmount, quote.principalAdded, quote.rewardSharesOut);
    }

    function buyWithUsdt(uint8 outcomeId, uint256 amountIn, uint256 minRewardSharesOut)
        external
        nonReentrant
        returns (uint256 rewardSharesOut)
    {
        _requireOpenActiveOutcome(outcomeId);
        BuyQuote memory quote = _quoteBuy(amountIn, _outcomePools[outcomeId].principal);
        if (quote.rewardSharesOut < minRewardSharesOut) revert Slippage();

        uint256 balanceBefore = usdt.balanceOf(address(this));
        usdt.safeTransferFrom(msg.sender, address(this), amountIn);
        if (usdt.balanceOf(address(this)) - balanceBefore != amountIn) revert TransferShortfall();

        accruedRealFees += quote.feeAmount;
        _applyBuy(msg.sender, outcomeId, quote, false);

        emit BoughtWithUsdt(
            msg.sender, outcomeId, amountIn, quote.feeAmount, quote.principalAdded, quote.rewardSharesOut
        );
        return quote.rewardSharesOut;
    }

    function buyWithCredit(uint8 outcomeId, uint256 creditAmount, uint256 minRewardSharesOut)
        external
        nonReentrant
        returns (uint256 rewardSharesOut)
    {
        _requireOpenActiveOutcome(outcomeId);
        BuyQuote memory quote = _quoteBuy(creditAmount, _outcomePools[outcomeId].principal);
        if (quote.rewardSharesOut < minRewardSharesOut) revert Slippage();
        if (quote.feeAmount > 0) revert CreditFeesUnsupported();

        creditReserve.spendCredit(creditEventId, msg.sender, address(this), creditAmount);
        _applyBuy(msg.sender, outcomeId, quote, true);

        emit BoughtWithCredit(
            msg.sender, outcomeId, creditAmount, quote.feeAmount, quote.principalAdded, quote.rewardSharesOut
        );
        return quote.rewardSharesOut;
    }

    function resolveFromFlap() external nonReentrant {
        if (state != WorldCupWinnerMarketState.Closed) revert MarketNotClosed();

        uint8 reportedWinner;
        uint256 winnerCount;
        bool otherWon;
        for (uint8 outcomeId = 0; outcomeId <= FLAP_OTHER_INDEX; outcomeId++) {
            (bool isReported, bool result, bool isFlagged) = worldCupResolver.getOutcomeStatus(outcomeId);
            if (isReported && result) {
                if (isFlagged) revert FlaggedOutcome();
                if (outcomeId == FLAP_OTHER_INDEX) {
                    otherWon = true;
                } else {
                    reportedWinner = outcomeId;
                }
                winnerCount += 1;
            }
        }

        if (otherWon) revert OtherWinner();
        if (winnerCount != 1) revert NoClearWinner();
        _resolve(reportedWinner, false, "flap");
    }

    function adminResolve(uint8 winnerOutcomeId, string calldata reason) external onlyRole(ADMIN_ROLE) nonReentrant {
        if (winnerOutcomeId >= OUTCOME_COUNT) revert InvalidOutcome();
        if (state != WorldCupWinnerMarketState.Closed) revert MarketNotClosed();
        _resolve(winnerOutcomeId, true, reason);
    }

    function invalidate(string calldata reason) external onlyRole(ADMIN_ROLE) {
        if (state == WorldCupWinnerMarketState.Resolved) revert MarketNotRefundable();
        state = WorldCupWinnerMarketState.Invalid;
        emit WorldCupInvalidated(reason);
    }

    function previewClaim(address user) public view returns (ClaimAmounts memory amounts) {
        if (state != WorldCupWinnerMarketState.Resolved) revert MarketNotResolved();
        WorldCupOutcomePool memory winningPool = _outcomePools[winningOutcomeId];
        WorldCupPosition memory realWinningPosition = _realPositions[user][winningOutcomeId];
        WorldCupPosition memory creditWinningPosition = _creditPositions[user][winningOutcomeId];
        uint256 losingPrincipal = totalPrincipal - winningPool.principal;

        if (realWinningPosition.rewardShares > 0 && losingPrincipal > 0 && winningPool.rewardShares > 0) {
            amounts.realPayout = realWinningPosition.principal
                + Math.mulDiv(losingPrincipal, realWinningPosition.rewardShares, winningPool.rewardShares);
        } else {
            amounts.realPayout = realWinningPosition.principal;
        }

        if (creditWinningPosition.rewardShares > 0 && losingPrincipal > 0 && winningPool.rewardShares > 0) {
            amounts.creditPayout = creditWinningPosition.principal
                + Math.mulDiv(losingPrincipal, creditWinningPosition.rewardShares, winningPool.rewardShares);
        } else {
            amounts.creditPayout = creditWinningPosition.principal;
        }

        amounts.winningCreditPrincipal = creditWinningPosition.principal;
        uint256 losingCreditPrincipal = _totalCreditPrincipal(user) - creditWinningPosition.principal;
        if (!losingCreditSettled[user]) {
            amounts.unsettledLosingCreditPrincipal = losingCreditPrincipal;
        }
    }

    function settleLosingCredit(address[] calldata users) public nonReentrant {
        _settleLosingCreditInternal(users);
    }

    function claim(address[] calldata creditUsersToSettle)
        external
        nonReentrant
        returns (uint256 realPayout, uint256 creditPayout)
    {
        if (creditUsersToSettle.length > 0) {
            _settleLosingCreditInternal(creditUsersToSettle);
        }

        ClaimAmounts memory amounts = previewClaim(msg.sender);
        if (amounts.realPayout == 0 && amounts.creditPayout == 0 && amounts.unsettledLosingCreditPrincipal == 0) {
            revert NothingToClaim();
        }

        _snapshotSettlement();

        totalPrincipal -= amounts.realPayout + amounts.creditPayout;
        for (uint8 outcomeId = 0; outcomeId < OUTCOME_COUNT; outcomeId++) {
            WorldCupPosition memory realPosition = _realPositions[msg.sender][outcomeId];
            WorldCupPosition memory creditPosition = _creditPositions[msg.sender][outcomeId];
            WorldCupOutcomePool storage pool = _outcomePools[outcomeId];
            pool.principal -= realPosition.principal + creditPosition.principal;
            pool.rewardShares -= realPosition.rewardShares + creditPosition.rewardShares;
            pool.realPrincipal -= realPosition.principal;
            pool.creditPrincipal -= creditPosition.principal;
            pool.realRewardShares -= realPosition.rewardShares;
            pool.creditRewardShares -= creditPosition.rewardShares;
            delete _realPositions[msg.sender][outcomeId];
            delete _creditPositions[msg.sender][outcomeId];
        }

        realPayout = amounts.realPayout;
        creditPayout = amounts.creditPayout;

        uint256 consumedCredit = amounts.winningCreditPrincipal + amounts.unsettledLosingCreditPrincipal;
        if (consumedCredit > 0 || creditPayout > 0) {
            if (creditPayout > 0) {
                usdt.safeTransfer(address(creditReserve), creditPayout);
            }
            creditReserve.settleCredit(creditEventId, msg.sender, consumedCredit, creditPayout);
            if (amounts.unsettledLosingCreditPrincipal > 0) {
                losingCreditSettled[msg.sender] = true;
            }
        }

        if (realPayout > 0) {
            usdt.safeTransfer(msg.sender, realPayout);
        }

        emit Claimed(msg.sender, realPayout, creditPayout);
    }

    function previewRefund(address user, uint8[] calldata outcomeIds)
        external
        view
        returns (RefundAmounts memory amounts)
    {
        amounts = _previewRefund(user, outcomeIds);
    }

    function refund(uint8[] calldata outcomeIds)
        external
        nonReentrant
        returns (uint256 realRefund, uint256 creditRefund)
    {
        RefundAmounts memory amounts = _previewRefund(msg.sender, outcomeIds);
        if (amounts.realRefund + amounts.creditRefund == 0) revert NothingToRefund();

        for (uint256 i = 0; i < outcomeIds.length; i++) {
            uint8 outcomeId = outcomeIds[i];
            WorldCupPosition memory realPosition = _realPositions[msg.sender][outcomeId];
            WorldCupPosition memory creditPosition = _creditPositions[msg.sender][outcomeId];
            WorldCupOutcomePool storage pool = _outcomePools[outcomeId];
            pool.principal -= realPosition.principal + creditPosition.principal;
            pool.rewardShares -= realPosition.rewardShares + creditPosition.rewardShares;
            pool.realPrincipal -= realPosition.principal;
            pool.creditPrincipal -= creditPosition.principal;
            pool.realRewardShares -= realPosition.rewardShares;
            pool.creditRewardShares -= creditPosition.rewardShares;
            delete _realPositions[msg.sender][outcomeId];
            delete _creditPositions[msg.sender][outcomeId];
        }

        realRefund = amounts.realRefund;
        creditRefund = amounts.creditRefund;
        totalPrincipal -= realRefund + creditRefund;

        if (creditRefund > 0) {
            usdt.safeTransfer(address(creditReserve), creditRefund);
            creditReserve.settleCredit(creditEventId, msg.sender, creditRefund, creditRefund);
        }
        if (realRefund > 0) {
            usdt.safeTransfer(msg.sender, realRefund);
        }

        emit Refunded(msg.sender, realRefund, creditRefund);
    }

    function getOutcomePool(uint8 outcomeId) external view returns (WorldCupOutcomePool memory) {
        if (outcomeId >= OUTCOME_COUNT) revert InvalidOutcome();
        return _outcomePools[outcomeId];
    }

    function getUserRealPosition(address user, uint8 outcomeId) external view returns (WorldCupPosition memory) {
        if (outcomeId >= OUTCOME_COUNT) revert InvalidOutcome();
        return _realPositions[user][outcomeId];
    }

    function getUserCreditPosition(address user, uint8 outcomeId) external view returns (WorldCupPosition memory) {
        if (outcomeId >= OUTCOME_COUNT) revert InvalidOutcome();
        return _creditPositions[user][outcomeId];
    }

    function _requireOpenActiveOutcome(uint8 outcomeId) internal view {
        if (state != WorldCupWinnerMarketState.Open) revert MarketNotOpen();
        if (outcomeId >= OUTCOME_COUNT) revert InvalidOutcome();
        (bool isReported, bool result, bool isFlagged) = worldCupResolver.getOutcomeStatus(outcomeId);
        if (isFlagged) revert FlaggedOutcome();
        if (isReported && !result) revert EliminatedOutcome();
    }

    function _quoteBuy(uint256 amountIn, uint256 currentOutcomePrincipal)
        internal
        view
        returns (BuyQuote memory quote)
    {
        currentOutcomePrincipal;
        if (amountIn == 0) revert ZeroAmount();
        if (amountIn < MIN_BUY_AMOUNT_IN) revert BelowMinimumBuy();

        quote.feeAmount = Math.mulDiv(amountIn, feeBps, BPS_DENOMINATOR);
        quote.principalAdded = amountIn - quote.feeAmount;
        if (quote.principalAdded == 0) revert ZeroAmount();
        quote.rewardSharesOut = Math.mulDiv(quote.principalAdded, roundMultiplierBps[currentRound], BPS_DENOMINATOR);
    }

    function _applyBuy(address user, uint8 outcomeId, BuyQuote memory quote, bool creditFunded) internal {
        WorldCupOutcomePool storage pool = _outcomePools[outcomeId];
        pool.principal += quote.principalAdded;
        pool.rewardShares += quote.rewardSharesOut;
        totalPrincipal += quote.principalAdded;

        if (creditFunded) {
            pool.creditPrincipal += quote.principalAdded;
            pool.creditRewardShares += quote.rewardSharesOut;
            WorldCupPosition storage position = _creditPositions[user][outcomeId];
            position.principal += quote.principalAdded;
            position.rewardShares += quote.rewardSharesOut;
        } else {
            pool.realPrincipal += quote.principalAdded;
            pool.realRewardShares += quote.rewardSharesOut;
            WorldCupPosition storage position = _realPositions[user][outcomeId];
            position.principal += quote.principalAdded;
            position.rewardShares += quote.rewardSharesOut;
        }
    }

    function _resolve(uint8 winnerOutcomeId, bool adminFallback, string memory reason) internal {
        state = WorldCupWinnerMarketState.Resolved;
        winningOutcomeId = winnerOutcomeId;
        hasWinner = true;
        emit WorldCupResolved(winnerOutcomeId, adminFallback, reason);
    }

    function _settleLosingCreditInternal(address[] calldata users) internal {
        if (state != WorldCupWinnerMarketState.Resolved) revert MarketNotResolved();
        for (uint256 i = 0; i < users.length; i++) {
            _settleOneLosingCredit(users[i]);
        }
    }

    function _settleOneLosingCredit(address user) internal {
        if (losingCreditSettled[user]) revert AlreadySettled();

        uint256 losingCreditPrincipal = _totalCreditPrincipal(user) - _creditPositions[user][winningOutcomeId].principal;
        if (losingCreditPrincipal == 0) {
            losingCreditSettled[user] = true;
            emit LosingCreditSettled(user, 0);
            return;
        }

        losingCreditSettled[user] = true;
        creditReserve.settleCredit(creditEventId, user, losingCreditPrincipal, 0);
        emit LosingCreditSettled(user, losingCreditPrincipal);
    }

    function _previewRefund(address user, uint8[] calldata outcomeIds)
        internal
        view
        returns (RefundAmounts memory amounts)
    {
        if (state != WorldCupWinnerMarketState.Invalid) revert MarketNotRefundable();
        if (outcomeIds.length == 0) revert EmptyOutcomes();

        uint256 seenOutcomeMask;
        for (uint256 i = 0; i < outcomeIds.length; i++) {
            uint8 outcomeId = outcomeIds[i];
            if (outcomeId >= OUTCOME_COUNT) revert InvalidOutcome();
            uint256 outcomeMask = uint256(1) << uint256(outcomeId);
            if ((seenOutcomeMask & outcomeMask) != 0) revert DuplicateOutcome();
            seenOutcomeMask |= outcomeMask;
            amounts.realRefund += _realPositions[user][outcomeId].principal;
            amounts.creditRefund += _creditPositions[user][outcomeId].principal;
        }
    }

    function _totalCreditPrincipal(address user) internal view returns (uint256 totalCreditPrincipal_) {
        for (uint8 outcomeId = 0; outcomeId < OUTCOME_COUNT; outcomeId++) {
            totalCreditPrincipal_ += _creditPositions[user][outcomeId].principal;
        }
    }

    function _snapshotSettlement() internal returns (SettlementSnapshot memory snapshot) {
        snapshot = _settlementSnapshot;
        if (snapshot.initialized) {
            return snapshot;
        }

        WorldCupOutcomePool memory winningPool = _outcomePools[winningOutcomeId];
        snapshot = SettlementSnapshot({initialized: true, totalWinningRewardShares: winningPool.rewardShares});
        _settlementSnapshot = snapshot;
    }
}
