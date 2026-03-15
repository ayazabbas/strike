// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/BatchAuction.sol";
import "../src/OrderBook.sol";
import "../src/Vault.sol";
import "../src/FeeModel.sol";
import "../src/OutcomeToken.sol";
import "../src/ITypes.sol";
import "./mocks/MockUSDT.sol";

contract BatchAuctionTest is Test {
    BatchAuction public auction;
    OrderBook public book;
    Vault public vault;
    FeeModel public feeModel;
    OutcomeToken public token;
    MockUSDT public usdt;

    address public admin = address(0x1);
    address public operator = address(0x2);
    address public user1 = address(0x3);
    address public user2 = address(0x4);
    address public user3 = address(0x5);

    uint256 public constant LOT = 1e16;

    function setUp() public {
        usdt = new MockUSDT();

        vm.startPrank(admin);
        vault = new Vault(admin, address(usdt));
        feeModel = new FeeModel(admin, 20, 0, 5e18, 1e17, admin);
        token = new OutcomeToken(admin);
        book = new OrderBook(admin, address(vault), address(feeModel), address(token));
        auction = new BatchAuction(admin, address(book), address(vault), address(token));

        book.grantRole(book.OPERATOR_ROLE(), operator);
        book.grantRole(book.OPERATOR_ROLE(), address(auction));
        vault.grantRole(vault.PROTOCOL_ROLE(), address(book));
        vault.grantRole(vault.PROTOCOL_ROLE(), address(auction));
        token.grantRole(token.MINTER_ROLE(), address(auction));
        vm.stopPrank();

        for (uint256 i = 0; i < 3; i++) {
            address u = [user1, user2, user3][i];
            usdt.mint(u, 100000 ether);
            vm.prank(u);
            usdt.approve(address(vault), type(uint256).max);
        }
    }

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    function _setupMarket() internal returns (uint256) {
        vm.prank(operator);
        return book.registerMarket(1, 3, block.timestamp + 3600);
    }

    function _calcCollateral(Side side, uint256 tick, uint256 lots) internal pure returns (uint256) {
        if (side == Side.Bid) return (lots * LOT * tick) / 100;
        return (lots * LOT * (100 - tick)) / 100;
    }

    function _placeOrder(
        address user,
        uint256 marketId,
        Side side,
        OrderType ot,
        uint256 tick,
        uint256 lots
    ) internal returns (uint256) {
        vm.prank(user);
        return book.placeOrder(marketId, side, ot, tick, lots);
    }

    function _createZeroFeeAuction() internal returns (BatchAuction) {
        vm.startPrank(admin);
        BatchAuction za = new BatchAuction(admin, address(book), address(vault), address(token));
        book.grantRole(book.OPERATOR_ROLE(), address(za));
        vault.grantRole(vault.PROTOCOL_ROLE(), address(za));
        token.grantRole(token.MINTER_ROLE(), address(za));
        vm.stopPrank();
        return za;
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
    // clearBatch — with crossing orders (atomic settlement)
    // =========================================================================

    function test_ClearBatch_PerfectMatch() public {
        BatchAuction za = _createZeroFeeAuction();
        uint256 mId = _setupMarket();

        _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilBatch, 50, 10);
        _placeOrder(user2, mId, Side.Ask, OrderType.GoodTilBatch, 50, 10);

        BatchResult memory r = za.clearBatch(mId);

        assertEq(r.clearingTick, 50);
        assertEq(r.matchedLots, 10);
        assertEq(r.totalBidLots, 10);
        assertEq(r.totalAskLots, 10);

        // Orders should be settled atomically
        (, , , , uint64 bidLots, , , , ) = book.orders(1);
        (, , , , uint64 askLots, , , , ) = book.orders(2);
        assertEq(bidLots, 0, "bid should be fully settled");
        assertEq(askLots, 0, "ask should be fully settled");
    }

    function test_ClearBatch_BidAboveAsk() public {
        BatchAuction za = _createZeroFeeAuction();
        uint256 mId = _setupMarket();

        _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilBatch, 60, 10);
        _placeOrder(user2, mId, Side.Ask, OrderType.GoodTilBatch, 40, 10);

        BatchResult memory r = za.clearBatch(mId);

        assertGe(r.clearingTick, 40);
        assertLe(r.clearingTick, 60);
        assertEq(r.matchedLots, 10);
    }

    function test_ClearBatch_AsymmetricVolume() public {
        BatchAuction za = _createZeroFeeAuction();
        uint256 mId = _setupMarket();

        _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilBatch, 50, 20);
        _placeOrder(user2, mId, Side.Ask, OrderType.GoodTilBatch, 50, 10);

        BatchResult memory r = za.clearBatch(mId);

        assertEq(r.clearingTick, 50);
        assertEq(r.matchedLots, 10);
        assertEq(r.totalBidLots, 20);
        assertEq(r.totalAskLots, 10);
    }

    // =========================================================================
    // Atomic settlement: token delivery
    // =========================================================================

    function test_Settlement_BidReceivesYesTokens() public {
        BatchAuction za = _createZeroFeeAuction();
        uint256 mId = _setupMarket();

        _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilBatch, 50, 10);
        _placeOrder(user2, mId, Side.Ask, OrderType.GoodTilBatch, 50, 10);

        za.clearBatch(mId);

        assertEq(token.balanceOf(user1, token.yesTokenId(mId)), 10);
        assertEq(token.balanceOf(user1, token.noTokenId(mId)), 0);
    }

    function test_Settlement_AskReceivesNoTokens() public {
        BatchAuction za = _createZeroFeeAuction();
        uint256 mId = _setupMarket();

        _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilBatch, 50, 10);
        _placeOrder(user2, mId, Side.Ask, OrderType.GoodTilBatch, 50, 10);

        za.clearBatch(mId);

        assertEq(token.balanceOf(user2, token.noTokenId(mId)), 10);
        assertEq(token.balanceOf(user2, token.yesTokenId(mId)), 0);
    }

    // =========================================================================
    // Settlement at CLEARING price (not order tick)
    // =========================================================================

    function test_Settlement_ClearingPriceRefund() public {
        BatchAuction za = _createZeroFeeAuction();
        uint256 mId = _setupMarket();

        // Bid at tick 70 (locks 70% per lot), ask at tick 40 (locks 60% per lot)
        // Clearing tick should be between 40-70 (zero fee auction)
        _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilBatch, 70, 10);
        _placeOrder(user2, mId, Side.Ask, OrderType.GoodTilBatch, 40, 10);

        uint256 user1UsdtBefore = usdt.balanceOf(user1);
        uint256 user2UsdtBefore = usdt.balanceOf(user2);

        BatchResult memory r = za.clearBatch(mId);
        assertGt(r.clearingTick, 0);

        // V2.1: locked = collateral + fee at order tick
        // excessRefund = (lockedForFilled + lockedFee) - filledCollateral - protocolFee
        uint256 bidLocked = (10 * LOT * 70) / 100;
        uint256 bidFilled = (10 * LOT * r.clearingTick) / 100;
        uint256 bidExcessRefund = (bidLocked + feeModel.calculateFee(bidLocked))
            - bidFilled - feeModel.calculateFee(bidFilled);

        uint256 askLocked = (10 * LOT * 60) / 100;
        uint256 askFilled = (10 * LOT * (100 - r.clearingTick)) / 100;
        uint256 askExcessRefund = (askLocked + feeModel.calculateFee(askLocked))
            - askFilled - feeModel.calculateFee(askFilled);

        assertEq(usdt.balanceOf(user1) - user1UsdtBefore, bidExcessRefund, "bid excess refund");
        assertEq(usdt.balanceOf(user2) - user2UsdtBefore, askExcessRefund, "ask excess refund");
    }

    // =========================================================================
    // Fee deduction
    // =========================================================================

    function test_Settlement_FeeDeducted() public {
        uint256 mId = _setupMarket();

        _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilBatch, 50, 10);
        _placeOrder(user2, mId, Side.Ask, OrderType.GoodTilBatch, 50, 10);

        uint256 collectorBefore = vault.balance(admin);
        auction.clearBatch(mId);

        uint256 filledCollateral = (10 * LOT * 50) / 100;
        uint256 expectedFee = (filledCollateral * 20) / 10000; // 20 bps
        // Both bid and ask pay fees
        assertGe(vault.balance(admin) - collectorBefore, expectedFee);
    }

    function test_Settlement_CollateralGoesToPool() public {
        BatchAuction za = _createZeroFeeAuction();
        uint256 mId = _setupMarket();

        _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilBatch, 50, 10);
        _placeOrder(user2, mId, Side.Ask, OrderType.GoodTilBatch, 50, 10);

        za.clearBatch(mId);

        // With zero fees and clearing at tick 50: pool = bid cost + ask cost = 50% + 50% = 100% per lot = LOT * 10
        assertEq(vault.marketPool(mId), 10 * LOT);
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
    // No batch interval enforcement (removed in V2)
    // =========================================================================

    function test_ClearBatch_CanClearImmediately() public {
        uint256 mId = _setupMarket();
        auction.clearBatch(mId);
        // Should NOT revert — no interval enforcement
        BatchResult memory r = auction.clearBatch(mId);
        assertEq(r.batchId, 2);
    }

    function test_ClearBatch_MultipleBatches() public {
        uint256 mId = _setupMarket();

        BatchResult memory r1 = auction.clearBatch(mId);
        assertEq(r1.batchId, 1);

        BatchResult memory r2 = auction.clearBatch(mId);
        assertEq(r2.batchId, 2);
    }

    // =========================================================================
    // GTB non-participating: collateral returned
    // =========================================================================

    function test_GTB_NonParticipating_CollateralReturned() public {
        uint256 mId = _setupMarket();

        // Bid at 50 and ask at 50 cross; low bid at 30 does NOT participate
        _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilBatch, 50, 5);
        _placeOrder(user2, mId, Side.Ask, OrderType.GoodTilBatch, 50, 5);
        uint256 lowBidId = _placeOrder(user3, mId, Side.Bid, OrderType.GoodTilBatch, 30, 5);

        uint256 user3UsdtBefore = usdt.balanceOf(user3);
        uint256 lowBidCollateral = _calcCollateral(Side.Bid, 30, 5);
        uint256 lowBidFee = feeModel.calculateFee(lowBidCollateral);

        auction.clearBatch(mId);

        // Low bid was GTB non-participating → collateral + fee returned, order removed
        (, , , , uint64 lots, , , , ) = book.orders(lowBidId);
        assertEq(lots, 0, "GTB non-participating should be removed");
        assertEq(usdt.balanceOf(user3) - user3UsdtBefore, lowBidCollateral + lowBidFee, "collateral+fee should be returned");
    }

    // =========================================================================
    // GTC non-participating: rolled to next batch
    // =========================================================================

    function test_GTC_NonParticipating_RolledToNextBatch() public {
        uint256 mId = _setupMarket();

        _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilCancel, 50, 5);
        _placeOrder(user2, mId, Side.Ask, OrderType.GoodTilCancel, 50, 5);
        uint256 lowBidId = _placeOrder(user3, mId, Side.Bid, OrderType.GoodTilCancel, 30, 5);

        auction.clearBatch(mId);

        // Low GTC bid should still have lots and be in next batch
        (, , , , uint64 lots, , , , ) = book.orders(lowBidId);
        assertEq(lots, 5, "GTC non-participating should keep lots");

        // Check it was pushed to batch 2
        uint256[] memory batch2Ids = book.getBatchOrderIds(mId, 2);
        bool found = false;
        for (uint256 i = 0; i < batch2Ids.length; i++) {
            if (batch2Ids[i] == lowBidId) found = true;
        }
        assertTrue(found, "GTC order should be in next batch");
    }

    // =========================================================================
    // GTC partial fill: reduce lots, roll remainder
    // =========================================================================

    function test_GTC_PartialFill_RollsRemainder() public {
        BatchAuction za = _createZeroFeeAuction();
        uint256 mId = _setupMarket();

        // 20 lots bid, 10 lots ask → 10 filled, 10 remaining (GTC)
        uint256 bidId = _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilCancel, 50, 20);
        _placeOrder(user2, mId, Side.Ask, OrderType.GoodTilCancel, 50, 10);

        za.clearBatch(mId);

        (, , , , uint64 remainingLots, , , , ) = book.orders(bidId);
        assertEq(remainingLots, 10, "GTC partial fill should have 10 lots remaining");
        assertEq(token.balanceOf(user1, token.yesTokenId(mId)), 10, "should have 10 YES tokens");

        // Should be in next batch
        uint256[] memory batch2Ids = book.getBatchOrderIds(mId, 2);
        bool found = false;
        for (uint256 i = 0; i < batch2Ids.length; i++) {
            if (batch2Ids[i] == bidId) found = true;
        }
        assertTrue(found, "GTC order remainder should be in next batch");
    }

    // =========================================================================
    // GTC multi-batch fill
    // =========================================================================

    function test_GTC_MultiBatchFill() public {
        BatchAuction za = _createZeroFeeAuction();
        uint256 mId = _setupMarket();

        // Batch 1: bid 20, ask 5 → partial fill
        uint256 bidId = _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilCancel, 50, 20);
        _placeOrder(user2, mId, Side.Ask, OrderType.GoodTilCancel, 50, 5);

        za.clearBatch(mId);

        (, , , , uint64 lots1, , , , ) = book.orders(bidId);
        assertEq(lots1, 15);
        assertEq(token.balanceOf(user1, token.yesTokenId(mId)), 5);

        // Batch 2: ask 15 → fills remainder
        _placeOrder(user3, mId, Side.Ask, OrderType.GoodTilCancel, 50, 15);

        za.clearBatch(mId);

        (, , , , uint64 lots2, , , , ) = book.orders(bidId);
        assertEq(lots2, 0, "should be fully filled");
        assertEq(token.balanceOf(user1, token.yesTokenId(mId)), 20);
    }

    // =========================================================================
    // Pro-rata fill
    // =========================================================================

    function test_ProRata_BidOversubscribed() public {
        BatchAuction za = _createZeroFeeAuction();
        uint256 mId = _setupMarket();

        uint256 bid1 = _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilBatch, 50, 10);
        uint256 bid2 = _placeOrder(user2, mId, Side.Bid, OrderType.GoodTilBatch, 50, 10);
        _placeOrder(user3, mId, Side.Ask, OrderType.GoodTilBatch, 50, 10);

        BatchResult memory r = za.clearBatch(mId);
        assertEq(r.matchedLots, 10);
        assertEq(r.totalBidLots, 20);

        // Each bidder gets 5 lots (10 * 10 / 20)
        assertEq(token.balanceOf(user1, token.yesTokenId(mId)), 5);
        assertEq(token.balanceOf(user2, token.yesTokenId(mId)), 5);

        // GTB orders should be fully removed
        (, , , , uint64 lots1, , , , ) = book.orders(bid1);
        (, , , , uint64 lots2, , , , ) = book.orders(bid2);
        assertEq(lots1, 0);
        assertEq(lots2, 0);
    }

    // =========================================================================
    // Edge cases
    // =========================================================================

    function test_ClearBatch_MultipleOrdersSameTick() public {
        BatchAuction za = _createZeroFeeAuction();
        uint256 mId = _setupMarket();

        _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilBatch, 50, 5);
        _placeOrder(user2, mId, Side.Bid, OrderType.GoodTilBatch, 50, 5);
        _placeOrder(user3, mId, Side.Ask, OrderType.GoodTilBatch, 50, 10);

        BatchResult memory r = za.clearBatch(mId);

        assertEq(r.clearingTick, 50);
        assertEq(r.matchedLots, 10);
    }

    function test_ClearBatch_Tick1() public {
        BatchAuction za = _createZeroFeeAuction();
        uint256 mId = _setupMarket();

        _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilBatch, 1, 10);
        _placeOrder(user2, mId, Side.Ask, OrderType.GoodTilBatch, 1, 10);

        BatchResult memory r = za.clearBatch(mId);
        assertEq(r.clearingTick, 1);
        assertEq(r.matchedLots, 10);
    }

    function test_ClearBatch_Tick99() public {
        BatchAuction za = _createZeroFeeAuction();
        uint256 mId = _setupMarket();

        _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilBatch, 99, 10);
        _placeOrder(user2, mId, Side.Ask, OrderType.GoodTilBatch, 99, 10);

        BatchResult memory r = za.clearBatch(mId);
        assertEq(r.clearingTick, 99);
        assertEq(r.matchedLots, 10);
    }

    function test_NoCross_GTC_OrdersSurvive() public {
        uint256 mId = _setupMarket();

        uint256 bidId = _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilCancel, 30, 10);
        uint256 askId = _placeOrder(user2, mId, Side.Ask, OrderType.GoodTilCancel, 70, 10);

        uint256 user1LockedBefore = vault.locked(user1);
        uint256 user2LockedBefore = vault.locked(user2);

        BatchResult memory r = auction.clearBatch(mId);
        assertEq(r.clearingTick, 0);
        assertEq(r.matchedLots, 0);

        (, , , , uint64 bidLots, , , , ) = book.orders(bidId);
        (, , , , uint64 askLots, , , , ) = book.orders(askId);
        assertEq(bidLots, 10);
        assertEq(askLots, 10);

        assertEq(vault.locked(user1), user1LockedBefore);
        assertEq(vault.locked(user2), user2LockedBefore);
    }

    // =========================================================================
    // getBatchResult view
    // =========================================================================

    function test_GetBatchResult() public {
        BatchAuction za = _createZeroFeeAuction();
        uint256 mId = _setupMarket();

        _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilBatch, 50, 10);
        _placeOrder(user2, mId, Side.Ask, OrderType.GoodTilBatch, 50, 10);

        za.clearBatch(mId);

        BatchResult memory r = za.getBatchResult(mId, 1);
        assertEq(r.marketId, mId);
        assertEq(r.batchId, 1);
        assertEq(r.clearingTick, 50);
        assertEq(r.matchedLots, 10);
        assertGt(r.timestamp, 0);
    }

    // =========================================================================
    // Full lifecycle
    // =========================================================================

    function test_FullLifecycle_PlaceClearSettle() public {
        BatchAuction za = _createZeroFeeAuction();
        uint256 mId = _setupMarket();

        _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilBatch, 50, 10);
        _placeOrder(user2, mId, Side.Ask, OrderType.GoodTilBatch, 50, 10);

        // V2.1: locked = collateral + fee (OrderBook uses real feeModel)
        uint256 bidCollateral = (10 * LOT * 50) / 100;
        uint256 askCollateral = (10 * LOT * 50) / 100;
        uint256 bidFee = feeModel.calculateFee(bidCollateral);
        uint256 askFee = feeModel.calculateFee(askCollateral);
        assertEq(vault.locked(user1), bidCollateral + bidFee);
        assertEq(vault.locked(user2), askCollateral + askFee);

        BatchResult memory r = za.clearBatch(mId);
        assertEq(r.clearingTick, 50);
        assertEq(r.matchedLots, 10);

        // All settled atomically
        assertEq(vault.locked(user1), 0);
        assertEq(vault.locked(user2), 0);
    }

    function test_FullLifecycle_CancelBeforeClear() public {
        uint256 mId = _setupMarket();
        uint256 collateral = _calcCollateral(Side.Bid, 50, 10);
        uint256 fee = feeModel.calculateFee(collateral);
        uint256 bidId = _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilCancel, 50, 10);

        uint256 walletBefore = usdt.balanceOf(user1);
        vm.prank(user1);
        book.cancelOrder(bidId);

        assertEq(vault.locked(user1), 0);
        assertEq(usdt.balanceOf(user1) - walletBefore, collateral + fee);
    }

    // =========================================================================
    // Fuzz
    // =========================================================================

    function testFuzz_PlaceClearSettle_Invariants(
        uint256 _bidTick,
        uint256 _askTick,
        uint256 _bidLots,
        uint256 _askLots
    ) public {
        uint8 bidTick = uint8(bound(_bidTick, 1, 99));
        uint8 askTick = uint8(bound(_askTick, 1, 99));
        uint8 bidLots = uint8(bound(_bidLots, 1, 50));
        uint8 askLots = uint8(bound(_askLots, 1, 50));

        BatchAuction za = _createZeroFeeAuction();
        uint256 mId = _setupMarket();

        _placeOrder(user1, mId, Side.Bid, OrderType.GoodTilBatch, bidTick, bidLots);
        _placeOrder(user2, mId, Side.Ask, OrderType.GoodTilBatch, askTick, askLots);

        uint256 user1LockedBefore = vault.locked(user1);
        uint256 user2LockedBefore = vault.locked(user2);

        BatchResult memory r = za.clearBatch(mId);

        if (r.clearingTick > 0) {
            uint256 minSide = r.totalBidLots < r.totalAskLots ? r.totalBidLots : r.totalAskLots;
            assertLe(r.matchedLots, minSide);
        }

        if (r.clearingTick == 0) {
            assertEq(r.matchedLots, 0);
        }

        assertLe(vault.locked(user1), user1LockedBefore);
        assertLe(vault.locked(user2), user2LockedBefore);
    }
}
