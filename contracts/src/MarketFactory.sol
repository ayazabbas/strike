// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./ITypes.sol";
import "./OrderBook.sol";
import "./OutcomeToken.sol";

/// @title MarketFactory
/// @notice Creates and manages binary outcome markets for the Strike CLOB protocol.
///         Market creation requires a bond (native token) to fund the resolver bounty.
///         Tracks market lifecycle: Open → Closed → Resolving → Resolved / Cancelled.
contract MarketFactory is AccessControl, ReentrancyGuard {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    OrderBook public immutable orderBook;
    OutcomeToken public immutable outcomeToken;

    uint256 public nextFactoryMarketId = 1;
    uint256 public creationBond = 0.01 ether;
    bool public paused;

    /// @notice Default market parameters
    uint256 public defaultBatchInterval = 60; // seconds
    uint128 public defaultMinLots = 1;
    address public feeCollector;

    /// @notice Market metadata stored by the factory
    struct MarketMeta {
        bytes32 priceId;       // Pyth price feed ID
        uint256 expiryTime;    // when the market closes
        uint256 creationBond;  // bond paid at creation
        address creator;       // who created the market
        MarketState state;     // lifecycle state
        bool outcomeYes;       // true = YES won (only valid in Resolved state)
        int64 settlementPrice; // price at resolution
        uint256 orderBookMarketId; // ID in the OrderBook
    }

    /// @notice factoryMarketId => MarketMeta
    mapping(uint256 => MarketMeta) public marketMeta;

    /// @notice Track active/closed/resolved market lists
    uint256[] public activeMarkets;
    uint256[] public closedMarkets;
    uint256[] public resolvedMarkets;

    /// @notice Index tracking for efficient removal from activeMarkets
    mapping(uint256 => uint256) internal activeMarketIndex;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event MarketCreated(
        uint256 indexed factoryMarketId,
        uint256 indexed orderBookMarketId,
        bytes32 priceId,
        uint256 expiryTime,
        address indexed creator
    );
    event MarketClosed(uint256 indexed factoryMarketId);
    event MarketStateChanged(uint256 indexed factoryMarketId, MarketState newState);
    event FactoryPaused(bool paused);
    event DefaultParamsUpdated(uint256 batchInterval, uint128 minLots);
    event CreationBondUpdated(uint256 newBond);
    event FeeCollectorUpdated(address indexed collector);

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor(address admin, address _orderBook, address _outcomeToken, address _feeCollector) {
        require(_orderBook != address(0), "MarketFactory: zero orderBook");
        require(_outcomeToken != address(0), "MarketFactory: zero outcomeToken");
        require(_feeCollector != address(0), "MarketFactory: zero feeCollector");

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);

        orderBook = OrderBook(_orderBook);
        outcomeToken = OutcomeToken(_outcomeToken);
        feeCollector = _feeCollector;
    }

    // -------------------------------------------------------------------------
    // Market creation
    // -------------------------------------------------------------------------

    /// @notice Create a new binary outcome market.
    /// @param priceId     Pyth price feed ID for resolution.
    /// @param duration    Duration in seconds from now until market expiry.
    /// @param batchInterval Seconds between batch auctions (0 = use default).
    /// @param minLots     Minimum order size in lots (0 = use default).
    /// @return factoryMarketId The new market's factory ID.
    function createMarket(
        bytes32 priceId,
        uint256 duration,
        uint256 batchInterval,
        uint128 minLots
    ) external payable nonReentrant returns (uint256 factoryMarketId) {
        require(!paused, "MarketFactory: paused");
        require(msg.value >= creationBond, "MarketFactory: insufficient bond");
        require(duration > 0, "MarketFactory: zero duration");
        require(priceId != bytes32(0), "MarketFactory: zero priceId");

        uint256 interval = batchInterval > 0 ? batchInterval : defaultBatchInterval;
        uint128 lots = minLots > 0 ? minLots : defaultMinLots;
        uint256 expiryTime = block.timestamp + duration;

        require(duration > interval, "MarketFactory: duration must exceed batchInterval");

        factoryMarketId = nextFactoryMarketId++;

        // Register in OrderBook (requires OPERATOR_ROLE on OrderBook)
        uint256 obMarketId = orderBook.registerMarket(lots, interval, expiryTime);

        marketMeta[factoryMarketId] = MarketMeta({
            priceId: priceId,
            expiryTime: expiryTime,
            creationBond: msg.value,
            creator: msg.sender,
            state: MarketState.Open,
            outcomeYes: false,
            settlementPrice: 0,
            orderBookMarketId: obMarketId
        });

        // Track as active
        activeMarketIndex[factoryMarketId] = activeMarkets.length;
        activeMarkets.push(factoryMarketId);

        // Refund excess bond
        if (msg.value > creationBond) {
            (bool ok, ) = msg.sender.call{value: msg.value - creationBond}("");
            require(ok, "MarketFactory: refund failed");
        }

        emit MarketCreated(factoryMarketId, obMarketId, priceId, expiryTime, msg.sender);
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
        }

        meta.state = MarketState.Cancelled;

        // Return bond to creator
        uint256 bond = meta.creationBond;
        if (bond > 0) {
            meta.creationBond = 0;
            (bool ok, ) = meta.creator.call{value: bond}("");
            require(ok, "MarketFactory: bond refund failed");
        }

        emit MarketStateChanged(factoryMarketId, MarketState.Cancelled);
    }

    /// @notice Pay resolver bounty from creation bond.
    function payResolverBounty(uint256 factoryMarketId, address resolver)
        external
        onlyRole(ADMIN_ROLE)
        nonReentrant
    {
        MarketMeta storage meta = marketMeta[factoryMarketId];
        uint256 bond = meta.creationBond;
        require(bond > 0, "MarketFactory: no bond");

        meta.creationBond = 0;
        (bool ok, ) = resolver.call{value: bond}("");
        require(ok, "MarketFactory: bounty transfer failed");
    }

    // -------------------------------------------------------------------------
    // Admin controls
    // -------------------------------------------------------------------------

    function pauseFactory(bool _paused) external onlyRole(ADMIN_ROLE) {
        paused = _paused;
        emit FactoryPaused(_paused);
    }

    function setDefaultParams(uint256 _batchInterval, uint128 _minLots) external onlyRole(ADMIN_ROLE) {
        require(_batchInterval > 0, "MarketFactory: zero batchInterval");
        defaultBatchInterval = _batchInterval;
        defaultMinLots = _minLots;
        emit DefaultParamsUpdated(_batchInterval, _minLots);
    }

    function setCreationBond(uint256 _bond) external onlyRole(ADMIN_ROLE) {
        creationBond = _bond;
        emit CreationBondUpdated(_bond);
    }

    function setFeeCollector(address _collector) external onlyRole(ADMIN_ROLE) {
        require(_collector != address(0), "MarketFactory: zero collector");
        feeCollector = _collector;
        emit FeeCollectorUpdated(_collector);
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

    // -------------------------------------------------------------------------
    // Receive
    // -------------------------------------------------------------------------

    receive() external payable {}
}
