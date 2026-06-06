// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title StrikeDuelsWagerVault
/// @notice Escrows native BNB PvP wagers and pooled STRIKE AI wagers for server-authoritative Strike Duels.
contract StrikeDuelsWagerVault is AccessControl, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant SETTLER_ROLE = keccak256("SETTLER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant TREASURY_ROLE = keccak256("TREASURY_ROLE");

    uint16 public constant MAX_BPS = 10_000;

    enum Mode {
        None,
        Pvp,
        Ai
    }

    enum Status {
        None,
        Created,
        Joined,
        Finalized,
        Refunded
    }

    enum Result {
        PlayerAWins,
        PlayerBWins,
        DrawNoContest
    }

    struct Wager {
        Mode mode;
        Status status;
        address playerA;
        address playerB;
        address opponent;
        uint256 stakeAmount;
        uint256 aiWinRewardAmount;
        uint16 pvpFeeBps;
        bytes32 aiConfigHash;
        bytes32 matchSummaryHash;
    }

    error ZeroAddress();
    error InvalidFeeBps();
    error InvalidWagerStatus();
    error WagerAlreadyExists();
    error InvalidPvpBracket();
    error PvpStakeExceedsCap();
    error InvalidPvpOpponent();
    error InvalidPvpJoiner();
    error IncorrectPvpStake();
    error InsufficientAiRewardLiquidity();
    error AiRewardExposureExceeded();
    error NativeTransferFailed();
    error InsufficientRecoverableBalance();

    IERC20 public immutable strikeToken;

    address public treasury;
    uint256 public aiStakeAmount;
    uint256 public aiWinRewardAmount;
    uint16 public pvpFeeBps;
    uint256 public maxPvpStakeAmount;
    uint256 public maxAiRewardExposure;
    uint256 public aiRewardExposure;
    uint256 public aiStakeEscrowed;
    uint256 public nativeEscrowed;
    uint256 public nativePendingWithdrawalsTotal;

    mapping(uint256 => bool) public pvpBracketEnabled;
    mapping(bytes32 => Wager) public wagers;
    mapping(address => uint256) public pendingNativeWithdrawals;

    event PvpWagerCreated(
        bytes32 indexed wagerId, address indexed creator, address indexed opponent, uint256 stakeAmount
    );
    event PvpWagerJoined(bytes32 indexed wagerId, address indexed joiner);
    event AiWagerCreated(
        bytes32 indexed wagerId,
        address indexed player,
        bytes32 aiConfigHash,
        uint256 stakeAmount,
        uint256 winRewardAmount
    );
    event WagerFinalized(
        bytes32 indexed wagerId,
        Result result,
        bytes32 matchSummaryHash,
        address indexed payoutRecipient,
        uint256 payoutAmount,
        uint256 feeAmount
    );
    event WagerRefunded(bytes32 indexed wagerId, bytes32 reason);
    event TreasuryUpdated(address indexed treasury);
    event CapsUpdated(uint256 maxPvpStakeAmount, uint256 maxAiRewardExposure);
    event PvpBracketUpdated(uint256 amount, bool enabled);
    event AiPrizeUpdated(uint256 stakeAmount, uint256 winRewardAmount);
    event PvpFeeUpdated(uint16 feeBps);
    event NativeSurplusRecovered(address indexed to, uint256 amount);
    event ERC20Recovered(address indexed token, address indexed to, uint256 amount);
    event NativePayoutPending(address indexed recipient, uint256 amount);
    event NativePayoutClaimed(address indexed recipient, uint256 amount);

    constructor(
        address strikeToken_,
        address admin,
        address treasury_,
        address settler,
        uint256 aiStakeAmount_,
        uint256 aiWinRewardAmount_,
        uint16 pvpFeeBps_,
        uint256 maxPvpStakeAmount_,
        uint256 maxAiRewardExposure_
    ) {
        if (strikeToken_ == address(0) || admin == address(0) || treasury_ == address(0) || settler == address(0)) {
            revert ZeroAddress();
        }
        if (pvpFeeBps_ > MAX_BPS) revert InvalidFeeBps();

        strikeToken = IERC20(strikeToken_);
        treasury = treasury_;
        aiStakeAmount = aiStakeAmount_;
        aiWinRewardAmount = aiWinRewardAmount_;
        pvpFeeBps = pvpFeeBps_;
        maxPvpStakeAmount = maxPvpStakeAmount_;
        maxAiRewardExposure = maxAiRewardExposure_;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(SETTLER_ROLE, settler);
        _grantRole(PAUSER_ROLE, admin);
        _grantRole(TREASURY_ROLE, admin);
        _grantRole(TREASURY_ROLE, treasury_);
    }

    function createPvpWager(bytes32 wagerId, address opponent) external payable nonReentrant whenNotPaused {
        if (wagers[wagerId].status != Status.None) revert WagerAlreadyExists();
        if (!pvpBracketEnabled[msg.value]) revert InvalidPvpBracket();
        if (msg.value > maxPvpStakeAmount) revert PvpStakeExceedsCap();
        if (opponent == msg.sender) revert InvalidPvpOpponent();

        nativeEscrowed += msg.value;
        wagers[wagerId] = Wager({
            mode: Mode.Pvp,
            status: Status.Created,
            playerA: msg.sender,
            playerB: address(0),
            opponent: opponent,
            stakeAmount: msg.value,
            aiWinRewardAmount: 0,
            pvpFeeBps: pvpFeeBps,
            aiConfigHash: bytes32(0),
            matchSummaryHash: bytes32(0)
        });

        emit PvpWagerCreated(wagerId, msg.sender, opponent, msg.value);
    }

    function joinPvpWager(bytes32 wagerId) external payable nonReentrant whenNotPaused {
        Wager storage wager = wagers[wagerId];
        if (wager.mode != Mode.Pvp || wager.status != Status.Created) revert InvalidWagerStatus();
        if (msg.sender == wager.playerA) revert InvalidPvpJoiner();
        if (wager.opponent != address(0) && msg.sender != wager.opponent) revert InvalidPvpJoiner();
        if (msg.value != wager.stakeAmount) revert IncorrectPvpStake();

        nativeEscrowed += msg.value;
        wager.playerB = msg.sender;
        wager.status = Status.Joined;

        emit PvpWagerJoined(wagerId, msg.sender);
    }

    function createAiWager(bytes32 wagerId, bytes32 aiConfigHash) external nonReentrant whenNotPaused {
        if (wagers[wagerId].status != Status.None) revert WagerAlreadyExists();
        if (_availableAiRewardLiquidity() < aiWinRewardAmount) revert InsufficientAiRewardLiquidity();
        if (aiRewardExposure + aiWinRewardAmount > maxAiRewardExposure) revert AiRewardExposureExceeded();

        uint256 stake = aiStakeAmount;
        uint256 reward = aiWinRewardAmount;
        aiRewardExposure += reward;
        strikeToken.safeTransferFrom(msg.sender, address(this), stake);
        aiStakeEscrowed += stake;

        wagers[wagerId] = Wager({
            mode: Mode.Ai,
            status: Status.Created,
            playerA: msg.sender,
            playerB: address(0),
            opponent: address(0),
            stakeAmount: stake,
            aiWinRewardAmount: reward,
            pvpFeeBps: 0,
            aiConfigHash: aiConfigHash,
            matchSummaryHash: bytes32(0)
        });

        emit AiWagerCreated(wagerId, msg.sender, aiConfigHash, stake, reward);
    }

    function finalizeWager(bytes32 wagerId, Result result, bytes32 matchSummaryHash)
        external
        nonReentrant
        whenNotPaused
        onlyRole(SETTLER_ROLE)
    {
        Wager storage wager = wagers[wagerId];
        if (wager.mode == Mode.Pvp) {
            _finalizePvp(wagerId, wager, result, matchSummaryHash);
        } else if (wager.mode == Mode.Ai) {
            _finalizeAi(wagerId, wager, result, matchSummaryHash);
        } else {
            revert InvalidWagerStatus();
        }
    }

    function refundWager(bytes32 wagerId, bytes32 reason) external nonReentrant whenNotPaused onlyRole(SETTLER_ROLE) {
        Wager storage wager = wagers[wagerId];
        if (wager.mode == Mode.Pvp) {
            if (wager.status != Status.Created && wager.status != Status.Joined) revert InvalidWagerStatus();
            Status status = wager.status;
            uint256 refundAmount = wager.stakeAmount;
            if (status == Status.Joined) refundAmount += wager.stakeAmount;
            nativeEscrowed -= refundAmount;
            wager.status = Status.Refunded;
            _sendOrCreditNative(wager.playerA, wager.stakeAmount);
            if (status == Status.Joined) {
                _sendOrCreditNative(wager.playerB, wager.stakeAmount);
            }
        } else if (wager.mode == Mode.Ai) {
            if (wager.status != Status.Created) revert InvalidWagerStatus();
            wager.status = Status.Refunded;
            aiRewardExposure -= wager.aiWinRewardAmount;
            aiStakeEscrowed -= wager.stakeAmount;
            strikeToken.safeTransfer(wager.playerA, wager.stakeAmount);
        } else {
            revert InvalidWagerStatus();
        }

        emit WagerRefunded(wagerId, reason);
    }

    function setPvpBracket(uint256 amount, bool enabled) external onlyRole(TREASURY_ROLE) {
        pvpBracketEnabled[amount] = enabled;
        emit PvpBracketUpdated(amount, enabled);
    }

    function setPvpFeeBps(uint16 feeBps) external onlyRole(TREASURY_ROLE) {
        if (feeBps > MAX_BPS) revert InvalidFeeBps();
        pvpFeeBps = feeBps;
        emit PvpFeeUpdated(feeBps);
    }

    function setTreasury(address treasury_) external onlyRole(TREASURY_ROLE) {
        if (treasury_ == address(0)) revert ZeroAddress();
        treasury = treasury_;
        emit TreasuryUpdated(treasury_);
    }

    function setCaps(uint256 maxPvpStakeAmount_, uint256 maxAiRewardExposure_) external onlyRole(TREASURY_ROLE) {
        maxPvpStakeAmount = maxPvpStakeAmount_;
        maxAiRewardExposure = maxAiRewardExposure_;
        emit CapsUpdated(maxPvpStakeAmount_, maxAiRewardExposure_);
    }

    function setAiPrize(uint256 stakeAmount, uint256 winRewardAmount) external onlyRole(TREASURY_ROLE) {
        aiStakeAmount = stakeAmount;
        aiWinRewardAmount = winRewardAmount;
        emit AiPrizeUpdated(stakeAmount, winRewardAmount);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function recoverNativeSurplus(address to, uint256 amount) external nonReentrant onlyRole(TREASURY_ROLE) {
        if (to == address(0)) revert ZeroAddress();
        if (amount > _recoverableNative()) revert InsufficientRecoverableBalance();
        _sendNative(to, amount);
        emit NativeSurplusRecovered(to, amount);
    }

    function recoverERC20(address token, address to, uint256 amount) external nonReentrant onlyRole(TREASURY_ROLE) {
        if (token == address(0) || to == address(0)) revert ZeroAddress();
        if (amount > _recoverableERC20(token)) revert InsufficientRecoverableBalance();
        IERC20(token).safeTransfer(to, amount);
        emit ERC20Recovered(token, to, amount);
    }

    function claimNativePayout() external nonReentrant {
        _claimNativePayoutTo(msg.sender, payable(msg.sender));
    }

    function claimNativePayoutTo(address payable to) external nonReentrant {
        if (to == address(0)) revert ZeroAddress();
        _claimNativePayoutTo(msg.sender, to);
    }

    function _claimNativePayoutTo(address recipient, address payable to) internal {
        uint256 amount = pendingNativeWithdrawals[recipient];
        if (amount == 0) revert InsufficientRecoverableBalance();
        pendingNativeWithdrawals[recipient] = 0;
        nativePendingWithdrawalsTotal -= amount;
        _sendNative(to, amount);
        emit NativePayoutClaimed(recipient, amount);
    }

    function _finalizePvp(bytes32 wagerId, Wager storage wager, Result result, bytes32 matchSummaryHash) internal {
        if (wager.status != Status.Joined) revert InvalidWagerStatus();
        wager.status = Status.Finalized;
        wager.matchSummaryHash = matchSummaryHash;

        uint256 pool = wager.stakeAmount * 2;
        nativeEscrowed -= pool;
        if (result == Result.DrawNoContest) {
            _sendOrCreditNative(wager.playerA, wager.stakeAmount);
            _sendOrCreditNative(wager.playerB, wager.stakeAmount);
            emit WagerFinalized(wagerId, result, matchSummaryHash, address(0), pool, 0);
            return;
        }

        address winner = result == Result.PlayerAWins ? wager.playerA : wager.playerB;
        uint256 fee = (pool * wager.pvpFeeBps) / MAX_BPS;
        uint256 payout = pool - fee;
        if (fee > 0) _sendOrCreditNative(treasury, fee);
        _sendOrCreditNative(winner, payout);

        emit WagerFinalized(wagerId, result, matchSummaryHash, winner, payout, fee);
    }

    function _finalizeAi(bytes32 wagerId, Wager storage wager, Result result, bytes32 matchSummaryHash) internal {
        if (wager.status != Status.Created) revert InvalidWagerStatus();
        wager.status = Status.Finalized;
        wager.matchSummaryHash = matchSummaryHash;
        aiRewardExposure -= wager.aiWinRewardAmount;
        aiStakeEscrowed -= wager.stakeAmount;

        uint256 payout;
        if (result == Result.PlayerAWins) {
            payout = wager.stakeAmount + wager.aiWinRewardAmount;
            strikeToken.safeTransfer(wager.playerA, payout);
        } else if (result == Result.DrawNoContest) {
            payout = wager.stakeAmount;
            strikeToken.safeTransfer(wager.playerA, payout);
        }

        emit WagerFinalized(wagerId, result, matchSummaryHash, wager.playerA, payout, 0);
    }

    function _availableAiRewardLiquidity() internal view returns (uint256) {
        uint256 balance = strikeToken.balanceOf(address(this));
        uint256 reserved = aiRewardExposure + aiStakeEscrowed;
        if (balance <= reserved) return 0;
        return balance - reserved;
    }

    function _recoverableNative() internal view returns (uint256) {
        uint256 reserved = nativeEscrowed + nativePendingWithdrawalsTotal;
        if (address(this).balance <= reserved) return 0;
        return address(this).balance - reserved;
    }

    function _recoverableERC20(address token) internal view returns (uint256) {
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (token != address(strikeToken)) return balance;

        uint256 reserved = aiRewardExposure + aiStakeEscrowed;
        if (balance <= reserved) return 0;
        return balance - reserved;
    }

    function _sendOrCreditNative(address to, uint256 amount) internal {
        if (amount == 0) return;
        (bool ok,) = to.call{value: amount}("");
        if (ok) return;

        pendingNativeWithdrawals[to] += amount;
        nativePendingWithdrawalsTotal += amount;
        emit NativePayoutPending(to, amount);
    }

    function _sendNative(address to, uint256 amount) internal {
        if (amount == 0) return;
        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert NativeTransferFailed();
    }

    receive() external payable {}
}
