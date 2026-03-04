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

    // =========================================================================
    // clearBatch — no cross
    // =========================================================================

    function test_ClearBatch_EmptyBook() public {
        uint256 mId = _setupMarket();

        BatchResult memory r = auction.clearBatch(mId);

        assertEq(r.clearingTick, 0);
        assertEq(r.matchedLots, 0);
        assertEq(r.batchId, 1);
    }

    function test_ClearBatch_OnlyBids() public {
        uint256 mId = _setupMarket();
        _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilBatch, 50, 10);

        BatchResult memory r = auction.clearBatch(mId);

        assertEq(r.clearingTick, 0);
        assertEq(r.matchedLots, 0);
    }

    function test_ClearBatch_AdvancesBatchId() public {
        uint256 mId = _setupMarket();

        auction.clearBatch(mId);

        (, , , uint32 batchId, , , ) = book.markets(mId);
        assertEq(batchId, 2);
    }

    function test_ClearBatch_EmitsEvent() public {
        uint256 mId = _setupMarket();

        vm.expectEmit(true, true, false, true);
        emit BatchAuction.BatchCleared(mId, 1, 0, 0);

        auction.clearBatch(mId);
    }

    // =========================================================================
    // clearBatch — with crossing orders
    // =========================================================================

    function test_ClearBatch_PerfectMatch() public {
        uint256 mId = _setupMarket();

        // Bid at 50 for 10 lots, Ask at 50 for 10 lots → perfect match
        _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilBatch, 50, 10);
        _placeOrder(user2, mId, Side.Ask, OrderType.GoodTilBatch, 50, 10);

        BatchResult memory r = auction.clearBatch(mId);

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

        BatchResult memory r = auction.clearBatch(mId);

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

        BatchResult memory r = auction.clearBatch(mId);

        assertEq(r.clearingTick, 50);
        assertEq(r.matchedLots, 10);
        assertEq(r.totalBidLots, 20);
        assertEq(r.totalAskLots, 10);
    }

    function test_ClearBatch_MultipleBatches() public {
        uint256 mId = _setupMarket();

        _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilCancel, 50, 10);
        _placeOrder(user2, mId, Side.Ask, OrderType.GoodTilCancel, 50, 10);

        BatchResult memory r1 = auction.clearBatch(mId);
        assertEq(r1.batchId, 1);

        // Advance past batch interval (3s) before second clear
        vm.warp(block.timestamp + 3);

        // Second batch (same GTC orders still in book)
        BatchResult memory r2 = auction.clearBatch(mId);
        assertEq(r2.batchId, 2);
    }

    // =========================================================================
    // clearBatch — validation
    // =========================================================================

    function test_ClearBatch_RevertIfMarketNotFound() public {
        vm.expectRevert("BatchAuction: market not found");
        auction.clearBatch(999);
    }

    function test_ClearBatch_RevertIfHalted() public {
        uint256 mId = _setupMarket();

        vm.prank(operator);
        book.haltMarket(mId);

        vm.expectRevert("BatchAuction: market halted");
        auction.clearBatch(mId);
    }

    function test_ClearBatch_RevertIfDeactivated() public {
        uint256 mId = _setupMarket();

        vm.prank(operator);
        book.deactivateMarket(mId);

        vm.expectRevert("BatchAuction: market not active");
        auction.clearBatch(mId);
    }

    // =========================================================================
    // claimFills — basic
    // =========================================================================

    function test_ClaimFills_FullFill() public {
        uint256 mId = _setupMarket();

        uint256 bidId = _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilBatch, 50, 10);
        uint256 askId = _placeOrder(user2, mId, Side.Ask, OrderType.GoodTilBatch, 50, 10);

        auction.clearBatch(mId);

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

        auction.clearBatch(mId);

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

        auction.clearBatch(mId);

        auction.claimFills(bidId);

        // All collateral should be unlocked after claim
        assertEq(vault.locked(user1), 0);
    }

    function test_ClaimFills_NoCross_NoFill() public {
        uint256 mId = _setupMarket();

        // Only bids, no asks → no cross
        uint256 bidId = _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilBatch, 50, 10);

        auction.clearBatch(mId);

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

        BatchResult memory r = auction.clearBatch(mId);
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

        BatchResult memory r = auction.clearBatch(mId);
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

        BatchResult memory r = auction.clearBatch(mId);
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

        auction.clearBatch(mId);

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
        auction.clearBatch(mId);

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

        auction.clearBatch(mId);

        vm.expectEmit(true, true, false, false);
        emit BatchAuction.OrderPruned(orderId, pruner);

        vm.prank(pruner);
        auction.pruneExpiredOrder(orderId);
    }

    function test_PruneExpired_AskOrder() public {
        uint256 mId = _setupMarket();

        uint256 orderId = _placeOrder(user1, mId, Side.Ask, OrderType.GoodTilBatch, 40, 10);
        uint256 expectedCollateral = (10 * LOT * 60) / 100;

        auction.clearBatch(mId);

        vm.prank(pruner);
        auction.pruneExpiredOrder(orderId);

        assertEq(vault.locked(user1), 0);
        assertEq(vault.available(user1), expectedCollateral);
    }

    function test_PruneExpired_RevertIfNotGTB() public {
        uint256 mId = _setupMarket();

        uint256 orderId = _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilCancel, 50, 10);

        auction.clearBatch(mId);

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

        auction.clearBatch(mId);

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

        auction.clearBatch(mId);

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

        auction.clearBatch(mId);

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
        BatchResult memory r = auction.clearBatch(mId);
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

        BatchResult memory r = auction.clearBatch(mId);

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

        BatchResult memory r = auction.clearBatch(mId);

        assertEq(r.clearingTick, 50);
        assertEq(r.matchedLots, 10);
    }

    function test_ClearBatch_Tick1() public {
        uint256 mId = _setupMarket();

        _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilBatch, 1, 10);
        _placeOrder(user2, mId, Side.Ask, OrderType.GoodTilBatch, 1, 10);

        BatchResult memory r = auction.clearBatch(mId);

        assertEq(r.clearingTick, 1);
        assertEq(r.matchedLots, 10);
    }

    function test_ClearBatch_Tick99() public {
        uint256 mId = _setupMarket();

        _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilBatch, 99, 10);
        _placeOrder(user2, mId, Side.Ask, OrderType.GoodTilBatch, 99, 10);

        BatchResult memory r = auction.clearBatch(mId);

        assertEq(r.clearingTick, 99);
        assertEq(r.matchedLots, 10);
    }

    function test_PruneAfterClaimFills() public {
        uint256 mId = _setupMarket();

        // Place GTB bid — no matching ask, so won't fill
        uint256 orderId = _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilBatch, 50, 10);

        // Clear batch (no cross)
        auction.clearBatch(mId);

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

        auction.clearBatch(mId);
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

        auction.clearBatch(mId);
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

        auction.clearBatch(mId);

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

        auction.clearBatch(mId);
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

        auction.clearBatch(mId);

        // Attempt second clear immediately — should revert
        vm.expectRevert("BatchAuction: too soon");
        auction.clearBatch(mId);
    }

    function test_ClearBatch_SucceedsAfterInterval() public {
        uint256 mId = _setupMarket(); // batchInterval = 3

        auction.clearBatch(mId);

        // Advance past interval
        vm.warp(block.timestamp + 3);

        // Should succeed
        BatchResult memory r = auction.clearBatch(mId);
        assertEq(r.batchId, 2);
    }
}
