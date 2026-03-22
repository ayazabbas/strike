// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./ITypes.sol";
import "./OrderBook.sol";
import "./Vault.sol";
import "./FeeModel.sol";
import "./OutcomeToken.sol";

/// @title BatchAuction
/// @notice Implements Frequent Batch Auction clearing for the Strike CLOB.
///         clearBatch(marketId) atomically: advances batch, finds clearing price,
///         and settles ALL orders in the batch. No separate claimFills needed.
///         Settlement uses the CLEARING price, not the order's limit price.
contract BatchAuction is AccessControl, ReentrancyGuard {
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    OrderBook public immutable orderBook;
    Vault public immutable vault;
    OutcomeToken public immutable outcomeToken;
    FeeModel public immutable feeModel;

    /// @notice marketId => batchId => BatchResult
    mapping(uint256 => mapping(uint256 => BatchResult)) public batchResults;

    /// @notice Tracks settlement progress for chunked clearing.
    ///         marketId => batchId => number of orders settled so far.
    mapping(uint256 => mapping(uint256 => uint256)) public settledUpTo;

    /// @notice Precomputed fill lots for chunked settlement.
    ///         orderId => fill lots (stored during first chunk, read in subsequent chunks).
    mapping(uint256 => uint256) private _precomputedFills;

    /// @notice Precomputed order info for chunked settlement.
    ///         orderId => encoded flag (1 = has precomputed data).
    mapping(uint256 => uint256) private _hasPrecomputed;

    /// @notice Maximum orders to settle per clearBatch call.
    uint256 public constant SETTLE_CHUNK_SIZE = 400;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event BatchCleared(
        uint256 indexed marketId,
        uint256 indexed batchId,
        uint256 clearingTick,
        uint256 matchedLots
    );
    event OrderSettled(
        uint256 indexed orderId,
        address indexed owner,
        uint256 filledLots,
        uint256 collateralReleased
    );
    event GtcAutoCancelled(uint256 indexed orderId, address indexed owner);

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor(address admin, address _orderBook, address _vault, address _outcomeToken) {
        require(_orderBook != address(0), "BatchAuction: zero orderBook");
        require(_vault != address(0), "BatchAuction: zero vault");
        require(_outcomeToken != address(0), "BatchAuction: zero outcomeToken");

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        orderBook = OrderBook(_orderBook);
        vault = Vault(_vault);
        outcomeToken = OutcomeToken(_outcomeToken);
        feeModel = OrderBook(_orderBook).feeModel();
    }

    // -------------------------------------------------------------------------
    // Batch clearing — atomic: advance + clear + settle all
    // -------------------------------------------------------------------------

    /// @notice Clear a batch for a market. Supports chunked settlement:
    ///         - First call: computes clearing price, stores BatchResult, advances batch,
    ///           and settles up to SETTLE_CHUNK_SIZE orders.
    ///         - Subsequent calls: settles the next chunk of orders.
    ///         - Small batches (<=400 orders) complete in a single tx.
    /// @return result The BatchResult for this batch.
    function clearBatch(uint256 marketId) external nonReentrant returns (BatchResult memory result) {
        // Check if we're continuing settlement of a previous batch
        (uint32 id, bool active, bool halted, uint32 currentBatchId, , , , ) = orderBook.markets(marketId);
        require(id != 0, "BatchAuction: market not found");

        // Check if there's a batch with pending settlement (batch before current)
        uint32 prevBatchId = currentBatchId > 1 ? currentBatchId - 1 : 0;
        if (prevBatchId > 0) {
            BatchResult storage prevResult = batchResults[marketId][prevBatchId];
            if (prevResult.batchId == prevBatchId && prevResult.timestamp > 0) {
                uint256[] memory prevIds = orderBook.getBatchOrderIds(marketId, prevBatchId);
                uint256 settled = settledUpTo[marketId][prevBatchId];
                if (settled < prevIds.length) {
                    // Continue settling the previous batch
                    result = prevResult;
                    _settleChunk(marketId, prevBatchId, result);
                    return result;
                }
            }
        }

        // Phase 1: New batch clearing
        require(active, "BatchAuction: market not active");
        require(!halted, "BatchAuction: market halted");

        uint256 clearingTick = orderBook.findClearingTick(marketId);

        uint256 totalBidLots;
        uint256 totalAskLots;
        uint256 matchedLots;

        if (clearingTick > 0) {
            totalBidLots = orderBook.cumulativeBidVolume(marketId, clearingTick);
            totalAskLots = orderBook.cumulativeAskVolume(marketId, clearingTick);
            matchedLots = totalBidLots < totalAskLots ? totalBidLots : totalAskLots;

            if (matchedLots == 0) {
                clearingTick = 0;
            }
        }

        require(totalBidLots <= type(uint64).max, "BatchAuction: totalBidLots overflow");
        require(totalAskLots <= type(uint64).max, "BatchAuction: totalAskLots overflow");

        result = BatchResult({
            marketId: uint32(marketId),
            batchId: currentBatchId,
            clearingTick: uint8(clearingTick),
            matchedLots: uint64(matchedLots),
            totalBidLots: uint64(totalBidLots),
            totalAskLots: uint64(totalAskLots),
            timestamp: uint40(block.timestamp)
        });

        batchResults[marketId][currentBatchId] = result;

        // Advance batch FIRST — new orders go to currentBatchId+1
        orderBook.advanceBatch(marketId);

        emit BatchCleared(marketId, currentBatchId, clearingTick, matchedLots);

        // Settle orders (first chunk)
        _settleChunk(marketId, currentBatchId, result);
    }

    /// @notice Returns true if the batch is fully settled.
    function isBatchFullySettled(uint256 marketId, uint256 batchId) external view returns (bool) {
        uint256[] memory ids = orderBook.getBatchOrderIds(marketId, batchId);
        return settledUpTo[marketId][batchId] >= ids.length;
    }

    /// @dev Settle a chunk of orders starting from settledUpTo.
    ///      First chunk: computes fills for ALL orders and stores them in _precomputedFills.
    ///      Subsequent chunks: reads from _precomputedFills (since chunk 1 mutated order lots).
    ///      Final chunk: clears the precomputed fill mapping entries.
    function _settleChunk(uint256 marketId, uint256 batchId, BatchResult memory result) internal {
        uint256[] memory ids = orderBook.getBatchOrderIds(marketId, batchId);
        uint256 startIdx = settledUpTo[marketId][batchId];
        if (startIdx >= ids.length) return;

        uint256 endIdx = startIdx + SETTLE_CHUNK_SIZE;
        if (endIdx > ids.length) endIdx = ids.length;
        bool isFinalChunk = (endIdx >= ids.length);

        // Cache isInternalPositions once per chunk (avoids repeated SLOAD per order)
        bool isInternal = _isInternalPositions(marketId);

        if (startIdx == 0) {
            // First chunk: compute fills for ALL orders and store in mapping
            (uint256[] memory fills, OrderInfo[] memory infos) = _computeFills(ids, result);

            // Store precomputed fills for all orders (needed by subsequent chunks)
            uint256 idsLen = ids.length;
            for (uint256 j = 0; j < idsLen; ) {
                _precomputedFills[ids[j]] = fills[j];
                _hasPrecomputed[ids[j]] = 1;
                unchecked { ++j; }
            }

            // Settle the first chunk using the freshly computed data
            for (uint256 i = 0; i < endIdx; ) {
                _settleOrder(ids[i], infos[i], result, fills[i], isInternal);
                unchecked { ++i; }
            }
        } else {
            // Subsequent chunks: read from _precomputedFills
            for (uint256 i = startIdx; i < endIdx; ) {
                uint256 fill = _precomputedFills[ids[i]];
                _settleOrder(ids[i], OrderInfo(0, address(0), Side.Bid, OrderType.GoodTilBatch, 0, 0, 0), result, fill, isInternal);
                unchecked { ++i; }
            }
        }

        // Clean up precomputed fills on final chunk
        if (isFinalChunk) {
            uint256 idsLen = ids.length;
            for (uint256 j = 0; j < idsLen; ) {
                delete _precomputedFills[ids[j]];
                delete _hasPrecomputed[ids[j]];
                unchecked { ++j; }
            }
        }

        settledUpTo[marketId][batchId] = endIdx;
    }

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

    function _isInternalPositions(uint256 marketId) internal view returns (bool) {
        (, , , , , , , bool useInternal) = orderBook.markets(marketId);
        return useInternal;
    }

    function _collateral(uint256 lots, uint256 tick, Side side) internal pure returns (uint256) {
        if (side == Side.Bid || side == Side.SellYes) {
            return (lots * LOT_SIZE * tick) / 100;
        } else {
            return (lots * LOT_SIZE * (100 - tick)) / 100;
        }
    }

    function _isSellOrder(Side side) internal pure returns (bool) {
        return side == Side.SellYes || side == Side.SellNo;
    }

    struct OrderInfo {
        uint256 marketId;
        address owner;
        Side side;
        OrderType orderType;
        uint256 tick;
        uint256 lots;
        uint256 batchId;
    }

    struct SettleAmounts {
        uint256 filledLots;
        uint256 filledCollateral;   // at clearing price
        uint256 excessRefund;       // (lockedForFilled + lockedFeeForFilled) - filledCollateral - protocolFee
        uint256 unfilledCollateral; // at order tick
        uint256 unfilledFee;        // fee portion of unfilled collateral
        uint256 toPool;
        uint256 protocolFee;
    }

    function _readOrder(uint256 orderId) internal view returns (OrderInfo memory info) {
        (
            address owner,
            Side side,
            OrderType orderType,
            uint8 tick,
            uint64 lots,
            uint64 id,
            uint32 marketId,
            uint32 batchId,
        ) = orderBook.orders(orderId);
        require(id != 0, "BatchAuction: order not found");
        info = OrderInfo(marketId, owner, side, orderType, tick, lots, batchId);
    }

    /// @dev Compute fills for all orders with rounding remainder correction.
    ///      Also returns OrderInfo[] so callers can avoid re-reading storage.
    function _computeFills(uint256[] memory ids, BatchResult memory result)
        internal
        view
        returns (uint256[] memory fills, OrderInfo[] memory infos)
    {
        uint256 idsLen = ids.length;
        fills = new uint256[](idsLen);
        infos = new OrderInfo[](idsLen);
        if (result.matchedLots == 0) return (fills, infos);

        uint256 totalFilledBid;
        uint256 totalFilledAsk;

        // 0 = not participating, 1 = participating bid, 2 = participating ask
        uint8[] memory pType = new uint8[](idsLen);

        for (uint256 i = 0; i < idsLen; ) {
            infos[i] = _readOrder(ids[i]);
            if (infos[i].lots == 0) { unchecked { ++i; } continue; }
            if (!_orderParticipates(infos[i].side, infos[i].tick, result.clearingTick)) { unchecked { ++i; } continue; }

            fills[i] = _calcFilledLots(infos[i].lots, infos[i].side, result);
            if (infos[i].side == Side.Bid || infos[i].side == Side.SellNo) {
                pType[i] = 1;
                totalFilledBid += fills[i];
            } else {
                pType[i] = 2;
                totalFilledAsk += fills[i];
            }
            unchecked { ++i; }
        }

        // Distribute bid-side rounding remainder (+1 per order, backwards)
        if (result.totalBidLots > result.matchedLots && totalFilledBid < result.matchedLots) {
            uint256 rem = result.matchedLots - totalFilledBid;
            for (uint256 i = idsLen; i > 0 && rem > 0; ) {
                unchecked { --i; }
                if (pType[i] == 1) {
                    fills[i]++;
                    unchecked { --rem; }
                }
            }
        }

        // Distribute ask-side rounding remainder (+1 per order, backwards)
        if (result.totalAskLots > result.matchedLots && totalFilledAsk < result.matchedLots) {
            uint256 rem = result.matchedLots - totalFilledAsk;
            for (uint256 i = idsLen; i > 0 && rem > 0; ) {
                unchecked { --i; }
                if (pType[i] == 2) {
                    fills[i]++;
                    unchecked { --rem; }
                }
            }
        }
    }

    /// @dev Settle amounts: pool gets full filledCollateral, fee from locked excess.
    ///      Buy side pays half fee (rounded down); sell side pays other half (rounded up).
    function _settleAmounts(OrderInfo memory o, BatchResult memory result, uint256 filledLots)
        internal
        view
        returns (SettleAmounts memory s)
    {
        s.filledLots = filledLots;
        uint256 unfilledLots = o.lots - s.filledLots;

        // Use OrderBook's feeModel for locked amounts (matches what was locked at placement)
        FeeModel obFee = feeModel;

        uint256 lockedForFilled = _collateral(s.filledLots, o.tick, o.side);
        uint256 lockedFeeForFilled = obFee.calculateFee(lockedForFilled);

        s.filledCollateral = _collateral(s.filledLots, result.clearingTick, o.side);
        // Buy side pays the other half (full - ceil(full/2)) so sell side gets the rounding extra
        s.protocolFee = obFee.calculateOtherHalfFee(s.filledCollateral);
        s.toPool = s.filledCollateral;

        s.excessRefund = (lockedForFilled + lockedFeeForFilled) - s.filledCollateral - s.protocolFee;

        s.unfilledCollateral = _collateral(unfilledLots, o.tick, o.side);
        s.unfilledFee = obFee.calculateFee(s.unfilledCollateral);
    }

    /// @dev Roll GTC order to next batch. No cap — chunked settlement handles large batches.
    function _tryRollOrCancel(uint256 orderId, OrderInfo memory o, uint256 nextBatchId) internal {
        orderBook.pushBatchOrderId(o.marketId, nextBatchId, orderId);
    }

    function _settleOrder(uint256 orderId, OrderInfo memory o, BatchResult memory result, uint256 precomputedFill, bool isInternal) internal {
        // If _computeFills didn't populate this order (lots == 0), read from storage as fallback
        if (o.marketId == 0) {
            o = _readOrder(orderId);
        }
        require(o.marketId == result.marketId, "BatchAuction: wrong market");

        // Skip already-filled/cancelled orders
        if (o.lots == 0) return;

        // Safety: validate batch relationship
        if (o.orderType == OrderType.GoodTilBatch) {
            require(o.batchId == result.batchId, "BatchAuction: wrong batch");
        } else {
            require(o.batchId <= result.batchId, "BatchAuction: batch not reached");
        }

        bool isSell = _isSellOrder(o.side);

        // Non-participating order (precomputedFill == 0 and tick doesn't cross)
        if (precomputedFill == 0 && !_orderParticipates(o.side, o.tick, result.clearingTick)) {
            if (o.orderType == OrderType.GoodTilBatch) {
                orderBook.decrementActiveOrderCount(o.owner, o.marketId);
                orderBook.reduceOrderLots(orderId, o.lots);
                orderBook.updateTreeVolume(o.marketId, o.side, o.tick, -int256(o.lots));

                if (isSell) {
                    bool isYes = (o.side == Side.SellYes);
                    if (isInternal) {
                        vault.unlockPosition(o.owner, o.marketId, uint128(o.lots), isYes);
                    } else {
                        uint256 tokenId = isYes
                            ? o.marketId * 2
                            : o.marketId * 2 + 1;
                        orderBook.transferEscrowTokens(o.owner, tokenId, o.lots);
                    }
                } else {
                    uint256 collateral = _collateral(o.lots, o.tick, o.side);
                    uint256 fee = feeModel.calculateFee(collateral);
                    if (collateral + fee > 0) {
                        vault.unlock(o.owner, collateral + fee);
                        vault.withdrawTo(o.owner, collateral + fee);
                    }
                }
            } else {
                _tryRollOrCancel(orderId, o, result.batchId + 1);
            }
            emit OrderSettled(orderId, o.owner, 0, 0);
            return;
        }

        // Participating but zero fill (pro-rata rounding edge case)
        if (precomputedFill == 0) {
            if (o.orderType == OrderType.GoodTilCancel) {
                _tryRollOrCancel(orderId, o, result.batchId + 1);
            } else {
                // GTB zero-fill cleanup: remove order, return collateral/tokens
                orderBook.decrementActiveOrderCount(o.owner, o.marketId);
                orderBook.reduceOrderLots(orderId, o.lots);
                orderBook.updateTreeVolume(o.marketId, o.side, o.tick, -int256(o.lots));

                if (isSell) {
                    bool isYes = (o.side == Side.SellYes);
                    if (isInternal) {
                        vault.unlockPosition(o.owner, o.marketId, uint128(o.lots), isYes);
                    } else {
                        uint256 tokenId = isYes
                            ? o.marketId * 2
                            : o.marketId * 2 + 1;
                        orderBook.transferEscrowTokens(o.owner, tokenId, o.lots);
                    }
                } else {
                    uint256 collateral = _collateral(o.lots, o.tick, o.side);
                    uint256 fee = feeModel.calculateFee(collateral);
                    if (collateral + fee > 0) {
                        vault.unlock(o.owner, collateral + fee);
                        vault.withdrawTo(o.owner, collateral + fee);
                    }
                }
            }
            emit OrderSettled(orderId, o.owner, 0, 0);
            return;
        }

        if (isSell) {
            _settleSellOrder(orderId, o, result, precomputedFill, isInternal);
        } else {
            _settleBuyOrder(orderId, o, result, precomputedFill, isInternal);
        }
    }

    function _settleBuyOrder(uint256 orderId, OrderInfo memory o, BatchResult memory result, uint256 precomputedFill, bool isInternal) internal {
        SettleAmounts memory s = _settleAmounts(o, result, precomputedFill);

        bool fullyFilled = s.filledLots == o.lots;

        if (fullyFilled || o.orderType == OrderType.GoodTilBatch) {
            orderBook.decrementActiveOrderCount(o.owner, o.marketId);
            orderBook.reduceOrderLots(orderId, o.lots);
            orderBook.updateTreeVolume(o.marketId, o.side, o.tick, -int256(o.lots));
            vault.settleFill(
                o.owner, o.marketId, s.toPool,
                feeModel.protocolFeeCollector(), s.protocolFee,
                s.unfilledCollateral + s.unfilledFee + s.excessRefund, true
            );
        } else {
            orderBook.reduceOrderLots(orderId, s.filledLots);
            orderBook.updateTreeVolume(o.marketId, o.side, o.tick, -int256(s.filledLots));
            vault.settleFill(
                o.owner, o.marketId, s.toPool,
                feeModel.protocolFeeCollector(), s.protocolFee,
                s.excessRefund, s.excessRefund > 0
            );
            _tryRollOrCancel(orderId, o, result.batchId + 1);
        }

        // Credit outcome tokens or internal positions
        if (s.filledLots > 0) {
            if (isInternal) {
                vault.creditPosition(o.owner, o.marketId, uint128(s.filledLots), o.side == Side.Bid);
            } else {
                outcomeToken.mintSingle(o.owner, o.marketId, s.filledLots, o.side == Side.Bid);
            }
        }

        uint256 released = (fullyFilled || o.orderType == OrderType.GoodTilBatch)
            ? s.unfilledCollateral + s.unfilledFee + s.excessRefund
            : s.excessRefund;
        emit OrderSettled(orderId, o.owner, s.filledLots, released);
    }

    function _settleSellOrder(uint256 orderId, OrderInfo memory o, BatchResult memory result, uint256 precomputedFill, bool isInternal) internal {
        uint256 filledLots = precomputedFill;
        uint256 unfilledLots = o.lots - filledLots;
        bool fullyFilled = filledLots == o.lots;
        bool isYes = (o.side == Side.SellYes);

        // Compute seller payout at clearing price, then deduct sell-side fee (half of total)
        uint256 grossPayout = _collateral(filledLots, result.clearingTick, o.side);
        uint256 sellFee = feeModel.calculateHalfFee(grossPayout);
        uint256 payout = grossPayout - sellFee;

        // Consume filled tokens/positions
        if (filledLots > 0) {
            if (isInternal) {
                vault.consumeLockedPosition(o.owner, o.marketId, uint128(filledLots), isYes);
            } else {
                uint256 tokenId = isYes
                    ? o.marketId * 2
                    : o.marketId * 2 + 1;
                outcomeToken.burnEscrow(address(orderBook), tokenId, filledLots);
            }
        }

        // Pay seller from market pool (net of fee)
        if (payout > 0) {
            vault.redeemFromPool(o.marketId, o.owner, payout);
        }
        // Collect sell-side fee from pool to protocol
        if (sellFee > 0) {
            vault.redeemFromPool(o.marketId, feeModel.protocolFeeCollector(), sellFee);
        }

        if (fullyFilled || o.orderType == OrderType.GoodTilBatch) {
            orderBook.decrementActiveOrderCount(o.owner, o.marketId);
            orderBook.reduceOrderLots(orderId, o.lots);
            orderBook.updateTreeVolume(o.marketId, o.side, o.tick, -int256(o.lots));
            // Return unfilled tokens/positions to seller
            if (unfilledLots > 0) {
                if (isInternal) {
                    vault.unlockPosition(o.owner, o.marketId, uint128(unfilledLots), isYes);
                } else {
                    uint256 tokenId = isYes
                        ? o.marketId * 2
                        : o.marketId * 2 + 1;
                    orderBook.transferEscrowTokens(o.owner, tokenId, unfilledLots);
                }
            }
        } else {
            // GTC partial fill: reduce filled, roll remainder
            orderBook.reduceOrderLots(orderId, filledLots);
            orderBook.updateTreeVolume(o.marketId, o.side, o.tick, -int256(filledLots));
            _tryRollOrCancel(orderId, o, result.batchId + 1);
        }

        emit OrderSettled(orderId, o.owner, filledLots, payout);
    }

    function _orderParticipates(Side side, uint256 tick, uint256 clearingTick) internal pure returns (bool) {
        if (clearingTick == 0) return false;
        // Bid and SellNo sit on the bid side: participate if tick >= clearingTick
        if (side == Side.Bid || side == Side.SellNo) return tick >= clearingTick;
        // Ask and SellYes sit on the ask side: participate if tick <= clearingTick
        return tick <= clearingTick;
    }

    function _calcFilledLots(uint256 lots, Side side, BatchResult memory result) internal pure returns (uint256) {
        // SellNo sits on bid side, SellYes sits on ask side
        uint256 totalSideLots = (side == Side.Bid || side == Side.SellNo) ? result.totalBidLots : result.totalAskLots;
        if (totalSideLots <= result.matchedLots) {
            return lots;
        }
        return (lots * result.matchedLots) / totalSideLots;
    }

    // -------------------------------------------------------------------------
    // View helpers
    // -------------------------------------------------------------------------

    function getBatchResult(uint256 marketId, uint256 batchId) external view returns (BatchResult memory) {
        return batchResults[marketId][batchId];
    }
}
