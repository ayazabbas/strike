// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./ITypes.sol";
import "./SegmentTree.sol";
import "./Vault.sol";

/// @title OrderBook
/// @notice Central limit order book for the Strike binary-outcome protocol.
///         Orders are placed at price ticks 1-99 (price = tick/100 per lot).
///         Each lot = LOT_SIZE collateral units. Collateral is ERC20 (USDT).
///         Orders feed into BatchAuction for periodic FBA clearing.
contract OrderBook is AccessControl, ReentrancyGuard {
    using SegmentTree for SegmentTree.Tree;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    uint256 public constant MIN_TICK = 1;
    uint256 public constant MAX_TICK = 99;
    uint256 public constant MAX_ORDERS_PER_BATCH = 400;

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    Vault public immutable vault;

    uint64 public nextOrderId = 1;
    uint32 public nextMarketId = 1;

    mapping(uint256 => Market) public markets;
    mapping(uint256 => Order) public orders;
    mapping(uint256 => SegmentTree.Tree) internal bidTrees;
    mapping(uint256 => SegmentTree.Tree) internal askTrees;

    /// @notice marketId => batchId => array of order IDs placed in that batch
    mapping(uint256 => mapping(uint256 => uint256[])) internal batchOrderIds;

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
        vault = Vault(_vault);
    }

    // -------------------------------------------------------------------------
    // Market management
    // -------------------------------------------------------------------------

    function registerMarket(uint256 minLots, uint256 batchInterval, uint256 expiryTime) external onlyRole(OPERATOR_ROLE) returns (uint256 marketId) {
        require(minLots <= type(uint32).max, "OrderBook: minLots overflow");
        require(batchInterval <= type(uint32).max, "OrderBook: batchInterval overflow");
        require(expiryTime <= type(uint40).max, "OrderBook: expiryTime overflow");

        uint32 id = nextMarketId++;
        marketId = id;
        markets[marketId] = Market({
            id: id,
            active: true,
            halted: false,
            currentBatchId: 1,
            minLots: uint32(minLots),
            batchInterval: uint32(batchInterval),
            expiryTime: uint40(expiryTime)
        });
        emit MarketRegistered(marketId, minLots);
    }

    function haltMarket(uint256 marketId) external onlyRole(OPERATOR_ROLE) {
        Market storage m = markets[marketId];
        require(m.active, "OrderBook: market not active");
        require(!m.halted, "OrderBook: already halted");
        m.halted = true;
        emit MarketHalted(marketId);
    }

    function resumeMarket(uint256 marketId) external onlyRole(OPERATOR_ROLE) {
        Market storage m = markets[marketId];
        require(m.active, "OrderBook: market not active");
        require(m.halted, "OrderBook: not halted");
        m.halted = false;
        emit MarketResumed(marketId);
    }

    function deactivateMarket(uint256 marketId) external onlyRole(OPERATOR_ROLE) {
        Market storage m = markets[marketId];
        require(m.active, "OrderBook: market not active");
        m.active = false;
        emit MarketDeactivated(marketId);
    }

    // -------------------------------------------------------------------------
    // Place order (ERC20 collateral — user must approve Vault)
    // -------------------------------------------------------------------------

    function placeOrder(
        uint256 marketId,
        Side side,
        OrderType orderType,
        uint256 tick,
        uint256 lots
    ) external nonReentrant returns (uint256 orderId) {
        Market storage m = markets[marketId];
        require(m.active, "OrderBook: market not active");
        require(!m.halted, "OrderBook: market halted");
        require(block.timestamp < m.expiryTime, "OrderBook: market expired");
        require(tick >= MIN_TICK && tick <= MAX_TICK, "OrderBook: tick out of range");
        require(lots > 0, "OrderBook: zero lots");
        require(lots >= m.minLots, "OrderBook: below min lots");
        require(lots <= type(uint64).max, "OrderBook: lots overflow");
        require(marketId <= type(uint32).max, "OrderBook: marketId overflow");

        uint256 collateral;
        if (side == Side.Bid) {
            collateral = (lots * LOT_SIZE * tick) / 100;
        } else {
            collateral = (lots * LOT_SIZE * (100 - tick)) / 100;
        }

        // Determine batch (overflow to next if current is full)
        uint256 batchId = m.currentBatchId;
        if (batchOrderIds[marketId][batchId].length >= MAX_ORDERS_PER_BATCH) {
            batchId = batchId + 1;
        }
        require(batchOrderIds[marketId][batchId].length < MAX_ORDERS_PER_BATCH, "OrderBook: batch overflow");

        uint64 oid = nextOrderId++;
        orderId = oid;
        orders[orderId] = Order({
            owner: msg.sender,
            side: side,
            orderType: orderType,
            tick: uint8(tick),
            lots: uint64(lots),
            id: oid,
            marketId: uint32(marketId),
            batchId: uint32(batchId),
            timestamp: uint40(block.timestamp)
        });

        // Update segment tree
        if (side == Side.Bid) {
            bidTrees[marketId].update(tick, int256(lots));
        } else {
            askTrees[marketId].update(tick, int256(lots));
        }

        // Track order in batch
        batchOrderIds[marketId][batchId].push(orderId);

        // Deposit collateral via ERC20 transferFrom (user must approve Vault)
        vault.depositFor(msg.sender, collateral);
        vault.lock(msg.sender, collateral);

        emit OrderPlaced(orderId, marketId, msg.sender, side, tick, lots, batchId);
    }

    // -------------------------------------------------------------------------
    // Cancel order
    // -------------------------------------------------------------------------

    function cancelOrder(uint256 orderId) external nonReentrant {
        Order storage o = orders[orderId];
        require(o.owner == msg.sender, "OrderBook: not owner");
        require(o.lots > 0, "OrderBook: already cancelled/filled");

        uint256 lots = o.lots;
        uint256 tick = o.tick;
        uint256 marketId = o.marketId;
        Side side = o.side;

        uint256 collateral;
        if (side == Side.Bid) {
            collateral = (lots * LOT_SIZE * tick) / 100;
        } else {
            collateral = (lots * LOT_SIZE * (100 - tick)) / 100;
        }

        o.lots = 0;

        if (side == Side.Bid) {
            bidTrees[marketId].update(tick, -int256(lots));
        } else {
            askTrees[marketId].update(tick, -int256(lots));
        }

        vault.unlock(msg.sender, collateral);
        vault.withdrawTo(msg.sender, collateral);

        emit OrderCancelled(orderId, msg.sender);
    }

    // -------------------------------------------------------------------------
    // Batch order tracking (for atomic settlement)
    // -------------------------------------------------------------------------

    function getBatchOrderIds(uint256 marketId, uint256 batchId) external view returns (uint256[] memory) {
        return batchOrderIds[marketId][batchId];
    }

    /// @notice Push an order ID to a batch's order list (for GTC rollover).
    function pushBatchOrderId(uint256 marketId, uint256 batchId, uint256 orderId) external onlyRole(OPERATOR_ROLE) {
        batchOrderIds[marketId][batchId].push(orderId);
    }

    // -------------------------------------------------------------------------
    // Views for BatchAuction
    // -------------------------------------------------------------------------

    function bidVolumeAt(uint256 marketId, uint256 tick) external view returns (uint256) {
        return bidTrees[marketId].volumeAt(tick);
    }

    function askVolumeAt(uint256 marketId, uint256 tick) external view returns (uint256) {
        return askTrees[marketId].volumeAt(tick);
    }

    function totalBidVolume(uint256 marketId) external view returns (uint256) {
        return bidTrees[marketId].totalVolume();
    }

    function totalAskVolume(uint256 marketId) external view returns (uint256) {
        return askTrees[marketId].totalVolume();
    }

    // -------------------------------------------------------------------------
    // Internal helpers for BatchAuction
    // -------------------------------------------------------------------------

    function reduceOrderLots(uint256 orderId, uint256 lotsToReduce) external onlyRole(OPERATOR_ROLE) {
        Order storage o = orders[orderId];
        require(o.lots >= lotsToReduce, "OrderBook: insufficient lots");
        o.lots -= uint64(lotsToReduce);
    }

    function updateTreeVolume(uint256 marketId, Side side, uint256 tick, int256 delta) external onlyRole(OPERATOR_ROLE) {
        if (side == Side.Bid) {
            bidTrees[marketId].update(tick, delta);
        } else {
            askTrees[marketId].update(tick, delta);
        }
    }

    function advanceBatch(uint256 marketId) external onlyRole(OPERATOR_ROLE) {
        markets[marketId].currentBatchId++;
    }

    function findClearingTick(uint256 marketId) external view returns (uint256) {
        return SegmentTree.findClearingTick(bidTrees[marketId], askTrees[marketId]);
    }

    function cumulativeBidVolume(uint256 marketId, uint256 tick) external view returns (uint256) {
        uint256 total = bidTrees[marketId].totalVolume();
        if (tick <= 1) return total;
        uint256 prefix = bidTrees[marketId].prefixSum(tick - 1);
        return total >= prefix ? total - prefix : 0;
    }

    function cumulativeAskVolume(uint256 marketId, uint256 tick) external view returns (uint256) {
        return askTrees[marketId].prefixSum(tick);
    }
}
