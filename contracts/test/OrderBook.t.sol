// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/OrderBook.sol";
import "../src/Vault.sol";
import "../src/FeeModel.sol";
import "../src/ITypes.sol";
import "./mocks/MockUSDT.sol";

contract OrderBookTest is Test {
    OrderBook public book;
    Vault public vault;
    FeeModel public feeModel;
    MockUSDT public usdt;

    address public admin = address(0x1);
    address public operator = address(0x2);
    address public user1 = address(0x3);
    address public user2 = address(0x4);
    address public unauthorized = address(0x5);

    uint256 public constant LOT = 1e16;

    function setUp() public {
        usdt = new MockUSDT();

        vm.startPrank(admin);
        vault = new Vault(admin, address(usdt));
        feeModel = new FeeModel(admin, 20, 0, 5e18, 1e17, admin);
        book = new OrderBook(admin, address(vault), address(feeModel));
        book.grantRole(book.OPERATOR_ROLE(), operator);
        vault.grantRole(vault.PROTOCOL_ROLE(), address(book));
        vm.stopPrank();

        usdt.mint(user1, 10000 ether);
        usdt.mint(user2, 10000 ether);

        vm.prank(user1);
        usdt.approve(address(vault), type(uint256).max);
        vm.prank(user2);
        usdt.approve(address(vault), type(uint256).max);
    }

    function test_Constructor_SetsVault() public view {
        assertEq(address(book.vault()), address(vault));
    }

    function test_Constructor_RevertZeroVault() public {
        vm.expectRevert("OrderBook: zero vault");
        new OrderBook(admin, address(0), address(feeModel));
    }

    // =========================================================================
    // registerMarket
    // =========================================================================

    function test_RegisterMarket_Basic() public {
        vm.prank(operator);
        uint256 id = book.registerMarket(10, 3, block.timestamp + 3600);

        (uint32 mId, bool active, bool halted, uint32 batchId, uint32 minLots, , ) = book.markets(id);
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
        book.registerMarket(5, 3, block.timestamp + 3600);
    }

    function test_RegisterMarket_IncrementsId() public {
        vm.startPrank(operator);
        uint256 id1 = book.registerMarket(0, 3, block.timestamp + 3600);
        uint256 id2 = book.registerMarket(0, 3, block.timestamp + 3600);
        vm.stopPrank();
        assertEq(id1, 1);
        assertEq(id2, 2);
    }

    function test_RegisterMarket_RevertIfNotOperator() public {
        vm.expectRevert();
        vm.prank(unauthorized);
        book.registerMarket(0, 3, block.timestamp + 3600);
    }

    // =========================================================================
    // haltMarket / resumeMarket / deactivateMarket
    // =========================================================================

    function test_HaltMarket_Basic() public {
        vm.startPrank(operator);
        uint256 id = book.registerMarket(0, 3, block.timestamp + 3600);
        book.haltMarket(id);
        vm.stopPrank();
        (, , bool halted, , , , ) = book.markets(id);
        assertTrue(halted);
    }

    function test_HaltMarket_RevertIfAlreadyHalted() public {
        vm.startPrank(operator);
        uint256 id = book.registerMarket(0, 3, block.timestamp + 3600);
        book.haltMarket(id);
        vm.expectRevert("OrderBook: already halted");
        book.haltMarket(id);
        vm.stopPrank();
    }

    function test_ResumeMarket_Basic() public {
        vm.startPrank(operator);
        uint256 id = book.registerMarket(0, 3, block.timestamp + 3600);
        book.haltMarket(id);
        book.resumeMarket(id);
        vm.stopPrank();
        (, , bool halted, , , , ) = book.markets(id);
        assertFalse(halted);
    }

    function test_ResumeMarket_RevertIfNotHalted() public {
        vm.startPrank(operator);
        uint256 id = book.registerMarket(0, 3, block.timestamp + 3600);
        vm.expectRevert("OrderBook: not halted");
        book.resumeMarket(id);
        vm.stopPrank();
    }

    function test_DeactivateMarket_Basic() public {
        vm.startPrank(operator);
        uint256 id = book.registerMarket(0, 3, block.timestamp + 3600);
        book.deactivateMarket(id);
        vm.stopPrank();
        (, bool active, , , , , ) = book.markets(id);
        assertFalse(active);
    }

    function test_DeactivateMarket_RevertIfAlreadyInactive() public {
        vm.startPrank(operator);
        uint256 id = book.registerMarket(0, 3, block.timestamp + 3600);
        book.deactivateMarket(id);
        vm.expectRevert("OrderBook: market not active");
        book.deactivateMarket(id);
        vm.stopPrank();
    }

    // =========================================================================
    // placeOrder — ERC20 flow
    // =========================================================================

    function _setupMarket() internal returns (uint256 marketId) {
        vm.prank(operator);
        marketId = book.registerMarket(1, 3, block.timestamp + 3600);
    }

    function _calcCollateral(Side side, uint256 tick, uint256 lots) internal pure returns (uint256) {
        if (side == Side.Bid) {
            return (lots * LOT * tick) / 100;
        } else {
            return (lots * LOT * (100 - tick)) / 100;
        }
    }

    function _placeOrder(
        address user,
        uint256 marketId,
        Side side,
        uint256 tick,
        uint256 lots
    ) internal returns (uint256 orderId) {
        vm.prank(user);
        orderId = book.placeOrder(marketId, side, OrderType.GoodTilCancel, tick, lots);
    }

    function test_PlaceOrder_BidBasic() public {
        uint256 mId = _setupMarket();
        uint256 orderId = _placeOrder(user1, mId, Side.Bid, 50, 10);

        (
            address owner,
            Side side,
            ,
            uint8 tick,
            uint64 lots,
            uint64 id,
            uint32 marketId,
            uint32 batchId,
        ) = book.orders(orderId);

        assertEq(id, 1);
        assertEq(marketId, uint32(mId));
        assertEq(owner, user1);
        assertTrue(side == Side.Bid);
        assertEq(tick, 50);
        assertEq(lots, 10);
        assertEq(batchId, 1);
    }

    function test_PlaceOrder_AskBasic() public {
        uint256 mId = _setupMarket();
        uint256 orderId = _placeOrder(user1, mId, Side.Ask, 60, 5);

        (, Side side, , uint8 tick, uint64 lots, , , , ) = book.orders(orderId);
        assertTrue(side == Side.Ask);
        assertEq(tick, 60);
        assertEq(lots, 5);
    }

    function test_PlaceOrder_EmitsEvent() public {
        uint256 mId = _setupMarket();

        vm.expectEmit(true, true, true, true);
        emit OrderBook.OrderPlaced(1, mId, user1, Side.Bid, 50, 10, 1);

        vm.prank(user1);
        book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 50, 10);
    }

    function test_PlaceOrder_LocksCollateralPlusFee_Bid() public {
        uint256 mId = _setupMarket();
        uint256 collateral = (10 * LOT * 50) / 100;
        uint256 fee = feeModel.calculateFee(collateral);

        vm.prank(user1);
        book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 50, 10);

        assertEq(vault.locked(user1), collateral + fee);
        assertEq(vault.available(user1), 0);
    }

    function test_PlaceOrder_LocksCollateralPlusFee_Ask() public {
        uint256 mId = _setupMarket();
        uint256 collateral = (10 * LOT * 40) / 100;
        uint256 fee = feeModel.calculateFee(collateral);

        vm.prank(user1);
        book.placeOrder(mId, Side.Ask, OrderType.GoodTilCancel, 60, 10);

        assertEq(vault.locked(user1), collateral + fee);
    }

    function test_PlaceOrder_UpdatesSegmentTree() public {
        uint256 mId = _setupMarket();
        _placeOrder(user1, mId, Side.Bid, 50, 10);
        _placeOrder(user2, mId, Side.Bid, 50, 5);

        assertEq(book.bidVolumeAt(mId, 50), 15);
        assertEq(book.totalBidVolume(mId), 15);
    }

    function test_PlaceOrder_UpdatesAskTree() public {
        uint256 mId = _setupMarket();
        _placeOrder(user1, mId, Side.Ask, 30, 7);

        assertEq(book.askVolumeAt(mId, 30), 7);
        assertEq(book.totalAskVolume(mId), 7);
    }

    function test_PlaceOrder_TracksBatchOrderIds() public {
        uint256 mId = _setupMarket();
        _placeOrder(user1, mId, Side.Bid, 50, 10);
        _placeOrder(user2, mId, Side.Ask, 60, 5);

        uint256[] memory ids = book.getBatchOrderIds(mId, 1);
        assertEq(ids.length, 2);
        assertEq(ids[0], 1);
        assertEq(ids[1], 2);
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
        uint256 mId = book.registerMarket(5, 3, block.timestamp + 3600);

        vm.expectRevert("OrderBook: below min lots");
        vm.prank(user1);
        book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 50, 3);
    }

    function test_PlaceOrder_RevertIfMarketExpired() public {
        vm.prank(operator);
        uint256 mId = book.registerMarket(1, 3, block.timestamp + 5);

        vm.warp(block.timestamp + 5);

        vm.expectRevert("OrderBook: market expired");
        vm.prank(user1);
        book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 50, 1);
    }

    function test_PlaceOrder_Tick1And99() public {
        uint256 mId = _setupMarket();

        vm.prank(user1);
        uint256 oid1 = book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 1, 1);
        (, , , , uint64 lots1, , , , ) = book.orders(oid1);
        assertEq(lots1, 1);

        vm.prank(user2);
        uint256 oid2 = book.placeOrder(mId, Side.Ask, OrderType.GoodTilCancel, 99, 1);
        (, , , , uint64 lots2, , , , ) = book.orders(oid2);
        assertEq(lots2, 1);
    }

    // =========================================================================
    // cancelOrder — returns USDT to wallet
    // =========================================================================

    function test_CancelOrder_Basic() public {
        uint256 mId = _setupMarket();
        uint256 collateral = _calcCollateral(Side.Bid, 50, 10);
        uint256 fee = feeModel.calculateFee(collateral);
        uint256 orderId = _placeOrder(user1, mId, Side.Bid, 50, 10);

        uint256 walletBefore = usdt.balanceOf(user1);
        vm.prank(user1);
        book.cancelOrder(orderId);

        (, , , , uint64 lots, , , , ) = book.orders(orderId);
        assertEq(lots, 0);
        assertEq(vault.locked(user1), 0);
        assertEq(vault.balance(user1), 0);
        assertEq(usdt.balanceOf(user1) - walletBefore, collateral + fee);
    }

    function test_CancelOrder_EmitsEvent() public {
        uint256 mId = _setupMarket();
        uint256 orderId = _placeOrder(user1, mId, Side.Bid, 50, 10);

        vm.expectEmit(true, true, false, false);
        emit OrderBook.OrderCancelled(orderId, user1);

        vm.prank(user1);
        book.cancelOrder(orderId);
    }

    function test_CancelOrder_UpdatesTree() public {
        uint256 mId = _setupMarket();
        uint256 orderId = _placeOrder(user1, mId, Side.Bid, 50, 10);

        assertEq(book.bidVolumeAt(mId, 50), 10);

        vm.prank(user1);
        book.cancelOrder(orderId);

        assertEq(book.bidVolumeAt(mId, 50), 0);
    }

    function test_CancelOrder_RevertIfNotOwner() public {
        uint256 mId = _setupMarket();
        uint256 orderId = _placeOrder(user1, mId, Side.Bid, 50, 10);

        vm.expectRevert("OrderBook: not owner");
        vm.prank(user2);
        book.cancelOrder(orderId);
    }

    function test_CancelOrder_RevertIfAlreadyCancelled() public {
        uint256 mId = _setupMarket();
        uint256 orderId = _placeOrder(user1, mId, Side.Bid, 50, 10);

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
        _placeOrder(user1, mId, Side.Bid, 60, 10);
        _placeOrder(user2, mId, Side.Ask, 40, 10);

        uint256 ct = book.findClearingTick(mId);
        assertGe(ct, 40);
        assertLe(ct, 60);
    }

    function test_FindClearingTick_NoCross() public {
        uint256 mId = _setupMarket();
        _placeOrder(user1, mId, Side.Bid, 30, 10);

        uint256 ct = book.findClearingTick(mId);
        assertEq(ct, 0);
    }

    function test_FindClearingTick_EmptyBook() public {
        uint256 mId = _setupMarket();
        uint256 ct = book.findClearingTick(mId);
        assertEq(ct, 0);
    }

    function test_CumulativeVolumes() public {
        uint256 mId = _setupMarket();
        _placeOrder(user1, mId, Side.Bid, 50, 10);
        _placeOrder(user1, mId, Side.Bid, 60, 5);

        assertEq(book.cumulativeBidVolume(mId, 50), 15);
        assertEq(book.cumulativeBidVolume(mId, 60), 5);
    }

    // =========================================================================
    // Fuzz tests
    // =========================================================================

    function testFuzz_PlaceOrder_CollateralPlusFeeLocked(uint8 tick, uint8 lotsRaw) public {
        uint256 t = (uint256(tick) % 99) + 1;
        uint256 l = (uint256(lotsRaw) % 100) + 1;

        uint256 mId = _setupMarket();

        uint256 collateral = (l * LOT * t) / 100;
        uint256 fee = feeModel.calculateFee(collateral);
        vm.prank(user1);
        book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, t, l);

        assertEq(vault.locked(user1), collateral + fee);
    }

    function testFuzz_CancelOrder_ReturnsUSDTPlusFee(uint8 tick, uint8 lotsRaw) public {
        uint256 t = (uint256(tick) % 99) + 1;
        uint256 l = (uint256(lotsRaw) % 100) + 1;

        uint256 mId = _setupMarket();
        uint256 collateral = _calcCollateral(Side.Bid, t, l);
        uint256 fee = feeModel.calculateFee(collateral);

        vm.prank(user1);
        uint256 orderId = book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, t, l);

        uint256 walletBefore = usdt.balanceOf(user1);
        vm.prank(user1);
        book.cancelOrder(orderId);

        assertEq(vault.locked(user1), 0);
        assertEq(usdt.balanceOf(user1) - walletBefore, collateral + fee);
    }
}
