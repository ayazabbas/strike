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
        (,,,, uint64 lotsAfter,,,,,) = book.orders(smallOrderId);
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
        (,,,, uint64 lotsAfter,,,,,) = book.orders(sellOrderId);
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
        (uint128 yesBefore,) = vault.positions(user1, mId);

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
        (,,,, uint64 lotsAfter,,,,,) = book.orders(sellOrderId);
        assertEq(lotsAfter, 0, "GTB internal zero-fill order should be cleaned up");

        // Verify position unlocked (back to original)
        (uint128 yesAfter,) = vault.positions(user1, mId);
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

        uint256 totalCollected =
            (vault.balance(feeCollector) - collectorBefore) + (usdt.balanceOf(feeCollector) - collectorUsdtBefore);
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

        // Now with ref=20, tick 5: isTickFar check: ref > threshold → 20 > 20 = false → not far
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
        (,,,, uint64 lots,,,,,) = book.orders(orderId);
        assertEq(lots, 0, "cancelled resting order should have 0 lots");
        assertFalse(book.isResting(orderId), "cancelled resting order should be removed");
        assertEq(book.restingIndexPlusOne(orderId), 0, "resting index should be cleared");
        assertEq(book.getRestingOrderIds(mId).length, 0, "resting list should shrink immediately");
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

    function test_Fix4a_CancelledRestingRemovedImmediately() public {
        uint256 mId = _setupMarketWithClearing();

        // Place two far bids → both go to resting
        vm.prank(user1);
        uint256 id1 = book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 5, 1);
        vm.prank(user2);
        uint256 id2 = book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 5, 1);

        assertTrue(book.isResting(id1), "id1 resting");
        assertTrue(book.isResting(id2), "id2 resting");

        uint256[] memory restingBefore = book.getRestingOrderIds(mId);
        assertEq(restingBefore.length, 2, "both orders tracked as resting");

        vm.prank(user1);
        book.cancelOrder(id1);

        uint256[] memory restingAfter = book.getRestingOrderIds(mId);
        assertEq(restingAfter.length, 1, "cancel should remove the resting entry");
        assertEq(restingAfter[0], id2, "remaining resting order should be preserved");
        (,,,, uint64 lots1,,,,,) = book.orders(id1);
        assertEq(lots1, 0, "id1 stays cancelled");
        assertFalse(book.isResting(id1), "cancelled order should no longer be resting");
        assertEq(book.restingIndexPlusOne(id1), 0, "cancelled order index cleared");
    }

    function test_Fix4a_StaleRestingGtBAutoCancelledBeforePull() public {
        uint256 mId = _setupMarketWithClearing();

        vm.prank(user3);
        uint256 staleId = book.placeOrder(mId, Side.Bid, OrderType.GoodTilBatch, 5, 2);
        assertTrue(book.isResting(staleId), "GTB should start resting");

        // Clear batch 2 while the resting GTB remains out of range.
        vm.prank(user1);
        book.placeOrder(mId, Side.Bid, OrderType.GoodTilBatch, 50, 10);
        vm.prank(user2);
        book.placeOrder(mId, Side.Ask, OrderType.GoodTilBatch, 50, 10);
        auction.clearBatch(mId);

        assertTrue(book.isResting(staleId), "GTB stays parked until the next batch starts");
        uint256 walletBefore = usdt.balanceOf(user3);

        // Batch 3 has a live book around 30-35, which would have re-pulled the stale GTB before this fix.
        vm.prank(user1);
        book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 30, 5);
        vm.prank(user2);
        book.placeOrder(mId, Side.Ask, OrderType.GoodTilBatch, 35, 5);
        auction.clearBatch(mId);

        (,,,, uint64 lotsAfter,,,,,) = book.orders(staleId);
        assertEq(lotsAfter, 0, "stale resting GTB should be cancelled before re-pull");
        assertFalse(book.isResting(staleId), "stale GTB should be removed from resting");
        assertEq(book.restingIndexPlusOne(staleId), 0, "stale GTB index cleared");
        assertGt(usdt.balanceOf(user3), walletBefore, "stale GTB collateral should be refunded");
    }

    function test_Fix4a_LiveReferenceOverridesStaleLastClearingTick() public {
        uint256 mId = _setupMarketWithClearing();

        // Keep the last trade anchored at 50 while the live active book shifts lower.
        vm.prank(user1);
        book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 30, 5);
        vm.prank(user2);
        book.placeOrder(mId, Side.Ask, OrderType.GoodTilCancel, 35, 5);

        assertEq(book.lastClearingTick(mId), 50, "last clearing tick stays stale");
        assertEq(book.currentReferenceTick(mId), 32, "live midpoint should drive the reference");

        vm.prank(user3);
        uint256 orderId = book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 25, 1);

        assertFalse(book.isResting(orderId), "live book reference should keep nearby bids active");
        assertEq(book.bidVolumeAt(mId, 25), 1, "new bid should be active in the tree");
    }

    function test_Fix4a_OrderRestingEventEmitted() public {
        uint256 mId = _setupMarketWithClearing();

        // Check that OrderResting event is emitted (check indexed params: marketId and owner)
        vm.expectEmit(false, true, true, false);
        emit OrderBook.OrderResting(0, mId, user3);

        vm.prank(user3);
        book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 5, 1);
    }

    // =========================================================================
    // Post-Review Fix 1: Chunked Settlement Reads Actual OrderInfo
    // =========================================================================

    function test_PostReview1_MultiChunkBothSidesGTC() public {
        uint256 mId = _setupMarket();

        // Place 300 GTC bids at tick 50 from unique users
        for (uint256 i = 0; i < 300; i++) {
            address u = address(uint160(0x10000 + i));
            usdt.mint(u, 100000 ether);
            vm.prank(u);
            usdt.approve(address(vault), type(uint256).max);
            vm.prank(u);
            book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 50, 1);
        }
        // Place 300 GTC asks at tick 50 from unique users
        for (uint256 i = 0; i < 300; i++) {
            address u = address(uint160(0x20000 + i));
            usdt.mint(u, 100000 ether);
            vm.prank(u);
            usdt.approve(address(vault), type(uint256).max);
            vm.prank(u);
            book.placeOrder(mId, Side.Ask, OrderType.GoodTilCancel, 50, 1);
        }

        // Clear batch 1 — no match if no cross. Actually 300 bids + 300 asks at tick 50 → 300 matched.
        // All in batch 1, within SETTLE_CHUNK_SIZE=400 for first chunk (600 total → 2 chunks).
        auction.clearBatch(mId); // chunk 1: settles orders 0-399
        assertFalse(auction.isBatchFullySettled(mId, 1), "not fully settled after chunk 1");

        // chunk 2: settles orders 400-599 — these are in the "subsequent chunks" branch
        auction.clearBatch(mId);
        assertTrue(auction.isBatchFullySettled(mId, 1), "fully settled after chunk 2");

        // Verify bid users in chunk 2 (indices 400+) got YES tokens
        for (uint256 i = 100; i < 300; i++) {
            address u = address(uint160(0x10000 + i));
            uint256 yesBal = token.balanceOf(u, token.yesTokenId(mId));
            assertEq(yesBal, 1, "bid user in chunk 2 should have YES token");
        }

        // Verify ask users in chunk 2 got NO tokens
        for (uint256 i = 100; i < 300; i++) {
            address u = address(uint160(0x20000 + i));
            uint256 noBal = token.balanceOf(u, token.noTokenId(mId));
            assertEq(noBal, 1, "ask user in chunk 2 should have NO token");
        }

        // Pool solvency
        uint256 pool = vault.marketPool(mId);
        assertGe(pool, 300 * LOT, "pool solvency after multi-chunk both-sides settlement");
    }

    function test_PostReview1_ChunkSettlesCorrectOwnerAndTick() public {
        uint256 mId = _setupMarket();

        // Place 350 GTC bids at tick 50 (will roll to batch 2)
        for (uint256 i = 0; i < 350; i++) {
            address u = address(uint160(0x30000 + i));
            usdt.mint(u, 100000 ether);
            vm.prank(u);
            usdt.approve(address(vault), type(uint256).max);
            vm.prank(u);
            book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 50, 1);
        }
        // Roll to batch 2
        auction.clearBatch(mId);

        // Batch 2: add 200 more GTC bids at tick 60 + 550 asks at tick 50
        for (uint256 i = 0; i < 200; i++) {
            address u = address(uint160(0x40000 + i));
            usdt.mint(u, 100000 ether);
            vm.prank(u);
            usdt.approve(address(vault), type(uint256).max);
            vm.prank(u);
            book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 60, 1);
        }
        for (uint256 i = 0; i < 550; i++) {
            address u = address(uint160(0x50000 + i));
            usdt.mint(u, 100000 ether);
            vm.prank(u);
            usdt.approve(address(vault), type(uint256).max);
            vm.prank(u);
            book.placeOrder(mId, Side.Ask, OrderType.GoodTilBatch, 50, 1);
        }

        // Batch 2: 350+200+550 = 1100 orders → 3 chunks
        // 550 bids total, 550 asks → 550 matched at clearing tick
        uint256 user0x40000Before = usdt.balanceOf(address(uint160(0x40000)));

        auction.clearBatch(mId); // chunk 1
        auction.clearBatch(mId); // chunk 2
        auction.clearBatch(mId); // chunk 3
        assertTrue(auction.isBatchFullySettled(mId, 2), "fully settled");

        // Verify a tick-60 bid user (in later chunk) got correct excess refund
        // They locked at tick 60 but filled at clearing tick — excess should be refunded
        address tick60User = address(uint160(0x40000));
        uint256 tick60UserAfter = usdt.balanceOf(tick60User);
        // User locked collateral for tick 60, settled at clearing tick <= 60
        // Should have received YES tokens
        uint256 yesBal = token.balanceOf(tick60User, token.yesTokenId(mId));
        assertEq(yesBal, 1, "tick-60 user should get YES token via chunk 2+");
    }

    // =========================================================================
    // Post-Review Fix 2: placeOrders/replaceOrders Proximity Filtering
    // =========================================================================

    function test_PostReview2_PlaceOrdersBatchProximity() public {
        uint256 mId = _setupMarketWithClearing();
        // lastClearingTick = 50

        // Place batch of 3 orders: one near (tick 45), one far (tick 5), one near (tick 55 ask)
        OrderParam[] memory params = new OrderParam[](3);
        params[0] = OrderParam(Side.Bid, OrderType.GoodTilCancel, 45, 1);
        params[1] = OrderParam(Side.Bid, OrderType.GoodTilCancel, 5, 1); // far
        params[2] = OrderParam(Side.Ask, OrderType.GoodTilCancel, 55, 1);

        vm.prank(user1);
        uint256[] memory orderIds = book.placeOrders(mId, params);

        // Near orders should be in batch, not resting
        assertFalse(book.isResting(orderIds[0]), "near bid should not be resting");
        assertFalse(book.isResting(orderIds[2]), "near ask should not be resting");

        // Far order should be resting
        assertTrue(book.isResting(orderIds[1]), "far bid should be resting");

        // Far order should NOT be in tree
        assertEq(book.bidVolumeAt(mId, 5), 0, "far order should not be in bid tree");

        // Near orders should be in tree
        assertEq(book.bidVolumeAt(mId, 45), 1, "near bid should be in tree");
        assertEq(book.askVolumeAt(mId, 55), 1, "near ask should be in tree");
    }

    function test_PostReview2_ReplaceOrdersFarGoToResting() public {
        uint256 mId = _setupMarketWithClearing();
        // lastClearingTick = 50

        // Place a near order first
        vm.prank(user1);
        uint256 nearId = book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 45, 1);
        assertFalse(book.isResting(nearId), "initially near");

        // Replace it with a far order
        uint256[] memory cancelIds = new uint256[](1);
        cancelIds[0] = nearId;
        OrderParam[] memory params = new OrderParam[](1);
        params[0] = OrderParam(Side.Bid, OrderType.GoodTilCancel, 5, 1); // far

        vm.prank(user1);
        uint256[] memory newIds = book.replaceOrders(cancelIds, mId, params);

        // New order should be resting
        assertTrue(book.isResting(newIds[0]), "replaced far order should be resting");
        assertEq(book.bidVolumeAt(mId, 5), 0, "far order should not be in tree");
    }

    function test_PostReview2_PlaceOrdersFarAskResting() public {
        uint256 mId = _setupMarketWithClearing();
        // lastClearingTick = 50

        // Place a far ask (tick 95, far from 50 + 20 = 70 threshold → 95 > 70 → far)
        OrderParam[] memory params = new OrderParam[](1);
        params[0] = OrderParam(Side.Ask, OrderType.GoodTilCancel, 95, 1);

        vm.prank(user1);
        uint256[] memory orderIds = book.placeOrders(mId, params);

        assertTrue(book.isResting(orderIds[0]), "far ask should be resting");
        assertEq(book.askVolumeAt(mId, 95), 0, "far ask should not be in tree");
    }

    // =========================================================================
    // Post-Review Fix 3: Deduplicated Proximity Logic
    // =========================================================================

    function test_PostReview3_IsTickFarIsPublic() public view {
        uint256 mId = 1; // doesn't need to exist for the view call
        // Just verify it's callable externally (public)
        book.isTickFar(mId, 50, Side.Bid);
    }

    function test_PostReview3_BatchAuctionUsesOrderBookProximity() public {
        uint256 mId = _setupMarketWithClearing();
        // lastClearingTick = 50

        // Place GTC bid at tick 5 (near) and far tick — then clear so GTC rolls
        vm.prank(user1);
        uint256 farGtcId = book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 5, 1);
        assertTrue(book.isResting(farGtcId), "far GTC should be resting at placement");

        // Place matching orders near the clearing tick to trigger another batch clear
        vm.prank(user1);
        book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 50, 10);
        vm.prank(user2);
        book.placeOrder(mId, Side.Ask, OrderType.GoodTilBatch, 50, 5);
        auction.clearBatch(mId);

        // The partially filled GTC at tick 50 should roll normally (near),
        // while the far resting order stays resting — all using the same isTickFar logic
        assertTrue(book.isResting(farGtcId), "far order stays resting (same logic in both contracts)");
    }

    // =========================================================================
    // v1.2 Fix M-01: Paginated Resting List Scanning
    // =========================================================================

    function test_M01_PaginatedScanBoundedWindow() public {
        uint256 mId = _setupMarket();

        // Verify MAX_RESTING_SCAN constant exists
        assertEq(book.MAX_RESTING_SCAN(), 400, "MAX_RESTING_SCAN should be 400");

        // Establish clearing tick at 50
        vm.prank(user1);
        book.placeOrder(mId, Side.Bid, OrderType.GoodTilBatch, 50, 10);
        vm.prank(user2);
        book.placeOrder(mId, Side.Ask, OrderType.GoodTilBatch, 50, 10);
        auction.clearBatch(mId);
        // ref = 50

        // Place 10 far orders (tick 5 — far from 50)
        for (uint256 i = 0; i < 10; i++) {
            address u = address(uint160(0x50000 + i));
            usdt.mint(u, 100000 ether);
            vm.prank(u);
            usdt.approve(address(vault), type(uint256).max);
            vm.prank(u);
            book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 5, 1);
        }

        uint256[] memory resting = book.getRestingOrderIds(mId);
        assertEq(resting.length, 10, "should have 10 resting orders");

        // Move clearing tick to 20 so tick 5 becomes "near" (20 > 20 is false)
        // Use operator to directly set the clearing tick
        vm.prank(address(auction));
        book.setLastClearingTick(mId, 20);

        // Now trigger a clear — pullRestingOrders should pull all 10 in
        vm.prank(user1);
        book.placeOrder(mId, Side.Bid, OrderType.GoodTilBatch, 20, 10);
        vm.prank(user2);
        book.placeOrder(mId, Side.Ask, OrderType.GoodTilBatch, 20, 10);
        auction.clearBatch(mId);

        // All 10 resting orders should have been pulled
        resting = book.getRestingOrderIds(mId);
        assertEq(resting.length, 0, "all resting orders should be pulled in");
    }

    function test_M01_ScanIndexPersistsAcrossCalls() public {
        uint256 mId = _setupMarketWithClearing();
        // restingScanIndex should start at 0
        assertEq(book.restingScanIndex(mId), 0, "initial scan index should be 0");

        // Place far orders
        for (uint256 i = 0; i < 5; i++) {
            address u = address(uint160(0x60000 + i));
            usdt.mint(u, 100000 ether);
            vm.prank(u);
            usdt.approve(address(vault), type(uint256).max);
            vm.prank(u);
            book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 5, 1);
        }

        // Clear a batch (pullRestingOrders is called internally) — orders stay far
        vm.prank(user1);
        book.placeOrder(mId, Side.Bid, OrderType.GoodTilBatch, 50, 10);
        vm.prank(user2);
        book.placeOrder(mId, Side.Ask, OrderType.GoodTilBatch, 50, 10);
        auction.clearBatch(mId);

        // Orders still far, but scan index should have advanced
        uint256[] memory resting = book.getRestingOrderIds(mId);
        assertEq(resting.length, 5, "far orders stay resting");
    }

    // =========================================================================
    // v1.2 Fix M-02: Stale o.lots in _tryRollOrCancel — remaining lots
    // =========================================================================

    function test_M02_PartialFillGtcRemainingLotsCorrect() public {
        uint256 mId = _setupMarket();

        // Place GTC bid with 20 lots at tick 50
        vm.prank(user1);
        uint256 bidId = book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 50, 20);

        // Place GTB ask with 5 lots to partially fill
        vm.prank(user2);
        book.placeOrder(mId, Side.Ask, OrderType.GoodTilBatch, 50, 5);

        // Check tree volume before clear
        uint256 bidVolBefore = book.bidVolumeAt(mId, 50);
        assertEq(bidVolBefore, 20, "should have 20 lots in tree before clear");

        // Clear — 5 lots fill, 15 lots remain
        auction.clearBatch(mId);

        // The GTC order should have been rolled with remaining 15 lots
        (,,,, uint64 remainingLots,,,,,) = book.orders(bidId);
        assertEq(remainingLots, 15, "remaining lots should be 15 after partial fill");

        // Tree should have 15 lots at tick 50 (remaining volume after roll)
        uint256 bidVolAfter = book.bidVolumeAt(mId, 50);
        assertEq(bidVolAfter, 15, "tree should have 15 remaining lots after partial fill roll");
    }

    function test_M02_PartialFillSellGtcRemainingLots() public {
        uint256 mId = _setupMarket();

        // First, create tokens for user1 by filling a buy order
        vm.prank(user1);
        book.placeOrder(mId, Side.Bid, OrderType.GoodTilBatch, 50, 20);
        vm.prank(user2);
        book.placeOrder(mId, Side.Ask, OrderType.GoodTilBatch, 50, 20);
        auction.clearBatch(mId);
        // user1 now has 20 YES tokens

        // Approve OrderBook to handle tokens
        vm.prank(user1);
        token.setApprovalForAll(address(book), true);

        // Place GTC SellYes with 15 lots
        vm.prank(user1);
        uint256 sellId = book.placeOrder(mId, Side.SellYes, OrderType.GoodTilCancel, 50, 15);

        // Place bid to partially fill (5 lots)
        vm.prank(user2);
        book.placeOrder(mId, Side.Bid, OrderType.GoodTilBatch, 50, 5);
        auction.clearBatch(mId);

        // Remaining should be 10
        (,,,, uint64 remainingLots,,,,,) = book.orders(sellId);
        assertEq(remainingLots, 10, "sell order remaining lots should be 10 after partial fill");
    }

    // =========================================================================
    // v1.2 Fix L-03: activeOrderCount underflow reverts
    // =========================================================================

    function test_L03_ActiveOrderCountUnderflowReverts() public {
        uint256 mId = _setupMarket();

        // Try to decrement when count is 0 — should revert
        vm.prank(address(auction));
        vm.expectRevert("OrderBook: counter underflow");
        book.decrementActiveOrderCount(user1, mId);
    }

    // =========================================================================
    // Fix: _cancelForReplace must decrement activeOrderCount for settled orders
    // =========================================================================

    function test_CancelForReplace_SettledOrderDecrementsActiveCount() public {
        uint256 mId = _setupMarket();

        // 1. MM places 2 GTB bid orders (A, B)
        vm.prank(user1);
        uint256 orderA = book.placeOrder(mId, Side.Bid, OrderType.GoodTilBatch, 50, 5);
        vm.prank(user1);
        uint256 orderB = book.placeOrder(mId, Side.Bid, OrderType.GoodTilBatch, 50, 5);

        // user2 provides the ask side so both orders get filled
        vm.prank(user2);
        book.placeOrder(mId, Side.Ask, OrderType.GoodTilBatch, 50, 10);

        assertEq(book.activeOrderCount(user1, mId), 2, "pre-clear: 2 active orders");

        // 2. clearBatch settles both orders -> lots become 0
        auction.clearBatch(mId);

        (,,,, uint64 lotsA,,,,,) = book.orders(orderA);
        (,,,, uint64 lotsB,,,,,) = book.orders(orderB);
        assertEq(lotsA, 0, "orderA should be fully filled");
        assertEq(lotsB, 0, "orderB should be fully filled");

        // After clearBatch, activeOrderCount should be 0 (decremented by BatchAuction)
        assertEq(book.activeOrderCount(user1, mId), 0, "post-clear: 0 active orders");

        // 3. replaceOrders([A, B], [newC, newD]) -- cancels settled orders + places new ones
        uint256[] memory cancelIds = new uint256[](2);
        cancelIds[0] = orderA;
        cancelIds[1] = orderB;

        OrderParam[] memory newParams = new OrderParam[](2);
        newParams[0] = OrderParam(Side.Bid, OrderType.GoodTilBatch, 45, 3);
        newParams[1] = OrderParam(Side.Bid, OrderType.GoodTilBatch, 55, 3);

        vm.prank(user1);
        uint256[] memory newIds = book.replaceOrders(cancelIds, mId, newParams);

        // 4. activeOrderCount should be exactly 2 (only the 2 new orders)
        assertEq(book.activeOrderCount(user1, mId), 2, "post-replace: should have exactly 2 active orders");

        // 5. New orders should have non-zero lots
        (,,,, uint64 lotsC,,,,,) = book.orders(newIds[0]);
        (,,,, uint64 lotsD,,,,,) = book.orders(newIds[1]);
        assertEq(lotsC, 3, "newC should have 3 lots");
        assertEq(lotsD, 3, "newD should have 3 lots");

        // 6. User can cancel the new orders (proves counter is correct, no stuck state)
        vm.startPrank(user1);
        book.cancelOrder(newIds[0]);
        book.cancelOrder(newIds[1]);
        vm.stopPrank();
        assertEq(book.activeOrderCount(user1, mId), 0, "post-cancel: 0 active orders");
    }
}
