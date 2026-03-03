// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/OrderBook.sol";
import "../src/Vault.sol";
import "../src/ITypes.sol";

contract OrderBookTest is Test {
    OrderBook public book;
    Vault public vault;

    address public admin = address(0x1);
    address public operator = address(0x2);
    address public user1 = address(0x3);
    address public user2 = address(0x4);
    address public unauthorized = address(0x5);

    uint256 public constant LOT = 1e15; // 0.001 BNB

    function setUp() public {
        vm.startPrank(admin);
        vault = new Vault(admin);
        book = new OrderBook(admin, address(vault));
        book.grantRole(book.OPERATOR_ROLE(), operator);
        // Grant OrderBook the PROTOCOL_ROLE on Vault so it can lock/unlock
        vault.grantRole(vault.PROTOCOL_ROLE(), address(book));
        vm.stopPrank();

        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
    }

    // =========================================================================
    // Constructor
    // =========================================================================

    function test_Constructor_SetsVault() public view {
        assertEq(address(book.vault()), address(vault));
    }

    function test_Constructor_RevertZeroVault() public {
        vm.expectRevert("OrderBook: zero vault");
        new OrderBook(admin, address(0));
    }

    // =========================================================================
    // registerMarket
    // =========================================================================

    function test_RegisterMarket_Basic() public {
        vm.prank(operator);
        uint256 id = book.registerMarket(10);

        (uint256 mId, bool active, bool halted, uint256 batchId, uint256 minLots) = book.markets(id);
        assertEq(mId, 1);
        assertTrue(active);
        assertFalse(halted);
        assertEq(batchId, 1);
        assertEq(minLots, 10);
    }

    function test_RegisterMarket_EmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit OrderBook.MarketRegistered(1, 5);

        vm.prank(operator);
        book.registerMarket(5);
    }

    function test_RegisterMarket_IncrementsId() public {
        vm.startPrank(operator);
        uint256 id1 = book.registerMarket(0);
        uint256 id2 = book.registerMarket(0);
        vm.stopPrank();

        assertEq(id1, 1);
        assertEq(id2, 2);
    }

    function test_RegisterMarket_RevertIfNotOperator() public {
        vm.expectRevert();
        vm.prank(unauthorized);
        book.registerMarket(0);
    }

    // =========================================================================
    // haltMarket / resumeMarket / deactivateMarket
    // =========================================================================

    function test_HaltMarket_Basic() public {
        vm.startPrank(operator);
        uint256 id = book.registerMarket(0);
        book.haltMarket(id);
        vm.stopPrank();

        (, , bool halted, , ) = book.markets(id);
        assertTrue(halted);
    }

    function test_HaltMarket_EmitsEvent() public {
        vm.prank(operator);
        uint256 id = book.registerMarket(0);

        vm.expectEmit(true, false, false, false);
        emit OrderBook.MarketHalted(id);

        vm.prank(operator);
        book.haltMarket(id);
    }

    function test_HaltMarket_RevertIfAlreadyHalted() public {
        vm.startPrank(operator);
        uint256 id = book.registerMarket(0);
        book.haltMarket(id);

        vm.expectRevert("OrderBook: already halted");
        book.haltMarket(id);
        vm.stopPrank();
    }

    function test_ResumeMarket_Basic() public {
        vm.startPrank(operator);
        uint256 id = book.registerMarket(0);
        book.haltMarket(id);
        book.resumeMarket(id);
        vm.stopPrank();

        (, , bool halted, , ) = book.markets(id);
        assertFalse(halted);
    }

    function test_ResumeMarket_EmitsEvent() public {
        vm.startPrank(operator);
        uint256 id = book.registerMarket(0);
        book.haltMarket(id);
        vm.stopPrank();

        vm.expectEmit(true, false, false, false);
        emit OrderBook.MarketResumed(id);

        vm.prank(operator);
        book.resumeMarket(id);
    }

    function test_ResumeMarket_RevertIfNotHalted() public {
        vm.startPrank(operator);
        uint256 id = book.registerMarket(0);

        vm.expectRevert("OrderBook: not halted");
        book.resumeMarket(id);
        vm.stopPrank();
    }

    function test_DeactivateMarket_Basic() public {
        vm.startPrank(operator);
        uint256 id = book.registerMarket(0);
        book.deactivateMarket(id);
        vm.stopPrank();

        (, bool active, , , ) = book.markets(id);
        assertFalse(active);
    }

    function test_DeactivateMarket_EmitsEvent() public {
        vm.prank(operator);
        uint256 id = book.registerMarket(0);

        vm.expectEmit(true, false, false, false);
        emit OrderBook.MarketDeactivated(id);

        vm.prank(operator);
        book.deactivateMarket(id);
    }

    function test_DeactivateMarket_RevertIfAlreadyInactive() public {
        vm.startPrank(operator);
        uint256 id = book.registerMarket(0);
        book.deactivateMarket(id);

        vm.expectRevert("OrderBook: market not active");
        book.deactivateMarket(id);
        vm.stopPrank();
    }

    // =========================================================================
    // placeOrder — basic
    // =========================================================================

    function _setupMarket() internal returns (uint256 marketId) {
        vm.prank(operator);
        marketId = book.registerMarket(1); // minLots = 1
    }

    function _depositAndPlace(
        address user,
        uint256 marketId,
        Side side,
        uint256 tick,
        uint256 lots
    ) internal returns (uint256 orderId) {
        // Calculate collateral needed
        uint256 collateral;
        if (side == Side.Bid) {
            collateral = (lots * LOT * tick) / 100;
        } else {
            collateral = (lots * LOT * (100 - tick)) / 100;
        }

        vm.prank(user);
        vault.deposit{value: collateral}();

        vm.prank(user);
        orderId = book.placeOrder(marketId, side, OrderType.GoodTilCancel, tick, lots);
    }

    function test_PlaceOrder_BidBasic() public {
        uint256 mId = _setupMarket();
        uint256 orderId = _depositAndPlace(user1, mId, Side.Bid, 50, 10);

        (
            uint256 id,
            uint256 marketId,
            address owner,
            Side side,
            ,
            uint256 tick,
            uint256 lots,
            uint256 batchId,
        ) = book.orders(orderId);

        assertEq(id, 1);
        assertEq(marketId, mId);
        assertEq(owner, user1);
        assertTrue(side == Side.Bid);
        assertEq(tick, 50);
        assertEq(lots, 10);
        assertEq(batchId, 1);
    }

    function test_PlaceOrder_AskBasic() public {
        uint256 mId = _setupMarket();
        uint256 orderId = _depositAndPlace(user1, mId, Side.Ask, 60, 5);

        (, , , Side side, , uint256 tick, uint256 lots, , ) = book.orders(orderId);
        assertTrue(side == Side.Ask);
        assertEq(tick, 60);
        assertEq(lots, 5);
    }

    function test_PlaceOrder_EmitsEvent() public {
        uint256 mId = _setupMarket();
        uint256 collateral = (10 * LOT * 50) / 100;

        vm.prank(user1);
        vault.deposit{value: collateral}();

        vm.expectEmit(true, true, true, true);
        emit OrderBook.OrderPlaced(1, mId, user1, Side.Bid, 50, 10, 1);

        vm.prank(user1);
        book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 50, 10);
    }

    function test_PlaceOrder_LocksCollateral_Bid() public {
        uint256 mId = _setupMarket();
        uint256 collateral = (10 * LOT * 50) / 100; // 50% of 10 lots

        vm.prank(user1);
        vault.deposit{value: collateral}();

        vm.prank(user1);
        book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 50, 10);

        assertEq(vault.locked(user1), collateral);
        assertEq(vault.available(user1), 0);
    }

    function test_PlaceOrder_LocksCollateral_Ask() public {
        uint256 mId = _setupMarket();
        // Ask at tick 60: collateral = lots * LOT * (100-60) / 100 = 40% of lot value
        uint256 collateral = (10 * LOT * 40) / 100;

        vm.prank(user1);
        vault.deposit{value: collateral}();

        vm.prank(user1);
        book.placeOrder(mId, Side.Ask, OrderType.GoodTilCancel, 60, 10);

        assertEq(vault.locked(user1), collateral);
    }

    function test_PlaceOrder_UpdatesSegmentTree() public {
        uint256 mId = _setupMarket();
        _depositAndPlace(user1, mId, Side.Bid, 50, 10);
        _depositAndPlace(user2, mId, Side.Bid, 50, 5);

        assertEq(book.bidVolumeAt(mId, 50), 15);
        assertEq(book.totalBidVolume(mId), 15);
    }

    function test_PlaceOrder_UpdatesAskTree() public {
        uint256 mId = _setupMarket();
        _depositAndPlace(user1, mId, Side.Ask, 30, 7);

        assertEq(book.askVolumeAt(mId, 30), 7);
        assertEq(book.totalAskVolume(mId), 7);
    }

    // =========================================================================
    // placeOrder — validation
    // =========================================================================

    function test_PlaceOrder_RevertIfMarketNotActive() public {
        uint256 mId = _setupMarket();

        vm.prank(operator);
        book.deactivateMarket(mId);

        vm.expectRevert("OrderBook: market not active");
        vm.prank(user1);
        book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 50, 10);
    }

    function test_PlaceOrder_RevertIfMarketHalted() public {
        uint256 mId = _setupMarket();

        vm.prank(operator);
        book.haltMarket(mId);

        vm.expectRevert("OrderBook: market halted");
        vm.prank(user1);
        book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 50, 10);
    }

    function test_PlaceOrder_RevertIfTickZero() public {
        uint256 mId = _setupMarket();

        vm.expectRevert("OrderBook: tick out of range");
        vm.prank(user1);
        book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 0, 10);
    }

    function test_PlaceOrder_RevertIfTickAbove99() public {
        uint256 mId = _setupMarket();

        vm.expectRevert("OrderBook: tick out of range");
        vm.prank(user1);
        book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 100, 10);
    }

    function test_PlaceOrder_RevertIfZeroLots() public {
        uint256 mId = _setupMarket();

        vm.expectRevert("OrderBook: zero lots");
        vm.prank(user1);
        book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 50, 0);
    }

    function test_PlaceOrder_RevertIfBelowMinLots() public {
        vm.prank(operator);
        uint256 mId = book.registerMarket(5); // minLots = 5

        vm.expectRevert("OrderBook: below min lots");
        vm.prank(user1);
        book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 50, 3);
    }

    function test_PlaceOrder_RevertIfInsufficientCollateral() public {
        uint256 mId = _setupMarket();

        // Deposit only 1 wei — not enough for a bid at tick 50
        vm.prank(user1);
        vault.deposit{value: 1 wei}();

        vm.expectRevert("Vault: insufficient available balance");
        vm.prank(user1);
        book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 50, 10);
    }

    function test_PlaceOrder_Tick1And99() public {
        uint256 mId = _setupMarket();

        // Bid at tick 1: collateral = lots * LOT * 1 / 100 = minimal
        uint256 collateralBid = (1 * LOT * 1) / 100;
        vm.prank(user1);
        vault.deposit{value: collateralBid}();
        vm.prank(user1);
        uint256 oid1 = book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 1, 1);
        (, , , , , , uint256 lots1, , ) = book.orders(oid1);
        assertEq(lots1, 1);

        // Ask at tick 99: collateral = lots * LOT * 1 / 100 = minimal
        uint256 collateralAsk = (1 * LOT * 1) / 100;
        vm.prank(user2);
        vault.deposit{value: collateralAsk}();
        vm.prank(user2);
        uint256 oid2 = book.placeOrder(mId, Side.Ask, OrderType.GoodTilCancel, 99, 1);
        (, , , , , , uint256 lots2, , ) = book.orders(oid2);
        assertEq(lots2, 1);
    }

    // =========================================================================
    // cancelOrder
    // =========================================================================

    function test_CancelOrder_Basic() public {
        uint256 mId = _setupMarket();
        uint256 orderId = _depositAndPlace(user1, mId, Side.Bid, 50, 10);

        uint256 collateral = (10 * LOT * 50) / 100;

        vm.prank(user1);
        book.cancelOrder(orderId);

        (, , , , , , uint256 lots, , ) = book.orders(orderId);
        assertEq(lots, 0);
        assertEq(vault.locked(user1), 0);
        assertEq(vault.available(user1), collateral);
    }

    function test_CancelOrder_EmitsEvent() public {
        uint256 mId = _setupMarket();
        uint256 orderId = _depositAndPlace(user1, mId, Side.Bid, 50, 10);

        vm.expectEmit(true, true, false, false);
        emit OrderBook.OrderCancelled(orderId, user1);

        vm.prank(user1);
        book.cancelOrder(orderId);
    }

    function test_CancelOrder_UpdatesTree() public {
        uint256 mId = _setupMarket();
        uint256 orderId = _depositAndPlace(user1, mId, Side.Bid, 50, 10);

        assertEq(book.bidVolumeAt(mId, 50), 10);

        vm.prank(user1);
        book.cancelOrder(orderId);

        assertEq(book.bidVolumeAt(mId, 50), 0);
        assertEq(book.totalBidVolume(mId), 0);
    }

    function test_CancelOrder_AskUnlocksCorrectly() public {
        uint256 mId = _setupMarket();
        uint256 orderId = _depositAndPlace(user1, mId, Side.Ask, 40, 10);

        uint256 collateral = (10 * LOT * 60) / 100; // 100 - 40 = 60

        vm.prank(user1);
        book.cancelOrder(orderId);

        assertEq(vault.locked(user1), 0);
        assertEq(vault.available(user1), collateral);
    }

    function test_CancelOrder_RevertIfNotOwner() public {
        uint256 mId = _setupMarket();
        uint256 orderId = _depositAndPlace(user1, mId, Side.Bid, 50, 10);

        vm.expectRevert("OrderBook: not owner");
        vm.prank(user2);
        book.cancelOrder(orderId);
    }

    function test_CancelOrder_RevertIfAlreadyCancelled() public {
        uint256 mId = _setupMarket();
        uint256 orderId = _depositAndPlace(user1, mId, Side.Bid, 50, 10);

        vm.prank(user1);
        book.cancelOrder(orderId);

        vm.expectRevert("OrderBook: already cancelled/filled");
        vm.prank(user1);
        book.cancelOrder(orderId);
    }

    // =========================================================================
    // View functions
    // =========================================================================

    function test_FindClearingTick_WithCross() public {
        uint256 mId = _setupMarket();
        // Bid at 60, Ask at 40 → should cross
        _depositAndPlace(user1, mId, Side.Bid, 60, 10);
        _depositAndPlace(user2, mId, Side.Ask, 40, 10);

        uint256 ct = book.findClearingTick(mId);
        // Clearing tick should be between 40 and 60 (highest where cumBid >= cumAsk)
        assertGe(ct, 40);
        assertLe(ct, 60);
    }

    function test_FindClearingTick_NoCross() public {
        uint256 mId = _setupMarket();
        // Only bids, no asks → no clearing tick
        _depositAndPlace(user1, mId, Side.Bid, 30, 10);

        uint256 ct = book.findClearingTick(mId);
        assertEq(ct, 0);
    }

    function test_FindClearingTick_BidBelowAsk() public {
        uint256 mId = _setupMarket();
        // Bid at 30, Ask at 70
        // cumBid >= cumAsk holds for ticks 1-69 (since cumAsk is 0 until tick 70,
        // and cumBid is 10 for ticks 1-30 then 0 for 31+).
        // Highest tick where cumBid(p) >= cumAsk(p):
        // At p=69: cumBid=0, cumAsk=0 → 0>=0 holds → clearing tick = 69
        _depositAndPlace(user1, mId, Side.Bid, 30, 10);
        _depositAndPlace(user2, mId, Side.Ask, 70, 10);

        uint256 ct = book.findClearingTick(mId);
        // Both sides have volume but don't truly cross.
        // The algorithm returns the highest tick where cumBid >= cumAsk.
        // For ticks 31-69: cumBid=0, cumAsk=0, so 0>=0 holds.
        assertEq(ct, 69);
    }

    function test_FindClearingTick_EmptyBook() public {
        uint256 mId = _setupMarket();
        uint256 ct = book.findClearingTick(mId);
        assertEq(ct, 0);
    }

    function test_CumulativeVolumes() public {
        uint256 mId = _setupMarket();
        _depositAndPlace(user1, mId, Side.Bid, 50, 10);
        _depositAndPlace(user1, mId, Side.Bid, 60, 5);

        // cumBid at 50 = bids at >= 50 = 10 + 5 = 15
        assertEq(book.cumulativeBidVolume(mId, 50), 15);
        // cumBid at 60 = bids at >= 60 = 5
        assertEq(book.cumulativeBidVolume(mId, 60), 5);
    }

    function test_GetOrderIdsAtTick() public {
        uint256 mId = _setupMarket();
        uint256 oid1 = _depositAndPlace(user1, mId, Side.Bid, 50, 10);
        uint256 oid2 = _depositAndPlace(user2, mId, Side.Bid, 50, 5);

        uint256[] memory ids = book.getOrderIdsAtTick(mId, Side.Bid, 50);
        assertEq(ids.length, 2);
        assertEq(ids[0], oid1);
        assertEq(ids[1], oid2);
    }

    // =========================================================================
    // Fuzz tests
    // =========================================================================

    function testFuzz_PlaceOrder_CollateralLockedCorrectly(uint8 tick, uint8 lotsRaw) public {
        uint256 t = (uint256(tick) % 99) + 1; // 1-99
        uint256 l = (uint256(lotsRaw) % 100) + 1; // 1-100

        uint256 mId = _setupMarket();

        uint256 collateral = (l * LOT * t) / 100;
        vm.deal(user1, collateral);
        vm.prank(user1);
        vault.deposit{value: collateral}();

        vm.prank(user1);
        book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, t, l);

        assertEq(vault.locked(user1), collateral);
    }

    function testFuzz_CancelOrder_UnlocksAll(uint8 tick, uint8 lotsRaw) public {
        uint256 t = (uint256(tick) % 99) + 1;
        uint256 l = (uint256(lotsRaw) % 100) + 1;

        uint256 mId = _setupMarket();
        uint256 orderId = _depositAndPlace(user1, mId, Side.Bid, t, l);

        vm.prank(user1);
        book.cancelOrder(orderId);

        assertEq(vault.locked(user1), 0);
    }
}
