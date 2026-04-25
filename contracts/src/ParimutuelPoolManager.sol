// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./ParimutuelFactory.sol";
import "./ParimutuelPricingLib.sol";
import "./ParimutuelTypes.sol";
import "./ParimutuelVault.sol";

/// @title ParimutuelPoolManager
/// @notice Pool accounting, quoting, purchases, claims, and refunds for parimutuel markets.
/// @dev This is intentionally separate from the live binary Vault/Redemption path.
contract ParimutuelPoolManager is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct BuyQuote {
        uint256 feeAmount;
        uint256 principalAdded;
        uint256 rewardSharesOut;
    }

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant REDEMPTION_ROLE = keccak256("REDEMPTION_ROLE");
    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint256 public constant MIN_BUY_AMOUNT_IN = 0.01e18;

    ParimutuelFactory public immutable factory;
    ParimutuelVault public immutable vault;
    IERC20 public immutable collateralToken;

    address public feeRecipient;
    uint256 public accruedFees;

    mapping(uint256 => mapping(uint8 => ParimutuelOutcomePool)) internal _outcomePools;
    mapping(uint256 => mapping(address => mapping(uint8 => ParimutuelPosition))) internal _positions;
    mapping(uint256 => uint256) public marketTotalPrincipal;

    mapping(uint256 => ParimutuelPiecewiseBand[]) internal _piecewiseBands;
    mapping(uint256 => uint32) public piecewiseTailRateBps;

    event PiecewiseBandsConfigured(uint256 indexed marketId, uint32 tailRateBps);
    event FeeRecipientUpdated(address indexed feeRecipient);
    event FeesWithdrawn(address indexed recipient, uint256 amount);
    event Bought(
        uint256 indexed marketId,
        address indexed user,
        uint8 indexed outcomeId,
        uint256 amountIn,
        uint256 feeAmount,
        uint256 principalAdded,
        uint256 rewardSharesOut
    );
    event Claimed(uint256 indexed marketId, address indexed user, uint256 payout);
    event Refunded(uint256 indexed marketId, address indexed user, uint256 refundAmount);

    constructor(address admin, address factory_, address vault_, address feeRecipient_) {
        require(admin != address(0), "ParimutuelPoolManager: zero admin");
        require(factory_ != address(0), "ParimutuelPoolManager: zero factory");
        require(vault_ != address(0), "ParimutuelPoolManager: zero vault");
        require(feeRecipient_ != address(0), "ParimutuelPoolManager: zero fee recipient");

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);

        factory = ParimutuelFactory(factory_);
        vault = ParimutuelVault(vault_);
        collateralToken = vault.collateralToken();
        feeRecipient = feeRecipient_;
    }

    function configurePiecewiseBands(uint256 marketId, ParimutuelPiecewiseBand[] calldata bands, uint32 tailRateBps)
        external
        onlyRole(ADMIN_ROLE)
    {
        require(factory.poolManager() == address(this), "ParimutuelPoolManager: manager not registered");
        ParimutuelMarket memory market = factory.getMarket(marketId);
        require(market.curveType == ParimutuelCurveType.PiecewiseBand, "ParimutuelPoolManager: market is not piecewise");
        require(marketTotalPrincipal[marketId] == 0, "ParimutuelPoolManager: market already funded");
        require(tailRateBps <= BPS_DENOMINATOR, "ParimutuelPoolManager: invalid tail rate");

        delete _piecewiseBands[marketId];
        uint256 previousUpperBound;
        for (uint256 i = 0; i < bands.length; i++) {
            require(bands[i].upperBound > previousUpperBound, "ParimutuelPoolManager: invalid band bounds");
            require(bands[i].rateBps <= BPS_DENOMINATOR, "ParimutuelPoolManager: invalid band rate");
            previousUpperBound = bands[i].upperBound;
            _piecewiseBands[marketId].push(bands[i]);
        }

        piecewiseTailRateBps[marketId] = tailRateBps;
        emit PiecewiseBandsConfigured(marketId, tailRateBps);
    }

    function setFeeRecipient(address feeRecipient_) external onlyRole(ADMIN_ROLE) {
        require(feeRecipient_ != address(0), "ParimutuelPoolManager: zero fee recipient");
        feeRecipient = feeRecipient_;
        emit FeeRecipientUpdated(feeRecipient_);
    }

    function withdrawFees(uint256 amount) external onlyRole(ADMIN_ROLE) nonReentrant {
        require(amount > 0, "ParimutuelPoolManager: zero amount");
        require(amount <= accruedFees, "ParimutuelPoolManager: insufficient fees");

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
        require(outcomeId < market.outcomeCount, "ParimutuelPoolManager: invalid outcomeId");

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
        ParimutuelMarket memory market = _requireBuyableMarket(marketId);
        require(buys.length > 0, "ParimutuelPoolManager: empty buys");

        uint256[] memory projectedPrincipalByOutcome = _loadProjectedPrincipalByOutcome(marketId, market.outcomeCount);
        uint256 totalAmountIn;
        uint256 totalFeeAmount;
        uint256 totalPrincipalAdded;

        BuyQuote[] memory quotes = new BuyQuote[](buys.length);

        for (uint256 i = 0; i < buys.length; i++) {
            _requireValidOutcome(market, buys[i].outcomeId);

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

        require(totalRewardSharesOut >= minTotalRewardSharesOut, "ParimutuelPoolManager: slippage");

        uint256 vaultBalanceBefore = collateralToken.balanceOf(address(vault));
        collateralToken.safeTransferFrom(msg.sender, address(vault), totalAmountIn);
        uint256 receivedAmount = collateralToken.balanceOf(address(vault)) - vaultBalanceBefore;
        require(receivedAmount == totalAmountIn, "ParimutuelPoolManager: collateral transfer shortfall");

        accruedFees += totalFeeAmount;
        marketTotalPrincipal[marketId] += totalPrincipalAdded;

        for (uint256 i = 0; i < buys.length; i++) {
            _applyBuy(marketId, msg.sender, buys[i], quotes[i]);
        }
    }

    function previewClaim(uint256 marketId, address user)
        public
        view
        returns (uint256 principalBack, uint256 rewardBonus, uint256 totalPayout)
    {
        ParimutuelMarket memory market = factory.getMarket(marketId);
        require(market.state == ParimutuelMarketState.Resolved, "ParimutuelPoolManager: market not resolved");
        require(market.hasWinner, "ParimutuelPoolManager: no winner");

        (principalBack, rewardBonus, totalPayout,) = _previewClaim(marketId, market, user);
    }

    function previewRefund(uint256 marketId, address user, uint8[] calldata outcomeIds)
        external
        view
        returns (uint256 refundAmount)
    {
        refundAmount = _previewRefund(marketId, user, outcomeIds);
    }

    function consumeClaim(uint256 marketId, address user) external onlyRole(REDEMPTION_ROLE) returns (uint256 payout) {
        ParimutuelMarket memory market = factory.getMarket(marketId);
        require(market.state == ParimutuelMarketState.Resolved, "ParimutuelPoolManager: market not resolved");
        require(market.hasWinner, "ParimutuelPoolManager: no winner");

        (uint256 principalBack, uint256 rewardBonus,, ParimutuelPosition memory winningPosition) =
            _previewClaim(marketId, market, user);
        payout = principalBack + rewardBonus;
        require(payout > 0, "ParimutuelPoolManager: nothing to claim");

        ParimutuelOutcomePool storage winningPool = _outcomePools[marketId][market.winningOutcomeId];
        winningPool.principal -= winningPosition.principal;
        winningPool.rewardShares -= winningPosition.rewardShares;
        marketTotalPrincipal[marketId] -= payout;

        for (uint8 outcomeId = 0; outcomeId < market.outcomeCount; outcomeId++) {
            delete _positions[marketId][user][outcomeId];
        }

        emit Claimed(marketId, user, payout);
    }

    function consumeRefund(uint256 marketId, address user, uint8[] calldata outcomeIds)
        external
        onlyRole(REDEMPTION_ROLE)
        returns (uint256 refundAmount)
    {
        refundAmount = _previewRefund(marketId, user, outcomeIds);
        require(refundAmount > 0, "ParimutuelPoolManager: nothing to refund");

        for (uint256 i = 0; i < outcomeIds.length; i++) {
            uint8 outcomeId = outcomeIds[i];
            ParimutuelPosition memory position = _positions[marketId][user][outcomeId];
            _outcomePools[marketId][outcomeId].principal -= position.principal;
            _outcomePools[marketId][outcomeId].rewardShares -= position.rewardShares;
            delete _positions[marketId][user][outcomeId];
        }
        marketTotalPrincipal[marketId] -= refundAmount;

        emit Refunded(marketId, user, refundAmount);
    }

    function getOutcomePool(uint256 marketId, uint8 outcomeId) external view returns (ParimutuelOutcomePool memory) {
        return _outcomePools[marketId][outcomeId];
    }

    function getUserPosition(uint256 marketId, address user, uint8 outcomeId)
        external
        view
        returns (ParimutuelPosition memory)
    {
        return _positions[marketId][user][outcomeId];
    }

    function getPiecewiseBands(uint256 marketId) external view returns (ParimutuelPiecewiseBand[] memory bands) {
        uint256 len = _piecewiseBands[marketId].length;
        bands = new ParimutuelPiecewiseBand[](len);
        for (uint256 i = 0; i < len; i++) {
            bands[i] = _piecewiseBands[marketId][i];
        }
    }

    function _requireBuyableMarket(uint256 marketId) internal view returns (ParimutuelMarket memory market) {
        require(factory.poolManager() == address(this), "ParimutuelPoolManager: manager not registered");
        market = factory.getMarket(marketId);
        require(market.state == ParimutuelMarketState.Open, "ParimutuelPoolManager: market not open");
        require(block.timestamp < market.closeTime, "ParimutuelPoolManager: market expired");
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
        require(outcomeId < market.outcomeCount, "ParimutuelPoolManager: invalid outcomeId");
    }

    function _applyBuy(uint256 marketId, address user, ParimutuelBuyParam memory buyParam, BuyQuote memory quote)
        internal
    {
        _outcomePools[marketId][buyParam.outcomeId].principal += quote.principalAdded;
        _outcomePools[marketId][buyParam.outcomeId].rewardShares += quote.rewardSharesOut;
        _positions[marketId][user][buyParam.outcomeId].principal += quote.principalAdded;
        _positions[marketId][user][buyParam.outcomeId].rewardShares += quote.rewardSharesOut;

        emit Bought(
            marketId,
            user,
            buyParam.outcomeId,
            buyParam.amountIn,
            quote.feeAmount,
            quote.principalAdded,
            quote.rewardSharesOut
        );
    }

    function _previewClaim(uint256 marketId, ParimutuelMarket memory market, address user)
        internal
        view
        returns (
            uint256 principalBack,
            uint256 rewardBonus,
            uint256 totalPayout,
            ParimutuelPosition memory winningPosition
        )
    {
        uint8 winningOutcomeId = market.winningOutcomeId;
        winningPosition = _positions[marketId][user][winningOutcomeId];
        principalBack = winningPosition.principal;

        if (winningPosition.rewardShares > 0) {
            uint256 losingPrincipal =
                marketTotalPrincipal[marketId] - _outcomePools[marketId][winningOutcomeId].principal;
            uint256 totalWinningRewardShares = _outcomePools[marketId][winningOutcomeId].rewardShares;
            if (losingPrincipal > 0 && totalWinningRewardShares > 0) {
                rewardBonus = Math.mulDiv(losingPrincipal, winningPosition.rewardShares, totalWinningRewardShares);
            }
        }

        totalPayout = principalBack + rewardBonus;
    }

    function _previewRefund(uint256 marketId, address user, uint8[] calldata outcomeIds)
        internal
        view
        returns (uint256 refundAmount)
    {
        ParimutuelMarket memory market = factory.getMarket(marketId);
        require(
            market.state == ParimutuelMarketState.Invalid || market.state == ParimutuelMarketState.Cancelled,
            "ParimutuelPoolManager: market not refundable"
        );
        require(outcomeIds.length > 0, "ParimutuelPoolManager: empty outcomes");

        uint256 seenOutcomeMask;
        for (uint256 i = 0; i < outcomeIds.length; i++) {
            uint8 outcomeId = outcomeIds[i];
            _requireValidOutcome(market, outcomeId);
            uint256 outcomeMask = uint256(1) << uint256(outcomeId);
            require((seenOutcomeMask & outcomeMask) == 0, "ParimutuelPoolManager: duplicate outcomeId");
            seenOutcomeMask |= outcomeMask;
            refundAmount += _positions[marketId][user][outcomeId].principal;
        }
    }

    function _quoteBuyAtPrincipal(
        uint256 marketId,
        ParimutuelMarket memory market,
        uint256 currentPrincipal,
        uint256 amountIn
    ) internal view returns (BuyQuote memory quote) {
        require(amountIn > 0, "ParimutuelPoolManager: zero amountIn");
        require(amountIn >= MIN_BUY_AMOUNT_IN, "ParimutuelPoolManager: below min buy");

        quote.feeAmount = Math.mulDiv(amountIn, market.feeBps, BPS_DENOMINATOR);
        quote.principalAdded = amountIn - quote.feeAmount;
        require(quote.principalAdded > 0, "ParimutuelPoolManager: zero principal");

        quote.rewardSharesOut = _quoteRewardShares(marketId, market, currentPrincipal, quote.principalAdded);
        require(quote.rewardSharesOut > 0, "ParimutuelPoolManager: zero reward shares");
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
            require(
                len > 0 || piecewiseTailRateBps[marketId] > 0, "ParimutuelPoolManager: piecewise bands not configured"
            );

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

        revert("ParimutuelPoolManager: curve not implemented");
    }
}
