// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/access/AccessControl.sol";
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
contract BatchAuction is AccessControl {
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    OrderBook public immutable orderBook;
    Vault public immutable vault;
    FeeModel public immutable feeModel;
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

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor(address admin, address _orderBook, address _vault, address _feeModel, address _outcomeToken) {
        require(_orderBook != address(0), "BatchAuction: zero orderBook");
        require(_vault != address(0), "BatchAuction: zero vault");
        require(_feeModel != address(0), "BatchAuction: zero feeModel");
        require(_outcomeToken != address(0), "BatchAuction: zero outcomeToken");

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        orderBook = OrderBook(_orderBook);
        vault = Vault(_vault);
        feeModel = FeeModel(_feeModel);
        outcomeToken = OutcomeToken(_outcomeToken);
    }

    // -------------------------------------------------------------------------
    // Batch clearing — atomic: advance + clear + settle all
    // -------------------------------------------------------------------------

    function clearBatch(uint256 marketId) external returns (BatchResult memory result) {
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
        for (uint256 i = 0; i < ids.length; i++) {
            _settleOrder(ids[i], result);
        }
    }

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

    function _collateral(uint256 lots, uint256 tick, Side side) internal pure returns (uint256) {
        if (side == Side.Bid) {
            return (lots * LOT_SIZE * tick) / 100;
        } else {
            return (lots * LOT_SIZE * (100 - tick)) / 100;
        }
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
        uint256 excessRefund;       // locked for filled - cost at clearing price
        uint256 unfilledCollateral; // at order tick
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

    function _settleAmounts(OrderInfo memory o, BatchResult memory result)
        internal
        view
        returns (SettleAmounts memory s)
    {
        s.filledLots = _calcFilledLots(o.lots, o.side, result);
        uint256 unfilledLots = o.lots - s.filledLots;

        uint256 lockedForFilled = _collateral(s.filledLots, o.tick, o.side);
        s.filledCollateral = _collateral(s.filledLots, result.clearingTick, o.side);
        s.excessRefund = lockedForFilled - s.filledCollateral;
        s.unfilledCollateral = _collateral(unfilledLots, o.tick, o.side);
        s.protocolFee = feeModel.calculateFee(s.filledCollateral);
        s.toPool = s.filledCollateral - s.protocolFee;
    }

    function _settleOrder(uint256 orderId, BatchResult memory result) internal {
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

        // Non-participating order (tick doesn't cross clearing)
        if (!_orderParticipates(o.side, o.tick, result.clearingTick)) {
            if (o.orderType == OrderType.GoodTilBatch) {
                // GTB non-participating: return collateral to wallet, remove from book
                uint256 collateral = _collateral(o.lots, o.tick, o.side);
                orderBook.reduceOrderLots(orderId, o.lots);
                orderBook.updateTreeVolume(o.marketId, o.side, o.tick, -int256(o.lots));
                if (collateral > 0) {
                    vault.unlock(o.owner, collateral);
                    vault.withdrawTo(o.owner, collateral);
                }
            } else {
                // GTC non-participating: roll to next batch, leave in tree
                orderBook.pushBatchOrderId(o.marketId, result.batchId + 1, orderId);
            }
            emit OrderSettled(orderId, o.owner, 0, 0);
            return;
        }

        // Participating order — compute fills at clearing price
        SettleAmounts memory s = _settleAmounts(o, result);

        if (s.filledLots == 0) {
            // Edge case: participating but zero fill (shouldn't happen normally)
            if (o.orderType == OrderType.GoodTilCancel) {
                orderBook.pushBatchOrderId(o.marketId, result.batchId + 1, orderId);
            }
            emit OrderSettled(orderId, o.owner, 0, 0);
            return;
        }

        bool fullyFilled = s.filledLots == o.lots;

        if (fullyFilled || o.orderType == OrderType.GoodTilBatch) {
            // Full fill or GTB: remove entire order, return unfilled + excess to wallet
            orderBook.reduceOrderLots(orderId, o.lots);
            orderBook.updateTreeVolume(o.marketId, o.side, o.tick, -int256(o.lots));
            vault.settleFill(
                o.owner, o.marketId, s.toPool,
                feeModel.protocolFeeCollector(), s.protocolFee,
                s.unfilledCollateral + s.excessRefund, true
            );
        } else {
            // GTC partial fill: reduce filled lots, return excess refund, roll remainder
            orderBook.reduceOrderLots(orderId, s.filledLots);
            orderBook.updateTreeVolume(o.marketId, o.side, o.tick, -int256(s.filledLots));
            vault.settleFill(
                o.owner, o.marketId, s.toPool,
                feeModel.protocolFeeCollector(), s.protocolFee,
                s.excessRefund, s.excessRefund > 0
            );
            // Roll to next batch
            orderBook.pushBatchOrderId(o.marketId, result.batchId + 1, orderId);
        }

        // Mint outcome tokens
        if (s.filledLots > 0) {
            outcomeToken.mintSingle(o.owner, o.marketId, s.filledLots, o.side == Side.Bid);
        }

        uint256 released = (fullyFilled || o.orderType == OrderType.GoodTilBatch)
            ? s.unfilledCollateral + s.excessRefund
            : s.excessRefund;
        emit OrderSettled(orderId, o.owner, s.filledLots, released);
    }

    function _orderParticipates(Side side, uint256 tick, uint256 clearingTick) internal pure returns (bool) {
        if (clearingTick == 0) return false;
        if (side == Side.Bid) return tick >= clearingTick;
        return tick <= clearingTick;
    }

    function _calcFilledLots(uint256 lots, Side side, BatchResult memory result) internal pure returns (uint256) {
        uint256 totalSideLots = side == Side.Bid ? result.totalBidLots : result.totalAskLots;
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
