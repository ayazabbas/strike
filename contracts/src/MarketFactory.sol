// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./ITypes.sol";
import "./OrderBook.sol";
import "./OutcomeToken.sol";

interface IAIResolver {
    function depositFee(uint256 marketId, string calldata prompt, uint8 modelId) external payable;
}

/// @title MarketFactory
/// @notice Creates and manages binary outcome markets for the Strike CLOB protocol.
///         Market creation is permissioned via MARKET_CREATOR_ROLE.
///         Tracks market lifecycle: Open → Closed → Resolving → Resolved / Cancelled.
contract MarketFactory is AccessControl, ReentrancyGuard {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MARKET_CREATOR_ROLE = keccak256("MARKET_CREATOR_ROLE");

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    OrderBook public immutable orderBook;
    OutcomeToken public immutable outcomeToken;

    uint256 public nextFactoryMarketId = 1;
    bool public paused;

    /// @notice Default market parameters
    uint256 public defaultBatchInterval = 60; // seconds
    uint128 public defaultMinLots = 1;

    /// @notice AI resolver contract for AI-resolved markets
    address public aiResolver;

    /// @notice Market metadata stored by the factory
    struct MarketMeta {
        bytes32 priceId;       // Pyth price feed ID
        int64 strikePrice;     // resolution threshold: price >= strikePrice → YES wins
        uint256 expiryTime;    // when the market closes
        address creator;       // who created the market
        MarketState state;     // lifecycle state
        bool outcomeYes;       // true = YES won (only valid in Resolved state)
        int64 settlementPrice; // price at resolution
        uint256 orderBookMarketId; // ID in the OrderBook
        bool useInternalPositions; // true = internal position tracking (no ERC1155)
        bool isAIMarket;           // true = resolved by AI oracle
    }

    /// @notice factoryMarketId => MarketMeta
    mapping(uint256 => MarketMeta) public marketMeta;

    /// @notice Track active/closed/resolved market lists
    uint256[] public activeMarkets;
    uint256[] public closedMarkets;
    uint256[] public resolvedMarkets;

    /// @notice Index tracking for efficient removal from activeMarkets
    mapping(uint256 => uint256) internal activeMarketIndex;

    /// @notice Index tracking for efficient removal from closedMarkets
    mapping(uint256 => uint256) internal closedMarketIndex;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event MarketCreated(
        uint256 indexed factoryMarketId,
        uint256 indexed orderBookMarketId,
        bytes32 priceId,
        int64 strikePrice,
        uint256 expiryTime,
        address indexed creator
    );
    event MarketClosed(uint256 indexed factoryMarketId);
    event MarketStateChanged(uint256 indexed factoryMarketId, MarketState newState);
    event FactoryPaused(bool paused);
    event DefaultParamsUpdated(uint256 batchInterval, uint128 minLots);

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor(address admin, address _orderBook, address _outcomeToken) {
        require(_orderBook != address(0), "MarketFactory: zero orderBook");
        require(_outcomeToken != address(0), "MarketFactory: zero outcomeToken");

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);

        orderBook = OrderBook(_orderBook);
        outcomeToken = OutcomeToken(_outcomeToken);
    }

    // -------------------------------------------------------------------------
    // Market creation
    // -------------------------------------------------------------------------

    /// @notice Create a new binary outcome market.
    /// @param priceId     Pyth price feed ID for resolution.
    /// @param strikePrice Resolution threshold: price >= strikePrice → YES wins.
    /// @param expiryTime  Unix timestamp when the market expires.
    /// @param batchInterval Seconds between batch auctions (0 = use default).
    /// @param minLots     Minimum order size in lots (0 = use default).
    /// @return factoryMarketId The new market's factory ID.
    function createMarket(
        bytes32 priceId,
        int64 strikePrice,
        uint256 expiryTime,
        uint256 batchInterval,
        uint128 minLots
    ) external onlyRole(MARKET_CREATOR_ROLE) nonReentrant returns (uint256 factoryMarketId) {
        require(priceId != bytes32(0), "MarketFactory: zero priceId");
        require(strikePrice > 0, "MarketFactory: zero strikePrice");
        return _createMarket(priceId, strikePrice, expiryTime, batchInterval, minLots, false);
    }

    function createMarketWithPositions(
        bytes32 priceId,
        int64 strikePrice,
        uint256 expiryTime,
        uint256 batchInterval,
        uint128 minLots
    ) external onlyRole(MARKET_CREATOR_ROLE) nonReentrant returns (uint256 factoryMarketId) {
        require(priceId != bytes32(0), "MarketFactory: zero priceId");
        require(strikePrice > 0, "MarketFactory: zero strikePrice");
        return _createMarket(priceId, strikePrice, expiryTime, batchInterval, minLots, true);
    }

    function createAIMarket(
        string calldata prompt,
        uint8 modelId,
        uint256 expiryTime,
        uint128 minLots
    ) external payable onlyRole(MARKET_CREATOR_ROLE) nonReentrant returns (uint256 factoryMarketId) {
        require(aiResolver != address(0), "MarketFactory: no AI resolver");

        factoryMarketId = _createMarket(bytes32(0), 0, expiryTime, defaultBatchInterval, minLots, true);
        marketMeta[factoryMarketId].isAIMarket = true;

        IAIResolver(aiResolver).depositFee{value: msg.value}(factoryMarketId, prompt, modelId);
    }

    function _createMarket(
        bytes32 priceId,
        int64 strikePrice,
        uint256 expiryTime,
        uint256 batchInterval,
        uint128 minLots,
        bool useInternalPositions
    ) internal returns (uint256 factoryMarketId) {
        require(!paused, "MarketFactory: paused");
        require(expiryTime > block.timestamp, "MarketFactory: expiry in the past");

        uint256 interval = batchInterval > 0 ? batchInterval : defaultBatchInterval;
        uint128 lots = minLots > 0 ? minLots : defaultMinLots;
        uint256 duration = expiryTime - block.timestamp;

        require(duration > interval, "MarketFactory: duration must exceed batchInterval");

        factoryMarketId = nextFactoryMarketId++;

        // Register in OrderBook (requires OPERATOR_ROLE on OrderBook)
        uint256 obMarketId = orderBook.registerMarket(lots, interval, expiryTime, useInternalPositions);

        marketMeta[factoryMarketId] = MarketMeta({
            priceId: priceId,
            strikePrice: strikePrice,
            expiryTime: expiryTime,
            creator: msg.sender,
            state: MarketState.Open,
            outcomeYes: false,
            settlementPrice: 0,
            orderBookMarketId: obMarketId,
            useInternalPositions: useInternalPositions,
            isAIMarket: false
        });

        // Track as active
        activeMarketIndex[factoryMarketId] = activeMarkets.length;
        activeMarkets.push(factoryMarketId);

        emit MarketCreated(factoryMarketId, obMarketId, priceId, strikePrice, expiryTime, msg.sender);
    }

    // -------------------------------------------------------------------------
    // State transitions (called by PythResolver / admin)
    // -------------------------------------------------------------------------

    /// @notice Close a market (no new orders). Called when expiry is reached.
    function closeMarket(uint256 factoryMarketId) external {
        MarketMeta storage meta = marketMeta[factoryMarketId];
        require(meta.creator != address(0), "MarketFactory: market not found");
        require(meta.state == MarketState.Open, "MarketFactory: not open");
        require(block.timestamp >= meta.expiryTime, "MarketFactory: not expired");

        meta.state = MarketState.Closed;
        orderBook.deactivateMarket(meta.orderBookMarketId);

        _removeFromActive(factoryMarketId);
        closedMarketIndex[factoryMarketId] = closedMarkets.length;
        closedMarkets.push(factoryMarketId);

        emit MarketClosed(factoryMarketId);
        emit MarketStateChanged(factoryMarketId, MarketState.Closed);
    }

    /// @notice Transition market to Resolving state. Called by PythResolver.
    function setResolving(uint256 factoryMarketId) external onlyRole(ADMIN_ROLE) {
        MarketMeta storage meta = marketMeta[factoryMarketId];
        require(meta.state == MarketState.Closed, "MarketFactory: not closed");
        meta.state = MarketState.Resolving;
        emit MarketStateChanged(factoryMarketId, MarketState.Resolving);
    }

    /// @notice Finalize resolution with outcome. Called by PythResolver.
    function setResolved(uint256 factoryMarketId, bool outcomeYes, int64 settlementPrice)
        external
        onlyRole(ADMIN_ROLE)
    {
        MarketMeta storage meta = marketMeta[factoryMarketId];
        require(
            meta.state == MarketState.Closed || meta.state == MarketState.Resolving,
            "MarketFactory: not closable"
        );
        meta.state = MarketState.Resolved;
        meta.outcomeYes = outcomeYes;
        meta.settlementPrice = settlementPrice;

        // Move from closed to resolved
        _removeFromClosed(factoryMarketId);
        resolvedMarkets.push(factoryMarketId);

        emit MarketStateChanged(factoryMarketId, MarketState.Resolved);
    }

    /// @notice Cancel a market (no resolution within 24h of expiry).
    function cancelMarket(uint256 factoryMarketId) external {
        MarketMeta storage meta = marketMeta[factoryMarketId];
        require(meta.creator != address(0), "MarketFactory: market not found");
        require(
            meta.state == MarketState.Closed || meta.state == MarketState.Open,
            "MarketFactory: cannot cancel"
        );
        require(block.timestamp >= meta.expiryTime + 24 hours, "MarketFactory: too early to cancel");

        // If still Open, close in OrderBook first
        if (meta.state == MarketState.Open) {
            orderBook.deactivateMarket(meta.orderBookMarketId);
            _removeFromActive(factoryMarketId);
        } else {
            // Was Closed — remove from closedMarkets array
            _removeFromClosed(factoryMarketId);
        }

        meta.state = MarketState.Cancelled;

        emit MarketStateChanged(factoryMarketId, MarketState.Cancelled);
    }

    // -------------------------------------------------------------------------
    // Admin controls
    // -------------------------------------------------------------------------

    function setAIResolver(address _aiResolver) external onlyRole(ADMIN_ROLE) {
        aiResolver = _aiResolver;
    }

    function pauseFactory(bool _paused) external onlyRole(ADMIN_ROLE) {
        paused = _paused;
        emit FactoryPaused(_paused);
    }

    function setDefaultParams(uint256 _batchInterval, uint128 _minLots) external onlyRole(ADMIN_ROLE) {
        require(_batchInterval > 0, "MarketFactory: zero batchInterval");
        require(_minLots > 0, "MarketFactory: zero minLots");
        defaultBatchInterval = _batchInterval;
        defaultMinLots = _minLots;
        emit DefaultParamsUpdated(_batchInterval, _minLots);
    }

    // -------------------------------------------------------------------------
    // View helpers
    // -------------------------------------------------------------------------

    function getMarketState(uint256 factoryMarketId) external view returns (MarketState) {
        return marketMeta[factoryMarketId].state;
    }

    function getActiveMarketCount() external view returns (uint256) {
        return activeMarkets.length;
    }

    function getClosedMarketCount() external view returns (uint256) {
        return closedMarkets.length;
    }

    function getResolvedMarketCount() external view returns (uint256) {
        return resolvedMarkets.length;
    }

    // -------------------------------------------------------------------------
    // Internal
    // -------------------------------------------------------------------------

    function _removeFromActive(uint256 factoryMarketId) internal {
        uint256 idx = activeMarketIndex[factoryMarketId];
        uint256 lastIdx = activeMarkets.length - 1;

        if (idx != lastIdx) {
            uint256 lastId = activeMarkets[lastIdx];
            activeMarkets[idx] = lastId;
            activeMarketIndex[lastId] = idx;
        }
        activeMarkets.pop();
        delete activeMarketIndex[factoryMarketId];
    }

    function _removeFromClosed(uint256 factoryMarketId) internal {
        if (closedMarkets.length == 0) return;
        uint256 idx = closedMarketIndex[factoryMarketId];
        uint256 lastIdx = closedMarkets.length - 1;

        if (idx != lastIdx) {
            uint256 lastId = closedMarkets[lastIdx];
            closedMarkets[idx] = lastId;
            closedMarketIndex[lastId] = idx;
        }
        closedMarkets.pop();
        delete closedMarketIndex[factoryMarketId];
    }

}
