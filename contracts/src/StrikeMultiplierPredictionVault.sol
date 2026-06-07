// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

/// @title StrikeMultiplierPredictionVault
/// @notice USDT escrow and bonus backstop vault for server-authoritative Strike Multiplier Predictions.
contract StrikeMultiplierPredictionVault is AccessControl, EIP712, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant EVENT_MANAGER_ROLE = keccak256("EVENT_MANAGER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant SUBMIT_PREDICTION_QUOTE_TYPEHASH = keccak256(
        "SubmitPredictionQuote(bytes32 predictionId,bytes32 eventId,address predictor,uint256 predictionAmount,uint256 potentialPayout,uint256 expiresAt)"
    );

    uint256 public constant MAX_BPS = 10_000;
    // Coverage BPS limits are admission and withdrawal safety gates. Settlements may draw down the backstop,
    // provided the remaining open predictions still have actual reserved coverage available.
    uint256 public constant PER_PREDICTION_COVERAGE_BPS = 500;
    uint256 public constant GLOBAL_COVERAGE_BPS = 4_000;
    uint256 public constant MAX_PREDICTIONS_PER_EVENT = 128;
    uint256 public constant MAX_TOTAL_PREDICTIONS = 1_000;
    uint256 public constant MAX_SETTLEMENT_WINNERS = 128;

    enum EventStatus {
        None,
        Open,
        Paused,
        Cancelled,
        Settled,
        Finalized
    }

    enum PredictionStatus {
        None,
        Accepted,
        Refundable,
        Refunded,
        Lost,
        Claimable,
        Paid
    }

    struct PredictionEvent {
        EventStatus status;
        uint256 predictionPoolTotal;
        uint256 reservedBackstopCoverage;
        uint256 winningPayoutRequirement;
        uint256 leftover;
        uint256 drawdown;
        uint256 refundableAmountRemaining;
        uint256 claimablePayoutsRemaining;
        uint256 acceptedCount;
    }

    struct PredictionReceipt {
        bytes32 eventId;
        address predictor;
        uint256 predictionAmount;
        uint256 potentialPayout;
        uint256 requiredBackstopCoverage;
        PredictionStatus status;
    }

    error ZeroAddress();
    error ZeroAmount();
    error ZeroId();
    error EventExists();
    error EventNotOpen();
    error EventNotPaused();
    error EventNotCancellable();
    error EventNotSettled();
    error PredictionExists();
    error PredictionNotFound();
    error InvalidPredictionStatus();
    error InvalidPayout();
    error CoverageUnavailable();
    error InsufficientShares();
    error InsufficientOutput();
    error WithdrawalImpairsCoverage();
    error InsufficientRecoverableBalance();
    error EventPredictionLimitExceeded();
    error TotalPredictionLimitExceeded();
    error SettlementWinnersLimitExceeded();
    error DuplicateWinningPrediction();
    error EventNotSettleable();
    error BackstopCoverageImpaired();
    error ExpiredPredictionQuote();
    error InvalidPredictionQuoteSigner();

    IERC20 public immutable usdt;

    uint256 public totalBackstopPool;
    uint256 public totalBackstopShares;
    uint256 public reservedBackstopCoverage;
    uint256 public maxOpenRequiredCoverage;
    uint256 public totalPredictionPoolEscrowed;
    uint256 public totalRefundablePredictions;
    uint256 public totalClaimablePayouts;

    mapping(address => uint256) public backstopSharesOf;
    mapping(bytes32 => PredictionEvent) public predictionEvents;
    mapping(bytes32 => PredictionReceipt) public predictionReceipts;

    bytes32[] internal _predictionIds;
    mapping(bytes32 => bytes32[]) internal _eventPredictionIds;

    event BackstopContributed(address indexed contributor, uint256 amount, uint256 sharesMinted);
    event BackstopWithdrawn(address indexed contributor, uint256 sharesBurned, uint256 amount);
    event PredictionEventCreated(bytes32 indexed eventId);
    event PredictionEventPaused(bytes32 indexed eventId);
    event PredictionEventResumed(bytes32 indexed eventId);
    event PredictionAccepted(
        bytes32 indexed predictionId,
        bytes32 indexed eventId,
        address indexed predictor,
        uint256 predictionAmount,
        uint256 potentialPayout,
        uint256 requiredBackstopCoverage
    );
    event PredictionEventCancelled(bytes32 indexed eventId, uint256 refundableAmount);
    event RefundClaimed(
        bytes32 indexed predictionId, bytes32 indexed eventId, address indexed predictor, uint256 amount
    );
    event PredictionEventSettled(
        bytes32 indexed eventId, uint256 winningPayoutRequirement, uint256 leftover, uint256 drawdown
    );
    event PredictionPayoutClaimed(
        bytes32 indexed predictionId, bytes32 indexed eventId, address indexed predictor, uint256 amount
    );
    event PredictionEventFinalized(bytes32 indexed eventId);
    event ERC20Recovered(address indexed token, address indexed to, uint256 amount);
    event USDTSurplusRecovered(address indexed to, uint256 amount);

    constructor(address usdt_, address admin, address eventManager) EIP712("StrikeMultiplierPredictionVault", "1") {
        if (usdt_ == address(0) || admin == address(0) || eventManager == address(0)) revert ZeroAddress();

        usdt = IERC20(usdt_);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(EVENT_MANAGER_ROLE, eventManager);
        _grantRole(PAUSER_ROLE, admin);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function createEvent(bytes32 eventId) external onlyRole(EVENT_MANAGER_ROLE) {
        if (eventId == bytes32(0)) revert ZeroId();
        if (predictionEvents[eventId].status != EventStatus.None) revert EventExists();

        predictionEvents[eventId].status = EventStatus.Open;
        emit PredictionEventCreated(eventId);
    }

    function pauseEvent(bytes32 eventId) external onlyRole(EVENT_MANAGER_ROLE) {
        PredictionEvent storage predictionEvent = predictionEvents[eventId];
        if (predictionEvent.status != EventStatus.Open) revert EventNotOpen();

        predictionEvent.status = EventStatus.Paused;
        emit PredictionEventPaused(eventId);
    }

    function resumeEvent(bytes32 eventId) external onlyRole(EVENT_MANAGER_ROLE) {
        PredictionEvent storage predictionEvent = predictionEvents[eventId];
        if (predictionEvent.status != EventStatus.Paused) revert EventNotPaused();

        predictionEvent.status = EventStatus.Open;
        emit PredictionEventResumed(eventId);
    }

    function contribute(uint256 amount, uint256 minSharesOut)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 shares)
    {
        if (amount == 0) revert ZeroAmount();

        uint256 poolBefore = totalBackstopPool;
        uint256 sharesBefore = totalBackstopShares;
        if (sharesBefore == 0 || poolBefore == 0) {
            shares = amount;
        } else {
            shares = (amount * sharesBefore) / poolBefore;
        }
        if (shares == 0) revert ZeroAmount();
        if (shares < minSharesOut) revert InsufficientOutput();

        totalBackstopPool = poolBefore + amount;
        totalBackstopShares = sharesBefore + shares;
        backstopSharesOf[msg.sender] += shares;
        usdt.safeTransferFrom(msg.sender, address(this), amount);

        emit BackstopContributed(msg.sender, amount, shares);
    }

    function withdraw(uint256 shares, uint256 minAmountOut)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 amount)
    {
        if (shares == 0) revert ZeroAmount();
        if (backstopSharesOf[msg.sender] < shares) revert InsufficientShares();

        amount = previewWithdraw(shares);
        if (amount == 0) revert ZeroAmount();
        if (amount < minAmountOut) revert InsufficientOutput();

        uint256 remainingPool = totalBackstopPool - amount;
        if (!_coverageFitsPool(remainingPool)) revert WithdrawalImpairsCoverage();

        backstopSharesOf[msg.sender] -= shares;
        totalBackstopShares -= shares;
        totalBackstopPool = remainingPool;
        usdt.safeTransfer(msg.sender, amount);

        emit BackstopWithdrawn(msg.sender, shares, amount);
    }

    function acceptPrediction(
        bytes32 predictionId,
        bytes32 eventId,
        address predictor,
        uint256 predictionAmount,
        uint256 potentialPayout
    ) external nonReentrant whenNotPaused onlyRole(EVENT_MANAGER_ROLE) {
        _acceptPrediction(predictionId, eventId, predictor, predictionAmount, potentialPayout);
    }

    function submitPredictionWithQuote(
        bytes32 predictionId,
        bytes32 eventId,
        uint256 predictionAmount,
        uint256 potentialPayout,
        uint256 expiresAt,
        bytes calldata signature
    ) external nonReentrant whenNotPaused {
        if (block.timestamp > expiresAt) revert ExpiredPredictionQuote();

        address signer = ECDSA.recover(
            getSubmitPredictionQuoteDigest(
                predictionId, eventId, msg.sender, predictionAmount, potentialPayout, expiresAt
            ),
            signature
        );
        if (!hasRole(EVENT_MANAGER_ROLE, signer)) revert InvalidPredictionQuoteSigner();

        _acceptPrediction(predictionId, eventId, msg.sender, predictionAmount, potentialPayout);
    }

    function getSubmitPredictionQuoteDigest(
        bytes32 predictionId,
        bytes32 eventId,
        address predictor,
        uint256 predictionAmount,
        uint256 potentialPayout,
        uint256 expiresAt
    ) public view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    SUBMIT_PREDICTION_QUOTE_TYPEHASH,
                    predictionId,
                    eventId,
                    predictor,
                    predictionAmount,
                    potentialPayout,
                    expiresAt
                )
            )
        );
    }

    function _acceptPrediction(
        bytes32 predictionId,
        bytes32 eventId,
        address predictor,
        uint256 predictionAmount,
        uint256 potentialPayout
    ) internal {
        if (predictionId == bytes32(0) || eventId == bytes32(0)) revert ZeroId();
        if (predictor == address(0)) revert ZeroAddress();
        if (predictionAmount == 0 || potentialPayout == 0) revert ZeroAmount();
        if (potentialPayout < predictionAmount) revert InvalidPayout();
        if (predictionReceipts[predictionId].status != PredictionStatus.None) revert PredictionExists();

        PredictionEvent storage predictionEvent = predictionEvents[eventId];
        if (predictionEvent.status != EventStatus.Open) revert EventNotOpen();
        if (predictionEvent.acceptedCount >= MAX_PREDICTIONS_PER_EVENT) revert EventPredictionLimitExceeded();
        if (_predictionIds.length >= MAX_TOTAL_PREDICTIONS) revert TotalPredictionLimitExceeded();

        uint256 requiredCoverage = potentialPayout > predictionAmount ? potentialPayout - predictionAmount : 0;
        if (!_coverageFitsPoolAfterReserve(requiredCoverage)) revert CoverageUnavailable();

        predictionReceipts[predictionId] = PredictionReceipt({
            eventId: eventId,
            predictor: predictor,
            predictionAmount: predictionAmount,
            potentialPayout: potentialPayout,
            requiredBackstopCoverage: requiredCoverage,
            status: PredictionStatus.Accepted
        });
        _predictionIds.push(predictionId);
        _eventPredictionIds[eventId].push(predictionId);

        predictionEvent.predictionPoolTotal += predictionAmount;
        predictionEvent.reservedBackstopCoverage += requiredCoverage;
        predictionEvent.acceptedCount += 1;
        totalPredictionPoolEscrowed += predictionAmount;
        reservedBackstopCoverage += requiredCoverage;
        if (requiredCoverage > maxOpenRequiredCoverage) {
            maxOpenRequiredCoverage = requiredCoverage;
        }

        usdt.safeTransferFrom(predictor, address(this), predictionAmount);

        emit PredictionAccepted(predictionId, eventId, predictor, predictionAmount, potentialPayout, requiredCoverage);
    }

    function cancelEvent(bytes32 eventId) external nonReentrant whenNotPaused onlyRole(EVENT_MANAGER_ROLE) {
        PredictionEvent storage predictionEvent = predictionEvents[eventId];
        if (predictionEvent.status != EventStatus.Open && predictionEvent.status != EventStatus.Paused) {
            revert EventNotCancellable();
        }

        uint256 refundableAmount;
        predictionEvent.status = EventStatus.Cancelled;
        bytes32[] storage eventPredictionIds = _eventPredictionIds[eventId];
        for (uint256 i = 0; i < eventPredictionIds.length; i++) {
            PredictionReceipt storage receipt = predictionReceipts[eventPredictionIds[i]];
            if (receipt.status == PredictionStatus.Accepted) {
                receipt.status = PredictionStatus.Refundable;
                refundableAmount += receipt.predictionAmount;
            }
        }

        reservedBackstopCoverage -= predictionEvent.reservedBackstopCoverage;
        predictionEvent.reservedBackstopCoverage = 0;
        predictionEvent.refundableAmountRemaining = refundableAmount;
        totalPredictionPoolEscrowed -= refundableAmount;
        totalRefundablePredictions += refundableAmount;
        _recomputeMaxOpenRequiredCoverage();

        emit PredictionEventCancelled(eventId, refundableAmount);
    }

    function claimRefund(bytes32 predictionId) external nonReentrant {
        PredictionReceipt storage receipt = predictionReceipts[predictionId];
        if (receipt.status == PredictionStatus.None) revert PredictionNotFound();
        if (receipt.status != PredictionStatus.Refundable) revert InvalidPredictionStatus();

        PredictionEvent storage predictionEvent = predictionEvents[receipt.eventId];
        uint256 amount = receipt.predictionAmount;
        receipt.status = PredictionStatus.Refunded;
        predictionEvent.refundableAmountRemaining -= amount;
        totalRefundablePredictions -= amount;
        usdt.safeTransfer(receipt.predictor, amount);

        emit RefundClaimed(predictionId, receipt.eventId, receipt.predictor, amount);
    }

    function settleEvent(bytes32 eventId, bytes32[] calldata winningPredictionIds)
        external
        nonReentrant
        whenNotPaused
        onlyRole(EVENT_MANAGER_ROLE)
    {
        PredictionEvent storage predictionEvent = predictionEvents[eventId];
        if (predictionEvent.status != EventStatus.Open && predictionEvent.status != EventStatus.Paused) {
            revert EventNotSettleable();
        }
        if (winningPredictionIds.length > MAX_SETTLEMENT_WINNERS) revert SettlementWinnersLimitExceeded();

        for (uint256 i = 0; i < winningPredictionIds.length; i++) {
            for (uint256 j = i + 1; j < winningPredictionIds.length; j++) {
                if (winningPredictionIds[i] == winningPredictionIds[j]) revert DuplicateWinningPrediction();
            }
        }

        uint256 winningPayoutRequirement;
        for (uint256 i = 0; i < winningPredictionIds.length; i++) {
            PredictionReceipt storage winner = predictionReceipts[winningPredictionIds[i]];
            if (winner.eventId != eventId || winner.status != PredictionStatus.Accepted) {
                revert InvalidPredictionStatus();
            }
            winner.status = PredictionStatus.Claimable;
            winningPayoutRequirement += winner.potentialPayout;
        }

        bytes32[] storage eventPredictionIds = _eventPredictionIds[eventId];
        for (uint256 i = 0; i < eventPredictionIds.length; i++) {
            PredictionReceipt storage receipt = predictionReceipts[eventPredictionIds[i]];
            if (receipt.status == PredictionStatus.Accepted) {
                receipt.status = PredictionStatus.Lost;
            }
        }

        uint256 predictionPool = predictionEvent.predictionPoolTotal;
        uint256 leftover;
        uint256 drawdown;
        if (winningPayoutRequirement > predictionPool) {
            drawdown = winningPayoutRequirement - predictionPool;
            if (drawdown > totalBackstopPool) revert CoverageUnavailable();
            totalBackstopPool -= drawdown;
        } else {
            leftover = predictionPool - winningPayoutRequirement;
            totalBackstopPool += leftover;
        }

        reservedBackstopCoverage -= predictionEvent.reservedBackstopCoverage;
        if (reservedBackstopCoverage > totalBackstopPool) revert BackstopCoverageImpaired();
        predictionEvent.reservedBackstopCoverage = 0;
        predictionEvent.winningPayoutRequirement = winningPayoutRequirement;
        predictionEvent.leftover = leftover;
        predictionEvent.drawdown = drawdown;
        predictionEvent.claimablePayoutsRemaining = winningPayoutRequirement;
        predictionEvent.status = EventStatus.Settled;
        totalPredictionPoolEscrowed -= predictionPool;
        totalClaimablePayouts += winningPayoutRequirement;
        _recomputeMaxOpenRequiredCoverage();

        emit PredictionEventSettled(eventId, winningPayoutRequirement, leftover, drawdown);
    }

    function claimPredictionPayout(bytes32 predictionId) external nonReentrant {
        PredictionReceipt storage receipt = predictionReceipts[predictionId];
        if (receipt.status == PredictionStatus.None) revert PredictionNotFound();
        if (receipt.status != PredictionStatus.Claimable) revert InvalidPredictionStatus();

        uint256 amount = receipt.potentialPayout;
        PredictionEvent storage predictionEvent = predictionEvents[receipt.eventId];
        receipt.status = PredictionStatus.Paid;
        predictionEvent.claimablePayoutsRemaining -= amount;
        totalClaimablePayouts -= amount;
        usdt.safeTransfer(receipt.predictor, amount);

        emit PredictionPayoutClaimed(predictionId, receipt.eventId, receipt.predictor, amount);
    }

    function finalizeEvent(bytes32 eventId) external onlyRole(EVENT_MANAGER_ROLE) {
        PredictionEvent storage predictionEvent = predictionEvents[eventId];
        if (predictionEvent.status != EventStatus.Settled && predictionEvent.status != EventStatus.Cancelled) {
            revert EventNotSettled();
        }
        if (predictionEvent.refundableAmountRemaining != 0 || predictionEvent.claimablePayoutsRemaining != 0) {
            revert InvalidPredictionStatus();
        }

        predictionEvent.status = EventStatus.Finalized;
        emit PredictionEventFinalized(eventId);
    }

    function recoverERC20(address token, address to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (to == address(0) || token == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (token == address(usdt)) {
            _recoverUSDTSurplus(to, amount);
        } else {
            IERC20(token).safeTransfer(to, amount);
            emit ERC20Recovered(token, to, amount);
        }
    }

    function maxWithdrawableAmount() public view returns (uint256) {
        uint256 pool = totalBackstopPool;
        uint256 minimumPool = reservedBackstopCoverage;
        uint256 globalMinimum = _ceilDiv(reservedBackstopCoverage * MAX_BPS, GLOBAL_COVERAGE_BPS);
        uint256 individualMinimum = _ceilDiv(maxOpenRequiredCoverage * MAX_BPS, PER_PREDICTION_COVERAGE_BPS);

        if (globalMinimum > minimumPool) minimumPool = globalMinimum;
        if (individualMinimum > minimumPool) minimumPool = individualMinimum;
        if (minimumPool >= pool) return 0;
        return pool - minimumPool;
    }

    function previewWithdraw(uint256 shares) public view returns (uint256) {
        if (shares == 0 || totalBackstopShares == 0) return 0;
        return (shares * totalBackstopPool) / totalBackstopShares;
    }

    function availableBackstopPool() public view returns (uint256) {
        if (reservedBackstopCoverage >= totalBackstopPool) return 0;
        return totalBackstopPool - reservedBackstopCoverage;
    }

    function predictionIdsLength() external view returns (uint256) {
        return _predictionIds.length;
    }

    function predictionIdAt(uint256 index) external view returns (bytes32) {
        return _predictionIds[index];
    }

    function eventPredictionIdsLength(bytes32 eventId) external view returns (uint256) {
        return _eventPredictionIds[eventId].length;
    }

    function eventPredictionIdAt(bytes32 eventId, uint256 index) external view returns (bytes32) {
        return _eventPredictionIds[eventId][index];
    }

    function recoverableUSDT() public view returns (uint256) {
        uint256 tracked =
            totalBackstopPool + totalPredictionPoolEscrowed + totalRefundablePredictions + totalClaimablePayouts;
        uint256 balance = usdt.balanceOf(address(this));
        if (balance <= tracked) return 0;
        return balance - tracked;
    }

    function _recoverUSDTSurplus(address to, uint256 amount) internal {
        if (amount > recoverableUSDT()) revert InsufficientRecoverableBalance();
        usdt.safeTransfer(to, amount);
        emit USDTSurplusRecovered(to, amount);
    }

    function _coverageFitsPoolAfterReserve(uint256 addedCoverage) internal view returns (bool) {
        uint256 pool = totalBackstopPool;
        if (pool == 0 && addedCoverage > 0) return false;
        if (addedCoverage * MAX_BPS > pool * PER_PREDICTION_COVERAGE_BPS) return false;
        if ((reservedBackstopCoverage + addedCoverage) * MAX_BPS > pool * GLOBAL_COVERAGE_BPS) return false;
        return true;
    }

    function _coverageFitsPool(uint256 pool) internal view returns (bool) {
        if (reservedBackstopCoverage > pool) return false;
        if (maxOpenRequiredCoverage * MAX_BPS > pool * PER_PREDICTION_COVERAGE_BPS) return false;
        if (reservedBackstopCoverage * MAX_BPS > pool * GLOBAL_COVERAGE_BPS) return false;
        return true;
    }

    function _recomputeMaxOpenRequiredCoverage() internal {
        uint256 maxRequired;
        for (uint256 i = 0; i < _predictionIds.length; i++) {
            PredictionReceipt storage receipt = predictionReceipts[_predictionIds[i]];
            if (receipt.status == PredictionStatus.Accepted && receipt.requiredBackstopCoverage > maxRequired) {
                maxRequired = receipt.requiredBackstopCoverage;
            }
        }
        maxOpenRequiredCoverage = maxRequired;
    }

    function _ceilDiv(uint256 numerator, uint256 denominator) internal pure returns (uint256) {
        if (numerator == 0) return 0;
        return (numerator - 1) / denominator + 1;
    }
}
