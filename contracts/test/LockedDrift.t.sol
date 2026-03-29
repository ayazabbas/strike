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

/// @notice Tests that vault.locked returns to 0 after full settlement lifecycle.
///         Demonstrates the locked drift bug when feeBps changes between
///         order placement and settlement.
contract LockedDriftTest is Test {
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

    uint256 public constant LOT = 1e16;

    function setUp() public {
        usdt = new MockUSDT();

        vm.startPrank(admin);
        vault = new Vault(admin, address(usdt));
        feeModel = new FeeModel(admin, 20, admin);
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

        for (uint256 i = 0; i < 2; i++) {
            address u = [user1, user2][i];
            usdt.mint(u, 1_000_000 ether);
            vm.prank(u);
            usdt.approve(address(vault), type(uint256).max);
        }
    }

    function _setupMarket() internal returns (uint256) {
        vm.prank(operator);
        return book.registerMarket(1, 3, block.timestamp + 3600, false);
    }

    // =========================================================================
    // Sanity: locked == 0 after full fill (no feeBps change)
    // =========================================================================

    function test_LockedReturnsToZero_FullFill_SameTick() public {
        uint256 mId = _setupMarket();

        vm.prank(user1);
        book.placeOrder(mId, Side.Bid, OrderType.GoodTilBatch, 50, 10);
        vm.prank(user2);
        book.placeOrder(mId, Side.Ask, OrderType.GoodTilBatch, 50, 10);

        assertGt(vault.locked(user1), 0, "should be locked after placement");

        auction.clearBatch(mId);

        assertEq(vault.locked(user1), 0, "locked should be 0 after full fill");
        assertEq(vault.locked(user2), 0, "locked should be 0 after full fill");
    }

    function test_LockedReturnsToZero_FullFill_DiffTick() public {
        uint256 mId = _setupMarket();

        vm.prank(user1);
        book.placeOrder(mId, Side.Bid, OrderType.GoodTilBatch, 70, 10);
        vm.prank(user2);
        book.placeOrder(mId, Side.Ask, OrderType.GoodTilBatch, 30, 10);

        auction.clearBatch(mId);

        assertEq(vault.locked(user1), 0, "bid locked should be 0");
        assertEq(vault.locked(user2), 0, "ask locked should be 0");
    }

    // =========================================================================
    // GTC partial fill + rollover + second fill
    // =========================================================================

    function test_LockedReturnsToZero_GTC_PartialFill() public {
        uint256 mId = _setupMarket();

        // Bid 20 lots GTC, Ask 5 lots GTB → partial fill
        vm.prank(user1);
        book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 50, 20);
        vm.prank(user2);
        book.placeOrder(mId, Side.Ask, OrderType.GoodTilBatch, 50, 5);

        uint256 lockedBefore = vault.locked(user1);

        auction.clearBatch(mId);

        // user1 should still have some locked (15 lots remaining)
        assertGt(vault.locked(user1), 0, "should still have locked for remaining GTC");
        assertLt(vault.locked(user1), lockedBefore, "locked should have decreased");
        assertEq(vault.locked(user2), 0, "ask locked should be 0");

        // Fill the rest
        vm.prank(user2);
        book.placeOrder(mId, Side.Ask, OrderType.GoodTilBatch, 50, 15);
        auction.clearBatch(mId);

        assertEq(vault.locked(user1), 0, "locked should be 0 after all lots filled");
    }

    // =========================================================================
    // THE BUG: feeBps changes between placement and settlement
    // =========================================================================

    function test_LockedDrift_FeeBpsChange() public {
        uint256 mId = _setupMarket();

        // Place orders at feeBps = 20
        vm.prank(user1);
        book.placeOrder(mId, Side.Bid, OrderType.GoodTilBatch, 50, 100);
        vm.prank(user2);
        book.placeOrder(mId, Side.Ask, OrderType.GoodTilBatch, 50, 100);

        uint256 user1LockedBefore = vault.locked(user1);
        assertGt(user1LockedBefore, 0);

        // Admin changes feeBps from 20 to 10
        vm.prank(admin);
        feeModel.setFeeBps(10);

        // Clear batch — settlement uses NEW feeBps to compute lockedFeeForFilled
        auction.clearBatch(mId);

        // THE BUG: locked should be 0 but it's not because settlement
        // computed a smaller fee than what was actually locked
        uint256 drift = vault.locked(user1);

        // With feeBps 20→10, the fee difference per user:
        // collateral = 100 * 50 * 1e14 = 5e17
        // oldFee = 5e17 * 20/10000 = 1e15
        // newFee = 5e17 * 10/10000 = 5e14
        // drift = oldFee - newFee = 5e14 (locked but never unlocked)
        //
        // But the actual drift also depends on the otherHalfFee calculation.
        // oldFullFee = 1e15, oldHalfFee = 5e14, oldOtherHalf = 5e14
        // newFullFee = 5e14, newHalfFee = 2.5e14, newOtherHalf = 2.5e14
        //
        // lockedFeeForFilled (using new rate) = 5e14
        // totalDeduct = toPool + protocolFee + excessRefund
        //   = filledCollateral + newOtherHalf + (collateral + newFullFee - filledCollateral - newOtherHalf)
        //   = collateral + newFullFee
        //   = 5e17 + 5e14
        //
        // originalLock = collateral + oldFullFee = 5e17 + 1e15
        // drift = originalLock - totalDeduct = 1e15 - 5e14 = 5e14

        // FIX: stored feeBps at order placement means drift == 0
        assertEq(drift, 0, "FIXED: no drift when feeBps changes");
    }

    // =========================================================================
    // Drift accumulates over many markets
    // =========================================================================

    function test_LockedDrift_AccumulatesOverMarkets() public {
        // Place orders at feeBps = 20
        uint256 totalDrift;
        for (uint256 i = 0; i < 10; i++) {
            uint256 mId = _setupMarket();
            vm.prank(user1);
            book.placeOrder(mId, Side.Bid, OrderType.GoodTilBatch, 50, 100);
            vm.prank(user2);
            book.placeOrder(mId, Side.Ask, OrderType.GoodTilBatch, 50, 100);
        }

        // Change fee
        vm.prank(admin);
        feeModel.setFeeBps(10);

        // Clear all batches
        uint256 nextMarketId = book.nextMarketId();
        for (uint256 mId = 1; mId < nextMarketId; mId++) {
            auction.clearBatch(mId);
        }

        totalDrift = vault.locked(user1);
        // FIX: stored feeBps means no drift even across many markets
        assertEq(totalDrift, 0, "FIXED: no drift across markets");
    }

    // =========================================================================
    // GTC partial fill with feeBps change should also drift
    // =========================================================================

    function test_LockedDrift_GTC_PartialFill_FeeBpsChange() public {
        uint256 mId = _setupMarket();

        // Place at feeBps = 20
        vm.prank(user1);
        book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 60, 20);
        vm.prank(user2);
        book.placeOrder(mId, Side.Ask, OrderType.GoodTilBatch, 50, 10);

        // Change fee to 10 bps
        vm.prank(admin);
        feeModel.setFeeBps(10);

        // First batch: partial fill (10 of 20 lots)
        auction.clearBatch(mId);

        // Change fee back to 20 bps
        vm.prank(admin);
        feeModel.setFeeBps(20);

        // Fill the rest
        vm.prank(user2);
        book.placeOrder(mId, Side.Ask, OrderType.GoodTilBatch, 50, 10);
        auction.clearBatch(mId);

        // FIX: stored feeBps at placement means each settlement uses the correct fee
        uint256 drift = vault.locked(user1);
        assertEq(drift, 0, "FIXED: no drift with GTC partial fills and feeBps changes");
    }

    // =========================================================================
    // replaceOrders with feeBps change
    // =========================================================================

    function test_LockedDrift_ReplaceOrders_FeeBpsChange() public {
        uint256 mId = _setupMarket();

        // Place at feeBps = 20
        vm.prank(user1);
        uint256 orderId = book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 50, 100);

        uint256 lockedBefore = vault.locked(user1);

        // Change fee to 10 bps
        vm.prank(admin);
        feeModel.setFeeBps(10);

        // Replace the order — _cancelForReplace computes refund with NEW feeBps
        uint256[] memory cancelIds = new uint256[](1);
        cancelIds[0] = orderId;
        OrderParam[] memory newParams = new OrderParam[](1);
        newParams[0] = OrderParam(Side.Bid, OrderType.GoodTilCancel, 50, 100);

        vm.prank(user1);
        book.replaceOrders(cancelIds, mId, newParams);

        uint256 lockedAfter = vault.locked(user1);

        // FIX: _cancelForReplace now uses stored feeBps, so the refund matches
        // the original lock exactly. The new order locks with the CURRENT feeBps.
        // No phantom locked.
        uint256 collateral = (100 * LOT * 50) / 100;
        uint256 expectedLock = collateral + feeModel.calculateFee(collateral); // with new feeBps
        assertEq(lockedAfter, expectedLock, "FIXED: locked matches new order deposit exactly");
    }

    // =========================================================================
    // Full lifecycle: place → fill → verify locked == 0 (all order types)
    // =========================================================================

    function test_LockedZero_FullLifecycle_BidAsk() public {
        uint256 mId = _setupMarket();

        // Place matching bid and ask orders at different ticks
        vm.prank(user1);
        book.placeOrder(mId, Side.Bid, OrderType.GoodTilBatch, 60, 50);
        vm.prank(user2);
        book.placeOrder(mId, Side.Ask, OrderType.GoodTilBatch, 40, 50);

        assertGt(vault.locked(user1), 0);
        assertGt(vault.locked(user2), 0);

        // Clear: fills at clearing tick between 40 and 60
        auction.clearBatch(mId);

        // Both users should have locked == 0
        assertEq(vault.locked(user1), 0, "bid locked should be 0 after full fill");
        assertEq(vault.locked(user2), 0, "ask locked should be 0 after full fill");

        // Verify tokens were minted
        uint256 yesId = mId * 2;
        uint256 noId = mId * 2 + 1;
        assertEq(token.balanceOf(user1, yesId), 50, "user1 should have YES tokens");
        assertEq(token.balanceOf(user2, noId), 50, "user2 should have NO tokens");
    }

    function test_LockedZero_Cancel_NoResidual() public {
        uint256 mId = _setupMarket();

        vm.prank(user1);
        uint256 orderId = book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 50, 100);

        assertGt(vault.locked(user1), 0, "should be locked");

        vm.prank(user1);
        book.cancelOrder(orderId);

        assertEq(vault.locked(user1), 0, "locked should be 0 after cancel");
    }

    // =========================================================================
    // activeOrderCount underflow: replaceOrders after settlement
    // =========================================================================

    function test_ActiveOrderCount_ReplaceSettled_NoPruningRevert() public {
        uint256 mId = _setupMarket();

        // Place two orders for user1 at different ticks so only A participates
        vm.prank(user1);
        uint256 orderA = book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 50, 10);
        vm.prank(user1);
        uint256 orderB = book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 30, 10);

        assertEq(book.activeOrderCount(user1, mId), 2);

        // Fill order A via batch (B at tick 30 doesn't participate at clearing tick 50)
        vm.prank(user2);
        book.placeOrder(mId, Side.Ask, OrderType.GoodTilBatch, 50, 10);
        auction.clearBatch(mId);

        // A is fully filled (lots=0), B rolled to next batch
        (, , , , uint64 lotsA, , , , , ) = book.orders(orderA);
        (, , , , uint64 lotsB, , , , , ) = book.orders(orderB);
        assertEq(lotsA, 0, "A should be filled");
        assertEq(lotsB, 10, "B should still have lots");

        // activeOrderCount should be 1 (A decremented by settlement)
        assertEq(book.activeOrderCount(user1, mId), 1, "count should be 1 after A filled");

        // Replace the settled order A with a new order
        uint256[] memory cancelIds = new uint256[](1);
        cancelIds[0] = orderA;
        OrderParam[] memory newParams = new OrderParam[](1);
        newParams[0] = OrderParam(Side.Bid, OrderType.GoodTilCancel, 50, 10);

        vm.prank(user1);
        uint256[] memory newIds = book.replaceOrders(cancelIds, mId, newParams);

        // Count should be 2 (B + new order), NOT 1
        assertEq(book.activeOrderCount(user1, mId), 2, "count should be 2: B + new order");

        // Now expire the market and cancel remaining orders
        vm.warp(block.timestamp + 3601);

        uint256[] memory toCancelIds = new uint256[](2);
        toCancelIds[0] = orderB;
        toCancelIds[1] = newIds[0];

        // This should NOT revert with "counter underflow"
        book.cancelExpiredOrders(toCancelIds);

        assertEq(book.activeOrderCount(user1, mId), 0, "count should be 0 after all cancelled");
        assertEq(vault.locked(user1), 0, "locked should be 0 after all cancelled");
    }
}
