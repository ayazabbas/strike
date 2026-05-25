// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./IUSDTCreditReserve.sol";
import "./USDTParimutuelV3Factory.sol";
import "./USDTParimutuelV3Types.sol";
import "./USDTParimutuelV3Vault.sol";

/// @title USDTParimutuelV3Manager
/// @notice V3 pool accounting with separate real-USDT and USDT-credit positions.
contract USDTParimutuelV3Manager is AccessControl, ReentrancyGuard {
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
        uint256 realWinningRewardShares;
        uint256 realLosingPrincipal;
    }

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant REDEMPTION_ROLE = keccak256("REDEMPTION_ROLE");
    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint256 public constant MIN_BUY_AMOUNT_IN = 0.01e18;

    USDTParimutuelV3Factory public immutable factory;
    USDTParimutuelV3Vault public immutable vault;
    IUSDTCreditReserve public immutable creditReserve;
    IERC20 public immutable usdt;

    address public feeRecipient;
    uint256 public accruedRealFees;

    mapping(uint256 => mapping(uint8 => USDTParimutuelV3OutcomePool)) internal _outcomePools;
    mapping(uint256 => mapping(address => mapping(uint8 => USDTParimutuelV3Position))) internal _realPositions;
    mapping(uint256 => mapping(address => mapping(uint8 => USDTParimutuelV3Position))) internal _creditPositions;
    mapping(uint256 => mapping(address => bool)) public losingCreditSettled;
    mapping(uint256 => uint256) public marketTotalPrincipal;
    mapping(uint256 => SettlementSnapshot) internal _settlementSnapshots;

    event FeeRecipientUpdated(address indexed feeRecipient);
    event FeesWithdrawn(address indexed recipient, uint256 amount);
    event BoughtWithUsdt(
        uint256 indexed marketId,
        address indexed user,
        uint8 indexed outcomeId,
        uint256 amountIn,
        uint256 feeAmount,
        uint256 principalAdded,
        uint256 rewardSharesOut
    );
    event BoughtWithCredit(
        uint256 indexed marketId,
        address indexed user,
        uint8 indexed outcomeId,
        uint256 creditAmount,
        uint256 feeAmount,
        uint256 principalAdded,
        uint256 rewardSharesOut
    );
    event LosingCreditSettled(
        uint256 indexed marketId, address indexed user, uint256 consumedCredit, uint256 withdrawnToVault
    );
    event Claimed(uint256 indexed marketId, address indexed user, uint256 realPayout, uint256 creditPayout);
    event Refunded(uint256 indexed marketId, address indexed user, uint256 realRefund, uint256 creditRefund);

    error ZeroAddress();
    error ZeroAmount();
    error BelowMinimumBuy();
    error ManagerNotRegistered();
    error MarketNotOpen();
    error TradingClosed();
    error InvalidOutcome();
    error Slippage();
    error TransferShortfall();
    error CreditDisabled();
    error MarketNotResolved();
    error MarketNotRefundable();
    error NoWinner();
    error NothingToClaim();
    error NothingToRefund();
    error EmptyOutcomes();
    error DuplicateOutcome();
    error AlreadySettled();
    error CreditLossNotSettled();
    error MissingCreditEvent();

    constructor(address admin, address factory_, address vault_, address creditReserve_, address feeRecipient_) {
        if (
            admin == address(0) || factory_ == address(0) || vault_ == address(0) || creditReserve_ == address(0)
                || feeRecipient_ == address(0)
        ) revert ZeroAddress();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);

        factory = USDTParimutuelV3Factory(factory_);
        vault = USDTParimutuelV3Vault(vault_);
        creditReserve = IUSDTCreditReserve(creditReserve_);
        usdt = vault.usdt();
        feeRecipient = feeRecipient_;
    }

    function setFeeRecipient(address feeRecipient_) external onlyRole(ADMIN_ROLE) {
        if (feeRecipient_ == address(0)) revert ZeroAddress();
        feeRecipient = feeRecipient_;
        emit FeeRecipientUpdated(feeRecipient_);
    }

    function withdrawFees(uint256 amount) external onlyRole(ADMIN_ROLE) nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (amount > accruedRealFees) revert NothingToRefund();

        accruedRealFees -= amount;
        vault.transferTo(feeRecipient, amount);
        emit FeesWithdrawn(feeRecipient, amount);
    }

    function quoteBuy(uint256 marketId, uint8 outcomeId, uint256 amountIn)
        public
        view
        returns (uint256 feeAmount, uint256 principalAdded, uint256 rewardSharesOut)
    {
        USDTParimutuelV3Market memory market = _requireBuyableMarket(marketId);
        if (outcomeId >= market.outcomeCount) revert InvalidOutcome();
        BuyQuote memory quote = _quoteBuy(_outcomePools[marketId][outcomeId].principal, amountIn, market.feeBps);
        return (quote.feeAmount, quote.principalAdded, quote.rewardSharesOut);
    }

    function buyWithUsdt(uint256 marketId, uint8 outcomeId, uint256 amountIn, uint256 minRewardSharesOut)
        external
        nonReentrant
        returns (uint256 rewardSharesOut)
    {
        USDTParimutuelV3Market memory market = _requireBuyableMarket(marketId);
        if (outcomeId >= market.outcomeCount) revert InvalidOutcome();

        BuyQuote memory quote = _quoteBuy(_outcomePools[marketId][outcomeId].principal, amountIn, market.feeBps);
        if (quote.rewardSharesOut < minRewardSharesOut) revert Slippage();

        uint256 vaultBalanceBefore = usdt.balanceOf(address(vault));
        usdt.safeTransferFrom(msg.sender, address(vault), amountIn);
        if (usdt.balanceOf(address(vault)) - vaultBalanceBefore != amountIn) revert TransferShortfall();

        accruedRealFees += quote.feeAmount;
        _applyBuy(marketId, msg.sender, outcomeId, quote, false);

        emit BoughtWithUsdt(
            marketId, msg.sender, outcomeId, amountIn, quote.feeAmount, quote.principalAdded, quote.rewardSharesOut
        );
        return quote.rewardSharesOut;
    }

    function buyWithCredit(uint256 marketId, uint8 outcomeId, uint256 creditAmount, uint256 minRewardSharesOut)
        external
        nonReentrant
        returns (uint256 rewardSharesOut)
    {
        USDTParimutuelV3Market memory market = _requireBuyableMarket(marketId);
        if (!market.creditEnabled) revert CreditDisabled();
        if (market.creditEventId == 0) revert MissingCreditEvent();
        if (outcomeId >= market.outcomeCount) revert InvalidOutcome();

        BuyQuote memory quote = _quoteBuy(_outcomePools[marketId][outcomeId].principal, creditAmount, market.feeBps);
        if (quote.rewardSharesOut < minRewardSharesOut) revert Slippage();

        creditReserve.lockCredit(market.creditEventId, msg.sender, creditAmount);
        if (quote.feeAmount > 0) {
            creditReserve.settleCreditPayout(market.creditEventId, msg.sender, quote.feeAmount, 0);
        }

        _applyBuy(marketId, msg.sender, outcomeId, quote, true);

        emit BoughtWithCredit(
            marketId, msg.sender, outcomeId, creditAmount, quote.feeAmount, quote.principalAdded, quote.rewardSharesOut
        );
        return quote.rewardSharesOut;
    }

    function previewClaim(uint256 marketId, address user) public view returns (ClaimAmounts memory amounts) {
        USDTParimutuelV3Market memory market = factory.getMarket(marketId);
        if (market.state != USDTParimutuelV3MarketState.Resolved) revert MarketNotResolved();
        if (!market.hasWinner) revert NoWinner();
        amounts = _previewClaim(marketId, market, user);
    }

    function settleLosingCredit(uint256 marketId, address[] calldata users) external nonReentrant {
        USDTParimutuelV3Market memory market = factory.getMarket(marketId);
        if (market.state != USDTParimutuelV3MarketState.Resolved) revert MarketNotResolved();
        if (market.creditEventId == 0) revert MissingCreditEvent();

        SettlementSnapshot memory snapshot = _snapshotSettlement(marketId, market);

        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];
            if (losingCreditSettled[marketId][user]) revert AlreadySettled();

            uint256 losingCreditPrincipal = _totalCreditPrincipal(marketId, user, market.outcomeCount)
                - _creditPositions[marketId][user][market.winningOutcomeId].principal;
            if (losingCreditPrincipal == 0) {
                losingCreditSettled[marketId][user] = true;
                emit LosingCreditSettled(marketId, user, 0, 0);
                continue;
            }

            uint256 withdrawAmount;
            if (snapshot.realWinningRewardShares > 0 && snapshot.totalWinningRewardShares > 0) {
                withdrawAmount = Math.mulDiv(
                    losingCreditPrincipal, snapshot.realWinningRewardShares, snapshot.totalWinningRewardShares
                );
            }

            losingCreditSettled[marketId][user] = true;
            creditReserve.settleCreditPayoutAndWithdraw(
                market.creditEventId, user, losingCreditPrincipal, 0, address(vault), withdrawAmount
            );
            emit LosingCreditSettled(marketId, user, losingCreditPrincipal, withdrawAmount);
        }
    }

    function consumeClaim(uint256 marketId, address user)
        external
        onlyRole(REDEMPTION_ROLE)
        returns (ClaimAmounts memory amounts)
    {
        USDTParimutuelV3Market memory market = factory.getMarket(marketId);
        if (market.state != USDTParimutuelV3MarketState.Resolved) revert MarketNotResolved();
        if (!market.hasWinner) revert NoWinner();

        SettlementSnapshot memory snapshot = _snapshotSettlement(marketId, market);
        amounts = _previewClaim(marketId, market, user);
        if (amounts.realPayout == 0 && amounts.creditPayout == 0 && amounts.unsettledLosingCreditPrincipal == 0) {
            revert NothingToClaim();
        }
        if (amounts.unsettledLosingCreditPrincipal > 0) revert CreditLossNotSettled();

        USDTParimutuelV3Position memory creditWinningPosition =
            _creditPositions[marketId][user][market.winningOutcomeId];
        uint256 realBackingForCreditPayout;
        if (creditWinningPosition.rewardShares > 0 && snapshot.totalWinningRewardShares > 0) {
            realBackingForCreditPayout = Math.mulDiv(
                snapshot.realLosingPrincipal, creditWinningPosition.rewardShares, snapshot.totalWinningRewardShares
            );
        }
        marketTotalPrincipal[marketId] -= amounts.realPayout + amounts.creditPayout;

        for (uint8 outcomeId = 0; outcomeId < market.outcomeCount; outcomeId++) {
            USDTParimutuelV3Position memory realPosition = _realPositions[marketId][user][outcomeId];
            USDTParimutuelV3Position memory creditPosition = _creditPositions[marketId][user][outcomeId];
            USDTParimutuelV3OutcomePool storage pool = _outcomePools[marketId][outcomeId];
            pool.principal -= realPosition.principal + creditPosition.principal;
            pool.rewardShares -= realPosition.rewardShares + creditPosition.rewardShares;
            pool.realPrincipal -= realPosition.principal;
            pool.creditPrincipal -= creditPosition.principal;
            pool.realRewardShares -= realPosition.rewardShares;
            pool.creditRewardShares -= creditPosition.rewardShares;
            delete _realPositions[marketId][user][outcomeId];
            delete _creditPositions[marketId][user][outcomeId];
        }

        if (amounts.winningCreditPrincipal > 0 || amounts.creditPayout > 0) {
            if (realBackingForCreditPayout > 0) {
                vault.transferTo(address(creditReserve), realBackingForCreditPayout);
                creditReserve.fundFromMarketSettlement(market.creditEventId, realBackingForCreditPayout);
            }
            creditReserve.settleCreditPayout(
                market.creditEventId, user, amounts.winningCreditPrincipal, amounts.creditPayout
            );
        }

        emit Claimed(marketId, user, amounts.realPayout, amounts.creditPayout);
    }

    function previewRefund(uint256 marketId, address user, uint8[] calldata outcomeIds)
        external
        view
        returns (RefundAmounts memory amounts)
    {
        amounts = _previewRefund(marketId, user, outcomeIds);
    }

    function consumeRefund(uint256 marketId, address user, uint8[] calldata outcomeIds)
        external
        onlyRole(REDEMPTION_ROLE)
        returns (RefundAmounts memory amounts)
    {
        amounts = _previewRefund(marketId, user, outcomeIds);
        if (amounts.realRefund + amounts.creditRefund == 0) revert NothingToRefund();

        USDTParimutuelV3Market memory market = factory.getMarket(marketId);
        for (uint256 i = 0; i < outcomeIds.length; i++) {
            uint8 outcomeId = outcomeIds[i];
            USDTParimutuelV3Position memory realPosition = _realPositions[marketId][user][outcomeId];
            USDTParimutuelV3Position memory creditPosition = _creditPositions[marketId][user][outcomeId];
            USDTParimutuelV3OutcomePool storage pool = _outcomePools[marketId][outcomeId];
            pool.principal -= realPosition.principal + creditPosition.principal;
            pool.rewardShares -= realPosition.rewardShares + creditPosition.rewardShares;
            pool.realPrincipal -= realPosition.principal;
            pool.creditPrincipal -= creditPosition.principal;
            pool.realRewardShares -= realPosition.rewardShares;
            pool.creditRewardShares -= creditPosition.rewardShares;
            delete _realPositions[marketId][user][outcomeId];
            delete _creditPositions[marketId][user][outcomeId];
        }
        marketTotalPrincipal[marketId] -= amounts.realRefund + amounts.creditRefund;

        if (amounts.creditRefund > 0) {
            creditReserve.returnLockedCredit(market.creditEventId, user, amounts.creditRefund);
        }

        emit Refunded(marketId, user, amounts.realRefund, amounts.creditRefund);
    }

    function getOutcomePool(uint256 marketId, uint8 outcomeId)
        external
        view
        returns (USDTParimutuelV3OutcomePool memory)
    {
        return _outcomePools[marketId][outcomeId];
    }

    function getUserRealPosition(uint256 marketId, address user, uint8 outcomeId)
        external
        view
        returns (USDTParimutuelV3Position memory)
    {
        return _realPositions[marketId][user][outcomeId];
    }

    function getUserCreditPosition(uint256 marketId, address user, uint8 outcomeId)
        external
        view
        returns (USDTParimutuelV3Position memory)
    {
        return _creditPositions[marketId][user][outcomeId];
    }

    function _requireBuyableMarket(uint256 marketId) internal view returns (USDTParimutuelV3Market memory market) {
        if (factory.manager() != address(this)) revert ManagerNotRegistered();
        market = factory.getMarket(marketId);
        if (market.state != USDTParimutuelV3MarketState.Open) revert MarketNotOpen();
        if (block.timestamp >= market.tradingCloseTime) revert TradingClosed();
    }

    function _applyBuy(uint256 marketId, address user, uint8 outcomeId, BuyQuote memory quote, bool creditFunded)
        internal
    {
        USDTParimutuelV3OutcomePool storage pool = _outcomePools[marketId][outcomeId];
        pool.principal += quote.principalAdded;
        pool.rewardShares += quote.rewardSharesOut;
        marketTotalPrincipal[marketId] += quote.principalAdded;

        if (creditFunded) {
            pool.creditPrincipal += quote.principalAdded;
            pool.creditRewardShares += quote.rewardSharesOut;
            USDTParimutuelV3Position storage position = _creditPositions[marketId][user][outcomeId];
            position.principal += quote.principalAdded;
            position.rewardShares += quote.rewardSharesOut;
        } else {
            pool.realPrincipal += quote.principalAdded;
            pool.realRewardShares += quote.rewardSharesOut;
            USDTParimutuelV3Position storage position = _realPositions[marketId][user][outcomeId];
            position.principal += quote.principalAdded;
            position.rewardShares += quote.rewardSharesOut;
        }
    }

    function _previewClaim(uint256 marketId, USDTParimutuelV3Market memory market, address user)
        internal
        view
        returns (ClaimAmounts memory amounts)
    {
        uint8 winningOutcomeId = market.winningOutcomeId;
        USDTParimutuelV3Position memory realWinningPosition = _realPositions[marketId][user][winningOutcomeId];
        USDTParimutuelV3Position memory creditWinningPosition = _creditPositions[marketId][user][winningOutcomeId];
        USDTParimutuelV3OutcomePool memory winningPool = _outcomePools[marketId][winningOutcomeId];
        uint256 losingPrincipal = marketTotalPrincipal[marketId] - winningPool.principal;

        uint256 realRewardBonus;
        if (realWinningPosition.rewardShares > 0 && losingPrincipal > 0 && winningPool.rewardShares > 0) {
            realRewardBonus = Math.mulDiv(losingPrincipal, realWinningPosition.rewardShares, winningPool.rewardShares);
        }

        uint256 creditRewardBonus;
        if (creditWinningPosition.rewardShares > 0 && losingPrincipal > 0 && winningPool.rewardShares > 0) {
            creditRewardBonus =
                Math.mulDiv(losingPrincipal, creditWinningPosition.rewardShares, winningPool.rewardShares);
        }

        amounts.realPayout = realWinningPosition.principal + realRewardBonus;
        amounts.creditPayout = creditWinningPosition.principal + creditRewardBonus;
        amounts.winningCreditPrincipal = creditWinningPosition.principal;

        uint256 losingCreditPrincipal =
            _totalCreditPrincipal(marketId, user, market.outcomeCount) - creditWinningPosition.principal;
        if (!losingCreditSettled[marketId][user]) {
            amounts.unsettledLosingCreditPrincipal = losingCreditPrincipal;
        }
    }

    function _previewRefund(uint256 marketId, address user, uint8[] calldata outcomeIds)
        internal
        view
        returns (RefundAmounts memory amounts)
    {
        USDTParimutuelV3Market memory market = factory.getMarket(marketId);
        if (
            market.state != USDTParimutuelV3MarketState.Invalid && market.state != USDTParimutuelV3MarketState.Cancelled
        ) revert MarketNotRefundable();
        if (outcomeIds.length == 0) revert EmptyOutcomes();

        uint256 seenOutcomeMask;
        for (uint256 i = 0; i < outcomeIds.length; i++) {
            uint8 outcomeId = outcomeIds[i];
            if (outcomeId >= market.outcomeCount) revert InvalidOutcome();
            uint256 outcomeMask = uint256(1) << uint256(outcomeId);
            if ((seenOutcomeMask & outcomeMask) != 0) revert DuplicateOutcome();
            seenOutcomeMask |= outcomeMask;
            amounts.realRefund += _realPositions[marketId][user][outcomeId].principal;
            amounts.creditRefund += _creditPositions[marketId][user][outcomeId].principal;
        }
    }

    function _totalCreditPrincipal(uint256 marketId, address user, uint8 outcomeCount)
        internal
        view
        returns (uint256 totalCreditPrincipal)
    {
        for (uint8 outcomeId = 0; outcomeId < outcomeCount; outcomeId++) {
            totalCreditPrincipal += _creditPositions[marketId][user][outcomeId].principal;
        }
    }

    function _snapshotSettlement(uint256 marketId, USDTParimutuelV3Market memory market)
        internal
        returns (SettlementSnapshot memory snapshot)
    {
        snapshot = _settlementSnapshots[marketId];
        if (snapshot.initialized) {
            return snapshot;
        }

        USDTParimutuelV3OutcomePool memory winningPool = _outcomePools[marketId][market.winningOutcomeId];
        snapshot = SettlementSnapshot({
            initialized: true,
            totalWinningRewardShares: winningPool.rewardShares,
            realWinningRewardShares: winningPool.realRewardShares,
            realLosingPrincipal: _realLosingPrincipal(marketId, market.outcomeCount, market.winningOutcomeId)
        });
        _settlementSnapshots[marketId] = snapshot;
    }

    function _realLosingPrincipal(uint256 marketId, uint8 outcomeCount, uint8 winningOutcomeId)
        internal
        view
        returns (uint256 realLosingPrincipal)
    {
        for (uint8 outcomeId = 0; outcomeId < outcomeCount; outcomeId++) {
            if (outcomeId != winningOutcomeId) {
                realLosingPrincipal += _outcomePools[marketId][outcomeId].realPrincipal;
            }
        }
    }

    function _quoteBuy(uint256 currentPrincipal, uint256 amountIn, uint16 feeBps)
        internal
        pure
        returns (BuyQuote memory quote)
    {
        currentPrincipal;
        if (amountIn == 0) revert ZeroAmount();
        if (amountIn < MIN_BUY_AMOUNT_IN) revert BelowMinimumBuy();

        quote.feeAmount = Math.mulDiv(amountIn, feeBps, BPS_DENOMINATOR);
        quote.principalAdded = amountIn - quote.feeAmount;
        if (quote.principalAdded == 0) revert ZeroAmount();

        quote.rewardSharesOut = quote.principalAdded;
    }
}
