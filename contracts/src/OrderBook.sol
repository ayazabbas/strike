// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./ITypes.sol";
import "./SegmentTree.sol";
import "./Vault.sol";
import "./FeeModel.sol";

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
    FeeModel public immutable feeModel;

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
    event OrderCancelled(uint256 indexed orderId, uint256 indexed marketId, address indexed owner);

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor(address admin, address _vault, address _feeModel) {
        require(_vault != address(0), "OrderBook: zero vault");
        require(_feeModel != address(0), "OrderBook: zero feeModel");
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        vault = Vault(_vault);
        feeModel = FeeModel(_feeModel);
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

        // V2.1: Lock collateral + fee upfront to prevent pool insolvency
        uint256 totalDeposit = collateral + feeModel.calculateFee(collateral);

        // Determine batch (overflow to next if current is full)
        uint256 batchId = m.currentBatchId;
        if (batchOrderIds[marketId][batchId].length >= MAX_ORDERS_PER_BATCH) {
            batchId = batchId + 1;
        }
        require(batchOrderIds[marketId][batchId].length < MAX_ORDERS_PER_BATCH, "OrderBook: batch overflow");

        {
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
        }

        // Update segment tree
        if (side == Side.Bid) {
            bidTrees[marketId].update(tick, int256(lots));
        } else {
            askTrees[marketId].update(tick, int256(lots));
        }

        // Track order in batch
        batchOrderIds[marketId][batchId].push(orderId);

        // Deposit collateral + fee via ERC20 transferFrom (user must approve Vault)
        vault.depositFor(msg.sender, totalDeposit);
        vault.lock(msg.sender, totalDeposit);

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

        // V2.1: Return collateral + fee (both were locked at placement)
        uint256 fee = feeModel.calculateFee(collateral);
        uint256 totalReturn = collateral + fee;

        o.lots = 0;

        if (side == Side.Bid) {
            bidTrees[marketId].update(tick, -int256(lots));
        } else {
            askTrees[marketId].update(tick, -int256(lots));
        }

        vault.unlock(msg.sender, totalReturn);
        vault.withdrawTo(msg.sender, totalReturn);

        emit OrderCancelled(orderId, marketId, msg.sender);
    }

    /// @notice Cancel an order on an expired market. Anyone can call this to
    ///         release escrowed funds back to the order owner.
    function cancelExpiredOrder(uint256 orderId) external nonReentrant {
        Order storage o = orders[orderId];
        require(o.lots > 0, "OrderBook: already cancelled/filled");

        Market storage m = markets[o.marketId];
        require(block.timestamp > m.expiryTime, "OrderBook: market not expired");

        address owner = o.owner;
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

        uint256 fee = feeModel.calculateFee(collateral);
        uint256 totalReturn = collateral + fee;

        o.lots = 0;

        if (side == Side.Bid) {
            bidTrees[marketId].update(tick, -int256(lots));
        } else {
            askTrees[marketId].update(tick, -int256(lots));
        }

        vault.unlock(owner, totalReturn);
        vault.withdrawTo(owner, totalReturn);

        emit OrderCancelled(orderId, marketId, owner);
    }

    /// @notice Batch cancel expired orders. Anyone can call.
    function cancelExpiredOrders(uint256[] calldata orderIds) external nonReentrant {
        for (uint256 i = 0; i < orderIds.length; i++) {
            Order storage o = orders[orderIds[i]];
            if (o.lots == 0) continue;
            Market storage m = markets[o.marketId];
            if (block.timestamp <= m.expiryTime) continue;

            address owner = o.owner;
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

            uint256 fee = feeModel.calculateFee(collateral);
            uint256 totalReturn = collateral + fee;

            o.lots = 0;

            if (side == Side.Bid) {
                bidTrees[marketId].update(tick, -int256(lots));
            } else {
                askTrees[marketId].update(tick, -int256(lots));
            }

            vault.unlock(owner, totalReturn);
            vault.withdrawTo(owner, totalReturn);

            emit OrderCancelled(orderIds[i], marketId, owner);
        }
    }

    // -------------------------------------------------------------------------
    // Batch order tracking (for atomic settlement)
    // -------------------------------------------------------------------------

    function getBatchOrderIds(uint256 marketId, uint256 batchId) external view returns (uint256[] memory) {
        return batchOrderIds[marketId][batchId];
    }

    /// @notice Push an order ID to a batch's order list (for GTC rollover).
    ///         Returns false if batch is full (caller should auto-cancel).
    function pushBatchOrderId(uint256 marketId, uint256 batchId, uint256 orderId) external onlyRole(OPERATOR_ROLE) returns (bool) {
        if (batchOrderIds[marketId][batchId].length >= MAX_ORDERS_PER_BATCH) {
            return false;
        }
        batchOrderIds[marketId][batchId].push(orderId);
        return true;
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
