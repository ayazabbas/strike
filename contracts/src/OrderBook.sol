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

    struct AmendEventData {
        uint256 orderId;
        uint256 marketId;
        address owner;
        uint256 oldTick;
        uint256 newTick;
        uint256 oldLots;
        uint256 newLots;
        uint256 oldFeeBps;
        uint256 newFeeBps;
        uint256 oldBatchId;
        uint256 newBatchId;
        bool wasResting;
        bool isResting;
    }

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    uint256 public constant MAX_ORDERS_PER_BATCH = 1600;
    uint16 public constant MAX_USER_ORDERS = 20;
    uint256 public constant PROXIMITY_THRESHOLD = 20;
    uint256 public constant MAX_RESTING_PULL = 200;
    uint256 public constant MAX_RESTING_SCAN = 400;

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    Vault public immutable vault;
    FeeModel public immutable feeModel;
    OutcomeToken public immutable outcomeToken;

    uint64 public nextOrderId = 1;
    uint32 public nextMarketId = 1;

    /// @notice Set the next market ID counter (admin only, for redeployments).
    function setNextMarketId(uint32 _nextId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_nextId >= nextMarketId, "OrderBook: cannot decrease");
        nextMarketId = _nextId;
    }

    /// @notice Set the next order ID counter (admin only, for redeployments).
    function setNextOrderId(uint64 _nextId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_nextId >= nextOrderId, "OrderBook: cannot decrease");
        nextOrderId = _nextId;
    }

    mapping(uint256 => Market) public markets;
    mapping(uint256 => Order) public orders;
    mapping(uint256 => SegmentTree.Tree) internal bidTrees;
    mapping(uint256 => SegmentTree.Tree) internal askTrees;

    /// @notice marketId => batchId => array of order IDs placed in that batch
    mapping(uint256 => mapping(uint256 => uint256[])) internal batchOrderIds;

    /// @notice user => marketId => number of active orders (both active and resting)
    mapping(address => mapping(uint256 => uint16)) public activeOrderCount;

    /// @notice marketId => array of resting (parked) order IDs far from price
    mapping(uint256 => uint256[]) public restingOrderIds;

    /// @notice marketId => last clearing tick (reference price for proximity filtering)
    mapping(uint256 => uint8) public lastClearingTick;

    /// @notice marketId => scan index for gas-bounded resting order pull-in
    mapping(uint256 => uint256) public restingScanIndex;

    /// @notice orderId => true if the order is in the resting list (not in tree)
    mapping(uint256 => bool) public isResting;

    /// @notice orderId => resting index + 1 for O(1) swap-removal
    mapping(uint256 => uint256) public restingIndexPlusOne;

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
    event OrderResting(uint256 indexed orderId, uint256 indexed marketId, address indexed owner);
    event OrderAmended(
        uint256 indexed orderId,
        uint256 indexed marketId,
        address indexed owner,
        uint256 oldTick,
        uint256 newTick,
        uint256 oldLots,
        uint256 newLots,
        uint256 oldFeeBps,
        uint256 newFeeBps,
        uint256 oldBatchId,
        uint256 newBatchId,
        bool wasResting,
        bool isResting
    );

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

    function registerMarket(uint256 minLots, uint256 batchInterval, uint256 expiryTime, bool useInternalPositions)
        external
        onlyRole(OPERATOR_ROLE)
        returns (uint256 marketId)
    {
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

    /// @dev Lock collateral/tokens and optionally add to tree for an order.
    function _lockAndTree(uint256 marketId, Side side, uint256 tick, uint256 lots, bool addToTree) internal {
        bool isSell = (side == Side.SellYes || side == Side.SellNo);
        if (isSell) {
            bool isYes = (side == Side.SellYes);
            if (markets[marketId].useInternalPositions) {
                vault.lockPosition(msg.sender, marketId, uint128(lots), isYes);
            } else {
                uint256 tokenId = isYes ? outcomeToken.yesTokenId(marketId) : outcomeToken.noTokenId(marketId);
                outcomeToken.safeTransferFrom(msg.sender, address(this), tokenId, lots, "");
            }
            if (addToTree) {
                if (side == Side.SellYes) {
                    askTrees[marketId].update(tick, int256(lots));
                } else {
                    bidTrees[marketId].update(tick, int256(lots));
                }
            }
        } else {
            uint256 collateral =
                (side == Side.Bid) ? (lots * LOT_SIZE * tick) / 100 : (lots * LOT_SIZE * (100 - tick)) / 100;
            uint256 totalDeposit = collateral + feeModel.calculateFee(collateral);
            if (addToTree) {
                if (side == Side.Bid) {
                    bidTrees[marketId].update(tick, int256(lots));
                } else {
                    askTrees[marketId].update(tick, int256(lots));
                }
            }
            vault.depositFor(msg.sender, totalDeposit);
            vault.lock(msg.sender, totalDeposit);
        }
    }

    function _requiredCollateral(Side side, uint256 tick, uint256 lots) internal pure returns (uint256) {
        return (side == Side.Bid) ? (lots * LOT_SIZE * tick) / 100 : (lots * LOT_SIZE * (100 - tick)) / 100;
    }

    function _requiredLockedAmount(Side side, uint256 tick, uint256 lots, uint256 feeBps)
        internal
        pure
        returns (uint256)
    {
        if (side == Side.SellYes || side == Side.SellNo) return 0;
        uint256 collateral = _requiredCollateral(side, tick, lots);
        return collateral + ((collateral * feeBps) / 10_000);
    }

    function _applyTreeDelta(uint256 marketId, Side side, uint256 tick, int256 delta) internal {
        if (side == Side.Bid || side == Side.SellNo) {
            bidTrees[marketId].update(tick, delta);
        } else {
            askTrees[marketId].update(tick, delta);
        }
    }

    function _addRestingOrder(uint256 marketId, uint256 orderId) internal {
        if (isResting[orderId]) return;
        restingOrderIds[marketId].push(orderId);
        restingIndexPlusOne[orderId] = restingOrderIds[marketId].length;
        isResting[orderId] = true;
    }

    function _removeRestingOrderAtIndex(uint256 marketId, uint256 idx)
        internal
        returns (uint256 swappedOrderId, bool swapped)
    {
        uint256[] storage resting = restingOrderIds[marketId];
        uint256 lastIdx = resting.length - 1;
        uint256 removedOrderId = resting[idx];

        restingIndexPlusOne[removedOrderId] = 0;
        isResting[removedOrderId] = false;

        if (idx != lastIdx) {
            swappedOrderId = resting[lastIdx];
            resting[idx] = swappedOrderId;
            restingIndexPlusOne[swappedOrderId] = idx + 1;
            swapped = true;
        }

        resting.pop();
    }

    function _removeRestingOrder(uint256 marketId, uint256 orderId) internal returns (bool removed) {
        uint256 idxPlusOne = restingIndexPlusOne[orderId];
        if (idxPlusOne == 0) return false;
        _removeRestingOrderAtIndex(marketId, idxPlusOne - 1);
        removed = true;
    }

    function placeOrder(uint256 marketId, Side side, OrderType orderType, uint256 tick, uint256 lots)
        external
        nonReentrant
        returns (uint256 orderId)
    {
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
                timestamp: uint40(block.timestamp),
                feeBps: uint16(feeModel.feeBps())
            });
        }

        bool shouldRest = isTickFar(marketId, tick, side);
        _lockAndTree(marketId, side, tick, lots, !shouldRest);

        if (shouldRest) {
            _addRestingOrder(marketId, orderId);
            emit OrderResting(orderId, marketId, msg.sender);
        } else {
            batchOrderIds[marketId][batchId].push(orderId);
            emit OrderPlaced(orderId, marketId, msg.sender, side, tick, lots, batchId);
        }
    }

    // -------------------------------------------------------------------------
    // Internal helpers for batch operations
    // -------------------------------------------------------------------------

    function _cancelForReplace(uint256 orderId, address caller) internal returns (uint256 refund) {
        Order storage o = orders[orderId];
        if (o.lots == 0) {
            // Order already settled by clearBatch — settlement already decremented
            // activeOrderCount. Do NOT decrement again; that would desync the counter
            // and cause "counter underflow" reverts when cancelling other live orders.
            return 0;
        }
        require(o.owner == caller, "OrderBook: not owner");

        uint256 lots = o.lots;
        uint256 tick = o.tick;
        uint256 mktId = o.marketId;
        Side side = o.side;
        uint256 storedFeeBps = o.feeBps;
        o.lots = 0;

        require(activeOrderCount[caller][mktId] > 0, "OrderBook: counter underflow");
        activeOrderCount[caller][mktId]--;

        if (!isResting[orderId]) {
            _applyTreeDelta(mktId, side, tick, -int256(lots));
        } else {
            _removeRestingOrder(mktId, orderId);
        }

        if (side == Side.SellYes || side == Side.SellNo) {
            bool isYes = (side == Side.SellYes);
            if (markets[mktId].useInternalPositions) {
                vault.unlockPosition(caller, mktId, uint128(lots), isYes);
            } else {
                uint256 tokenId = isYes ? outcomeToken.yesTokenId(mktId) : outcomeToken.noTokenId(mktId);
                outcomeToken.safeTransferFrom(address(this), caller, tokenId, lots, "");
            }
        } else {
            uint256 collateral = _requiredCollateral(side, tick, lots);
            uint256 fee = (collateral * storedFeeBps) / 10_000;
            refund = collateral + fee;
        }

        emit OrderCancelled(orderId, mktId, caller);
    }

    function _placeOne(uint256 marketId, uint32 batchId, OrderParam calldata p, address caller)
        internal
        returns (uint64 oid, uint256 deposit)
    {
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
            timestamp: uint40(block.timestamp),
            feeBps: uint16(feeModel.feeBps())
        });

        bool shouldRest = isTickFar(marketId, p.tick, p.side);

        if (p.side == Side.SellYes || p.side == Side.SellNo) {
            bool isYes = (p.side == Side.SellYes);
            if (markets[marketId].useInternalPositions) {
                vault.lockPosition(caller, marketId, uint128(p.lots), isYes);
            } else {
                uint256 tokenId = isYes ? outcomeToken.yesTokenId(marketId) : outcomeToken.noTokenId(marketId);
                outcomeToken.safeTransferFrom(caller, address(this), tokenId, p.lots, "");
            }
            if (!shouldRest) {
                if (p.side == Side.SellYes) {
                    askTrees[marketId].update(p.tick, int256(uint256(p.lots)));
                } else {
                    bidTrees[marketId].update(p.tick, int256(uint256(p.lots)));
                }
            }
        } else {
            uint256 collateral = (p.side == Side.Bid)
                ? (uint256(p.lots) * LOT_SIZE * p.tick) / 100
                : (uint256(p.lots) * LOT_SIZE * (100 - uint256(p.tick))) / 100;
            deposit = collateral + feeModel.calculateFee(collateral);
            if (!shouldRest) {
                if (p.side == Side.Bid) {
                    bidTrees[marketId].update(p.tick, int256(uint256(p.lots)));
                } else {
                    askTrees[marketId].update(p.tick, int256(uint256(p.lots)));
                }
            }
        }

        if (shouldRest) {
            _addRestingOrder(marketId, oid);
            emit OrderResting(oid, marketId, caller);
        } else {
            batchOrderIds[marketId][batchId].push(oid);
            emit OrderPlaced(oid, marketId, caller, p.side, p.tick, p.lots, batchId);
        }
    }

    // -------------------------------------------------------------------------
    // Batch place orders
    // -------------------------------------------------------------------------

    function placeOrders(uint256 marketId, OrderParam[] calldata params)
        external
        nonReentrant
        returns (uint256[] memory orderIds)
    {
        Market storage m = markets[marketId];
        require(m.active, "OrderBook: market not active");
        require(!m.halted, "OrderBook: market halted");
        require(block.timestamp < m.expiryTime, "OrderBook: market expired");
        require(params.length > 0, "OrderBook: invalid batch size");
        require(marketId <= type(uint32).max, "OrderBook: marketId overflow");
        require(
            activeOrderCount[msg.sender][marketId] + uint16(params.length) <= MAX_USER_ORDERS,
            "OrderBook: too many orders"
        );

        activeOrderCount[msg.sender][marketId] += uint16(params.length);

        orderIds = new uint256[](params.length);
        uint256 totalDeposit;

        uint256 batchId = m.currentBatchId;
        if (batchOrderIds[marketId][batchId].length + params.length > MAX_ORDERS_PER_BATCH) {
            batchId = batchId + 1;
        }
        require(
            batchOrderIds[marketId][batchId].length + params.length <= MAX_ORDERS_PER_BATCH, "OrderBook: batch overflow"
        );

        uint256 paramsLen = params.length;
        for (uint256 i = 0; i < paramsLen;) {
            require(params[i].tick >= 1 && params[i].tick <= SegmentTree.MAX_TICK, "OrderBook: tick out of range");
            require(params[i].lots > 0, "OrderBook: zero lots");
            require(params[i].lots >= m.minLots, "OrderBook: below min lots");

            (uint64 oid, uint256 deposit) = _placeOne(marketId, uint32(batchId), params[i], msg.sender);
            orderIds[i] = oid;
            totalDeposit += deposit;
            unchecked {
                ++i;
            }
        }

        if (totalDeposit > 0) {
            vault.depositFor(msg.sender, totalDeposit);
            vault.lock(msg.sender, totalDeposit);
        }
    }

    function _applyAmendVaultDelta(address user, uint256 oldRequired, uint256 newRequired) internal {
        if (newRequired > oldRequired) {
            uint256 netIncrease = newRequired - oldRequired;
            uint256 available = vault.available(user);
            if (available < netIncrease) {
                vault.depositFor(user, netIncrease - available);
            }
            vault.lock(user, netIncrease);
        } else if (oldRequired > newRequired) {
            vault.unlock(user, oldRequired - newRequired);
        }
    }

    function _previewAmendOrders(
        uint256 marketId,
        Market storage m,
        AmendOrderParam[] calldata params,
        address caller,
        bool[] memory wasResting,
        bool[] memory willRest,
        uint16[] memory refreshedFeeBps
    ) internal view returns (uint256 totalOldRequired, uint256 totalNewRequired, uint256 activatingCount) {
        uint256 len = params.length;
        for (uint256 i = 0; i < len;) {
            AmendOrderParam calldata p = params[i];
            for (uint256 j = i + 1; j < len;) {
                require(p.orderId != params[j].orderId, "OrderBook: duplicate amend");
                unchecked {
                    ++j;
                }
            }

            Order storage o = orders[p.orderId];
            require(o.owner == caller, "OrderBook: not owner");
            require(o.lots > 0, "OrderBook: already cancelled/filled");
            require(o.marketId == marketId, "OrderBook: wrong market");
            require(o.orderType == OrderType.GoodTilCancel, "OrderBook: amend only GTC");
            require(o.side == Side.Bid || o.side == Side.Ask, "OrderBook: amend buy-side only");
            require(p.newTick >= 1 && p.newTick <= SegmentTree.MAX_TICK, "OrderBook: tick out of range");
            require(p.newLots > 0, "OrderBook: zero lots");
            require(p.newLots >= m.minLots, "OrderBook: below min lots");

            wasResting[i] = isResting[p.orderId];
            willRest[i] = isTickFar(marketId, p.newTick, o.side);
            require(wasResting[i] || !willRest[i], "OrderBook: amend would rest");
            if (wasResting[i] && !willRest[i]) {
                activatingCount++;
            }

            refreshedFeeBps[i] = uint16(feeModel.feeBps());
            totalOldRequired += _requiredLockedAmount(o.side, o.tick, o.lots, o.feeBps);
            totalNewRequired += _requiredLockedAmount(o.side, p.newTick, p.newLots, refreshedFeeBps[i]);

            unchecked {
                ++i;
            }
        }
    }

    function _resolveAmendBatchId(uint256 marketId, uint32 currentBatchId, uint256 activatingCount)
        internal
        view
        returns (uint32 amendBatchId)
    {
        amendBatchId = currentBatchId;
        if (activatingCount == 0) return amendBatchId;

        if (batchOrderIds[marketId][amendBatchId].length + activatingCount > MAX_ORDERS_PER_BATCH) {
            amendBatchId = amendBatchId + 1;
        }
        require(
            batchOrderIds[marketId][amendBatchId].length + activatingCount <= MAX_ORDERS_PER_BATCH,
            "OrderBook: batch overflow"
        );
    }

    function _applySingleAmend(
        uint256 marketId,
        uint32 amendBatchId,
        AmendOrderParam calldata p,
        bool wasRestingOrder,
        bool willRestOrder,
        uint16 refreshedFeeBps,
        address owner
    ) internal {
        Order storage o = orders[p.orderId];
        AmendEventData memory eventData;
        eventData.orderId = p.orderId;
        eventData.marketId = marketId;
        eventData.owner = owner;
        eventData.oldTick = o.tick;
        eventData.newTick = p.newTick;
        eventData.oldLots = o.lots;
        eventData.newLots = p.newLots;
        eventData.oldFeeBps = o.feeBps;
        eventData.newFeeBps = refreshedFeeBps;
        eventData.oldBatchId = o.batchId;
        eventData.wasResting = wasRestingOrder;
        eventData.isResting = willRestOrder;

        if (wasRestingOrder) {
            if (!willRestOrder) {
                _removeRestingOrder(marketId, p.orderId);
                _applyTreeDelta(marketId, o.side, p.newTick, int256(uint256(p.newLots)));
                batchOrderIds[marketId][amendBatchId].push(p.orderId);
                o.batchId = amendBatchId;
            }
        } else if (o.tick == p.newTick) {
            if (p.newLots > o.lots) {
                _applyTreeDelta(marketId, o.side, p.newTick, int256(uint256(p.newLots - o.lots)));
            } else if (o.lots > p.newLots) {
                _applyTreeDelta(marketId, o.side, p.newTick, -int256(uint256(o.lots - p.newLots)));
            }
        } else {
            _applyTreeDelta(marketId, o.side, o.tick, -int256(uint256(o.lots)));
            _applyTreeDelta(marketId, o.side, p.newTick, int256(uint256(p.newLots)));
        }

        o.tick = p.newTick;
        o.lots = p.newLots;
        o.feeBps = refreshedFeeBps;
        eventData.newBatchId = o.batchId;
        _emitOrderAmended(eventData);
    }

    function _emitOrderAmended(AmendEventData memory eventData) internal {
        emit OrderAmended(
            eventData.orderId,
            eventData.marketId,
            eventData.owner,
            eventData.oldTick,
            eventData.newTick,
            eventData.oldLots,
            eventData.newLots,
            eventData.oldFeeBps,
            eventData.newFeeBps,
            eventData.oldBatchId,
            eventData.newBatchId,
            eventData.wasResting,
            eventData.isResting
        );
    }

    // -------------------------------------------------------------------------
    // Amend orders (in-place GTC update)
    // -------------------------------------------------------------------------

    function amendOrders(uint256 marketId, AmendOrderParam[] calldata params) external nonReentrant {
        Market storage m = markets[marketId];
        require(m.active, "OrderBook: market not active");
        require(!m.halted, "OrderBook: market halted");
        require(block.timestamp < m.expiryTime, "OrderBook: market expired");
        require(params.length > 0, "OrderBook: invalid batch size");
        require(marketId <= type(uint32).max, "OrderBook: marketId overflow");

        uint256 len = params.length;
        bool[] memory wasResting = new bool[](len);
        bool[] memory willRest = new bool[](len);
        uint16[] memory newFeeBps = new uint16[](len);
        (uint256 totalOldRequired, uint256 totalNewRequired, uint256 activatingCount) =
            _previewAmendOrders(marketId, m, params, msg.sender, wasResting, willRest, newFeeBps);

        _applyAmendVaultDelta(msg.sender, totalOldRequired, totalNewRequired);

        uint32 amendBatchId = _resolveAmendBatchId(marketId, m.currentBatchId, activatingCount);

        for (uint256 i = 0; i < len;) {
            _applySingleAmend(marketId, amendBatchId, params[i], wasResting[i], willRest[i], newFeeBps[i], msg.sender);

            unchecked {
                ++i;
            }
        }
    }

    // -------------------------------------------------------------------------
    // Replace orders (atomic cancel + place with net settlement)
    // -------------------------------------------------------------------------

    function replaceOrders(uint256[] calldata cancelIds, uint256 marketId, OrderParam[] calldata params)
        external
        nonReentrant
        returns (uint256[] memory orderIds)
    {
        Market storage m = markets[marketId];
        require(m.active, "OrderBook: market not active");
        require(!m.halted, "OrderBook: market halted");
        require(block.timestamp < m.expiryTime, "OrderBook: market expired");
        require(marketId <= type(uint32).max, "OrderBook: marketId overflow");

        uint256 totalRefund;
        uint256 cancelLen = cancelIds.length;
        for (uint256 i = 0; i < cancelLen;) {
            totalRefund += _cancelForReplace(cancelIds[i], msg.sender);
            unchecked {
                ++i;
            }
        }

        orderIds = new uint256[](params.length);
        uint256 totalDeposit;

        if (params.length > 0) {
            require(
                activeOrderCount[msg.sender][marketId] + uint16(params.length) <= MAX_USER_ORDERS,
                "OrderBook: too many orders"
            );
            activeOrderCount[msg.sender][marketId] += uint16(params.length);

            uint256 batchId = m.currentBatchId;
            if (batchOrderIds[marketId][batchId].length + params.length > MAX_ORDERS_PER_BATCH) {
                batchId = batchId + 1;
            }
            require(
                batchOrderIds[marketId][batchId].length + params.length <= MAX_ORDERS_PER_BATCH,
                "OrderBook: batch overflow"
            );

            uint256 paramsLen2 = params.length;
            for (uint256 i = 0; i < paramsLen2;) {
                require(params[i].tick >= 1 && params[i].tick <= SegmentTree.MAX_TICK, "OrderBook: tick out of range");
                require(params[i].lots > 0, "OrderBook: zero lots");
                require(params[i].lots >= m.minLots, "OrderBook: below min lots");

                (uint64 oid, uint256 deposit) = _placeOne(marketId, uint32(batchId), params[i], msg.sender);
                orderIds[i] = oid;
                totalDeposit += deposit;
                unchecked {
                    ++i;
                }
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
    ///      Resting orders are NOT in the tree — they are lazy-skipped during scan.
    function _cancelCore(uint256 orderId, address recipient) internal {
        Order storage o = orders[orderId];
        uint256 lots = o.lots;
        uint256 tick = o.tick;
        uint256 marketId = o.marketId;
        Side side = o.side;
        uint256 storedFeeBps = o.feeBps;

        o.lots = 0;

        require(activeOrderCount[recipient][marketId] > 0, "OrderBook: counter underflow");
        activeOrderCount[recipient][marketId]--;

        // Only update tree if order is NOT resting (resting orders were never added to tree)
        if (!isResting[orderId]) {
            _applyTreeDelta(marketId, side, tick, -int256(lots));
        } else {
            _removeRestingOrder(marketId, orderId);
        }

        if (side == Side.SellYes || side == Side.SellNo) {
            bool isYes = (side == Side.SellYes);
            if (markets[marketId].useInternalPositions) {
                vault.unlockPosition(recipient, marketId, uint128(lots), isYes);
            } else {
                uint256 tokenId = isYes ? outcomeToken.yesTokenId(marketId) : outcomeToken.noTokenId(marketId);
                outcomeToken.safeTransferFrom(address(this), recipient, tokenId, lots, "");
            }
        } else {
            uint256 collateral = _requiredCollateral(side, tick, lots);
            uint256 fee = (collateral * storedFeeBps) / 10_000;
            uint256 totalReturn = collateral + fee;
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
        for (uint256 i = 0; i < len;) {
            Order storage o = orders[orderIds[i]];
            if (o.lots == 0) {
                unchecked {
                    ++i;
                }
                continue;
            }
            require(o.owner == msg.sender, "OrderBook: not owner");
            _cancelCore(orderIds[i], msg.sender);
            unchecked {
                ++i;
            }
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
        for (uint256 i = 0; i < len;) {
            Order storage o = orders[orderIds[i]];
            if (o.lots == 0) {
                unchecked {
                    ++i;
                }
                continue;
            }
            Market storage m = markets[o.marketId];
            if (block.timestamp <= m.expiryTime) {
                unchecked {
                    ++i;
                }
                continue;
            }
            _cancelCore(orderIds[i], o.owner);
            unchecked {
                ++i;
            }
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
    function pushBatchOrderId(uint256 marketId, uint256 batchId, uint256 orderId)
        external
        onlyRole(OPERATOR_ROLE)
        returns (bool)
    {
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

    function updateTreeVolume(uint256 marketId, Side side, uint256 tick, int256 delta)
        external
        onlyRole(OPERATOR_ROLE)
    {
        _applyTreeDelta(marketId, side, tick, delta);
    }

    /// @notice Transfer outcome tokens held in escrow to a recipient (for sell order settlement).
    function transferEscrowTokens(address to, uint256 tokenId, uint256 amount) external onlyRole(OPERATOR_ROLE) {
        outcomeToken.safeTransferFrom(address(this), to, tokenId, amount, "");
    }

    function decrementActiveOrderCount(address user, uint256 marketId) external onlyRole(OPERATOR_ROLE) {
        require(activeOrderCount[user][marketId] > 0, "OrderBook: counter underflow");
        activeOrderCount[user][marketId]--;
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
    // Resting order management (price-proximity filtering)
    // -------------------------------------------------------------------------

    function _isTickFarFromReference(uint256 ref, uint256 tick, Side side) internal pure returns (bool) {
        if (ref == 0) return false;
        if (side == Side.Bid || side == Side.SellNo) {
            if (ref > PROXIMITY_THRESHOLD) {
                return tick < ref - PROXIMITY_THRESHOLD;
            }
            return false;
        } else {
            if (ref + PROXIMITY_THRESHOLD < 100) {
                return tick > ref + PROXIMITY_THRESHOLD;
            }
            return false;
        }
    }

    /// @notice Returns the live reference tick used for active/resting classification.
    ///         Uses the current active book when possible and falls back to the last
    ///         clearing tick only when the book is empty.
    function currentReferenceTick(uint256 marketId) public view returns (uint256 ref) {
        uint256 bestBid = bidTrees[marketId].highestTick();
        uint256 bestAsk = askTrees[marketId].lowestTick();

        if (bestBid > 0 && bestAsk > 0) {
            if (bestBid >= bestAsk) {
                ref = SegmentTree.findClearingTick(bidTrees[marketId], askTrees[marketId]);
                if (ref > 0) return ref;
            }
            return (bestBid + bestAsk) / 2;
        }

        if (bestBid > 0) return bestBid;
        if (bestAsk > 0) return bestAsk;
        return lastClearingTick[marketId];
    }

    /// @dev Returns true if order tick is far from the current live reference.
    function isTickFar(uint256 marketId, uint256 tick, Side side) public view returns (bool) {
        return _isTickFarFromReference(currentReferenceTick(marketId), tick, side);
    }

    /// @notice Pull in-range resting orders into the current batch and tree.
    ///         Scans a bounded window (MAX_RESTING_SCAN) starting from restingScanIndex,
    ///         pruning cancelled/stale GTB orders as encountered.
    ///         Pulls at most MAX_RESTING_PULL orders per call (gas-bounded).
    ///         Multiple clearBatch calls will eventually process the full list.
    ///         Called by BatchAuction before computing clearing price.
    function pullRestingOrders(uint256 marketId) external onlyRole(OPERATOR_ROLE) returns (uint256 pulled) {
        uint256[] storage resting = restingOrderIds[marketId];
        if (resting.length == 0) return 0;

        uint256 batchId = markets[marketId].currentBatchId;
        uint256 ref = currentReferenceTick(marketId);
        uint256 i = restingScanIndex[marketId];
        if (i >= resting.length) i = 0;
        uint256 remaining = resting.length; // track original size for scan bound
        uint256 scanned;

        while (scanned < MAX_RESTING_SCAN && scanned < remaining && resting.length > 0) {
            if (i >= resting.length) i = 0;

            uint256 oid = resting[i];
            Order storage o = orders[oid];

            if (o.lots == 0) {
                _removeRestingOrderAtIndex(marketId, i);
                if (resting.length > 0 && i >= resting.length) i = 0;
            } else if (o.orderType == OrderType.GoodTilBatch && o.batchId < batchId) {
                _cancelCore(oid, o.owner);
                if (resting.length > 0 && i >= resting.length) i = 0;
            } else if (pulled < MAX_RESTING_PULL && !_isTickFarFromReference(ref, o.tick, o.side)) {
                _addToTreeAndBatch(marketId, batchId, oid, o.side, o.tick, o.lots);
                _removeRestingOrderAtIndex(marketId, i);
                pulled++;
                if (resting.length > 0 && i >= resting.length) i = 0;
            } else {
                unchecked {
                    ++i;
                }
            }
            unchecked {
                ++scanned;
            }
        }

        restingScanIndex[marketId] = (resting.length > 0 && i < resting.length) ? i : 0;
    }

    /// @dev Add a resting order to the tree and batch list.
    function _addToTreeAndBatch(uint256 marketId, uint256 batchId, uint256 oid, Side side, uint256 tick, uint256 lots)
        internal
    {
        _applyTreeDelta(marketId, side, tick, int256(lots));
        batchOrderIds[marketId][batchId].push(oid);
    }

    /// @notice Push an order to the resting list (for GTC orders moving away from price).
    function pushRestingOrderId(uint256 marketId, uint256 orderId) external onlyRole(OPERATOR_ROLE) {
        _addRestingOrder(marketId, orderId);
    }

    /// @notice Update the last clearing tick reference price.
    function setLastClearingTick(uint256 marketId, uint8 tick) external onlyRole(OPERATOR_ROLE) {
        lastClearingTick[marketId] = tick;
    }

    /// @notice Remove order volume from the tree (for GTC orders moving to resting).
    function removeFromTree(uint256 marketId, Side side, uint256 tick, uint256 lots) external onlyRole(OPERATOR_ROLE) {
        _applyTreeDelta(marketId, side, tick, -int256(lots));
    }

    /// @notice Get the resting order IDs for a market.
    function getRestingOrderIds(uint256 marketId) external view returns (uint256[] memory) {
        return restingOrderIds[marketId];
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
