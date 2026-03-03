// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "./ITypes.sol";
import "./OrderBook.sol";
import "./Vault.sol";
import "./FeeModel.sol";

/// @title BatchAuction
/// @notice Implements Frequent Batch Auction clearing for the Strike CLOB.
///         An operator calls clearBatch() to find the clearing price via segment
///         trees, then users call claimFills() for pro-rata settlement.
///         Expired GoodTilBatch orders can be pruned for a bounty.
contract BatchAuction is AccessControl {
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    OrderBook public immutable orderBook;
    Vault public immutable vault;
    FeeModel public immutable feeModel;

    /// @notice marketId => batchId => BatchResult
    mapping(uint256 => mapping(uint256 => BatchResult)) public batchResults;

    /// @notice orderId => true if fills have been claimed for this order
    mapping(uint256 => bool) public claimed;

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

    constructor(address admin, address _orderBook, address _vault, address _feeModel) {
        require(_orderBook != address(0), "BatchAuction: zero orderBook");
        require(_vault != address(0), "BatchAuction: zero vault");
        require(_feeModel != address(0), "BatchAuction: zero feeModel");

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        orderBook = OrderBook(_orderBook);
        vault = Vault(payable(_vault));
        feeModel = FeeModel(_feeModel);
    }

    // -------------------------------------------------------------------------
    // Batch clearing
    // -------------------------------------------------------------------------

    /// @notice Clear the current batch for a market.
    function clearBatch(uint256 marketId) external onlyRole(OPERATOR_ROLE) returns (BatchResult memory result) {
        (uint256 id, bool active, bool halted, uint256 currentBatchId, ) = orderBook.markets(marketId);
        require(id != 0, "BatchAuction: market not found");
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
        }

        // The segment tree finds the highest tick where cumBid >= cumAsk.
        // Check tick+1: if more volume matches there (asks exceed bids at that tick),
        // use it as the clearing tick instead.
        if (clearingTick < 99) {
            uint256 nextTick = clearingTick + 1;
            uint256 nextBid = orderBook.cumulativeBidVolume(marketId, nextTick);
            uint256 nextAsk = orderBook.cumulativeAskVolume(marketId, nextTick);
            uint256 nextMatched = nextBid < nextAsk ? nextBid : nextAsk;
            if (nextMatched > matchedLots) {
                clearingTick = nextTick;
                totalBidLots = nextBid;
                totalAskLots = nextAsk;
                matchedLots = nextMatched;
            }
        }

        result = BatchResult({
            marketId: marketId,
            batchId: currentBatchId,
            clearingTick: clearingTick,
            matchedLots: matchedLots,
            totalBidLots: totalBidLots,
            totalAskLots: totalAskLots,
            timestamp: block.timestamp
        });

        batchResults[marketId][currentBatchId] = result;
        orderBook.advanceBatch(marketId);

        emit BatchCleared(marketId, currentBatchId, clearingTick, matchedLots);
    }

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

    /// @dev Calculate collateral for lots at a given tick and side.
    function _collateral(uint256 lots, uint256 tick, Side side) internal view returns (uint256) {
        if (side == Side.Bid) {
            return (lots * orderBook.LOT_SIZE() * tick) / 100;
        } else {
            return (lots * orderBook.LOT_SIZE() * (100 - tick)) / 100;
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

    function _readOrder(uint256 orderId) internal view returns (OrderInfo memory info) {
        (
            uint256 id,
            uint256 marketId,
            address owner,
            Side side,
            OrderType orderType,
            uint256 tick,
            uint256 lots,
            uint256 batchId,
        ) = orderBook.orders(orderId);
        require(id != 0, "BatchAuction: order not found");
        info = OrderInfo(marketId, owner, side, orderType, tick, lots, batchId);
    }

    // -------------------------------------------------------------------------
    // Claim fills (pro-rata settlement)
    // -------------------------------------------------------------------------

    /// @notice Claim fills for an order after its batch has been cleared.
    ///         Pro-rata: if side is oversubscribed, each order gets a proportional fill.
    ///         All collateral for the order is unlocked (filled + unfilled).
    /// @param orderId The order to claim fills for.
    function claimFills(uint256 orderId) external {
        require(!claimed[orderId], "BatchAuction: already claimed");
        claimed[orderId] = true;

        OrderInfo memory o = _readOrder(orderId);

        BatchResult storage result = batchResults[o.marketId][o.batchId];
        require(result.timestamp != 0, "BatchAuction: batch not cleared");

        uint256 clearingTick = result.clearingTick;

        // Check if order participates in the clearing
        bool participates = _orderParticipates(o.side, o.tick, clearingTick);

        if (!participates || o.lots == 0) {
            emit FillClaimed(orderId, o.owner, 0, 0);
            return;
        }

        // Calculate pro-rata fill
        uint256 filledLots = _calcFilledLots(o.lots, o.side, result);

        // Unlock ALL collateral that was locked for this order
        uint256 totalLockedCollateral = _collateral(o.lots, o.tick, o.side);

        // Remove entire order from the book (filled + unfilled)
        orderBook.reduceOrderLots(orderId, o.lots);
        orderBook.updateTreeVolume(o.marketId, o.side, o.tick, -int256(o.lots));
        vault.unlock(o.owner, totalLockedCollateral);

        emit FillClaimed(orderId, o.owner, filledLots, totalLockedCollateral);
    }

    function _orderParticipates(Side side, uint256 tick, uint256 clearingTick) internal pure returns (bool) {
        if (clearingTick == 0) return false;
        if (side == Side.Bid) return tick >= clearingTick;
        return tick <= clearingTick;
    }

    function _calcFilledLots(uint256 lots, Side side, BatchResult storage result) internal view returns (uint256) {
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

        (, , , uint256 currentBatchId, ) = orderBook.markets(o.marketId);
        require(currentBatchId > o.batchId, "BatchAuction: batch not yet advanced");

        require(
            claimed[orderId] || batchResults[o.marketId][o.batchId].timestamp != 0,
            "BatchAuction: batch not cleared"
        );

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
