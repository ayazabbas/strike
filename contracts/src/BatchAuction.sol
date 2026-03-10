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
///         A keeper calls clearBatch(marketId, orderIds) to find the clearing price
///         and settle orders inline. claimFills() remains as a public fallback.
///         Expired GoodTilBatch orders can be pruned for a bounty.
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

    /// @notice orderId => last batchId for which fills were claimed (0 = never claimed)
    mapping(uint256 => uint256) public lastClaimedBatch;

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
    event FillClaimed(
        uint256 indexed orderId,
        address indexed owner,
        uint256 filledLots,
        uint256 collateralReleased
    );
    event OrderPruned(uint256 indexed orderId, address indexed pruner);

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
        vault = Vault(payable(_vault));
        feeModel = FeeModel(_feeModel);
        outcomeToken = OutcomeToken(_outcomeToken);
    }

    // -------------------------------------------------------------------------
    // Batch clearing
    // -------------------------------------------------------------------------

    /// @notice Clear the current batch for a market. Optionally settles orders inline.
    /// @param marketId The market to clear.
    /// @param orderIds Order IDs to settle inline (keeper-provided). Pass empty for no inline settlement.
    function clearBatch(uint256 marketId, uint256[] calldata orderIds) external returns (BatchResult memory result) {
        uint32 currentBatchId;
        {
            (uint32 id, bool active, bool halted, uint32 _batchId, , uint32 batchInterval, ) = orderBook.markets(marketId);
            require(id != 0, "BatchAuction: market not found");
            require(active, "BatchAuction: market not active");
            require(!halted, "BatchAuction: market halted");
            currentBatchId = _batchId;

            // Enforce batch interval (skip for first clear)
            uint256 lastClear = lastClearTime[marketId];
            if (lastClear != 0) {
                require(block.timestamp >= lastClear + batchInterval, "BatchAuction: too soon");
            }
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
        orderBook.advanceBatch(marketId);

        emit BatchCleared(marketId, currentBatchId, clearingTick, matchedLots);

        // Inline settlement
        for (uint256 i = 0; i < orderIds.length; i++) {
            _settleOrder(orderIds[i], result);
        }
    }

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

    /// @dev Calculate collateral for lots at a given tick and side.
    function _collateral(uint256 lots, uint256 tick, Side side) internal pure returns (uint256) {
        if (side == Side.Bid) {
            return (lots * LOT_SIZE * tick) / 100;
        } else {
            return (lots * LOT_SIZE * (100 - tick)) / 100;
        }
    }

    /// @dev Read order fields we need, packed to avoid stack-too-deep.
    struct OrderInfo {
        uint256 marketId;
        address owner;
        Side side;
        OrderType orderType;
        uint256 tick;
        uint256 lots;
        uint256 batchId;
    }

    /// @dev Settlement amounts computed during claimFills.
    struct SettleAmounts {
        uint256 filledLots;
        uint256 unfilledCollateral;
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

    /// @dev Compute settlement amounts for an order.
    function _settleAmounts(OrderInfo memory o, BatchResult memory result)
        internal
        view
        returns (SettleAmounts memory s)
    {
        s.filledLots = _calcFilledLots(o.lots, o.side, result);
        uint256 unfilledLots = o.lots - s.filledLots;
        s.unfilledCollateral = _collateral(unfilledLots, o.tick, o.side);
        uint256 filledCollateral = _collateral(o.lots, o.tick, o.side) - s.unfilledCollateral;
        s.protocolFee = feeModel.calculateTakerFee(filledCollateral);
        s.toPool = filledCollateral - s.protocolFee;
    }

    /// @dev Settle a single order against a batch result. Used by clearBatch (inline)
    ///      and claimFills (fallback). Validates market/batch, performs pro-rata fill,
    ///      settles vault, and mints outcome tokens.
    function _settleOrder(uint256 orderId, BatchResult memory result) internal {
        OrderInfo memory o = _readOrder(orderId);
        require(o.marketId == result.marketId, "BatchAuction: wrong market");
        require(o.lots > 0, "BatchAuction: order empty");

        // Determine expected batch and prevent double-settle
        uint256 lastClaimed = lastClaimedBatch[orderId];
        if (lastClaimed == 0) {
            require(o.batchId == result.batchId, "BatchAuction: wrong batch");
        } else {
            require(o.orderType == OrderType.GoodTilCancel, "BatchAuction: already claimed");
            require(lastClaimed + 1 == result.batchId, "BatchAuction: wrong batch");
        }

        lastClaimedBatch[orderId] = result.batchId;

        // Non-participating order: just mark as claimed
        if (!_orderParticipates(o.side, o.tick, result.clearingTick)) {
            emit FillClaimed(orderId, o.owner, 0, 0);
            return;
        }

        SettleAmounts memory s = _settleAmounts(o, result);

        if (o.orderType == OrderType.GoodTilCancel && s.filledLots < o.lots) {
            // GTC partial fill: only remove filled lots, leave unfilled resting
            orderBook.reduceOrderLots(orderId, s.filledLots);
            orderBook.updateTreeVolume(o.marketId, o.side, o.tick, -int256(s.filledLots));
            vault.settleFill(o.owner, o.marketId, s.toPool, feeModel.protocolFeeCollector(), s.protocolFee, 0);
        } else {
            // GTB or GTC full fill: remove entire order from the book
            orderBook.reduceOrderLots(orderId, o.lots);
            orderBook.updateTreeVolume(o.marketId, o.side, o.tick, -int256(o.lots));
            vault.settleFill(o.owner, o.marketId, s.toPool, feeModel.protocolFeeCollector(), s.protocolFee, s.unfilledCollateral);
        }

        if (s.filledLots > 0) {
            outcomeToken.mintSingle(o.owner, o.marketId, s.filledLots, o.side == Side.Bid);
        }

        uint256 released = (o.orderType == OrderType.GoodTilCancel && s.filledLots < o.lots) ? 0 : s.unfilledCollateral;
        emit FillClaimed(orderId, o.owner, s.filledLots, released);
    }

    // -------------------------------------------------------------------------
    // Claim fills — public fallback (pro-rata settlement)
    // -------------------------------------------------------------------------

    /// @notice Claim fills for an order after its batch has been cleared.
    ///         Fallback for orders not settled inline by clearBatch.
    /// @param orderId The order to claim fills for.
    function claimFills(uint256 orderId) external {
        OrderInfo memory o = _readOrder(orderId);

        // Determine which batch to claim
        uint256 batchToClaim;
        uint256 lastClaimed = lastClaimedBatch[orderId];
        if (lastClaimed == 0) {
            batchToClaim = o.batchId;
        } else {
            require(o.orderType == OrderType.GoodTilCancel, "BatchAuction: already claimed");
            require(o.lots > 0, "BatchAuction: order fully filled");
            batchToClaim = lastClaimed + 1;
        }

        BatchResult memory result = batchResults[o.marketId][batchToClaim];
        require(result.timestamp != 0, "BatchAuction: batch not cleared");

        _settleOrder(orderId, result);
    }

    /// @notice Check if fills have been claimed for an order (backward-compatible view).
    function claimed(uint256 orderId) external view returns (bool) {
        return lastClaimedBatch[orderId] > 0;
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
    // Prune expired orders
    // -------------------------------------------------------------------------

    /// @notice Prune a GoodTilBatch order that has expired (batch has advanced).
    ///         Unlocks the order's collateral.
    /// @param orderId The expired order to prune.
    function pruneExpiredOrder(uint256 orderId) external {
        OrderInfo memory o = _readOrder(orderId);

        require(o.orderType == OrderType.GoodTilBatch, "BatchAuction: not GTB order");
        require(o.lots > 0, "BatchAuction: order already empty");

        (, , , uint32 currentBatchId, , , ) = orderBook.markets(o.marketId);
        require(currentBatchId > o.batchId, "BatchAuction: batch not yet advanced");

        // Batch must have been cleared
        BatchResult memory result = batchResults[o.marketId][o.batchId];
        require(result.timestamp != 0, "BatchAuction: batch not cleared");

        // If the order participated in clearing, it must be claimed first
        // to ensure filled collateral flows to market pool (prevents settlement bypass)
        if (_orderParticipates(o.side, o.tick, result.clearingTick)) {
            require(lastClaimedBatch[orderId] >= o.batchId, "BatchAuction: claim fills first");
        }

        // Mark as claimed to prevent any future claimFills attempt
        lastClaimedBatch[orderId] = o.batchId;

        uint256 collateral = _collateral(o.lots, o.tick, o.side);

        // Remove from book
        orderBook.reduceOrderLots(orderId, o.lots);
        orderBook.updateTreeVolume(o.marketId, o.side, o.tick, -int256(o.lots));

        if (collateral > 0) {
            vault.unlock(o.owner, collateral);
        }

        emit OrderPruned(orderId, msg.sender);
    }

    // -------------------------------------------------------------------------
    // View helpers
    // -------------------------------------------------------------------------

    /// @notice Get the batch result for a specific market and batch.
    function getBatchResult(uint256 marketId, uint256 batchId) external view returns (BatchResult memory) {
        return batchResults[marketId][batchId];
    }
}
