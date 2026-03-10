// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/BatchAuction.sol";
import "../src/OrderBook.sol";
import "../src/Vault.sol";
import "../src/FeeModel.sol";
import "../src/OutcomeToken.sol";
import "../src/ITypes.sol";

contract BatchAuctionTest is Test {
    BatchAuction public auction;
    OrderBook public book;
    Vault public vault;
    FeeModel public feeModel;
    OutcomeToken public token;

    address public admin = address(0x1);
    address public operator = address(0x2);
    address public user1 = address(0x3);
    address public user2 = address(0x4);
    address public user3 = address(0x5);
    address public pruner = address(0x6);

    uint256 public constant LOT = 1e15;

    function setUp() public {
        vm.startPrank(admin);

        vault = new Vault(admin);
        feeModel = new FeeModel(admin, 30, 10, 0.01 ether, 0.001 ether, admin);
        token = new OutcomeToken(admin);
        book = new OrderBook(admin, address(vault));
        auction = new BatchAuction(admin, address(book), address(vault), address(feeModel), address(token));

        // Grant roles
        book.grantRole(book.OPERATOR_ROLE(), operator);
        book.grantRole(book.OPERATOR_ROLE(), address(auction));
        vault.grantRole(vault.PROTOCOL_ROLE(), address(book));
        vault.grantRole(vault.PROTOCOL_ROLE(), address(auction));
        token.grantRole(token.MINTER_ROLE(), address(auction));
        vm.stopPrank();

        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        vm.deal(user3, 100 ether);
    }

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    function _setupMarket() internal returns (uint256) {
        vm.prank(operator);
        return book.registerMarket(1, 3, block.timestamp + 3600);
    }

    function _deposit(address user, uint256 amount) internal {
        vm.prank(user);
        vault.deposit{value: amount}();
    }

    function _placeOrder(
        address user,
        uint256 marketId,
        Side side,
        OrderType ot,
        uint256 tick,
        uint256 lots
    ) internal returns (uint256) {
        uint256 collateral;
        if (side == Side.Bid) {
            collateral = (lots * LOT * tick) / 100;
        } else {
            collateral = (lots * LOT * (100 - tick)) / 100;
        }

        _deposit(user, collateral);
        vm.prank(user);
        return book.placeOrder(marketId, side, ot, tick, lots);
    }

    // -------------------------------------------------------------------------
    // Order-ID array helpers
    // -------------------------------------------------------------------------

    function _noIds() internal pure returns (uint256[] memory) {
        return new uint256[](0);
    }

    function _ids(uint256 a) internal pure returns (uint256[] memory arr) {
        arr = new uint256[](1);
        arr[0] = a;
    }

    function _ids(uint256 a, uint256 b) internal pure returns (uint256[] memory arr) {
        arr = new uint256[](2);
        arr[0] = a;
        arr[1] = b;
    }

    function _ids(uint256 a, uint256 b, uint256 c) internal pure returns (uint256[] memory arr) {
        arr = new uint256[](3);
        arr[0] = a;
        arr[1] = b;
        arr[2] = c;
    }

    function _ids(uint256 a, uint256 b, uint256 c, uint256 d) internal pure returns (uint256[] memory arr) {
        arr = new uint256[](4);
        arr[0] = a;
        arr[1] = b;
        arr[2] = c;
        arr[3] = d;
    }

    // =========================================================================
    // clearBatch — no cross
    // =========================================================================

    function test_ClearBatch_EmptyBook() public {
        uint256 mId = _setupMarket();

        BatchResult memory r = auction.clearBatch(mId, _noIds());

        assertEq(r.clearingTick, 0);
        assertEq(r.matchedLots, 0);
        assertEq(r.batchId, 1);
    }

    function test_ClearBatch_OnlyBids() public {
        uint256 mId = _setupMarket();
        _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilBatch, 50, 10);

        BatchResult memory r = auction.clearBatch(mId, _noIds());

        assertEq(r.clearingTick, 0);
        assertEq(r.matchedLots, 0);
    }

    function test_ClearBatch_AdvancesBatchId() public {
        uint256 mId = _setupMarket();

        auction.clearBatch(mId, _noIds());

        (, , , uint32 batchId, , , ) = book.markets(mId);
        assertEq(batchId, 2);
    }

    function test_ClearBatch_EmitsEvent() public {
        uint256 mId = _setupMarket();

        vm.expectEmit(true, true, false, true);
        emit BatchAuction.BatchCleared(mId, 1, 0, 0);

        auction.clearBatch(mId, _noIds());
    }

    // =========================================================================
    // clearBatch — with crossing orders
    // =========================================================================

    function test_ClearBatch_PerfectMatch() public {
        uint256 mId = _setupMarket();

        // Bid at 50 for 10 lots, Ask at 50 for 10 lots → perfect match
        _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilBatch, 50, 10);
        _placeOrder(user2, mId, Side.Ask, OrderType.GoodTilBatch, 50, 10);

        BatchResult memory r = auction.clearBatch(mId, _noIds());

        assertEq(r.clearingTick, 50);
        assertEq(r.matchedLots, 10);
        assertEq(r.totalBidLots, 10);
        assertEq(r.totalAskLots, 10);
    }

    function test_ClearBatch_BidAboveAsk() public {
        uint256 mId = _setupMarket();

        // Bid at 60, Ask at 40 → cross somewhere in between
        _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilBatch, 60, 10);
        _placeOrder(user2, mId, Side.Ask, OrderType.GoodTilBatch, 40, 10);

        BatchResult memory r = auction.clearBatch(mId, _noIds());

        // Should find a clearing tick in [40, 60]
        assertGe(r.clearingTick, 40);
        assertLe(r.clearingTick, 60);
        assertEq(r.matchedLots, 10);
    }

    function test_ClearBatch_AsymmetricVolume() public {
        uint256 mId = _setupMarket();

        // 20 lots bid, 10 lots ask at same tick → matched = 10
        _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilBatch, 50, 20);
        _placeOrder(user2, mId, Side.Ask, OrderType.GoodTilBatch, 50, 10);

        BatchResult memory r = auction.clearBatch(mId, _noIds());

        assertEq(r.clearingTick, 50);
        assertEq(r.matchedLots, 10);
        assertEq(r.totalBidLots, 20);
        assertEq(r.totalAskLots, 10);
    }

    function test_ClearBatch_MultipleBatches() public {
        uint256 mId = _setupMarket();

        _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilCancel, 50, 10);
        _placeOrder(user2, mId, Side.Ask, OrderType.GoodTilCancel, 50, 10);

        BatchResult memory r1 = auction.clearBatch(mId, _noIds());
        assertEq(r1.batchId, 1);

        // Advance past batch interval (3s) before second clear
        vm.warp(block.timestamp + 3);

        // Second batch (same GTC orders still in book)
        BatchResult memory r2 = auction.clearBatch(mId, _noIds());
        assertEq(r2.batchId, 2);
    }

    // =========================================================================
    // clearBatch — validation
    // =========================================================================

    function test_ClearBatch_RevertIfMarketNotFound() public {
        vm.expectRevert("BatchAuction: market not found");
        auction.clearBatch(999, _noIds());
    }

    function test_ClearBatch_RevertIfHalted() public {
        uint256 mId = _setupMarket();

        vm.prank(operator);
        book.haltMarket(mId);

        vm.expectRevert("BatchAuction: market halted");
        auction.clearBatch(mId, _noIds());
    }

    function test_ClearBatch_RevertIfDeactivated() public {
        uint256 mId = _setupMarket();

        vm.prank(operator);
        book.deactivateMarket(mId);

        vm.expectRevert("BatchAuction: market not active");
        auction.clearBatch(mId, _noIds());
    }

    // =========================================================================
    // claimFills — basic
    // =========================================================================

    function test_ClaimFills_FullFill() public {
        uint256 mId = _setupMarket();

        uint256 bidId = _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilBatch, 50, 10);
        uint256 askId = _placeOrder(user2, mId, Side.Ask, OrderType.GoodTilBatch, 50, 10);

        auction.clearBatch(mId, _noIds());

        // Claim bid fill
        auction.claimFills(bidId);

        // Order should be zeroed out
        (, , , , uint64 bidLots, , , , ) = book.orders(bidId);
        assertEq(bidLots, 0);

        // Claim ask fill
        auction.claimFills(askId);

        (, , , , uint64 askLots, , , , ) = book.orders(askId);
        assertEq(askLots, 0);
    }

    function test_ClaimFills_EmitsEvent() public {
        uint256 mId = _setupMarket();

        uint256 bidId = _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilBatch, 50, 10);
        _placeOrder(user2, mId, Side.Ask, OrderType.GoodTilBatch, 50, 10);

        auction.clearBatch(mId, _noIds());

        // Full fill → unfilledCollateral = 0
        vm.expectEmit(true, true, false, true);
        emit BatchAuction.FillClaimed(bidId, user1, 10, 0);

        auction.claimFills(bidId);
    }

    function test_ClaimFills_UnlocksCollateral() public {
        uint256 mId = _setupMarket();

        uint256 bidId = _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilBatch, 50, 10);
        _placeOrder(user2, mId, Side.Ask, OrderType.GoodTilBatch, 50, 10);

        uint256 lockedBefore = vault.locked(user1);
        assertGt(lockedBefore, 0);

        auction.clearBatch(mId, _noIds());

        auction.claimFills(bidId);

        // All collateral should be unlocked after claim
        assertEq(vault.locked(user1), 0);
    }

    function test_ClaimFills_NoCross_NoFill() public {
        uint256 mId = _setupMarket();

        // Only bids, no asks → no cross
        uint256 bidId = _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilBatch, 50, 10);

        auction.clearBatch(mId, _noIds());

        // Claim should succeed but with 0 fill
        vm.expectEmit(true, true, false, true);
        emit BatchAuction.FillClaimed(bidId, user1, 0, 0);

        auction.claimFills(bidId);
    }

    function test_ClaimFills_NonParticipatingOrder() public {
        uint256 mId = _setupMarket();

        // Bid at 30 (below clearing), Ask at 50, Bid at 50
        _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilBatch, 50, 10);
        _placeOrder(user2, mId, Side.Ask, OrderType.GoodTilBatch, 50, 10);

        // Extra bid at tick 30 — below clearing tick of 50
        uint256 lowBidId = _placeOrder(user3, mId, Side.Bid, OrderType.GoodTilBatch, 30, 5);

        BatchResult memory r = auction.clearBatch(mId, _noIds());
        assertEq(r.clearingTick, 50);

        // Low bid doesn't participate (tick 30 < clearing 50)
        auction.claimFills(lowBidId);

        // Should not change the order lots (no fill, but claim marks it)
        assertTrue(auction.claimed(lowBidId));
    }

    // =========================================================================
    // claimFills — pro-rata
    // =========================================================================

    function test_ClaimFills_ProRata_BidOversubscribed() public {
        uint256 mId = _setupMarket();

        // 20 lots bid, 10 lots ask → bids oversubscribed 2:1
        uint256 bid1 = _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilBatch, 50, 10);
        uint256 bid2 = _placeOrder(user2, mId, Side.Bid, OrderType.GoodTilBatch, 50, 10);
        _placeOrder(user3, mId, Side.Ask, OrderType.GoodTilBatch, 50, 10);

        BatchResult memory r = auction.clearBatch(mId, _noIds());
        assertEq(r.matchedLots, 10);
        assertEq(r.totalBidLots, 20);

        // Each bid should get 50% fill (5 lots each)
        auction.claimFills(bid1);
        auction.claimFills(bid2);

        // Both orders should be fully removed from book
        (, , , , uint64 lots1, , , , ) = book.orders(bid1);
        (, , , , uint64 lots2, , , , ) = book.orders(bid2);
        assertEq(lots1, 0);
        assertEq(lots2, 0);
    }

    function test_ClaimFills_ProRata_AskOversubscribed() public {
        uint256 mId = _setupMarket();

        // 10 lots bid, 20 lots ask → asks oversubscribed 2:1
        _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilBatch, 50, 10);
        uint256 ask1 = _placeOrder(user2, mId, Side.Ask, OrderType.GoodTilBatch, 50, 10);
        uint256 ask2 = _placeOrder(user3, mId, Side.Ask, OrderType.GoodTilBatch, 50, 10);

        BatchResult memory r = auction.clearBatch(mId, _noIds());
        assertEq(r.matchedLots, 10);
        assertEq(r.totalAskLots, 20);

        auction.claimFills(ask1);
        auction.claimFills(ask2);

        // Both orders should be fully removed
        (, , , , uint64 lots1, , , , ) = book.orders(ask1);
        (, , , , uint64 lots2, , , , ) = book.orders(ask2);
        assertEq(lots1, 0);
        assertEq(lots2, 0);
    }

    // =========================================================================
    // claimFills — validation
    // =========================================================================

    function test_ClaimFills_RevertIfAlreadyClaimed() public {
        uint256 mId = _setupMarket();

        uint256 bidId = _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilBatch, 50, 10);
        _placeOrder(user2, mId, Side.Ask, OrderType.GoodTilBatch, 50, 10);

        auction.clearBatch(mId, _noIds());

        auction.claimFills(bidId);

        vm.expectRevert("BatchAuction: already claimed");
        auction.claimFills(bidId);
    }

    function test_ClaimFills_RevertIfBatchNotCleared() public {
        uint256 mId = _setupMarket();
        uint256 bidId = _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilBatch, 50, 10);

        // Don't clear the batch
        vm.expectRevert("BatchAuction: batch not cleared");
        auction.claimFills(bidId);
    }

    // =========================================================================
    // pruneExpiredOrder
    // =========================================================================

    function test_PruneExpired_Basic() public {
        uint256 mId = _setupMarket();

        uint256 orderId = _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilBatch, 50, 10);

        // Clear batch to advance it
        auction.clearBatch(mId, _noIds());

        // Now the GTB order is expired (batch advanced)
        vm.prank(pruner);
        auction.pruneExpiredOrder(orderId);

        // Order should be zeroed out
        (, , , , uint64 lots, , , , ) = book.orders(orderId);
        assertEq(lots, 0);

        // Collateral should be unlocked
        assertEq(vault.locked(user1), 0);
    }

    function test_PruneExpired_EmitsEvent() public {
        uint256 mId = _setupMarket();

        uint256 orderId = _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilBatch, 50, 10);

        auction.clearBatch(mId, _noIds());

        vm.expectEmit(true, true, false, false);
        emit BatchAuction.OrderPruned(orderId, pruner);

        vm.prank(pruner);
        auction.pruneExpiredOrder(orderId);
    }

    function test_PruneExpired_AskOrder() public {
        uint256 mId = _setupMarket();

        uint256 orderId = _placeOrder(user1, mId, Side.Ask, OrderType.GoodTilBatch, 40, 10);
        uint256 expectedCollateral = (10 * LOT * 60) / 100;

        auction.clearBatch(mId, _noIds());

        vm.prank(pruner);
        auction.pruneExpiredOrder(orderId);

        assertEq(vault.locked(user1), 0);
        assertEq(vault.available(user1), expectedCollateral);
    }

    function test_PruneExpired_RevertIfNotGTB() public {
        uint256 mId = _setupMarket();

        uint256 orderId = _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilCancel, 50, 10);

        auction.clearBatch(mId, _noIds());

        vm.expectRevert("BatchAuction: not GTB order");
        vm.prank(pruner);
        auction.pruneExpiredOrder(orderId);
    }

    function test_PruneExpired_RevertIfBatchNotAdvanced() public {
        uint256 mId = _setupMarket();

        uint256 orderId = _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilBatch, 50, 10);

        // Don't clear batch
        vm.expectRevert("BatchAuction: batch not yet advanced");
        vm.prank(pruner);
        auction.pruneExpiredOrder(orderId);
    }

    function test_PruneExpired_RevertIfAlreadyEmpty() public {
        uint256 mId = _setupMarket();

        uint256 orderId = _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilBatch, 50, 10);

        auction.clearBatch(mId, _noIds());

        // Prune once
        vm.prank(pruner);
        auction.pruneExpiredOrder(orderId);

        // Prune again — should fail
        vm.expectRevert("BatchAuction: order already empty");
        vm.prank(pruner);
        auction.pruneExpiredOrder(orderId);
    }

    function test_PruneExpired_UpdatesTree() public {
        uint256 mId = _setupMarket();

        _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilBatch, 50, 10);
        uint256 orderId2 = _placeOrder(user2, mId, Side.Bid, OrderType.GoodTilBatch, 50, 5);

        assertEq(book.bidVolumeAt(mId, 50), 15);

        auction.clearBatch(mId, _noIds());

        vm.prank(pruner);
        auction.pruneExpiredOrder(orderId2);

        // Only orderId2 (5 lots) pruned from 15
        assertEq(book.bidVolumeAt(mId, 50), 10);
    }

    // =========================================================================
    // getBatchResult view
    // =========================================================================

    function test_GetBatchResult() public {
        uint256 mId = _setupMarket();

        _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilBatch, 50, 10);
        _placeOrder(user2, mId, Side.Ask, OrderType.GoodTilBatch, 50, 10);

        auction.clearBatch(mId, _noIds());

        BatchResult memory r = auction.getBatchResult(mId, 1);
        assertEq(r.marketId, mId);
        assertEq(r.batchId, 1);
        assertEq(r.clearingTick, 50);
        assertEq(r.matchedLots, 10);
        assertGt(r.timestamp, 0);
    }

    // =========================================================================
    // Integration: full lifecycle
    // =========================================================================

    function test_FullLifecycle_PlaceClearClaim() public {
        uint256 mId = _setupMarket();

        // Place matching orders
        uint256 bidId = _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilBatch, 50, 10);
        uint256 askId = _placeOrder(user2, mId, Side.Ask, OrderType.GoodTilBatch, 50, 10);

        // Verify collateral locked
        uint256 bidCollateral = (10 * LOT * 50) / 100;
        uint256 askCollateral = (10 * LOT * 50) / 100;
        assertEq(vault.locked(user1), bidCollateral);
        assertEq(vault.locked(user2), askCollateral);

        // Clear batch
        BatchResult memory r = auction.clearBatch(mId, _noIds());
        assertEq(r.clearingTick, 50);
        assertEq(r.matchedLots, 10);

        // Claim fills
        auction.claimFills(bidId);
        auction.claimFills(askId);

        // All collateral unlocked
        assertEq(vault.locked(user1), 0);
        assertEq(vault.locked(user2), 0);
    }

    function test_FullLifecycle_MultiTickCross() public {
        uint256 mId = _setupMarket();

        // Bids at different ticks
        uint256 bid60 = _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilBatch, 60, 10);
        uint256 bid55 = _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilBatch, 55, 5);

        // Asks at different ticks
        uint256 ask40 = _placeOrder(user2, mId, Side.Ask, OrderType.GoodTilBatch, 40, 8);
        uint256 ask50 = _placeOrder(user2, mId, Side.Ask, OrderType.GoodTilBatch, 50, 7);

        BatchResult memory r = auction.clearBatch(mId, _noIds());

        // Should find a clearing tick
        assertGt(r.clearingTick, 0);
        assertGt(r.matchedLots, 0);

        // Claim all
        auction.claimFills(bid60);
        auction.claimFills(bid55);
        auction.claimFills(ask40);
        auction.claimFills(ask50);
    }

    function test_FullLifecycle_CancelBeforeClear() public {
        uint256 mId = _setupMarket();

        uint256 bidId = _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilCancel, 50, 10);

        // Cancel before clearing
        vm.prank(user1);
        book.cancelOrder(bidId);

        // Verify collateral unlocked
        assertEq(vault.locked(user1), 0);
    }

    // =========================================================================
    // Edge cases
    // =========================================================================

    function test_ClearBatch_MultipleOrdersSameTick() public {
        uint256 mId = _setupMarket();

        _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilBatch, 50, 5);
        _placeOrder(user2, mId, Side.Bid, OrderType.GoodTilBatch, 50, 5);
        _placeOrder(user3, mId, Side.Ask, OrderType.GoodTilBatch, 50, 10);

        BatchResult memory r = auction.clearBatch(mId, _noIds());

        assertEq(r.clearingTick, 50);
        assertEq(r.matchedLots, 10);
    }

    function test_ClearBatch_Tick1() public {
        uint256 mId = _setupMarket();

        _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilBatch, 1, 10);
        _placeOrder(user2, mId, Side.Ask, OrderType.GoodTilBatch, 1, 10);

        BatchResult memory r = auction.clearBatch(mId, _noIds());

        assertEq(r.clearingTick, 1);
        assertEq(r.matchedLots, 10);
    }

    function test_ClearBatch_Tick99() public {
        uint256 mId = _setupMarket();

        _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilBatch, 99, 10);
        _placeOrder(user2, mId, Side.Ask, OrderType.GoodTilBatch, 99, 10);

        BatchResult memory r = auction.clearBatch(mId, _noIds());

        assertEq(r.clearingTick, 99);
        assertEq(r.matchedLots, 10);
    }

    function test_PruneAfterClaimFills() public {
        uint256 mId = _setupMarket();

        // Place GTB bid — no matching ask, so won't fill
        uint256 orderId = _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilBatch, 50, 10);

        // Clear batch (no cross)
        auction.clearBatch(mId, _noIds());

        // Claim fills (0 fill since no cross)
        auction.claimFills(orderId);

        // Order still has lots since it got 0 fill but claim didn't remove non-participating orders
        // Actually our claimFills removes 0 lots for non-participating
        (, , , , uint64 lots, , , , ) = book.orders(orderId);
        assertEq(lots, 10); // Still has lots

        // Now prune
        vm.prank(pruner);
        auction.pruneExpiredOrder(orderId);

        (, , , , uint64 lotsAfter, , , , ) = book.orders(orderId);
        assertEq(lotsAfter, 0);
    }

    // =========================================================================
    // Token delivery — bidder gets YES, asker gets NO
    // =========================================================================

    function test_ClaimFills_BidReceivesYesTokens() public {
        uint256 mId = _setupMarket();

        uint256 bidId = _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilBatch, 50, 10);
        _placeOrder(user2, mId, Side.Ask, OrderType.GoodTilBatch, 50, 10);

        auction.clearBatch(mId, _noIds());
        auction.claimFills(bidId);

        // Bidder should have 10 YES tokens
        uint256 yesId = token.yesTokenId(mId);
        assertEq(token.balanceOf(user1, yesId), 10);

        // Bidder should NOT have NO tokens (burned during claim)
        uint256 noId = token.noTokenId(mId);
        assertEq(token.balanceOf(user1, noId), 0);
    }

    function test_ClaimFills_AskReceivesNoTokens() public {
        uint256 mId = _setupMarket();

        _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilBatch, 50, 10);
        uint256 askId = _placeOrder(user2, mId, Side.Ask, OrderType.GoodTilBatch, 50, 10);

        auction.clearBatch(mId, _noIds());
        auction.claimFills(askId);

        // Asker should have 10 NO tokens
        uint256 noId = token.noTokenId(mId);
        assertEq(token.balanceOf(user2, noId), 10);

        // Asker should NOT have YES tokens (burned during claim)
        uint256 yesId = token.yesTokenId(mId);
        assertEq(token.balanceOf(user2, yesId), 0);
    }

    // =========================================================================
    // Fee deduction
    // =========================================================================

    function test_ClaimFills_FeeDeducted() public {
        uint256 mId = _setupMarket();

        uint256 bidId = _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilBatch, 50, 10);
        _placeOrder(user2, mId, Side.Ask, OrderType.GoodTilBatch, 50, 10);

        auction.clearBatch(mId, _noIds());

        uint256 collectorBefore = vault.balance(admin); // admin is fee collector
        auction.claimFills(bidId);

        // Filled collateral = 10 * LOT * 50 / 100 = 5e15
        uint256 filledCollateral = (10 * LOT * 50) / 100;
        uint256 expectedFee = (filledCollateral * 30) / 10000; // 30 bps
        assertEq(vault.balance(admin) - collectorBefore, expectedFee);
    }

    function test_ClaimFills_CollateralGoesToPool() public {
        uint256 mId = _setupMarket();

        uint256 bidId = _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilBatch, 50, 10);
        _placeOrder(user2, mId, Side.Ask, OrderType.GoodTilBatch, 50, 10);

        auction.clearBatch(mId, _noIds());
        auction.claimFills(bidId);

        uint256 filledCollateral = (10 * LOT * 50) / 100;
        uint256 fee = (filledCollateral * 30) / 10000;
        uint256 expectedPool = filledCollateral - fee;
        assertEq(vault.marketPool(mId), expectedPool);
    }

    // =========================================================================
    // Batch interval enforcement
    // =========================================================================

    function test_ClearBatch_RevertIfTooSoon() public {
        uint256 mId = _setupMarket(); // batchInterval = 3

        auction.clearBatch(mId, _noIds());

        // Attempt second clear immediately — should revert
        vm.expectRevert("BatchAuction: too soon");
        auction.clearBatch(mId, _noIds());
    }

    function test_ClearBatch_SucceedsAfterInterval() public {
        uint256 mId = _setupMarket(); // batchInterval = 3

        auction.clearBatch(mId, _noIds());

        // Advance past interval
        vm.warp(block.timestamp + 3);

        // Should succeed
        BatchResult memory r = auction.clearBatch(mId, _noIds());
        assertEq(r.batchId, 2);
    }

    // =========================================================================
    // _orderParticipates — bid/ask logic (tested via claimFills)
    // =========================================================================

    function test_Participates_BidAtClearingTick() public {
        uint256 mId = _setupMarket();

        // Clearing tick will be 50
        uint256 bidId = _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilBatch, 50, 5);
        _placeOrder(user2, mId, Side.Ask, OrderType.GoodTilBatch, 50, 5);

        auction.clearBatch(mId, _noIds());
        auction.claimFills(bidId);

        // Bid at clearing tick participates — should get fill
        uint256 yesId = token.yesTokenId(mId);
        assertEq(token.balanceOf(user1, yesId), 5, "bid at clearing tick should fill");
    }

    function test_Participates_BidAboveClearingTick() public {
        uint256 mId = _setupMarket();

        // Bid at 60, ask at 50 → clearing at 50 (or somewhere ≤60)
        uint256 bidId = _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilBatch, 60, 5);
        _placeOrder(user2, mId, Side.Ask, OrderType.GoodTilBatch, 50, 5);

        BatchResult memory r = auction.clearBatch(mId, _noIds());
        assertLe(r.clearingTick, 60, "clearing tick should be <= 60");

        auction.claimFills(bidId);

        // Bid above clearing tick participates
        uint256 yesId = token.yesTokenId(mId);
        assertEq(token.balanceOf(user1, yesId), 5, "bid above clearing tick should fill");
    }

    function test_Participates_BidBelowClearingTick() public {
        uint256 mId = _setupMarket();

        // Create crossing at tick 50, place a bid at 30 (below clearing)
        _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilBatch, 50, 5);
        _placeOrder(user2, mId, Side.Ask, OrderType.GoodTilBatch, 50, 5);
        uint256 lowBidId = _placeOrder(user3, mId, Side.Bid, OrderType.GoodTilBatch, 30, 5);

        BatchResult memory r = auction.clearBatch(mId, _noIds());
        assertEq(r.clearingTick, 50);

        auction.claimFills(lowBidId);

        // Bid below clearing tick does NOT participate — 0 tokens
        uint256 yesId = token.yesTokenId(mId);
        assertEq(token.balanceOf(user3, yesId), 0, "bid below clearing tick should NOT fill");
    }

    function test_Participates_AskAtClearingTick() public {
        uint256 mId = _setupMarket();

        _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilBatch, 50, 5);
        uint256 askId = _placeOrder(user2, mId, Side.Ask, OrderType.GoodTilBatch, 50, 5);

        auction.clearBatch(mId, _noIds());
        auction.claimFills(askId);

        // Ask at clearing tick participates
        uint256 noId = token.noTokenId(mId);
        assertEq(token.balanceOf(user2, noId), 5, "ask at clearing tick should fill");
    }

    function test_Participates_AskBelowClearingTick() public {
        uint256 mId = _setupMarket();

        // Bid at 50, ask at 40 → clearing at some tick in [40,50]; ask at 40 is below or at clearing
        uint256 askId = _placeOrder(user2, mId, Side.Ask, OrderType.GoodTilBatch, 40, 5);
        _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilBatch, 50, 5);

        BatchResult memory r = auction.clearBatch(mId, _noIds());
        assertGe(r.clearingTick, 40, "clearing should be >= ask tick");

        auction.claimFills(askId);

        // Ask below clearing tick participates
        uint256 noId = token.noTokenId(mId);
        assertEq(token.balanceOf(user2, noId), 5, "ask below clearing tick should fill");
    }

    function test_Participates_AskAboveClearingTick() public {
        uint256 mId = _setupMarket();

        // Create crossing at tick 50, place an ask at 70 (above clearing)
        _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilBatch, 50, 5);
        _placeOrder(user2, mId, Side.Ask, OrderType.GoodTilBatch, 50, 5);
        uint256 highAskId = _placeOrder(user3, mId, Side.Ask, OrderType.GoodTilBatch, 70, 5);

        BatchResult memory r = auction.clearBatch(mId, _noIds());
        assertEq(r.clearingTick, 50);

        auction.claimFills(highAskId);

        // Ask above clearing tick does NOT participate — 0 tokens
        uint256 noId = token.noTokenId(mId);
        assertEq(token.balanceOf(user3, noId), 0, "ask above clearing tick should NOT fill");
    }

    function test_Participates_NoCross_ClearingTickZero() public {
        uint256 mId = _setupMarket();

        // Only bids, no asks → clearingTick = 0
        uint256 bidId = _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilBatch, 50, 5);

        BatchResult memory r = auction.clearBatch(mId, _noIds());
        assertEq(r.clearingTick, 0, "one-sided book should have clearingTick = 0");
        assertEq(r.matchedLots, 0);

        // Bid gets 0 fill when clearingTick == 0
        auction.claimFills(bidId);

        uint256 yesId = token.yesTokenId(mId);
        assertEq(token.balanceOf(user1, yesId), 0, "bid should not fill when clearingTick = 0");
    }

    /// @notice Phantom clearing tick: non-overlapping bid/ask survive clearBatch untouched
    function test_PhantomClearingTick_OrdersSurvive() public {
        uint256 mId = _setupMarket();

        // Bid at 30, ask at 70 — no overlap
        uint256 bidId = _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilCancel, 30, 10);
        uint256 askId = _placeOrder(user2, mId, Side.Ask, OrderType.GoodTilCancel, 70, 10);

        uint256 user1LockedBefore = vault.locked(user1);
        uint256 user2LockedBefore = vault.locked(user2);

        BatchResult memory r = auction.clearBatch(mId, _noIds());

        // Should have zero fills and clearing tick 0
        assertEq(r.clearingTick, 0, "clearingTick should be 0 with non-overlapping orders");
        assertEq(r.matchedLots, 0, "matchedLots should be 0");

        // Claim — no fills, collateral unchanged
        auction.claimFills(bidId);
        auction.claimFills(askId);

        // GTC orders should still have their lots (no destruction)
        (, , , , uint64 bidLots, , , , ) = book.orders(bidId);
        (, , , , uint64 askLots, , , , ) = book.orders(askId);
        assertEq(bidLots, 10, "bid order should still have all lots");
        assertEq(askLots, 10, "ask order should still have all lots");

        // Collateral should still be locked
        assertEq(vault.locked(user1), user1LockedBefore, "bid collateral should remain locked");
        assertEq(vault.locked(user2), user2LockedBefore, "ask collateral should remain locked");
    }

    function test_Participates_NoCross_NeitherSideParticipates() public {
        uint256 mId = _setupMarket();

        // Bid far below ask — segment tree may find a non-zero clearing tick
        // but neither order participates because bid < clearing and ask > clearing
        uint256 bidId = _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilBatch, 30, 5);
        uint256 askId = _placeOrder(user2, mId, Side.Ask, OrderType.GoodTilBatch, 70, 5);

        BatchResult memory r = auction.clearBatch(mId, _noIds());
        // matchedLots should be 0 regardless of clearing tick
        assertEq(r.matchedLots, 0, "no real cross means 0 matched lots");

        // Neither side gets tokens
        auction.claimFills(bidId);
        auction.claimFills(askId);

        uint256 yesId = token.yesTokenId(mId);
        uint256 noId = token.noTokenId(mId);
        assertEq(token.balanceOf(user1, yesId), 0, "bid should not fill");
        assertEq(token.balanceOf(user2, noId), 0, "ask should not fill");
    }

    // =========================================================================
    // pruneExpiredOrder — participation-dependent pruning
    // =========================================================================

    function test_PruneExpired_AskBelowClearing_RequiresClaimFirst() public {
        uint256 mId = _setupMarket();

        // Ask at tick 40, bid at tick 50 → clearing at some tick >= 40
        // Ask participates (tick <= clearingTick)
        uint256 askId = _placeOrder(user2, mId, Side.Ask, OrderType.GoodTilBatch, 40, 5);
        _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilBatch, 50, 5);

        BatchResult memory r = auction.clearBatch(mId, _noIds());
        assertGe(r.clearingTick, 40, "clearing tick should be >= 40");

        // Try to prune without claiming — should revert because the ask participated
        vm.expectRevert("BatchAuction: claim fills first");
        vm.prank(pruner);
        auction.pruneExpiredOrder(askId);
    }

    function test_PruneExpired_AskAboveClearing_PrunesDirectly() public {
        uint256 mId = _setupMarket();

        // Ask at tick 70 (above clearing of 50), does NOT participate
        uint256 highAskId = _placeOrder(user3, mId, Side.Ask, OrderType.GoodTilBatch, 70, 5);
        _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilBatch, 50, 5);
        _placeOrder(user2, mId, Side.Ask, OrderType.GoodTilBatch, 50, 5);

        BatchResult memory r = auction.clearBatch(mId, _noIds());
        assertEq(r.clearingTick, 50);

        // High ask didn't participate — can be pruned directly without claiming
        vm.prank(pruner);
        auction.pruneExpiredOrder(highAskId);

        (, , , , uint64 lots, , , , ) = book.orders(highAskId);
        assertEq(lots, 0, "non-participating ask should be pruned");
        assertEq(vault.locked(user3), 0, "collateral should be unlocked");
    }

    // =========================================================================
    // Fuzz: placeOrder with random tick/lots/side → clearBatch → invariants
    // =========================================================================

    function testFuzz_PlaceClearClaim_Invariants(
        uint256 _bidTick,
        uint256 _askTick,
        uint256 _bidLots,
        uint256 _askLots
    ) public {
        // Bound inputs to valid ranges
        uint8 bidTick = uint8(bound(_bidTick, 1, 99));
        uint8 askTick = uint8(bound(_askTick, 1, 99));
        uint8 bidLots = uint8(bound(_bidLots, 1, 100));
        uint8 askLots = uint8(bound(_askLots, 1, 100));

        uint256 mId = _setupMarket();

        uint256 bidId = _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilBatch, bidTick, bidLots);
        uint256 askId = _placeOrder(user2, mId, Side.Ask, OrderType.GoodTilBatch, askTick, askLots);

        uint256 user1LockedBefore = vault.locked(user1);
        uint256 user2LockedBefore = vault.locked(user2);

        BatchResult memory r = auction.clearBatch(mId, _noIds());

        // Invariant: matchedLots <= min(totalBidLots, totalAskLots)
        if (r.clearingTick > 0) {
            uint256 minSide = r.totalBidLots < r.totalAskLots ? r.totalBidLots : r.totalAskLots;
            assertLe(r.matchedLots, minSide, "matchedLots <= min side");
        }

        // Invariant: clearingTick 0 → matchedLots 0
        if (r.clearingTick == 0) {
            assertEq(r.matchedLots, 0, "zero clearing tick means zero matched");
        }

        // Claim should succeed without revert
        auction.claimFills(bidId);
        auction.claimFills(askId);

        // Invariant: user's locked balance should decrease or stay same after claim
        assertLe(vault.locked(user1), user1LockedBefore, "user1 locked should not increase");
        assertLe(vault.locked(user2), user2LockedBefore, "user2 locked should not increase");
    }

    // =========================================================================
    // Inline settlement — new tests
    // =========================================================================

    function test_InlineSettlement_VerifiesBalances() public {
        uint256 mId = _setupMarket();

        uint256 bidId = _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilBatch, 50, 10);
        uint256 askId = _placeOrder(user2, mId, Side.Ask, OrderType.GoodTilBatch, 50, 10);

        // Clear with inline settlement
        BatchResult memory r = auction.clearBatch(mId, _ids(bidId, askId));
        assertEq(r.clearingTick, 50);
        assertEq(r.matchedLots, 10);

        // Orders should be zeroed out (settled inline)
        (, , , , uint64 bidLots, , , , ) = book.orders(bidId);
        (, , , , uint64 askLots, , , , ) = book.orders(askId);
        assertEq(bidLots, 0, "bid should be settled inline");
        assertEq(askLots, 0, "ask should be settled inline");

        // Tokens minted
        assertEq(token.balanceOf(user1, token.yesTokenId(mId)), 10, "bidder should have YES tokens");
        assertEq(token.balanceOf(user2, token.noTokenId(mId)), 10, "asker should have NO tokens");

        // Collateral unlocked
        assertEq(vault.locked(user1), 0, "bid collateral should be unlocked");
        assertEq(vault.locked(user2), 0, "ask collateral should be unlocked");

        // Marked as claimed
        assertTrue(auction.claimed(bidId));
        assertTrue(auction.claimed(askId));
    }

    function test_InlineSettlement_EmptyOrderIds() public {
        uint256 mId = _setupMarket();

        _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilBatch, 50, 10);
        _placeOrder(user2, mId, Side.Ask, OrderType.GoodTilBatch, 50, 10);

        // Clear with empty orderIds — batch clears, no settlement
        BatchResult memory r = auction.clearBatch(mId, _noIds());
        assertEq(r.clearingTick, 50);
        assertEq(r.matchedLots, 10);

        // Collateral still locked (not settled)
        assertGt(vault.locked(user1), 0, "bid collateral still locked");
        assertGt(vault.locked(user2), 0, "ask collateral still locked");
    }

    function test_InlineSettlement_WrongMarket() public {
        uint256 mId1 = _setupMarket();

        // Create a second market
        vm.prank(operator);
        uint256 mId2 = book.registerMarket(1, 3, block.timestamp + 3600);

        // Place order in market 2
        uint256 orderId = _placeOrder(user1, mId2, Side.Bid, OrderType.GoodTilBatch, 50, 10);

        // Place crossing orders in market 1 so clearBatch has something to clear
        _placeOrder(user1, mId1, Side.Bid, OrderType.GoodTilBatch, 50, 10);
        _placeOrder(user2, mId1, Side.Ask, OrderType.GoodTilBatch, 50, 10);

        // Try to settle market-2 order in market-1 batch
        vm.expectRevert("BatchAuction: wrong market");
        auction.clearBatch(mId1, _ids(orderId));
    }

    function test_InlineSettlement_WrongBatch() public {
        uint256 mId = _setupMarket();

        // Clear batch 1 (empty)
        auction.clearBatch(mId, _noIds());

        // Advance time past batch interval
        vm.warp(block.timestamp + 3);

        // Place order in batch 2
        uint256 orderId = _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilBatch, 50, 10);

        // Clear batch 2 — order was placed in batch 2 so it should work
        auction.clearBatch(mId, _ids(orderId));

        // Verify it was settled
        assertTrue(auction.claimed(orderId));
    }

    function test_InlineSettlement_FallbackClaimFills() public {
        uint256 mId = _setupMarket();

        uint256 bidId = _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilBatch, 50, 10);
        uint256 askId = _placeOrder(user2, mId, Side.Ask, OrderType.GoodTilBatch, 50, 10);

        // Clear with only bid settled inline; ask not included
        auction.clearBatch(mId, _ids(bidId));

        // Bid was settled inline
        assertTrue(auction.claimed(bidId), "bid should be claimed inline");
        assertEq(token.balanceOf(user1, token.yesTokenId(mId)), 10);

        // Ask not settled yet — use fallback claimFills
        assertFalse(auction.claimed(askId), "ask should not be claimed yet");

        auction.claimFills(askId);

        // Now ask is settled
        assertTrue(auction.claimed(askId), "ask should be claimed via fallback");
        assertEq(token.balanceOf(user2, token.noTokenId(mId)), 10);
    }

    function test_InlineSettlement_DoubleClaim_Reverts() public {
        uint256 mId = _setupMarket();

        uint256 bidId = _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilBatch, 50, 10);
        _placeOrder(user2, mId, Side.Ask, OrderType.GoodTilBatch, 50, 10);

        // Settle bid inline
        auction.clearBatch(mId, _ids(bidId));

        // Fallback claimFills on already-settled order should revert
        vm.expectRevert("BatchAuction: already claimed");
        auction.claimFills(bidId);
    }
}
