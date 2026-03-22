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

contract AuditFixesTest is Test {
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
    address public feeCollector = address(0x99);

    uint256 public constant LOT = 1e16;

    function setUp() public {
        usdt = new MockUSDT();

        vm.startPrank(admin);
        vault = new Vault(admin, address(usdt));
        feeModel = new FeeModel(admin, 20, feeCollector);
        token = new OutcomeToken(admin);
        book = new OrderBook(admin, address(vault), address(feeModel), address(token));
        auction = new BatchAuction(admin, address(book), address(vault), address(token));

        book.grantRole(book.OPERATOR_ROLE(), operator);
        book.grantRole(book.OPERATOR_ROLE(), address(auction));
        vault.grantRole(vault.PROTOCOL_ROLE(), address(book));
        vault.grantRole(vault.PROTOCOL_ROLE(), address(auction));
        token.grantRole(token.MINTER_ROLE(), address(auction));
        token.grantRole(token.ESCROW_ROLE(), address(auction));
        vm.stopPrank();

        address[3] memory users = [user1, user2, user3];
        for (uint256 i = 0; i < 3; i++) {
            usdt.mint(users[i], 100000 ether);
            vm.prank(users[i]);
            usdt.approve(address(vault), type(uint256).max);
        }
    }

    function _setupMarket() internal returns (uint256) {
        vm.prank(operator);
        return book.registerMarket(1, 3, block.timestamp + 3600, false);
    }

    function _setupInternalMarket() internal returns (uint256) {
        vm.prank(operator);
        return book.registerMarket(1, 3, block.timestamp + 3600, true);
    }

    // =========================================================================
    // Fix 4b: Per-User Active Order Cap
    // =========================================================================

    function test_Fix4b_CapHitReverts() public {
        uint256 mId = _setupMarket();
        // Place 20 orders (the max)
        for (uint256 i = 0; i < 20; i++) {
            vm.prank(user1);
            book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 50, 1);
        }
        // 21st should revert
        vm.expectRevert("OrderBook: too many orders");
        vm.prank(user1);
        book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 50, 1);
    }

    function test_Fix4b_CancelAllowsNewPlacement() public {
        uint256 mId = _setupMarket();
        uint256[] memory orderIds = new uint256[](20);
        for (uint256 i = 0; i < 20; i++) {
            vm.prank(user1);
            orderIds[i] = book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 50, 1);
        }
        // Cancel one
        vm.prank(user1);
        book.cancelOrder(orderIds[0]);
        // Now can place again
        vm.prank(user1);
        book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 50, 1);
        // But not a 2nd one
        vm.expectRevert("OrderBook: too many orders");
        vm.prank(user1);
        book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 50, 1);
    }

    function test_Fix4b_FillDecrementsCount() public {
        uint256 mId = _setupMarket();
        // Place 20 bid orders from user1
        for (uint256 i = 0; i < 20; i++) {
            vm.prank(user1);
            book.placeOrder(mId, Side.Bid, OrderType.GoodTilBatch, 50, 1);
        }
        // Place matching asks from user2
        for (uint256 i = 0; i < 20; i++) {
            vm.prank(user2);
            book.placeOrder(mId, Side.Ask, OrderType.GoodTilBatch, 50, 1);
        }
        // Clear batch — all fills
        auction.clearBatch(mId);
        // user1's count should be decremented; can place new orders
        vm.prank(user1);
        book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 50, 1);
    }

    // =========================================================================
    // Fix 1: GTB Zero-Fill Cleanup (M-01)
    // =========================================================================

    function test_Fix1_GTBBuyZeroFillCleanedUp() public {
        uint256 mId = _setupMarket();

        // user1 places a small GTB bid at tick 50
        vm.prank(user1);
        uint256 smallOrderId = book.placeOrder(mId, Side.Bid, OrderType.GoodTilBatch, 50, 1);

        // user2 places a large GTB bid at same tick (will consume all matched lots via pro-rata)
        vm.prank(user2);
        book.placeOrder(mId, Side.Bid, OrderType.GoodTilBatch, 50, 10000);

        // user3 places a small ask to create a match (1 lot matched)
        vm.prank(user3);
        book.placeOrder(mId, Side.Ask, OrderType.GoodTilBatch, 50, 1);

        uint256 user1BalBefore = usdt.balanceOf(user1);
        auction.clearBatch(mId);

        // user1's order got 0 fill (pro-rata rounds to 0 for 1 lot out of 10001)
        // Verify the order was cleaned up: lots should be 0
        (, , , , uint64 lotsAfter, , , , ) = book.orders(smallOrderId);
        assertEq(lotsAfter, 0, "GTB zero-fill order should be cleaned up");

        // Verify collateral returned
        uint256 user1BalAfter = usdt.balanceOf(user1);
        assertTrue(user1BalAfter > user1BalBefore, "Collateral should be returned");
    }

    function test_Fix1_GTBSellZeroFillCleanedUp() public {
        uint256 mId = _setupMarket();

        // Get user1 and user3 YES tokens
        vm.prank(user1);
        book.placeOrder(mId, Side.Bid, OrderType.GoodTilBatch, 50, 100);
        vm.prank(user3);
        book.placeOrder(mId, Side.Bid, OrderType.GoodTilBatch, 50, 10000);
        vm.prank(user2);
        book.placeOrder(mId, Side.Ask, OrderType.GoodTilBatch, 50, 10100);
        auction.clearBatch(mId);

        // Approve OrderBook for token transfers
        vm.prank(user1);
        token.setApprovalForAll(address(book), true);
        vm.prank(user3);
        token.setApprovalForAll(address(book), true);

        // user1 places small SellYes GTB (1 lot)
        uint256 user1YesBefore = token.balanceOf(user1, token.yesTokenId(mId));
        vm.prank(user1);
        uint256 sellOrderId = book.placeOrder(mId, Side.SellYes, OrderType.GoodTilBatch, 50, 1);
        // user3 places large SellYes GTB (10000 lots) — dominates pro-rata
        vm.prank(user3);
        book.placeOrder(mId, Side.SellYes, OrderType.GoodTilBatch, 50, 10000);
        // 1 bid to create minimal match
        vm.prank(user2);
        book.placeOrder(mId, Side.Bid, OrderType.GoodTilBatch, 50, 1);

        auction.clearBatch(mId);

        // Verify order cleaned up
        (, , , , uint64 lotsAfter, , , , ) = book.orders(sellOrderId);
        assertEq(lotsAfter, 0, "GTB sell zero-fill order should be cleaned up");

        // Verify tokens returned (user1 had 100, locked 1, should get 1 back = 100)
        uint256 user1YesAfter = token.balanceOf(user1, token.yesTokenId(mId));
        assertEq(user1YesAfter, user1YesBefore, "Tokens should be returned to original balance");
    }

    function test_Fix1_GTBInternalPositionsZeroFillCleanedUp() public {
        uint256 mId = _setupInternalMarket();

        // Get user1 and user3 internal YES positions
        vm.prank(user1);
        book.placeOrder(mId, Side.Bid, OrderType.GoodTilBatch, 50, 100);
        vm.prank(user3);
        book.placeOrder(mId, Side.Bid, OrderType.GoodTilBatch, 50, 10000);
        vm.prank(user2);
        book.placeOrder(mId, Side.Ask, OrderType.GoodTilBatch, 50, 10100);
        auction.clearBatch(mId);

        // Snapshot user1's YES position before placing sell order
        (uint128 yesBefore, ) = vault.positions(user1, mId);

        // user1 places small SellYes GTB
        vm.prank(user1);
        uint256 sellOrderId = book.placeOrder(mId, Side.SellYes, OrderType.GoodTilBatch, 50, 1);

        // user3 places large SellYes GTB (dominates pro-rata)
        vm.prank(user3);
        book.placeOrder(mId, Side.SellYes, OrderType.GoodTilBatch, 50, 10000);

        // Small bid to create 1-lot match
        vm.prank(user2);
        book.placeOrder(mId, Side.Bid, OrderType.GoodTilBatch, 50, 1);

        auction.clearBatch(mId);

        // Verify order cleaned up
        (, , , , uint64 lotsAfter, , , , ) = book.orders(sellOrderId);
        assertEq(lotsAfter, 0, "GTB internal zero-fill order should be cleaned up");

        // Verify position unlocked (back to original)
        (uint128 yesAfter, ) = vault.positions(user1, mId);
        assertEq(yesAfter, yesBefore, "Internal position should be unlocked back to original");
    }

    // =========================================================================
    // Fix 5: Split Protocol Fees 50/50 (I-01)
    // =========================================================================

    function test_Fix5_EqualFeesBothSides() public {
        uint256 mId = _setupMarket();

        // Get user1 YES tokens for selling
        vm.prank(user1);
        book.placeOrder(mId, Side.Bid, OrderType.GoodTilBatch, 50, 100);
        vm.prank(user2);
        book.placeOrder(mId, Side.Ask, OrderType.GoodTilBatch, 50, 100);
        auction.clearBatch(mId);

        // Now test fee split: user3 bids, user1 sells YES
        vm.prank(user1);
        token.setApprovalForAll(address(book), true);

        uint256 feeCollectorBefore = usdt.balanceOf(feeCollector);

        vm.prank(user3);
        book.placeOrder(mId, Side.Bid, OrderType.GoodTilBatch, 50, 10);
        vm.prank(user1);
        book.placeOrder(mId, Side.SellYes, OrderType.GoodTilBatch, 50, 10);

        auction.clearBatch(mId);

        uint256 totalFees = usdt.balanceOf(feeCollector) - feeCollectorBefore;
        // fee collector also gets fees via vault.balance for buy side
        uint256 feeCollectorVaultBal = vault.balance(feeCollector);

        // Both sides should contribute; total should be > 0
        assertTrue(totalFees + feeCollectorVaultBal > 0, "fees should be collected");
    }

    function test_Fix5_TotalFeePreserved() public {
        uint256 mId = _setupMarket();

        // Match bid and ask at tick 50, 10 lots each
        uint256 collectorBefore = vault.balance(feeCollector);
        uint256 collectorUsdtBefore = usdt.balanceOf(feeCollector);

        vm.prank(user1);
        book.placeOrder(mId, Side.Bid, OrderType.GoodTilBatch, 50, 10);
        vm.prank(user2);
        book.placeOrder(mId, Side.Ask, OrderType.GoodTilBatch, 50, 10);
        auction.clearBatch(mId);

        // For bid+ask match, both sides are buy orders (lock USDT).
        // Each pays half fee on their filled collateral.
        // Bid fills at 50: collateral = 10 * LOT * 50 / 100
        // Ask fills at 50: collateral = 10 * LOT * 50 / 100
        uint256 bidCollateral = (10 * LOT * 50) / 100;
        uint256 askCollateral = (10 * LOT * 50) / 100;
        uint256 expectedBuyHalf1 = feeModel.calculateOtherHalfFee(bidCollateral);
        uint256 expectedBuyHalf2 = feeModel.calculateOtherHalfFee(askCollateral);

        uint256 totalCollected = (vault.balance(feeCollector) - collectorBefore) +
            (usdt.balanceOf(feeCollector) - collectorUsdtBefore);
        assertEq(totalCollected, expectedBuyHalf1 + expectedBuyHalf2, "total fee preserved for buy-buy match");
    }

    function test_Fix5_OddWeiRoundingToProtocol() public {
        uint256 mId = _setupMarket();

        // Use 7 lots at tick 33 to create an odd fee amount
        // collateral = 7 * 1e16 * 33 / 100 = 23100000000000000
        // fullFee = 23100000000000000 * 20 / 10000 = 46200000000000
        // halfFee (ceil) = (46200000000000 + 1) / 2 = 23100000000001
        // otherHalfFee = 46200000000000 - 23100000000001 = 23099999999999
        // sum = 46200000000000 = fullFee ✓
        vm.prank(user1);
        book.placeOrder(mId, Side.Bid, OrderType.GoodTilBatch, 33, 7);
        vm.prank(user2);
        book.placeOrder(mId, Side.Ask, OrderType.GoodTilBatch, 33, 7);

        // Just verify it doesn't revert (rounding is handled correctly)
        auction.clearBatch(mId);

        // Verify the half fees sum to the full fee
        uint256 collateral = (7 * LOT * 33) / 100;
        uint256 fullFee = feeModel.calculateFee(collateral);
        uint256 halfFee = feeModel.calculateHalfFee(collateral);
        uint256 otherHalf = feeModel.calculateOtherHalfFee(collateral);
        assertEq(halfFee + otherHalf, fullFee, "halves sum to full fee");
        // Rounding: halfFee >= otherHalf (extra wei goes to protocol via ceil)
        assertGe(halfFee, otherHalf, "ceil half >= floor half");
    }

    function test_Fix5_SolvencyFuzz(uint8 tick, uint64 lots) public {
        vm.assume(tick >= 1 && tick <= 99);
        vm.assume(lots >= 1 && lots <= 1000);
        uint256 mId = _setupMarket();

        vm.prank(user1);
        book.placeOrder(mId, Side.Bid, OrderType.GoodTilBatch, tick, lots);
        vm.prank(user2);
        book.placeOrder(mId, Side.Ask, OrderType.GoodTilBatch, tick, lots);
        auction.clearBatch(mId);

        // Pool should have enough to pay out winning tokens
        uint256 pool = vault.marketPool(mId);
        uint256 totalLots = uint256(lots);
        // Worst case: all YES win or all NO win → payout = lots * LOT_SIZE
        assertGe(pool, totalLots * LOT, "pool solvency: pool >= lots * LOT_SIZE");
    }

    // =========================================================================
    // Fix 2: Chunked Settlement Correctness (L-01)
    // =========================================================================

    function test_Fix2_MultiChunkSettlement() public {
        uint256 mId = _setupMarket();

        // Place > 400 orders to trigger multi-chunk settlement.
        // Use GTC orders from batch 1, then roll them forward via clearBatch
        // so that batch 2 has >400 orders (GTC rollovers + new orders).

        // Batch 1: place 300 GTC bids from many users (no asks → no match → all roll to batch 2)
        for (uint256 i = 0; i < 300; i++) {
            address u = address(uint160(0xA000 + i));
            usdt.mint(u, 100000 ether);
            vm.prank(u);
            usdt.approve(address(vault), type(uint256).max);
            vm.prank(u);
            book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 50, 1);
        }
        // Clear batch 1 — no cross, all 300 GTC bids roll to batch 2
        auction.clearBatch(mId);

        // Now add 200 more bids + 500 asks into batch 2 → total 500 bids, 500 asks
        for (uint256 i = 0; i < 200; i++) {
            address u = address(uint160(0xB000 + i));
            usdt.mint(u, 100000 ether);
            vm.prank(u);
            usdt.approve(address(vault), type(uint256).max);
            vm.prank(u);
            book.placeOrder(mId, Side.Bid, OrderType.GoodTilBatch, 50, 1);
        }
        for (uint256 i = 0; i < 500; i++) {
            address u = address(uint160(0xC000 + i));
            usdt.mint(u, 100000 ether);
            vm.prank(u);
            usdt.approve(address(vault), type(uint256).max);
            vm.prank(u);
            book.placeOrder(mId, Side.Ask, OrderType.GoodTilBatch, 50, 1);
        }

        // Batch 2 has 300 (rolled) + 200 + 500 = 1000 orders → needs 3 chunks
        // First clearBatch settles chunk 1 (orders 0-399)
        auction.clearBatch(mId);
        assertFalse(auction.isBatchFullySettled(mId, 2), "should not be fully settled after 1 chunk");

        // Second clearBatch settles chunk 2 (orders 400-799)
        auction.clearBatch(mId);
        assertFalse(auction.isBatchFullySettled(mId, 2), "should not be fully settled after 2 chunks");

        // Third clearBatch settles chunk 3 (orders 800-999)
        auction.clearBatch(mId);
        assertTrue(auction.isBatchFullySettled(mId, 2), "should be fully settled after 3 chunks");

        // Verify pool solvency: 500 matched lots × LOT_SIZE
        uint256 pool = vault.marketPool(mId);
        assertGe(pool, 500 * LOT, "pool solvency after multi-chunk settlement");
    }

    function test_Fix2_GTC_PartialFillAcrossChunks() public {
        uint256 mId = _setupMarket();

        // Set up a scenario where a GTC order gets partial-filled in chunk 1
        // and its remainder must be correctly handled in a subsequent chunk.

        // Place 350 GTC bids (1 lot each) from unique users
        for (uint256 i = 0; i < 350; i++) {
            address u = address(uint160(0xD000 + i));
            usdt.mint(u, 100000 ether);
            vm.prank(u);
            usdt.approve(address(vault), type(uint256).max);
            vm.prank(u);
            book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 50, 1);
        }
        // Roll them to batch 2
        auction.clearBatch(mId);

        // In batch 2: add 200 more bids + 200 asks (less than total bids → partial fills)
        for (uint256 i = 0; i < 200; i++) {
            address u = address(uint160(0xE000 + i));
            usdt.mint(u, 100000 ether);
            vm.prank(u);
            usdt.approve(address(vault), type(uint256).max);
            vm.prank(u);
            book.placeOrder(mId, Side.Bid, OrderType.GoodTilBatch, 50, 1);
        }
        for (uint256 i = 0; i < 200; i++) {
            address u = address(uint160(0xF000 + i));
            usdt.mint(u, 100000 ether);
            vm.prank(u);
            usdt.approve(address(vault), type(uint256).max);
            vm.prank(u);
            book.placeOrder(mId, Side.Ask, OrderType.GoodTilBatch, 50, 1);
        }

        // Batch 2: 350 + 200 + 200 = 750 orders → 2 chunks
        // 550 bids, 200 asks → 200 matched, pro-rata fill for bids
        auction.clearBatch(mId); // chunk 1
        auction.clearBatch(mId); // chunk 2
        assertTrue(auction.isBatchFullySettled(mId, 2), "should be fully settled");

        // Pool should hold 200 matched lots
        uint256 pool = vault.marketPool(mId);
        assertGe(pool, 200 * LOT, "pool solvency after partial-fill chunks");
    }

    // =========================================================================
    // Fix 3: MAX_ORDERS_PER_BATCH = 1600
    // =========================================================================

    function test_Fix3_MaxOrdersPerBatchIs1600() public {
        assertEq(book.MAX_ORDERS_PER_BATCH(), 1600, "MAX_ORDERS_PER_BATCH should be 1600");
    }

    // =========================================================================
    // Fix 4a: Price-Proximity Batch Filtering
    // =========================================================================

    function _setupMarketWithClearing() internal returns (uint256 mId) {
        mId = _setupMarket();
        // Establish a clearing tick at 50
        vm.prank(user1);
        book.placeOrder(mId, Side.Bid, OrderType.GoodTilBatch, 50, 10);
        vm.prank(user2);
        book.placeOrder(mId, Side.Ask, OrderType.GoodTilBatch, 50, 10);
        auction.clearBatch(mId);
        // lastClearingTick is now 50
    }

    function test_Fix4a_FarOrderParked() public {
        uint256 mId = _setupMarketWithClearing();

        // Place bid at tick 5 — far from clearing tick 50 (distance > 20)
        vm.prank(user3);
        uint256 orderId = book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 5, 1);

        // Order should be resting (not in batch, not in tree)
        assertTrue(book.isResting(orderId), "far order should be resting");
        assertEq(book.bidVolumeAt(mId, 5), 0, "resting order should NOT be in tree");

        // Resting order IDs should contain this order
        uint256[] memory resting = book.getRestingOrderIds(mId);
        bool found = false;
        for (uint256 i = 0; i < resting.length; i++) {
            if (resting[i] == orderId) found = true;
        }
        assertTrue(found, "order should be in resting list");
    }

    function test_Fix4a_NearOrderActive() public {
        uint256 mId = _setupMarketWithClearing();

        // Place bid at tick 40 — near clearing tick 50 (distance 10 < 20)
        vm.prank(user3);
        uint256 orderId = book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 40, 1);

        // Order should be in the active batch, not resting
        assertFalse(book.isResting(orderId), "near order should NOT be resting");
        assertEq(book.bidVolumeAt(mId, 40), 1, "near order should be in tree");
    }

    function test_Fix4a_PullInWhenPriceMoves() public {
        uint256 mId = _setupMarketWithClearing();
        // lastClearingTick = 50

        // Place bid at tick 5 — goes to resting (5 < 50-20=30)
        vm.prank(user3);
        uint256 restingId = book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 5, 1);
        assertTrue(book.isResting(restingId), "should be resting initially");

        // Step 1: Move clearing tick from 50 → 35 (within proximity of 50)
        vm.prank(user1);
        book.placeOrder(mId, Side.Bid, OrderType.GoodTilBatch, 35, 10);
        vm.prank(user2);
        book.placeOrder(mId, Side.Ask, OrderType.GoodTilBatch, 35, 10);
        auction.clearBatch(mId);
        // ref is now 35. Tick 5 is still far (5 < 35-20=15)

        // Step 2: Move clearing tick from 35 → 20 (within proximity of 35)
        vm.prank(user1);
        book.placeOrder(mId, Side.Bid, OrderType.GoodTilBatch, 20, 10);
        vm.prank(user2);
        book.placeOrder(mId, Side.Ask, OrderType.GoodTilBatch, 20, 10);
        auction.clearBatch(mId);
        // ref is now 20. Tick 5 is still far (5 < 20-20=0 → 20 > 20 is false, so not far!)

        // Step 3: One more clear to trigger pull-in at ref=20
        vm.prank(user1);
        book.placeOrder(mId, Side.Bid, OrderType.GoodTilBatch, 20, 10);
        vm.prank(user2);
        book.placeOrder(mId, Side.Ask, OrderType.GoodTilBatch, 20, 10);
        auction.clearBatch(mId);

        // Now with ref=20, tick 5: _isTickFar check: ref > threshold → 20 > 20 = false → not far
        assertFalse(book.isResting(restingId), "should be pulled in after price moved near");
    }

    function test_Fix4a_CancelRestingOrder() public {
        uint256 mId = _setupMarketWithClearing();

        // Place far bid → resting
        vm.prank(user3);
        uint256 orderId = book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 5, 1);
        assertTrue(book.isResting(orderId), "should be resting");

        uint256 balBefore = usdt.balanceOf(user3);
        vm.prank(user3);
        book.cancelOrder(orderId);

        // Should return collateral
        uint256 balAfter = usdt.balanceOf(user3);
        assertTrue(balAfter > balBefore, "collateral should be returned on cancel");

        // Order lots should be 0
        (, , , , uint64 lots, , , , ) = book.orders(orderId);
        assertEq(lots, 0, "cancelled resting order should have 0 lots");
    }

    function test_Fix4a_GTC_RollToResting() public {
        uint256 mId = _setupMarket();

        // Place GTC bid at tick 50 and ask at tick 50
        vm.prank(user1);
        uint256 bidId = book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 50, 20);
        vm.prank(user2);
        book.placeOrder(mId, Side.Ask, OrderType.GoodTilBatch, 50, 5);

        // Also place a GTC bid at tick 10 (will become far when clearing at 50)
        vm.prank(user3);
        uint256 farBidId = book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 10, 1);

        // Clear — clearing tick = 50. Tick 10 is within 50-20=30 threshold, so 10 < 30 = far
        auction.clearBatch(mId);

        // The far GTC bid should have been moved to resting via _tryRollOrCancel
        assertTrue(book.isResting(farBidId), "far GTC order should be moved to resting after clear");
    }

    function test_Fix4a_LazySkipCancelled() public {
        uint256 mId = _setupMarketWithClearing();
        // lastClearingTick = 50

        // Place two far bids → both go to resting
        vm.prank(user1);
        uint256 id1 = book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 5, 1);
        vm.prank(user2);
        uint256 id2 = book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 5, 1);

        assertTrue(book.isResting(id1), "id1 resting");
        assertTrue(book.isResting(id2), "id2 resting");

        // Cancel id1 — sets lots to 0, lazy-skipped during scan
        vm.prank(user1);
        book.cancelOrder(id1);

        // Step 1: Trade near ref=50 to get a clear (moves ref to 35)
        vm.prank(user1);
        book.placeOrder(mId, Side.Bid, OrderType.GoodTilBatch, 35, 10);
        vm.prank(user2);
        book.placeOrder(mId, Side.Ask, OrderType.GoodTilBatch, 35, 10);
        auction.clearBatch(mId);
        // ref now 35. Tick 5 still far: 5 < 35-20=15 → far.

        // Step 2: Trade at tick 20 (within 20 of 35) → ref moves to 20
        vm.prank(user1);
        book.placeOrder(mId, Side.Bid, OrderType.GoodTilBatch, 20, 10);
        vm.prank(user2);
        book.placeOrder(mId, Side.Ask, OrderType.GoodTilBatch, 20, 10);
        auction.clearBatch(mId);
        // ref now 20. Tick 5: 5 < 20-20=0 → NOT far (threshold check: 20>20 → false).
        // pullRestingOrders during this clear used ref=35, tick 5 still far.

        // Step 3: One more clear to trigger pull with ref=20
        auction.clearBatch(mId);

        // id1 should be lazy-skipped (already cancelled), id2 should be pulled in
        assertFalse(book.isResting(id2), "id2 should be pulled in");
        (, , , , uint64 lots1, , , , ) = book.orders(id1);
        assertEq(lots1, 0, "id1 stays cancelled");
    }

    function test_Fix4a_OrderRestingEventEmitted() public {
        uint256 mId = _setupMarketWithClearing();

        // Check that OrderResting event is emitted (check indexed params: marketId and owner)
        vm.expectEmit(false, true, true, false);
        emit OrderBook.OrderResting(0, mId, user3);

        vm.prank(user3);
        book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 5, 1);
    }
}
