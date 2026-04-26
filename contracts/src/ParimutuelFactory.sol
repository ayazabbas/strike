// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./ParimutuelTypes.sol";

interface IParimutuelPoolManagerView {
    function marketTotalPrincipal(uint256 marketId) external view returns (uint256);
    function getOutcomePool(uint256 marketId, uint8 outcomeId) external view returns (ParimutuelOutcomePool memory);
}

/// @title ParimutuelFactory
/// @notice Separate lifecycle surface for multi-outcome parimutuel markets.
/// @dev This intentionally does not touch the live binary orderbook path.
contract ParimutuelFactory is AccessControl, ReentrancyGuard {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MARKET_CREATOR_ROLE = keccak256("MARKET_CREATOR_ROLE");
    bytes32 public constant RESOLVER_ROLE = keccak256("RESOLVER_ROLE");

    uint128 public constant INDEPENDENT_LOG_LIQUIDITY_MIN = 1_000e18;
    uint128 public constant INDEPENDENT_LOG_LIQUIDITY_RECOMMENDED = 40_000e18;
    uint128 public constant INDEPENDENT_LOG_LIQUIDITY_CONSERVATIVE = 100_000e18;
    uint128 public constant INDEPENDENT_LOG_LIQUIDITY_MAX = 1_000_000e18;

    uint256 public nextMarketId = 1;
    bool public paused;
    address public poolManager;

    mapping(uint256 => ParimutuelMarket) internal _markets;

    event ParimutuelMarketCreated(
        uint256 indexed marketId,
        address indexed creator,
        uint8 outcomeCount,
        ParimutuelResolverType resolverType,
        ParimutuelResolverType fallbackResolverType,
        ParimutuelCurveType curveType,
        uint64 closeTime,
        bytes32 metadataHash,
        string metadataURI
    );
    event ParimutuelMarketClosed(uint256 indexed marketId);
    event ParimutuelResolutionRequested(uint256 indexed marketId, ParimutuelResolverType resolverType);
    event ParimutuelFallbackToAdmin(uint256 indexed marketId, ParimutuelResolverType previousResolverType);
    event ParimutuelResolved(uint256 indexed marketId, uint8 indexed winningOutcomeId);
    event ParimutuelResolvedByResolver(
        uint256 indexed marketId, address indexed resolver, uint8 indexed winningOutcomeId
    );
    event ParimutuelInvalidated(uint256 indexed marketId);
    event ParimutuelCancelled(uint256 indexed marketId);
    event ParimutuelFactoryPaused(bool paused);
    event ParimutuelPoolManagerUpdated(address indexed poolManager);

    constructor(address admin) {
        require(admin != address(0), "ParimutuelFactory: zero admin");

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
    }

    function createMarket(ParimutuelMarketConfig calldata config)
        external
        onlyRole(MARKET_CREATOR_ROLE)
        nonReentrant
        returns (uint256 marketId)
    {
        require(!paused, "ParimutuelFactory: paused");
        require(config.closeTime > block.timestamp, "ParimutuelFactory: closeTime in past");
        require(config.outcomeCount >= 2 && config.outcomeCount <= 8, "ParimutuelFactory: invalid outcomeCount");
        require(config.metadataHash != bytes32(0), "ParimutuelFactory: zero metadataHash");
        require(config.feeBps <= 10_000, "ParimutuelFactory: invalid fee");
        require(
            config.fallbackResolverType == ParimutuelResolverType.Admin, "ParimutuelFactory: fallback must be admin"
        );
        _validateCurveConfig(config.curveType, config.curveParam);

        marketId = nextMarketId++;

        _markets[marketId] = ParimutuelMarket({
            marketId: marketId,
            creator: msg.sender,
            closeTime: config.closeTime,
            outcomeCount: config.outcomeCount,
            state: ParimutuelMarketState.Open,
            resolverType: config.resolverType,
            fallbackResolverType: config.fallbackResolverType,
            curveType: config.curveType,
            curveParam: config.curveParam,
            feeBps: config.feeBps,
            winningOutcomeId: 0,
            hasWinner: false,
            adminFallbackActivated: false,
            metadataHash: config.metadataHash,
            metadataURI: config.metadataURI,
            resolverConfig: config.resolverConfig
        });

        emit ParimutuelMarketCreated(
            marketId,
            msg.sender,
            config.outcomeCount,
            config.resolverType,
            config.fallbackResolverType,
            config.curveType,
            config.closeTime,
            config.metadataHash,
            config.metadataURI
        );
    }

    function closeMarket(uint256 marketId) external {
        ParimutuelMarket storage market = _requireMarket(marketId);
        require(market.state == ParimutuelMarketState.Open, "ParimutuelFactory: not open");
        require(block.timestamp >= market.closeTime, "ParimutuelFactory: not expired");

        market.state = ParimutuelMarketState.Closed;
        emit ParimutuelMarketClosed(marketId);
    }

    function requestResolution(uint256 marketId) external {
        _requireAdminOrResolver();
        ParimutuelMarket storage market = _requireMarket(marketId);
        require(market.state == ParimutuelMarketState.Closed, "ParimutuelFactory: not closed");

        market.state = ParimutuelMarketState.Resolving;
        emit ParimutuelResolutionRequested(marketId, currentResolverType(marketId));
    }

    function fallbackToAdmin(uint256 marketId) external onlyRole(ADMIN_ROLE) {
        ParimutuelMarket storage market = _requireMarket(marketId);
        require(market.resolverType != ParimutuelResolverType.Admin, "ParimutuelFactory: already admin");
        require(!market.adminFallbackActivated, "ParimutuelFactory: fallback already active");
        require(
            market.state == ParimutuelMarketState.Closed || market.state == ParimutuelMarketState.Resolving,
            "ParimutuelFactory: not fallbackable"
        );

        ParimutuelResolverType previousResolverType = market.resolverType;
        market.adminFallbackActivated = true;
        market.state = ParimutuelMarketState.Resolving;

        emit ParimutuelFallbackToAdmin(marketId, previousResolverType);
    }

    function resolveToWinner(uint256 marketId, uint8 winningOutcomeId) external onlyRole(ADMIN_ROLE) {
        ParimutuelMarket storage market = _requireMarket(marketId);
        require(
            market.state == ParimutuelMarketState.Closed || market.state == ParimutuelMarketState.Resolving,
            "ParimutuelFactory: not resolvable"
        );
        require(currentResolverType(marketId) == ParimutuelResolverType.Admin, "ParimutuelFactory: not admin resolver");
        require(winningOutcomeId < market.outcomeCount, "ParimutuelFactory: invalid winningOutcomeId");
        _requireResolvableWinningOutcome(marketId, winningOutcomeId);

        market.state = ParimutuelMarketState.Resolved;
        market.winningOutcomeId = winningOutcomeId;
        market.hasWinner = true;

        emit ParimutuelResolved(marketId, winningOutcomeId);
    }

    function resolveFromResolver(uint256 marketId, uint8 winningOutcomeId) external onlyRole(RESOLVER_ROLE) {
        ParimutuelMarket storage market = _requireMarket(marketId);
        require(market.state == ParimutuelMarketState.Resolving, "ParimutuelFactory: not resolving");
        require(currentResolverType(marketId) != ParimutuelResolverType.Admin, "ParimutuelFactory: admin resolver");
        require(winningOutcomeId < market.outcomeCount, "ParimutuelFactory: invalid winningOutcomeId");
        _requireResolvableWinningOutcome(marketId, winningOutcomeId);

        market.state = ParimutuelMarketState.Resolved;
        market.winningOutcomeId = winningOutcomeId;
        market.hasWinner = true;

        emit ParimutuelResolved(marketId, winningOutcomeId);
        emit ParimutuelResolvedByResolver(marketId, msg.sender, winningOutcomeId);
    }

    function resolveInvalid(uint256 marketId) external onlyRole(ADMIN_ROLE) {
        ParimutuelMarket storage market = _requireMarket(marketId);
        require(
            market.state == ParimutuelMarketState.Closed || market.state == ParimutuelMarketState.Resolving,
            "ParimutuelFactory: not invalidatable"
        );

        market.state = ParimutuelMarketState.Invalid;
        emit ParimutuelInvalidated(marketId);
    }

    function cancelMarket(uint256 marketId) external onlyRole(ADMIN_ROLE) {
        ParimutuelMarket storage market = _requireMarket(marketId);
        require(
            market.state == ParimutuelMarketState.Open || market.state == ParimutuelMarketState.Closed
                || market.state == ParimutuelMarketState.Resolving,
            "ParimutuelFactory: cannot cancel"
        );

        market.state = ParimutuelMarketState.Cancelled;
        emit ParimutuelCancelled(marketId);
    }

    function pauseFactory(bool paused_) external onlyRole(ADMIN_ROLE) {
        paused = paused_;
        emit ParimutuelFactoryPaused(paused_);
    }

    function setPoolManager(address poolManager_) external onlyRole(ADMIN_ROLE) {
        require(poolManager == address(0), "ParimutuelFactory: pool manager already set");
        require(poolManager_ != address(0), "ParimutuelFactory: zero pool manager");
        poolManager = poolManager_;
        emit ParimutuelPoolManagerUpdated(poolManager_);
    }

    function getMarket(uint256 marketId) external view returns (ParimutuelMarket memory) {
        return _requireMarket(marketId);
    }

    function getMarketState(uint256 marketId) external view returns (ParimutuelMarketState) {
        return _requireMarket(marketId).state;
    }

    function currentResolverType(uint256 marketId) public view returns (ParimutuelResolverType) {
        ParimutuelMarket storage market = _requireMarket(marketId);
        if (market.adminFallbackActivated) {
            return ParimutuelResolverType.Admin;
        }
        return market.resolverType;
    }

    function _requireResolvableWinningOutcome(uint256 marketId, uint8 winningOutcomeId) internal view {
        if (poolManager == address(0)) {
            return;
        }

        IParimutuelPoolManagerView manager = IParimutuelPoolManagerView(poolManager);
        uint256 totalPrincipal = manager.marketTotalPrincipal(marketId);
        if (totalPrincipal == 0) {
            return;
        }

        ParimutuelOutcomePool memory winningPool = manager.getOutcomePool(marketId, winningOutcomeId);
        require(winningPool.rewardShares > 0, "ParimutuelFactory: empty winning outcome");
    }

    function _validateCurveConfig(ParimutuelCurveType curveType, uint128 curveParam) internal pure {
        if (curveType == ParimutuelCurveType.Flat || curveType == ParimutuelCurveType.PiecewiseBand) {
            require(curveParam == 0, "ParimutuelFactory: invalid curve param");
            return;
        }

        if (curveType == ParimutuelCurveType.IndependentLog) {
            require(
                curveParam >= INDEPENDENT_LOG_LIQUIDITY_MIN && curveParam <= INDEPENDENT_LOG_LIQUIDITY_MAX,
                "ParimutuelFactory: invalid log liquidity"
            );
            return;
        }

        revert("ParimutuelFactory: invalid curve");
    }

    function _requireAdminOrResolver() internal view {
        require(
            hasRole(ADMIN_ROLE, msg.sender) || hasRole(RESOLVER_ROLE, msg.sender),
            "ParimutuelFactory: not admin or resolver"
        );
    }

    function _requireMarket(uint256 marketId) internal view returns (ParimutuelMarket storage market) {
        market = _markets[marketId];
        require(market.creator != address(0), "ParimutuelFactory: market not found");
    }
}
