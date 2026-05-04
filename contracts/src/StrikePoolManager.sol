// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./ParimutuelPricingLib.sol";
import "./ParimutuelTypes.sol";
import "./StrikeCreditReserve.sol";
import "./StrikeParimutuelFactory.sol";
import "./StrikePoolVault.sol";

/// @title StrikePoolManager
/// @notice STRIKE-denominated pool accounting with separate real and credit-funded positions.
contract StrikePoolManager is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct BuyQuote {
        uint256 feeAmount;
        uint256 principalAdded;
        uint256 rewardSharesOut;
    }

    struct ClaimAmounts {
        uint256 realPayout;
        uint256 creditPrincipal;
        uint256 creditProfit;
        uint256 creditLost;
    }

    struct RefundAmounts {
        uint256 realRefund;
        uint256 creditRefund;
    }

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant REDEMPTION_ROLE = keccak256("REDEMPTION_ROLE");
    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint256 public constant MIN_BUY_AMOUNT_IN = 0.01e18;

    StrikeParimutuelFactory public immutable factory;
    StrikePoolVault public immutable vault;
    StrikeCreditReserve public immutable creditReserve;
    IERC20 public immutable strikeToken;

    address public feeRecipient;
    uint256 public accruedFees;

    mapping(uint256 => mapping(uint8 => ParimutuelOutcomePool)) internal _outcomePools;
    mapping(uint256 => mapping(address => mapping(uint8 => ParimutuelPosition))) internal _realPositions;
    mapping(uint256 => mapping(address => mapping(uint8 => ParimutuelPosition))) internal _creditPositions;
    mapping(uint256 => uint256) public marketTotalPrincipal;
    mapping(uint256 => uint256) public marketCreditEventId;
    mapping(uint256 => bool) public creditMarketCleared;

    mapping(uint256 => ParimutuelPiecewiseBand[]) internal _piecewiseBands;
    mapping(uint256 => uint32) public piecewiseTailRateBps;

    event PiecewiseBandsConfigured(uint256 indexed marketId, uint32 tailRateBps);
    event FeeRecipientUpdated(address indexed feeRecipient);
    event FeesWithdrawn(address indexed recipient, uint256 amount);
    event Bought(
        uint256 indexed marketId,
        address indexed user,
        uint8 indexed outcomeId,
        bool creditFunded,
        uint256 amountIn,
        uint256 feeAmount,
        uint256 principalAdded,
        uint256 rewardSharesOut
    );
    event Claimed(
        uint256 indexed marketId,
        address indexed user,
        uint256 realPayout,
        uint256 creditPrincipal,
        uint256 creditProfit,
        uint256 creditLost
    );
    event Refunded(uint256 indexed marketId, address indexed user, uint256 realRefund, uint256 creditRefund);
    event CreditMarketCleared(uint256 indexed marketId, uint256 indexed eventId);

    constructor(address admin, address factory_, address vault_, address creditReserve_, address feeRecipient_) {
        require(admin != address(0), "StrikePoolManager: zero admin");
        require(factory_ != address(0), "StrikePoolManager: zero factory");
        require(vault_ != address(0), "StrikePoolManager: zero vault");
        require(creditReserve_ != address(0), "StrikePoolManager: zero credit reserve");
        require(feeRecipient_ != address(0), "StrikePoolManager: zero fee recipient");

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);

        factory = StrikeParimutuelFactory(factory_);
        vault = StrikePoolVault(vault_);
        creditReserve = StrikeCreditReserve(creditReserve_);
        strikeToken = vault.strikeToken();
        feeRecipient = feeRecipient_;
    }

    function configurePiecewiseBands(uint256 marketId, ParimutuelPiecewiseBand[] calldata bands, uint32 tailRateBps)
        external
        onlyRole(ADMIN_ROLE)
    {
        require(factory.poolManager() == address(this), "StrikePoolManager: manager not registered");
        ParimutuelMarket memory market = factory.getMarket(marketId);
        require(market.curveType == ParimutuelCurveType.PiecewiseBand, "StrikePoolManager: market is not piecewise");
        require(marketTotalPrincipal[marketId] == 0, "StrikePoolManager: market already funded");
        require(tailRateBps <= BPS_DENOMINATOR, "StrikePoolManager: invalid tail rate");

        delete _piecewiseBands[marketId];
        uint256 previousUpperBound;
        for (uint256 i = 0; i < bands.length; i++) {
            require(bands[i].upperBound > previousUpperBound, "StrikePoolManager: invalid band bounds");
            require(bands[i].rateBps <= BPS_DENOMINATOR, "StrikePoolManager: invalid band rate");
            previousUpperBound = bands[i].upperBound;
            _piecewiseBands[marketId].push(bands[i]);
        }

        piecewiseTailRateBps[marketId] = tailRateBps;
        emit PiecewiseBandsConfigured(marketId, tailRateBps);
    }

    function setFeeRecipient(address feeRecipient_) external onlyRole(ADMIN_ROLE) {
        require(feeRecipient_ != address(0), "StrikePoolManager: zero fee recipient");
        feeRecipient = feeRecipient_;
        emit FeeRecipientUpdated(feeRecipient_);
    }

    function withdrawFees(uint256 amount) external onlyRole(ADMIN_ROLE) nonReentrant {
        require(amount > 0, "StrikePoolManager: zero amount");
        require(amount <= accruedFees, "StrikePoolManager: insufficient fees");

        accruedFees -= amount;
        vault.transferTo(feeRecipient, amount);
        emit FeesWithdrawn(feeRecipient, amount);
    }

    function quoteBuy(uint256 marketId, uint8 outcomeId, uint256 amountIn)
        public
        view
        returns (uint256 feeAmount, uint256 principalAdded, uint256 rewardSharesOut)
    {
        ParimutuelMarket memory market = _requireBuyableMarket(marketId);
        require(outcomeId < market.outcomeCount, "StrikePoolManager: invalid outcomeId");

        BuyQuote memory quote =
            _quoteBuyAtPrincipal(marketId, market, _outcomePools[marketId][outcomeId].principal, amountIn);

        return (quote.feeAmount, quote.principalAdded, quote.rewardSharesOut);
    }

    function quoteBuyMany(uint256 marketId, ParimutuelBuyParam[] calldata buys)
        external
        view
        returns (
            uint256 totalAmountIn,
            uint256 totalFeeAmount,
            uint256 totalPrincipalAdded,
            uint256 totalRewardSharesOut,
            uint256[] memory rewardSharesByBuy
        )
    {
        ParimutuelMarket memory market = _requireBuyableMarket(marketId);
        uint256[] memory projectedPrincipalByOutcome = _loadProjectedPrincipalByOutcome(marketId, market.outcomeCount);
        rewardSharesByBuy = new uint256[](buys.length);

        for (uint256 i = 0; i < buys.length; i++) {
            _requireValidOutcome(market, buys[i].outcomeId);
            BuyQuote memory quote = _quoteBuyAtPrincipal(
                marketId, market, projectedPrincipalByOutcome[buys[i].outcomeId], buys[i].amountIn
            );

            rewardSharesByBuy[i] = quote.rewardSharesOut;
            projectedPrincipalByOutcome[buys[i].outcomeId] += quote.principalAdded;
            totalAmountIn += buys[i].amountIn;
            totalFeeAmount += quote.feeAmount;
            totalPrincipalAdded += quote.principalAdded;
            totalRewardSharesOut += quote.rewardSharesOut;
        }
    }

    function buy(uint256 marketId, uint8 outcomeId, uint256 amountIn, uint256 minRewardSharesOut)
        external
        returns (uint256 rewardSharesOut)
    {
        ParimutuelBuyParam[] memory buys = new ParimutuelBuyParam[](1);
        buys[0] = ParimutuelBuyParam({outcomeId: outcomeId, amountIn: amountIn});
        rewardSharesOut = buyMany(marketId, buys, minRewardSharesOut);
    }

    function buyMany(uint256 marketId, ParimutuelBuyParam[] memory buys, uint256 minTotalRewardSharesOut)
        public
        nonReentrant
        returns (uint256 totalRewardSharesOut)
    {
        (uint256 totalAmountIn, uint256 totalFeeAmount, uint256 totalPrincipalAdded, BuyQuote[] memory quotes) =
            _prepareBuy(marketId, msg.sender, buys, minTotalRewardSharesOut, false);

        uint256 vaultBalanceBefore = strikeToken.balanceOf(address(vault));
        strikeToken.safeTransferFrom(msg.sender, address(vault), totalAmountIn);
        uint256 receivedAmount = strikeToken.balanceOf(address(vault)) - vaultBalanceBefore;
        require(receivedAmount == totalAmountIn, "StrikePoolManager: strike transfer shortfall");

        accruedFees += totalFeeAmount;
        marketTotalPrincipal[marketId] += totalPrincipalAdded;

        for (uint256 i = 0; i < buys.length; i++) {
            totalRewardSharesOut += quotes[i].rewardSharesOut;
            _applyBuy(marketId, msg.sender, buys[i], quotes[i], false);
        }
    }

    function buyWithCredit(uint256 eventId, uint256 marketId, ParimutuelBuyParam[] memory buys, uint256 minTotalRewardSharesOut)
        external
        nonReentrant
        returns (uint256 totalRewardSharesOut)
    {
        _registerOrRequireCreditMarket(eventId, marketId);

        (uint256 totalAmountIn, uint256 totalFeeAmount, uint256 totalPrincipalAdded, BuyQuote[] memory quotes) =
            _prepareBuy(marketId, msg.sender, buys, minTotalRewardSharesOut, true);

        uint256 vaultBalanceBefore = strikeToken.balanceOf(address(vault));
        creditReserve.spendCredit(eventId, msg.sender, address(vault), totalAmountIn);
        uint256 receivedAmount = strikeToken.balanceOf(address(vault)) - vaultBalanceBefore;
        require(receivedAmount == totalAmountIn, "StrikePoolManager: credit transfer shortfall");
        if (totalFeeAmount > 0) {
            creditReserve.settleCredit(eventId, msg.sender, totalFeeAmount, 0);
        }

        accruedFees += totalFeeAmount;
        marketTotalPrincipal[marketId] += totalPrincipalAdded;

        for (uint256 i = 0; i < buys.length; i++) {
            totalRewardSharesOut += quotes[i].rewardSharesOut;
            _applyBuy(marketId, msg.sender, buys[i], quotes[i], true);
        }
    }

    function clearCreditMarket(uint256 marketId) external {
        uint256 eventId = marketCreditEventId[marketId];
        require(eventId != 0, "StrikePoolManager: not credit market");
        require(!creditMarketCleared[marketId], "StrikePoolManager: credit market cleared");

        ParimutuelMarket memory market = factory.getMarket(marketId);
        require(
            market.state == ParimutuelMarketState.Resolved || market.state == ParimutuelMarketState.Invalid
                || market.state == ParimutuelMarketState.Cancelled,
            "StrikePoolManager: market unresolved"
        );

        creditMarketCleared[marketId] = true;
        creditReserve.clearCreditMarket(eventId, marketId);
        emit CreditMarketCleared(marketId, eventId);
    }

    function previewClaim(uint256 marketId, address user) public view returns (ClaimAmounts memory amounts) {
        ParimutuelMarket memory market = factory.getMarket(marketId);
        require(market.state == ParimutuelMarketState.Resolved, "StrikePoolManager: market not resolved");
        require(market.hasWinner, "StrikePoolManager: no winner");

        amounts = _previewClaim(marketId, market, user);
    }

    function previewRefund(uint256 marketId, address user, uint8[] calldata outcomeIds)
        external
        view
        returns (RefundAmounts memory amounts)
    {
        amounts = _previewRefund(marketId, user, outcomeIds);
    }

    function consumeClaim(uint256 marketId, address user)
        external
        onlyRole(REDEMPTION_ROLE)
        returns (ClaimAmounts memory amounts)
    {
        ParimutuelMarket memory market = factory.getMarket(marketId);
        require(market.state == ParimutuelMarketState.Resolved, "StrikePoolManager: market not resolved");
        require(market.hasWinner, "StrikePoolManager: no winner");

        amounts = _previewClaim(marketId, market, user);
        uint256 totalPayout = amounts.realPayout + amounts.creditPrincipal + amounts.creditProfit;
        require(totalPayout > 0 || amounts.creditLost > 0, "StrikePoolManager: nothing to claim");

        ParimutuelPosition memory realWinningPosition = _realPositions[marketId][user][market.winningOutcomeId];
        ParimutuelPosition memory creditWinningPosition = _creditPositions[marketId][user][market.winningOutcomeId];
        ParimutuelOutcomePool storage winningPool = _outcomePools[marketId][market.winningOutcomeId];
        winningPool.principal -= realWinningPosition.principal + creditWinningPosition.principal;
        winningPool.rewardShares -= realWinningPosition.rewardShares + creditWinningPosition.rewardShares;
        marketTotalPrincipal[marketId] -= totalPayout;

        for (uint8 outcomeId = 0; outcomeId < market.outcomeCount; outcomeId++) {
            delete _realPositions[marketId][user][outcomeId];
            delete _creditPositions[marketId][user][outcomeId];
        }

        emit Claimed(marketId, user, amounts.realPayout, amounts.creditPrincipal, amounts.creditProfit, amounts.creditLost);
    }

    function consumeRefund(uint256 marketId, address user, uint8[] calldata outcomeIds)
        external
        onlyRole(REDEMPTION_ROLE)
        returns (RefundAmounts memory amounts)
    {
        amounts = _previewRefund(marketId, user, outcomeIds);
        uint256 totalRefund = amounts.realRefund + amounts.creditRefund;
        require(totalRefund > 0, "StrikePoolManager: nothing to refund");

        for (uint256 i = 0; i < outcomeIds.length; i++) {
            uint8 outcomeId = outcomeIds[i];
            ParimutuelPosition memory realPosition = _realPositions[marketId][user][outcomeId];
            ParimutuelPosition memory creditPosition = _creditPositions[marketId][user][outcomeId];
            _outcomePools[marketId][outcomeId].principal -= realPosition.principal + creditPosition.principal;
            _outcomePools[marketId][outcomeId].rewardShares -= realPosition.rewardShares + creditPosition.rewardShares;
            delete _realPositions[marketId][user][outcomeId];
            delete _creditPositions[marketId][user][outcomeId];
        }
        marketTotalPrincipal[marketId] -= totalRefund;

        emit Refunded(marketId, user, amounts.realRefund, amounts.creditRefund);
    }

    function getOutcomePool(uint256 marketId, uint8 outcomeId) external view returns (ParimutuelOutcomePool memory) {
        return _outcomePools[marketId][outcomeId];
    }

    function getUserRealPosition(uint256 marketId, address user, uint8 outcomeId)
        external
        view
        returns (ParimutuelPosition memory)
    {
        return _realPositions[marketId][user][outcomeId];
    }

    function getUserCreditPosition(uint256 marketId, address user, uint8 outcomeId)
        external
        view
        returns (ParimutuelPosition memory)
    {
        return _creditPositions[marketId][user][outcomeId];
    }

    function getPiecewiseBands(uint256 marketId) external view returns (ParimutuelPiecewiseBand[] memory bands) {
        uint256 len = _piecewiseBands[marketId].length;
        bands = new ParimutuelPiecewiseBand[](len);
        for (uint256 i = 0; i < len; i++) {
            bands[i] = _piecewiseBands[marketId][i];
        }
    }

    function _prepareBuy(
        uint256 marketId,
        address user,
        ParimutuelBuyParam[] memory buys,
        uint256 minTotalRewardSharesOut,
        bool creditFunded
    )
        internal
        view
        returns (uint256 totalAmountIn, uint256 totalFeeAmount, uint256 totalPrincipalAdded, BuyQuote[] memory quotes)
    {
        ParimutuelMarket memory market = _requireBuyableMarket(marketId);
        require(buys.length > 0, "StrikePoolManager: empty buys");

        uint256[] memory projectedPrincipalByOutcome = _loadProjectedPrincipalByOutcome(marketId, market.outcomeCount);
        uint256 totalRewardSharesOut;
        quotes = new BuyQuote[](buys.length);

        for (uint256 i = 0; i < buys.length; i++) {
            _requireValidOutcome(market, buys[i].outcomeId);
            _requireNoMixedFunding(marketId, user, market.outcomeCount, creditFunded);

            BuyQuote memory quote = _quoteBuyAtPrincipal(
                marketId, market, projectedPrincipalByOutcome[buys[i].outcomeId], buys[i].amountIn
            );

            quotes[i] = quote;
            projectedPrincipalByOutcome[buys[i].outcomeId] += quote.principalAdded;
            totalAmountIn += buys[i].amountIn;
            totalFeeAmount += quote.feeAmount;
            totalPrincipalAdded += quote.principalAdded;
            totalRewardSharesOut += quote.rewardSharesOut;
        }

        require(totalRewardSharesOut >= minTotalRewardSharesOut, "StrikePoolManager: slippage");
    }

    function _requireBuyableMarket(uint256 marketId) internal view returns (ParimutuelMarket memory market) {
        require(factory.poolManager() == address(this), "StrikePoolManager: manager not registered");
        market = factory.getMarket(marketId);
        require(market.state == ParimutuelMarketState.Open, "StrikePoolManager: market not open");
        require(block.timestamp < market.tradingCloseTime, "StrikePoolManager: trading closed");
    }

    function _loadProjectedPrincipalByOutcome(uint256 marketId, uint8 outcomeCount)
        internal
        view
        returns (uint256[] memory projectedPrincipalByOutcome)
    {
        projectedPrincipalByOutcome = new uint256[](outcomeCount);
        for (uint8 outcomeId = 0; outcomeId < outcomeCount; outcomeId++) {
            projectedPrincipalByOutcome[outcomeId] = _outcomePools[marketId][outcomeId].principal;
        }
    }

    function _requireValidOutcome(ParimutuelMarket memory market, uint8 outcomeId) internal pure {
        require(outcomeId < market.outcomeCount, "StrikePoolManager: invalid outcomeId");
    }

    function _requireNoMixedFunding(uint256 marketId, address user, uint8 outcomeCount, bool creditFunded)
        internal
        view
    {
        // MVP supports real and credit liquidity in the same market, but blocks one user from mixing sources
        // in one market. Per-user mixed funding needs pro-rata source accounting across all outcomes and claims.
        for (uint8 outcomeId = 0; outcomeId < outcomeCount; outcomeId++) {
            if (creditFunded) {
                require(
                    _realPositions[marketId][user][outcomeId].principal == 0,
                    "StrikePoolManager: mixed funding blocked"
                );
            } else {
                require(
                    _creditPositions[marketId][user][outcomeId].principal == 0,
                    "StrikePoolManager: mixed funding blocked"
                );
            }
        }
    }

    function _registerOrRequireCreditMarket(uint256 eventId, uint256 marketId) internal {
        require(eventId != 0, "StrikePoolManager: zero eventId");
        uint256 currentEventId = marketCreditEventId[marketId];
        if (currentEventId == 0) {
            marketCreditEventId[marketId] = eventId;
            creditReserve.registerCreditMarket(eventId, marketId);
        } else {
            require(currentEventId == eventId, "StrikePoolManager: wrong credit event");
            require(!creditMarketCleared[marketId], "StrikePoolManager: credit market cleared");
        }
    }

    function _applyBuy(
        uint256 marketId,
        address user,
        ParimutuelBuyParam memory buyParam,
        BuyQuote memory quote,
        bool creditFunded
    ) internal {
        _outcomePools[marketId][buyParam.outcomeId].principal += quote.principalAdded;
        _outcomePools[marketId][buyParam.outcomeId].rewardShares += quote.rewardSharesOut;

        ParimutuelPosition storage position = creditFunded
            ? _creditPositions[marketId][user][buyParam.outcomeId]
            : _realPositions[marketId][user][buyParam.outcomeId];
        position.principal += quote.principalAdded;
        position.rewardShares += quote.rewardSharesOut;

        emit Bought(
            marketId,
            user,
            buyParam.outcomeId,
            creditFunded,
            buyParam.amountIn,
            quote.feeAmount,
            quote.principalAdded,
            quote.rewardSharesOut
        );
    }

    function _previewClaim(uint256 marketId, ParimutuelMarket memory market, address user)
        internal
        view
        returns (ClaimAmounts memory amounts)
    {
        uint8 winningOutcomeId = market.winningOutcomeId;
        ParimutuelPosition memory realWinningPosition = _realPositions[marketId][user][winningOutcomeId];
        ParimutuelPosition memory creditWinningPosition = _creditPositions[marketId][user][winningOutcomeId];

        uint256 totalCreditPrincipal;
        for (uint8 outcomeId = 0; outcomeId < market.outcomeCount; outcomeId++) {
            totalCreditPrincipal += _creditPositions[marketId][user][outcomeId].principal;
        }

        uint256 totalWinningRewardShares = _outcomePools[marketId][winningOutcomeId].rewardShares;
        uint256 losingPrincipal = marketTotalPrincipal[marketId] - _outcomePools[marketId][winningOutcomeId].principal;

        uint256 realRewardBonus;
        if (realWinningPosition.rewardShares > 0 && losingPrincipal > 0 && totalWinningRewardShares > 0) {
            realRewardBonus = Math.mulDiv(losingPrincipal, realWinningPosition.rewardShares, totalWinningRewardShares);
        }

        uint256 creditRewardBonus;
        if (creditWinningPosition.rewardShares > 0 && losingPrincipal > 0 && totalWinningRewardShares > 0) {
            creditRewardBonus =
                Math.mulDiv(losingPrincipal, creditWinningPosition.rewardShares, totalWinningRewardShares);
        }

        amounts.realPayout = realWinningPosition.principal + realRewardBonus;
        amounts.creditPrincipal = creditWinningPosition.principal;
        amounts.creditProfit = creditRewardBonus;
        amounts.creditLost = totalCreditPrincipal - creditWinningPosition.principal;
    }

    function _previewRefund(uint256 marketId, address user, uint8[] calldata outcomeIds)
        internal
        view
        returns (RefundAmounts memory amounts)
    {
        ParimutuelMarket memory market = factory.getMarket(marketId);
        require(
            market.state == ParimutuelMarketState.Invalid || market.state == ParimutuelMarketState.Cancelled,
            "StrikePoolManager: market not refundable"
        );
        require(outcomeIds.length > 0, "StrikePoolManager: empty outcomes");

        uint256 seenOutcomeMask;
        for (uint256 i = 0; i < outcomeIds.length; i++) {
            uint8 outcomeId = outcomeIds[i];
            _requireValidOutcome(market, outcomeId);
            uint256 outcomeMask = uint256(1) << uint256(outcomeId);
            require((seenOutcomeMask & outcomeMask) == 0, "StrikePoolManager: duplicate outcomeId");
            seenOutcomeMask |= outcomeMask;
            amounts.realRefund += _realPositions[marketId][user][outcomeId].principal;
            amounts.creditRefund += _creditPositions[marketId][user][outcomeId].principal;
        }
    }

    function _quoteBuyAtPrincipal(
        uint256 marketId,
        ParimutuelMarket memory market,
        uint256 currentPrincipal,
        uint256 amountIn
    ) internal view returns (BuyQuote memory quote) {
        require(amountIn > 0, "StrikePoolManager: zero amountIn");
        require(amountIn >= MIN_BUY_AMOUNT_IN, "StrikePoolManager: below min buy");

        quote.feeAmount = Math.mulDiv(amountIn, market.feeBps, BPS_DENOMINATOR);
        quote.principalAdded = amountIn - quote.feeAmount;
        require(quote.principalAdded > 0, "StrikePoolManager: zero principal");

        quote.rewardSharesOut = _quoteRewardShares(marketId, market, currentPrincipal, quote.principalAdded);
        require(quote.rewardSharesOut > 0, "StrikePoolManager: zero reward shares");
    }

    function _quoteRewardShares(
        uint256 marketId,
        ParimutuelMarket memory market,
        uint256 currentPrincipal,
        uint256 principalAdded
    ) internal view returns (uint256 rewardSharesOut) {
        if (market.curveType == ParimutuelCurveType.Flat) {
            return ParimutuelPricingLib.quoteFlat(principalAdded);
        }

        if (market.curveType == ParimutuelCurveType.PiecewiseBand) {
            uint256 len = _piecewiseBands[marketId].length;
            require(len > 0 || piecewiseTailRateBps[marketId] > 0, "StrikePoolManager: piecewise bands not configured");

            ParimutuelPiecewiseBand[] memory bands = new ParimutuelPiecewiseBand[](len);
            for (uint256 i = 0; i < len; i++) {
                bands[i] = _piecewiseBands[marketId][i];
            }

            return ParimutuelPricingLib.quotePiecewise(
                currentPrincipal, principalAdded, bands, piecewiseTailRateBps[marketId]
            );
        }

        if (market.curveType == ParimutuelCurveType.IndependentLog) {
            return ParimutuelPricingLib.quoteIndependentLog(currentPrincipal, principalAdded, market.curveParam);
        }

        revert("StrikePoolManager: curve not implemented");
    }
}
