// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "./ITypes.sol";
import "./SegmentTree.sol";
import "./Vault.sol";

/// @title OrderBook
/// @notice Central limit order book for the Strike binary-outcome protocol.
///         Orders are placed at price ticks 1-99 (price = tick/100 BNB per lot).
///         Each lot = LOT_SIZE wei (0.001 BNB). Collateral is locked in the Vault
///         on placement and unlocked on cancel.
///
///         Orders feed into BatchAuction for periodic FBA clearing.
contract OrderBook is AccessControl {
    using SegmentTree for SegmentTree.Tree;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    uint256 public constant LOT_SIZE = 1e15; // 0.001 BNB per lot
    uint256 public constant MIN_TICK = 1;
    uint256 public constant MAX_TICK = 99;

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    Vault public immutable vault;

    uint256 public nextOrderId = 1;
    uint256 public nextMarketId = 1;

    /// @notice marketId => Market descriptor
    mapping(uint256 => Market) public markets;

    /// @notice orderId => Order
    mapping(uint256 => Order) public orders;

    /// @notice marketId => bid segment tree (tick = willingness to pay)
    mapping(uint256 => SegmentTree.Tree) internal bidTrees;

    /// @notice marketId => ask segment tree (tick = willingness to sell)
    mapping(uint256 => SegmentTree.Tree) internal askTrees;

    /// @notice marketId => tick => array of order IDs at that tick (bid side)
    mapping(uint256 => mapping(uint256 => uint256[])) public bidOrderIds;

    /// @notice marketId => tick => array of order IDs at that tick (ask side)
    mapping(uint256 => mapping(uint256 => uint256[])) public askOrderIds;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event MarketRegistered(uint256 indexed marketId, uint256 minLots);
    event MarketHalted(uint256 indexed marketId);
    event MarketResumed(uint256 indexed marketId);
    event MarketDeactivated(uint256 indexed marketId);
    event OrderPlaced(
        uint256 indexed orderId,
        uint256 indexed marketId,
        address indexed owner,
        Side side,
        uint256 tick,
        uint256 lots,
        uint256 batchId
    );
    event OrderCancelled(uint256 indexed orderId, address indexed owner);

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor(address admin, address _vault) {
        require(_vault != address(0), "OrderBook: zero vault");
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        vault = Vault(payable(_vault));
    }

    // -------------------------------------------------------------------------
    // Market management
    // -------------------------------------------------------------------------

    /// @notice Register a new market for trading.
    /// @param minLots Minimum order size in lots (0 = no minimum).
    /// @param batchInterval Seconds between batch auctions.
    /// @param expiryTime Timestamp when market expires.
    /// @return marketId The new market's ID.
    function registerMarket(uint256 minLots, uint256 batchInterval, uint256 expiryTime) external onlyRole(OPERATOR_ROLE) returns (uint256 marketId) {
        marketId = nextMarketId++;
        markets[marketId] = Market({
            id: marketId,
            active: true,
            halted: false,
            currentBatchId: 1,
            minLots: minLots,
            batchInterval: batchInterval,
            expiryTime: expiryTime
        });
        emit MarketRegistered(marketId, minLots);
    }

    /// @notice Halt trading on a market (orders cannot be placed, but can be cancelled).
    function haltMarket(uint256 marketId) external onlyRole(OPERATOR_ROLE) {
        Market storage m = markets[marketId];
        require(m.active, "OrderBook: market not active");
        require(!m.halted, "OrderBook: already halted");
        m.halted = true;
        emit MarketHalted(marketId);
    }

    /// @notice Resume trading on a halted market.
    function resumeMarket(uint256 marketId) external onlyRole(OPERATOR_ROLE) {
        Market storage m = markets[marketId];
        require(m.active, "OrderBook: market not active");
        require(m.halted, "OrderBook: not halted");
        m.halted = false;
        emit MarketResumed(marketId);
    }

    /// @notice Permanently deactivate a market (no new orders, no clearing).
    function deactivateMarket(uint256 marketId) external onlyRole(OPERATOR_ROLE) {
        Market storage m = markets[marketId];
        require(m.active, "OrderBook: market not active");
        m.active = false;
        emit MarketDeactivated(marketId);
    }

    // -------------------------------------------------------------------------
    // Place order
    // -------------------------------------------------------------------------

    /// @notice Place an order in the book.
    /// @param marketId  Market to trade in.
    /// @param side      Bid or Ask.
    /// @param orderType GoodTilBatch or GoodTilCancel.
    /// @param tick      Price tick in [1, 99].
    /// @param lots      Number of lots (each = LOT_SIZE wei).
    /// @return orderId  The new order's ID.
    function placeOrder(
        uint256 marketId,
        Side side,
        OrderType orderType,
        uint256 tick,
        uint256 lots
    ) external returns (uint256 orderId) {
        Market storage m = markets[marketId];
        require(m.active, "OrderBook: market not active");
        require(!m.halted, "OrderBook: market halted");
        require(block.timestamp + m.batchInterval < m.expiryTime, "OrderBook: trading halted");
        require(tick >= MIN_TICK && tick <= MAX_TICK, "OrderBook: tick out of range");
        require(lots > 0, "OrderBook: zero lots");
        require(lots >= m.minLots, "OrderBook: below min lots");

        // Calculate collateral required:
        // Bid: pay tick/100 per lot → collateral = lots * LOT_SIZE * tick / 100
        // Ask: risk (100-tick)/100 per lot → collateral = lots * LOT_SIZE * (100 - tick) / 100
        uint256 collateral;
        if (side == Side.Bid) {
            collateral = (lots * LOT_SIZE * tick) / 100;
        } else {
            collateral = (lots * LOT_SIZE * (100 - tick)) / 100;
        }

        // Lock collateral in vault
        vault.lock(msg.sender, collateral);

        // Create order
        orderId = nextOrderId++;
        orders[orderId] = Order({
            id: orderId,
            marketId: marketId,
            owner: msg.sender,
            side: side,
            orderType: orderType,
            tick: tick,
            lots: lots,
            batchId: m.currentBatchId,
            timestamp: block.timestamp
        });

        // Update segment tree and order list
        if (side == Side.Bid) {
            bidTrees[marketId].update(tick, int256(lots));
            bidOrderIds[marketId][tick].push(orderId);
        } else {
            askTrees[marketId].update(tick, int256(lots));
            askOrderIds[marketId][tick].push(orderId);
        }

        emit OrderPlaced(orderId, marketId, msg.sender, side, tick, lots, m.currentBatchId);
    }

    // -------------------------------------------------------------------------
    // Cancel order
    // -------------------------------------------------------------------------

    /// @notice Cancel an open order. Unlocks collateral in the vault.
    /// @param orderId The order to cancel.
    function cancelOrder(uint256 orderId) external {
        Order storage o = orders[orderId];
        require(o.owner == msg.sender, "OrderBook: not owner");
        require(o.lots > 0, "OrderBook: already cancelled/filled");

        uint256 lots = o.lots;
        uint256 tick = o.tick;
        uint256 marketId = o.marketId;
        Side side = o.side;

        // Calculate collateral to unlock
        uint256 collateral;
        if (side == Side.Bid) {
            collateral = (lots * LOT_SIZE * tick) / 100;
        } else {
            collateral = (lots * LOT_SIZE * (100 - tick)) / 100;
        }

        // Zero out remaining lots
        o.lots = 0;

        // Update segment tree
        if (side == Side.Bid) {
            bidTrees[marketId].update(tick, -int256(lots));
        } else {
            askTrees[marketId].update(tick, -int256(lots));
        }

        // Unlock collateral
        vault.unlock(msg.sender, collateral);

        emit OrderCancelled(orderId, msg.sender);
    }

    // -------------------------------------------------------------------------
    // Views for BatchAuction
    // -------------------------------------------------------------------------

    /// @notice Get bid volume at a specific tick.
    function bidVolumeAt(uint256 marketId, uint256 tick) external view returns (uint256) {
        return bidTrees[marketId].volumeAt(tick);
    }

    /// @notice Get ask volume at a specific tick.
    function askVolumeAt(uint256 marketId, uint256 tick) external view returns (uint256) {
        return askTrees[marketId].volumeAt(tick);
    }

    /// @notice Total bid volume for a market.
    function totalBidVolume(uint256 marketId) external view returns (uint256) {
        return bidTrees[marketId].totalVolume();
    }

    /// @notice Total ask volume for a market.
    function totalAskVolume(uint256 marketId) external view returns (uint256) {
        return askTrees[marketId].totalVolume();
    }

    /// @notice Get order IDs at a tick for a side.
    function getOrderIdsAtTick(uint256 marketId, Side side, uint256 tick)
        external
        view
        returns (uint256[] memory)
    {
        if (side == Side.Bid) {
            return bidOrderIds[marketId][tick];
        } else {
            return askOrderIds[marketId][tick];
        }
    }

    // -------------------------------------------------------------------------
    // Internal helpers for BatchAuction
    // -------------------------------------------------------------------------

    /// @notice Reduce an order's lots (called by BatchAuction during settlement).
    /// @dev Only callable by OPERATOR_ROLE (BatchAuction contract).
    function reduceOrderLots(uint256 orderId, uint256 lotsToReduce) external onlyRole(OPERATOR_ROLE) {
        Order storage o = orders[orderId];
        require(o.lots >= lotsToReduce, "OrderBook: insufficient lots");
        o.lots -= lotsToReduce;
    }

    /// @notice Update segment tree volume (called by BatchAuction after fills).
    /// @dev Only callable by OPERATOR_ROLE.
    function updateTreeVolume(uint256 marketId, Side side, uint256 tick, int256 delta)
        external
        onlyRole(OPERATOR_ROLE)
    {
        if (side == Side.Bid) {
            bidTrees[marketId].update(tick, delta);
        } else {
            askTrees[marketId].update(tick, delta);
        }
    }

    /// @notice Advance the batch counter for a market.
    /// @dev Only callable by OPERATOR_ROLE.
    function advanceBatch(uint256 marketId) external onlyRole(OPERATOR_ROLE) {
        markets[marketId].currentBatchId++;
    }

    /// @notice Find the clearing tick using segment trees.
    function findClearingTick(uint256 marketId) external view returns (uint256) {
        return SegmentTree.findClearingTick(bidTrees[marketId], askTrees[marketId]);
    }

    /// @notice Get the cumulative bid volume at a tick (bids willing to pay >= tick).
    function cumulativeBidVolume(uint256 marketId, uint256 tick) external view returns (uint256) {
        uint256 total = bidTrees[marketId].totalVolume();
        if (tick <= 1) return total;
        uint256 prefix = bidTrees[marketId].prefixSum(tick - 1);
        return total >= prefix ? total - prefix : 0;
    }

    /// @notice Get the cumulative ask volume at a tick (asks willing to sell <= tick).
    function cumulativeAskVolume(uint256 marketId, uint256 tick) external view returns (uint256) {
        return askTrees[marketId].prefixSum(tick);
    }
}
