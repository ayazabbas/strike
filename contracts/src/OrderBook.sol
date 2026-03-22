// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "./ITypes.sol";
import "./SegmentTree.sol";
import "./Vault.sol";
import "./FeeModel.sol";
import "./OutcomeToken.sol";

/// @title OrderBook
/// @notice Central limit order book for the Strike binary-outcome protocol.
///         Orders are placed at price ticks 1-99 (price = tick/100 per lot).
///         Each lot = LOT_SIZE collateral units. Collateral is ERC20 (USDT).
///         Orders feed into BatchAuction for periodic FBA clearing.
contract OrderBook is AccessControl, ReentrancyGuard, ERC1155Holder {
    using SegmentTree for SegmentTree.Tree;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    uint256 public constant MAX_ORDERS_PER_BATCH = 1600;
    uint16 public constant MAX_USER_ORDERS = 20;

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    Vault public immutable vault;
    FeeModel public immutable feeModel;
    OutcomeToken public immutable outcomeToken;

    uint64 public nextOrderId = 1;
    uint32 public nextMarketId = 1;

    mapping(uint256 => Market) public markets;
    mapping(uint256 => Order) public orders;
    mapping(uint256 => SegmentTree.Tree) internal bidTrees;
    mapping(uint256 => SegmentTree.Tree) internal askTrees;

    /// @notice marketId => batchId => array of order IDs placed in that batch
    mapping(uint256 => mapping(uint256 => uint256[])) internal batchOrderIds;

    /// @notice user => marketId => number of active orders (both active and resting)
    mapping(address => mapping(uint256 => uint16)) public activeOrderCount;

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

    constructor(address admin, address _vault, address _feeModel, address _outcomeToken) {
        require(_vault != address(0), "OrderBook: zero vault");
        require(_feeModel != address(0), "OrderBook: zero feeModel");
        require(_outcomeToken != address(0), "OrderBook: zero outcomeToken");
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        vault = Vault(_vault);
        feeModel = FeeModel(_feeModel);
        outcomeToken = OutcomeToken(_outcomeToken);
    }

    // -------------------------------------------------------------------------
    // Market management
    // -------------------------------------------------------------------------

    function registerMarket(uint256 minLots, uint256 batchInterval, uint256 expiryTime, bool useInternalPositions) external onlyRole(OPERATOR_ROLE) returns (uint256 marketId) {
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
            expiryTime: uint40(expiryTime),
            useInternalPositions: useInternalPositions
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
        require(tick >= 1 && tick <= SegmentTree.MAX_TICK, "OrderBook: tick out of range");
        require(lots > 0, "OrderBook: zero lots");
        require(lots >= m.minLots, "OrderBook: below min lots");
        require(lots <= type(uint64).max, "OrderBook: lots overflow");
        require(marketId <= type(uint32).max, "OrderBook: marketId overflow");
        require(activeOrderCount[msg.sender][marketId] < MAX_USER_ORDERS, "OrderBook: too many orders");

        activeOrderCount[msg.sender][marketId]++;

        bool isSell = (side == Side.SellYes || side == Side.SellNo);

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

        if (isSell) {
            bool isYes = (side == Side.SellYes);
            if (m.useInternalPositions) {
                vault.lockPosition(msg.sender, marketId, uint128(lots), isYes);
            } else {
                uint256 tokenId = isYes
                    ? outcomeToken.yesTokenId(marketId)
                    : outcomeToken.noTokenId(marketId);
                outcomeToken.safeTransferFrom(msg.sender, address(this), tokenId, lots, "");
            }

            // SellYes sits on the ask side, SellNo sits on the bid side
            if (side == Side.SellYes) {
                askTrees[marketId].update(tick, int256(lots));
            } else {
                bidTrees[marketId].update(tick, int256(lots));
            }
        } else {
            // Buy order: lock USDT collateral + fee
            uint256 collateral;
            if (side == Side.Bid) {
                collateral = (lots * LOT_SIZE * tick) / 100;
            } else {
                collateral = (lots * LOT_SIZE * (100 - tick)) / 100;
            }
            uint256 totalDeposit = collateral + feeModel.calculateFee(collateral);

            if (side == Side.Bid) {
                bidTrees[marketId].update(tick, int256(lots));
            } else {
                askTrees[marketId].update(tick, int256(lots));
            }

            vault.depositFor(msg.sender, totalDeposit);
            vault.lock(msg.sender, totalDeposit);
        }

        // Track order in batch
        batchOrderIds[marketId][batchId].push(orderId);

        emit OrderPlaced(orderId, marketId, msg.sender, side, tick, lots, batchId);
    }

    // -------------------------------------------------------------------------
    // Internal helpers for batch operations
    // -------------------------------------------------------------------------

    function _cancelForReplace(uint256 orderId, address caller) internal returns (uint256 refund) {
        Order storage o = orders[orderId];
        if (o.lots == 0) return 0;
        require(o.owner == caller, "OrderBook: not owner");

        uint256 lots = o.lots;
        uint256 tick = o.tick;
        uint256 mktId = o.marketId;
        Side side = o.side;
        o.lots = 0;

        if (activeOrderCount[caller][mktId] > 0) {
            activeOrderCount[caller][mktId]--;
        }

        if (side == Side.Bid || side == Side.SellNo) {
            bidTrees[mktId].update(tick, -int256(lots));
        } else {
            askTrees[mktId].update(tick, -int256(lots));
        }

        if (side == Side.SellYes || side == Side.SellNo) {
            bool isYes = (side == Side.SellYes);
            if (markets[mktId].useInternalPositions) {
                vault.unlockPosition(caller, mktId, uint128(lots), isYes);
            } else {
                uint256 tokenId = isYes
                    ? outcomeToken.yesTokenId(mktId)
                    : outcomeToken.noTokenId(mktId);
                outcomeToken.safeTransferFrom(address(this), caller, tokenId, lots, "");
            }
        } else {
            uint256 collateral = (side == Side.Bid)
                ? (lots * LOT_SIZE * tick) / 100
                : (lots * LOT_SIZE * (100 - tick)) / 100;
            refund = collateral + feeModel.calculateFee(collateral);
        }

        emit OrderCancelled(orderId, mktId, caller);
    }

    function _placeOne(
        uint256 marketId,
        uint32 batchId,
        OrderParam calldata p,
        address caller
    ) internal returns (uint64 oid, uint256 deposit) {
        oid = nextOrderId++;
        orders[oid] = Order({
            owner: caller,
            side: p.side,
            orderType: p.orderType,
            tick: p.tick,
            lots: p.lots,
            id: oid,
            marketId: uint32(marketId),
            batchId: batchId,
            timestamp: uint40(block.timestamp)
        });

        if (p.side == Side.SellYes || p.side == Side.SellNo) {
            bool isYes = (p.side == Side.SellYes);
            if (markets[marketId].useInternalPositions) {
                vault.lockPosition(caller, marketId, uint128(p.lots), isYes);
            } else {
                uint256 tokenId = isYes
                    ? outcomeToken.yesTokenId(marketId)
                    : outcomeToken.noTokenId(marketId);
                outcomeToken.safeTransferFrom(caller, address(this), tokenId, p.lots, "");
            }
            if (p.side == Side.SellYes) {
                askTrees[marketId].update(p.tick, int256(uint256(p.lots)));
            } else {
                bidTrees[marketId].update(p.tick, int256(uint256(p.lots)));
            }
        } else {
            uint256 collateral = (p.side == Side.Bid)
                ? (uint256(p.lots) * LOT_SIZE * p.tick) / 100
                : (uint256(p.lots) * LOT_SIZE * (100 - uint256(p.tick))) / 100;
            deposit = collateral + feeModel.calculateFee(collateral);
            if (p.side == Side.Bid) {
                bidTrees[marketId].update(p.tick, int256(uint256(p.lots)));
            } else {
                askTrees[marketId].update(p.tick, int256(uint256(p.lots)));
            }
        }

        batchOrderIds[marketId][batchId].push(oid);
        emit OrderPlaced(oid, marketId, caller, p.side, p.tick, p.lots, batchId);
    }

    // -------------------------------------------------------------------------
    // Batch place orders
    // -------------------------------------------------------------------------

    function placeOrders(uint256 marketId, OrderParam[] calldata params) external nonReentrant returns (uint256[] memory orderIds) {
        Market storage m = markets[marketId];
        require(m.active, "OrderBook: market not active");
        require(!m.halted, "OrderBook: market halted");
        require(block.timestamp < m.expiryTime, "OrderBook: market expired");
        require(params.length > 0, "OrderBook: invalid batch size");
        require(marketId <= type(uint32).max, "OrderBook: marketId overflow");
        require(activeOrderCount[msg.sender][marketId] + uint16(params.length) <= MAX_USER_ORDERS, "OrderBook: too many orders");

        activeOrderCount[msg.sender][marketId] += uint16(params.length);

        orderIds = new uint256[](params.length);
        uint256 totalDeposit;

        uint256 batchId = m.currentBatchId;
        if (batchOrderIds[marketId][batchId].length + params.length > MAX_ORDERS_PER_BATCH) {
            batchId = batchId + 1;
        }
        require(batchOrderIds[marketId][batchId].length + params.length <= MAX_ORDERS_PER_BATCH, "OrderBook: batch overflow");

        uint256 paramsLen = params.length;
        for (uint256 i = 0; i < paramsLen; ) {
            require(params[i].tick >= 1 && params[i].tick <= SegmentTree.MAX_TICK, "OrderBook: tick out of range");
            require(params[i].lots > 0, "OrderBook: zero lots");
            require(params[i].lots >= m.minLots, "OrderBook: below min lots");

            (uint64 oid, uint256 deposit) = _placeOne(marketId, uint32(batchId), params[i], msg.sender);
            orderIds[i] = oid;
            totalDeposit += deposit;
            unchecked { ++i; }
        }

        if (totalDeposit > 0) {
            vault.depositFor(msg.sender, totalDeposit);
            vault.lock(msg.sender, totalDeposit);
        }
    }

    // -------------------------------------------------------------------------
    // Replace orders (atomic cancel + place with net settlement)
    // -------------------------------------------------------------------------

    function replaceOrders(uint256[] calldata cancelIds, uint256 marketId, OrderParam[] calldata params) external nonReentrant returns (uint256[] memory orderIds) {
        Market storage m = markets[marketId];
        require(m.active, "OrderBook: market not active");
        require(!m.halted, "OrderBook: market halted");
        require(block.timestamp < m.expiryTime, "OrderBook: market expired");
        require(marketId <= type(uint32).max, "OrderBook: marketId overflow");

        uint256 totalRefund;
        uint256 cancelLen = cancelIds.length;
        for (uint256 i = 0; i < cancelLen; ) {
            totalRefund += _cancelForReplace(cancelIds[i], msg.sender);
            unchecked { ++i; }
        }

        orderIds = new uint256[](params.length);
        uint256 totalDeposit;

        if (params.length > 0) {
            require(activeOrderCount[msg.sender][marketId] + uint16(params.length) <= MAX_USER_ORDERS, "OrderBook: too many orders");
            activeOrderCount[msg.sender][marketId] += uint16(params.length);

            uint256 batchId = m.currentBatchId;
            if (batchOrderIds[marketId][batchId].length + params.length > MAX_ORDERS_PER_BATCH) {
                batchId = batchId + 1;
            }
            require(batchOrderIds[marketId][batchId].length + params.length <= MAX_ORDERS_PER_BATCH, "OrderBook: batch overflow");

            uint256 paramsLen2 = params.length;
            for (uint256 i = 0; i < paramsLen2; ) {
                require(params[i].tick >= 1 && params[i].tick <= SegmentTree.MAX_TICK, "OrderBook: tick out of range");
                require(params[i].lots > 0, "OrderBook: zero lots");
                require(params[i].lots >= m.minLots, "OrderBook: below min lots");

                (uint64 oid, uint256 deposit) = _placeOne(marketId, uint32(batchId), params[i], msg.sender);
                orderIds[i] = oid;
                totalDeposit += deposit;
                unchecked { ++i; }
            }
        }

        // Net settlement
        if (totalDeposit > totalRefund) {
            uint256 netDeposit = totalDeposit - totalRefund;
            vault.depositFor(msg.sender, netDeposit);
            vault.lock(msg.sender, netDeposit);
        } else if (totalRefund > totalDeposit) {
            uint256 netRefund = totalRefund - totalDeposit;
            vault.unlock(msg.sender, netRefund);
            vault.withdrawTo(msg.sender, netRefund);
        }
    }

    // -------------------------------------------------------------------------
    // Cancel order
    // -------------------------------------------------------------------------

    /// @dev Core cancel logic: zeroes lots, updates tree, returns tokens or USDT.
    function _cancelCore(uint256 orderId, address recipient) internal {
        Order storage o = orders[orderId];
        uint256 lots = o.lots;
        uint256 tick = o.tick;
        uint256 marketId = o.marketId;
        Side side = o.side;

        o.lots = 0;

        if (activeOrderCount[recipient][marketId] > 0) {
            activeOrderCount[recipient][marketId]--;
        }

        if (side == Side.Bid || side == Side.SellNo) {
            bidTrees[marketId].update(tick, -int256(lots));
        } else {
            askTrees[marketId].update(tick, -int256(lots));
        }

        if (side == Side.SellYes || side == Side.SellNo) {
            bool isYes = (side == Side.SellYes);
            if (markets[marketId].useInternalPositions) {
                vault.unlockPosition(recipient, marketId, uint128(lots), isYes);
            } else {
                uint256 tokenId = isYes
                    ? outcomeToken.yesTokenId(marketId)
                    : outcomeToken.noTokenId(marketId);
                outcomeToken.safeTransferFrom(address(this), recipient, tokenId, lots, "");
            }
        } else {
            uint256 collateral = (side == Side.Bid)
                ? (lots * LOT_SIZE * tick) / 100
                : (lots * LOT_SIZE * (100 - tick)) / 100;
            uint256 totalReturn = collateral + feeModel.calculateFee(collateral);
            vault.unlock(recipient, totalReturn);
            vault.withdrawTo(recipient, totalReturn);
        }

        emit OrderCancelled(orderId, marketId, recipient);
    }

    function cancelOrder(uint256 orderId) external nonReentrant {
        Order storage o = orders[orderId];
        require(o.owner == msg.sender, "OrderBook: not owner");
        require(o.lots > 0, "OrderBook: already cancelled/filled");
        _cancelCore(orderId, msg.sender);
    }

    /// @notice Batch cancel multiple orders owned by the caller.
    /// @dev Skips already-cancelled/filled orders (lots == 0) silently.
    ///      Reverts the whole batch if any order is not owned by msg.sender.
    function cancelOrders(uint256[] calldata orderIds) external nonReentrant {
        uint256 len = orderIds.length;
        for (uint256 i = 0; i < len; ) {
            Order storage o = orders[orderIds[i]];
            if (o.lots == 0) { unchecked { ++i; } continue; }
            require(o.owner == msg.sender, "OrderBook: not owner");
            _cancelCore(orderIds[i], msg.sender);
            unchecked { ++i; }
        }
    }

    /// @notice Cancel an order on an expired market. Anyone can call this to
    ///         release escrowed funds back to the order owner.
    function cancelExpiredOrder(uint256 orderId) external nonReentrant {
        Order storage o = orders[orderId];
        require(o.lots > 0, "OrderBook: already cancelled/filled");
        Market storage m = markets[o.marketId];
        require(block.timestamp > m.expiryTime, "OrderBook: market not expired");
        _cancelCore(orderId, o.owner);
    }

    /// @notice Batch cancel expired orders. Anyone can call.
    function cancelExpiredOrders(uint256[] calldata orderIds) external nonReentrant {
        uint256 len = orderIds.length;
        for (uint256 i = 0; i < len; ) {
            Order storage o = orders[orderIds[i]];
            if (o.lots == 0) { unchecked { ++i; } continue; }
            Market storage m = markets[o.marketId];
            if (block.timestamp <= m.expiryTime) { unchecked { ++i; } continue; }
            _cancelCore(orderIds[i], o.owner);
            unchecked { ++i; }
        }
    }

    // -------------------------------------------------------------------------
    // Batch order tracking (for atomic settlement)
    // -------------------------------------------------------------------------

    function getBatchOrderIds(uint256 marketId, uint256 batchId) external view returns (uint256[] memory) {
        return batchOrderIds[marketId][batchId];
    }

    /// @notice Push an order ID to a batch's order list (for GTC rollover).
    ///         No cap — chunked clearBatch handles arbitrarily large batches.
    function pushBatchOrderId(uint256 marketId, uint256 batchId, uint256 orderId) external onlyRole(OPERATOR_ROLE) returns (bool) {
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
        if (side == Side.Bid || side == Side.SellNo) {
            bidTrees[marketId].update(tick, delta);
        } else {
            askTrees[marketId].update(tick, delta);
        }
    }

    /// @notice Transfer outcome tokens held in escrow to a recipient (for sell order settlement).
    function transferEscrowTokens(address to, uint256 tokenId, uint256 amount) external onlyRole(OPERATOR_ROLE) {
        outcomeToken.safeTransferFrom(address(this), to, tokenId, amount, "");
    }

    function decrementActiveOrderCount(address user, uint256 marketId) external onlyRole(OPERATOR_ROLE) {
        if (activeOrderCount[user][marketId] > 0) {
            activeOrderCount[user][marketId]--;
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

    // -------------------------------------------------------------------------
    // ERC-165 override (AccessControl + ERC1155Holder)
    // -------------------------------------------------------------------------

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(AccessControl, ERC1155Holder)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
