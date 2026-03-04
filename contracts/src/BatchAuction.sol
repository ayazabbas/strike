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
    OutcomeToken public immutable outcomeToken;

    /// @notice marketId => batchId => BatchResult
    mapping(uint256 => mapping(uint256 => BatchResult)) public batchResults;

    /// @notice orderId => true if fills have been claimed for this order
    mapping(uint256 => bool) public claimed;

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

    /// @notice Clear the current batch for a market.
    function clearBatch(uint256 marketId) external returns (BatchResult memory result) {
        (uint256 id, bool active, bool halted, uint256 currentBatchId, , uint256 batchInterval, ) = orderBook.markets(marketId);
        require(id != 0, "BatchAuction: market not found");
        require(active, "BatchAuction: market not active");
        require(!halted, "BatchAuction: market halted");

        // Enforce batch interval (skip for first clear)
        uint256 lastClear = lastClearTime[marketId];
        if (lastClear != 0) {
            require(block.timestamp >= lastClear + batchInterval, "BatchAuction: too soon");
        }

        uint256 clearingTick = orderBook.findClearingTick(marketId);

        uint256 totalBidLots;
        uint256 totalAskLots;
        uint256 matchedLots;

        if (clearingTick > 0) {
            totalBidLots = orderBook.cumulativeBidVolume(marketId, clearingTick);
            totalAskLots = orderBook.cumulativeAskVolume(marketId, clearingTick);
            matchedLots = totalBidLots < totalAskLots ? totalBidLots : totalAskLots;
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
        lastClearTime[marketId] = block.timestamp;
        orderBook.advanceBatch(marketId);

        emit BatchCleared(marketId, currentBatchId, clearingTick, matchedLots);
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

    /// @dev Compute settlement amounts for an order.
    function _settleAmounts(OrderInfo memory o, BatchResult storage result)
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

    // -------------------------------------------------------------------------
    // Claim fills (pro-rata settlement)
    // -------------------------------------------------------------------------

    /// @notice Claim fills for an order after its batch has been cleared.
    ///         Pro-rata: if side is oversubscribed, each order gets a proportional fill.
    ///         Filled collateral goes to the market pool; unfilled is returned to owner.
    ///         Bidders receive YES outcome tokens; askers receive NO outcome tokens.
    /// @param orderId The order to claim fills for.
    function claimFills(uint256 orderId) external {
        require(!claimed[orderId], "BatchAuction: already claimed");
        claimed[orderId] = true;

        OrderInfo memory o = _readOrder(orderId);

        BatchResult storage result = batchResults[o.marketId][o.batchId];
        require(result.timestamp != 0, "BatchAuction: batch not cleared");

        // Check if order participates in the clearing
        if (!_orderParticipates(o.side, o.tick, result.clearingTick) || o.lots == 0) {
            emit FillClaimed(orderId, o.owner, 0, 0);
            return;
        }

        SettleAmounts memory s = _settleAmounts(o, result);

        // Remove entire order from the book
        orderBook.reduceOrderLots(orderId, o.lots);
        orderBook.updateTreeVolume(o.marketId, o.side, o.tick, -int256(o.lots));

        // Move filled collateral to market pool (minus fee)
        if (s.toPool > 0) {
            vault.addToMarketPool(o.owner, o.marketId, s.toPool);
        }

        // Send protocol fee to fee collector
        if (s.protocolFee > 0) {
            vault.transferCollateral(o.owner, feeModel.protocolFeeCollector(), s.protocolFee);
        }

        // Return unfilled collateral to owner
        if (s.unfilledCollateral > 0) {
            vault.unlock(o.owner, s.unfilledCollateral);
        }

        // Mint outcome tokens: bid → YES, ask → NO
        if (s.filledLots > 0) {
            outcomeToken.mintPair(o.owner, o.marketId, s.filledLots);
            // Burn the side the user doesn't want: bidder burns NO, asker burns YES
            outcomeToken.redeem(o.owner, o.marketId, s.filledLots, o.side != Side.Bid);
        }

        emit FillClaimed(orderId, o.owner, s.filledLots, s.unfilledCollateral);
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

        (, , , uint256 currentBatchId, , , ) = orderBook.markets(o.marketId);
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
