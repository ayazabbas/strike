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

    /// @notice marketId => batchId => BatchResult
    mapping(uint256 => mapping(uint256 => BatchResult)) public batchResults;

    /// @notice marketId => timestamp of last batch clear
    mapping(uint256 => uint256) public lastClearTime;

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
    }

    // -------------------------------------------------------------------------
    // Batch clearing — atomic: advance + clear + settle all
    // -------------------------------------------------------------------------

    function clearBatch(uint256 marketId) external nonReentrant returns (BatchResult memory result) {
        uint32 currentBatchId;
        {
            (uint32 id, bool active, bool halted, uint32 _batchId, , , ) = orderBook.markets(marketId);
            require(id != 0, "BatchAuction: market not found");
            require(active, "BatchAuction: market not active");
            require(!halted, "BatchAuction: market halted");
            currentBatchId = _batchId;
        }

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
        lastClearTime[marketId] = block.timestamp;

        // Advance batch FIRST — new orders go to currentBatchId+1
        orderBook.advanceBatch(marketId);

        emit BatchCleared(marketId, currentBatchId, clearingTick, matchedLots);

        // Settle ALL orders in this batch atomically
        uint256[] memory ids = orderBook.getBatchOrderIds(marketId, currentBatchId);

        // Two-pass settlement: compute fills first (with rounding correction), then settle
        uint256[] memory fills = _computeFills(ids, result);

        for (uint256 i = 0; i < ids.length; i++) {
            _settleOrder(ids[i], result, fills[i]);
        }
    }

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

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

    /// @dev Compute fills for all orders with rounding remainder correction (Fix 4).
    function _computeFills(uint256[] memory ids, BatchResult memory result)
        internal
        view
        returns (uint256[] memory fills)
    {
        fills = new uint256[](ids.length);
        if (result.matchedLots == 0) return fills;

        uint256 totalFilledBid;
        uint256 totalFilledAsk;

        // 0 = not participating, 1 = participating bid, 2 = participating ask
        uint8[] memory pType = new uint8[](ids.length);

        for (uint256 i = 0; i < ids.length; i++) {
            OrderInfo memory o = _readOrder(ids[i]);
            if (o.lots == 0) continue;
            if (!_orderParticipates(o.side, o.tick, result.clearingTick)) continue;

            fills[i] = _calcFilledLots(o.lots, o.side, result);
            if (o.side == Side.Bid || o.side == Side.SellNo) {
                pType[i] = 1;
                totalFilledBid += fills[i];
            } else {
                pType[i] = 2;
                totalFilledAsk += fills[i];
            }
        }

        // Distribute bid-side rounding remainder (+1 per order, backwards)
        if (result.totalBidLots > result.matchedLots && totalFilledBid < result.matchedLots) {
            uint256 rem = result.matchedLots - totalFilledBid;
            for (uint256 i = ids.length; i > 0 && rem > 0; i--) {
                if (pType[i - 1] == 1) {
                    fills[i - 1]++;
                    rem--;
                }
            }
        }

        // Distribute ask-side rounding remainder (+1 per order, backwards)
        if (result.totalAskLots > result.matchedLots && totalFilledAsk < result.matchedLots) {
            uint256 rem = result.matchedLots - totalFilledAsk;
            for (uint256 i = ids.length; i > 0 && rem > 0; i--) {
                if (pType[i - 1] == 2) {
                    fills[i - 1]++;
                    rem--;
                }
            }
        }
    }

    /// @dev V2.1 settle amounts: pool gets full filledCollateral, fee from locked excess.
    function _settleAmounts(OrderInfo memory o, BatchResult memory result, uint256 filledLots)
        internal
        view
        returns (SettleAmounts memory s)
    {
        s.filledLots = filledLots;
        uint256 unfilledLots = o.lots - s.filledLots;

        // Use OrderBook's feeModel for locked amounts (matches what was locked at placement)
        FeeModel obFee = orderBook.feeModel();

        uint256 lockedForFilled = _collateral(s.filledLots, o.tick, o.side);
        uint256 lockedFeeForFilled = obFee.calculateFee(lockedForFilled);

        s.filledCollateral = _collateral(s.filledLots, result.clearingTick, o.side);
        s.protocolFee = obFee.calculateFee(s.filledCollateral);
        s.toPool = s.filledCollateral; // V2.1: full amount goes to pool (no fee deduction)

        s.excessRefund = (lockedForFilled + lockedFeeForFilled) - s.filledCollateral - s.protocolFee;

        s.unfilledCollateral = _collateral(unfilledLots, o.tick, o.side);
        s.unfilledFee = obFee.calculateFee(s.unfilledCollateral);
    }

    /// @dev Try GTC rollover; auto-cancel if next batch is full (Fix 2).
    function _tryRollOrCancel(uint256 orderId, OrderInfo memory o, uint256 nextBatchId) internal {
        bool pushed = orderBook.pushBatchOrderId(o.marketId, nextBatchId, orderId);
        if (!pushed) {
            orderBook.reduceOrderLots(orderId, o.lots);
            orderBook.updateTreeVolume(o.marketId, o.side, o.tick, -int256(o.lots));

            if (_isSellOrder(o.side)) {
                // Return outcome tokens to seller
                bool isYes = (o.side == Side.SellYes);
                uint256 tokenId = isYes
                    ? outcomeToken.yesTokenId(o.marketId)
                    : outcomeToken.noTokenId(o.marketId);
                orderBook.transferEscrowTokens(o.owner, tokenId, o.lots);
            } else {
                // Return USDT collateral + fee
                uint256 collateral = _collateral(o.lots, o.tick, o.side);
                uint256 fee = orderBook.feeModel().calculateFee(collateral);
                vault.unlock(o.owner, collateral + fee);
                vault.withdrawTo(o.owner, collateral + fee);
            }
            emit GtcAutoCancelled(orderId, o.owner);
        }
    }

    function _settleOrder(uint256 orderId, BatchResult memory result, uint256 precomputedFill) internal {
        OrderInfo memory o = _readOrder(orderId);
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
                orderBook.reduceOrderLots(orderId, o.lots);
                orderBook.updateTreeVolume(o.marketId, o.side, o.tick, -int256(o.lots));

                if (isSell) {
                    // GTB non-participating sell: return tokens
                    bool isYes = (o.side == Side.SellYes);
                    uint256 tokenId = isYes
                        ? outcomeToken.yesTokenId(o.marketId)
                        : outcomeToken.noTokenId(o.marketId);
                    orderBook.transferEscrowTokens(o.owner, tokenId, o.lots);
                } else {
                    // GTB non-participating buy: return USDT
                    uint256 collateral = _collateral(o.lots, o.tick, o.side);
                    uint256 fee = orderBook.feeModel().calculateFee(collateral);
                    if (collateral + fee > 0) {
                        vault.unlock(o.owner, collateral + fee);
                        vault.withdrawTo(o.owner, collateral + fee);
                    }
                }
            } else {
                // GTC non-participating: roll to next batch (or auto-cancel if full)
                _tryRollOrCancel(orderId, o, result.batchId + 1);
            }
            emit OrderSettled(orderId, o.owner, 0, 0);
            return;
        }

        // Participating but zero fill (edge case)
        if (precomputedFill == 0) {
            if (o.orderType == OrderType.GoodTilCancel) {
                _tryRollOrCancel(orderId, o, result.batchId + 1);
            }
            emit OrderSettled(orderId, o.owner, 0, 0);
            return;
        }

        if (isSell) {
            _settleSellOrder(orderId, o, result, precomputedFill);
        } else {
            _settleBuyOrder(orderId, o, result, precomputedFill);
        }
    }

    function _settleBuyOrder(uint256 orderId, OrderInfo memory o, BatchResult memory result, uint256 precomputedFill) internal {
        SettleAmounts memory s = _settleAmounts(o, result, precomputedFill);

        bool fullyFilled = s.filledLots == o.lots;

        if (fullyFilled || o.orderType == OrderType.GoodTilBatch) {
            orderBook.reduceOrderLots(orderId, o.lots);
            orderBook.updateTreeVolume(o.marketId, o.side, o.tick, -int256(o.lots));
            vault.settleFill(
                o.owner, o.marketId, s.toPool,
                orderBook.feeModel().protocolFeeCollector(), s.protocolFee,
                s.unfilledCollateral + s.unfilledFee + s.excessRefund, true
            );
        } else {
            orderBook.reduceOrderLots(orderId, s.filledLots);
            orderBook.updateTreeVolume(o.marketId, o.side, o.tick, -int256(s.filledLots));
            vault.settleFill(
                o.owner, o.marketId, s.toPool,
                orderBook.feeModel().protocolFeeCollector(), s.protocolFee,
                s.excessRefund, s.excessRefund > 0
            );
            _tryRollOrCancel(orderId, o, result.batchId + 1);
        }

        // Mint outcome tokens
        if (s.filledLots > 0) {
            outcomeToken.mintSingle(o.owner, o.marketId, s.filledLots, o.side == Side.Bid);
        }

        uint256 released = (fullyFilled || o.orderType == OrderType.GoodTilBatch)
            ? s.unfilledCollateral + s.unfilledFee + s.excessRefund
            : s.excessRefund;
        emit OrderSettled(orderId, o.owner, s.filledLots, released);
    }

    function _settleSellOrder(uint256 orderId, OrderInfo memory o, BatchResult memory result, uint256 precomputedFill) internal {
        uint256 filledLots = precomputedFill;
        uint256 unfilledLots = o.lots - filledLots;
        bool fullyFilled = filledLots == o.lots;

        bool isYes = (o.side == Side.SellYes);
        uint256 tokenId = isYes
            ? outcomeToken.yesTokenId(o.marketId)
            : outcomeToken.noTokenId(o.marketId);

        // Compute seller payout at clearing price
        uint256 payout = _collateral(filledLots, result.clearingTick, o.side);

        // Burn filled tokens from OrderBook custody
        if (filledLots > 0) {
            outcomeToken.burnEscrow(address(orderBook), tokenId, filledLots);
        }

        // Pay seller from market pool
        if (payout > 0) {
            vault.redeemFromPool(o.marketId, o.owner, payout);
        }

        if (fullyFilled || o.orderType == OrderType.GoodTilBatch) {
            orderBook.reduceOrderLots(orderId, o.lots);
            orderBook.updateTreeVolume(o.marketId, o.side, o.tick, -int256(o.lots));
            // Return unfilled tokens to seller
            if (unfilledLots > 0) {
                orderBook.transferEscrowTokens(o.owner, tokenId, unfilledLots);
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
