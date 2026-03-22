// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "@pythnetwork/pyth-sdk-solidity/MockPyth.sol";
import "../src/MarketFactory.sol";
import "../src/PythResolver.sol";
import "../src/OrderBook.sol";
import "../src/BatchAuction.sol";
import "../src/OutcomeToken.sol";
import "../src/Vault.sol";
import "../src/FeeModel.sol";
import "../src/Redemption.sol";
import "../src/ITypes.sol";
import "./mocks/MockUSDT.sol";

contract BatchOrderBookTest is Test {
    MarketFactory public factory;
    PythResolver public resolver;
    OrderBook public book;
    BatchAuction public auction;
    OutcomeToken public token;
    Vault public vault;
    FeeModel public feeModel;
    Redemption public redemption;
    MockPyth public mockPyth;
    MockUSDT public usdt;

    address public admin = address(0x1);
    address public operator = address(0x2);
    address public user1 = address(0x3);
    address public user2 = address(0x4);
    address public user3 = address(0x5);
    address public feeCollector = address(0x99);

    bytes32 public constant PRICE_ID = bytes32(uint256(0xB7C));
    int64 public constant STRIKE_PRICE = int64(50000_00000000);
    uint256 public constant LOT = 1e16;

    function setUp() public {
        usdt = new MockUSDT();

        vm.startPrank(admin);
        vault = new Vault(admin, address(usdt));
        token = new OutcomeToken(admin);
        feeModel = new FeeModel(admin, 20, feeCollector);
        book = new OrderBook(admin, address(vault), address(feeModel), address(token));
        auction = new BatchAuction(admin, address(book), address(vault), address(token));

        mockPyth = new MockPyth(120, 1);
        factory = new MarketFactory(admin, address(book), address(token));
        resolver = new PythResolver(address(mockPyth), address(factory));
        redemption = new Redemption(address(factory), address(token), address(vault));

        book.grantRole(book.OPERATOR_ROLE(), operator);
        book.grantRole(book.OPERATOR_ROLE(), address(auction));
        book.grantRole(book.OPERATOR_ROLE(), address(factory));
        vault.grantRole(vault.PROTOCOL_ROLE(), address(book));
        vault.grantRole(vault.PROTOCOL_ROLE(), address(auction));
        vault.grantRole(vault.PROTOCOL_ROLE(), address(redemption));
        token.grantRole(token.MINTER_ROLE(), address(auction));
        token.grantRole(token.MINTER_ROLE(), address(redemption));
        token.grantRole(token.ESCROW_ROLE(), address(auction));
        factory.grantRole(factory.ADMIN_ROLE(), address(resolver));
        factory.grantRole(factory.MARKET_CREATOR_ROLE(), user1);
        vm.stopPrank();

        for (uint256 i = 0; i < 3; i++) {
            address u = [user1, user2, user3][i];
            usdt.mint(u, 100000 ether);
            vm.prank(u);
            usdt.approve(address(vault), type(uint256).max);
        }
    }

    // =========================================================================
    // Helpers
    // =========================================================================

    function _createMarket(uint256 duration) internal returns (uint256 fmId, uint256 obId) {
        vm.prank(user1);
        fmId = factory.createMarket(PRICE_ID, STRIKE_PRICE, block.timestamp + duration, 60, 1);
        (, , , , , , , uint256 _obId, ) = factory.marketMeta(fmId);
        obId = _obId;
    }

    function _setupSimpleMarket() internal returns (uint256 obId) {
        vm.prank(operator);
        obId = book.registerMarket(1, 3, block.timestamp + 3600, false);
    }

    function _calcCollateral(Side side, uint256 tick, uint256 lots) internal pure returns (uint256) {
        if (side == Side.Bid) {
            return (lots * LOT * tick) / 100;
        } else {
            return (lots * LOT * (100 - tick)) / 100;
        }
    }

    function _calcTotal(Side side, uint256 tick, uint256 lots) internal view returns (uint256) {
        uint256 collateral = _calcCollateral(side, tick, lots);
        return collateral + feeModel.calculateFee(collateral);
    }

    function _mintTokensViaMatch(uint256 obId, uint256 tick, uint256 lots) internal {
        vm.prank(user1);
        book.placeOrder(obId, Side.Bid, OrderType.GoodTilCancel, tick, lots);
        vm.prank(user3);
        book.placeOrder(obId, Side.Ask, OrderType.GoodTilCancel, tick, lots);
        auction.clearBatch(obId);
    }

    function _approveTokensForOrderBook(address user) internal {
        vm.prank(user);
        token.setApprovalForAll(address(book), true);
    }

    function _op(Side side, OrderType ot, uint8 tick, uint64 lots) internal pure returns (OrderParam memory) {
        return OrderParam(side, ot, tick, lots);
    }

    // =========================================================================
    // placeOrders — basic functionality
    // =========================================================================

    function test_PlaceOrders_4Orders_2Bid2Ask() public {
        uint256 mId = _setupSimpleMarket();

        OrderParam[] memory params = new OrderParam[](4);
        params[0] = _op(Side.Bid, OrderType.GoodTilCancel, 50, 10);
        params[1] = _op(Side.Bid, OrderType.GoodTilCancel, 60, 5);
        params[2] = _op(Side.Ask, OrderType.GoodTilCancel, 40, 8);
        params[3] = _op(Side.Ask, OrderType.GoodTilCancel, 30, 3);

        uint256 expectedDeposit = _calcTotal(Side.Bid, 50, 10)
            + _calcTotal(Side.Bid, 60, 5)
            + _calcTotal(Side.Ask, 40, 8)
            + _calcTotal(Side.Ask, 30, 3);

        uint256 walletBefore = usdt.balanceOf(user1);

        vm.prank(user1);
        uint256[] memory orderIds = book.placeOrders(mId, params);

        assertEq(orderIds.length, 4);

        // Verify each order
        for (uint256 i = 0; i < 4; i++) {
            (address owner, Side side, , uint8 tick, uint64 oLots, , uint32 marketId, uint32 batchId, ) = book.orders(orderIds[i]);
            assertEq(owner, user1);
            assertEq(uint8(side), uint8(params[i].side));
            assertEq(tick, params[i].tick);
            assertEq(oLots, params[i].lots);
            assertEq(marketId, uint32(mId));
            assertEq(batchId, 1);
        }

        // Single USDT transfer
        assertEq(walletBefore - usdt.balanceOf(user1), expectedDeposit);
        assertEq(vault.locked(user1), expectedDeposit);

        // Tree state
        assertEq(book.bidVolumeAt(mId, 50), 10);
        assertEq(book.bidVolumeAt(mId, 60), 5);
        assertEq(book.askVolumeAt(mId, 40), 8);
        assertEq(book.askVolumeAt(mId, 30), 3);

        // Batch tracking
        uint256[] memory batchIds = book.getBatchOrderIds(mId, 1);
        assertEq(batchIds.length, 4);
    }

    function test_PlaceOrders_MixedGTCandGTB() public {
        uint256 mId = _setupSimpleMarket();

        OrderParam[] memory params = new OrderParam[](2);
        params[0] = _op(Side.Bid, OrderType.GoodTilCancel, 50, 10);
        params[1] = _op(Side.Ask, OrderType.GoodTilBatch, 60, 5);

        vm.prank(user1);
        uint256[] memory orderIds = book.placeOrders(mId, params);

        (, , OrderType ot0, , , , , , ) = book.orders(orderIds[0]);
        (, , OrderType ot1, , , , , , ) = book.orders(orderIds[1]);
        assertEq(uint8(ot0), uint8(OrderType.GoodTilCancel));
        assertEq(uint8(ot1), uint8(OrderType.GoodTilBatch));
    }

    function test_PlaceOrders_WithSellSides() public {
        (, uint256 obId) = _createMarket(3600);
        _mintTokensViaMatch(obId, 60, 20);

        uint256 yesId = token.yesTokenId(obId);
        assertEq(token.balanceOf(user1, yesId), 20);

        _approveTokensForOrderBook(user1);

        OrderParam[] memory params = new OrderParam[](3);
        params[0] = _op(Side.SellYes, OrderType.GoodTilCancel, 50, 8);
        params[1] = _op(Side.SellYes, OrderType.GoodTilCancel, 60, 5);
        params[2] = _op(Side.Bid, OrderType.GoodTilCancel, 40, 10);

        uint256 usdtBefore = usdt.balanceOf(user1);

        vm.prank(user1);
        uint256[] memory orderIds = book.placeOrders(obId, params);

        assertEq(orderIds.length, 3);

        // 13 YES tokens transferred to OrderBook (8 + 5)
        assertEq(token.balanceOf(user1, yesId), 7);
        assertEq(token.balanceOf(address(book), yesId), 13);

        // USDT locked for the bid order only
        uint256 bidDeposit = _calcTotal(Side.Bid, 40, 10);
        assertEq(usdtBefore - usdt.balanceOf(user1), bidDeposit);
    }

    function test_PlaceOrders_EmitsEvents() public {
        uint256 mId = _setupSimpleMarket();

        OrderParam[] memory params = new OrderParam[](2);
        params[0] = _op(Side.Bid, OrderType.GoodTilCancel, 50, 10);
        params[1] = _op(Side.Ask, OrderType.GoodTilCancel, 60, 5);

        uint64 startId = book.nextOrderId();

        vm.expectEmit(true, true, true, true);
        emit OrderBook.OrderPlaced(startId, mId, user1, Side.Bid, 50, 10, 1);
        vm.expectEmit(true, true, true, true);
        emit OrderBook.OrderPlaced(startId + 1, mId, user1, Side.Ask, 60, 5, 1);

        vm.prank(user1);
        book.placeOrders(mId, params);
    }

    // =========================================================================
    // placeOrders — reverts
    // =========================================================================

    function test_PlaceOrders_RevertOnEmptyArray() public {
        uint256 mId = _setupSimpleMarket();
        OrderParam[] memory params = new OrderParam[](0);

        vm.expectRevert("OrderBook: invalid batch size");
        vm.prank(user1);
        book.placeOrders(mId, params);
    }

    function test_PlaceOrders_RevertOnInactiveMarket() public {
        uint256 mId = _setupSimpleMarket();
        vm.prank(operator);
        book.deactivateMarket(mId);

        OrderParam[] memory params = new OrderParam[](1);
        params[0] = _op(Side.Bid, OrderType.GoodTilCancel, 50, 10);

        vm.expectRevert("OrderBook: market not active");
        vm.prank(user1);
        book.placeOrders(mId, params);
    }

    function test_PlaceOrders_RevertOnHaltedMarket() public {
        uint256 mId = _setupSimpleMarket();
        vm.prank(operator);
        book.haltMarket(mId);

        OrderParam[] memory params = new OrderParam[](1);
        params[0] = _op(Side.Bid, OrderType.GoodTilCancel, 50, 10);

        vm.expectRevert("OrderBook: market halted");
        vm.prank(user1);
        book.placeOrders(mId, params);
    }

    function test_PlaceOrders_RevertOnExpiredMarket() public {
        vm.prank(operator);
        uint256 mId = book.registerMarket(1, 3, block.timestamp + 5, false);
        vm.warp(block.timestamp + 5);

        OrderParam[] memory params = new OrderParam[](1);
        params[0] = _op(Side.Bid, OrderType.GoodTilCancel, 50, 10);

        vm.expectRevert("OrderBook: market expired");
        vm.prank(user1);
        book.placeOrders(mId, params);
    }

    function test_PlaceOrders_RevertOnInsufficientBalance() public {
        uint256 mId = _setupSimpleMarket();

        address poorUser = address(0xDEAD);
        usdt.mint(poorUser, 1);
        vm.prank(poorUser);
        usdt.approve(address(vault), type(uint256).max);

        OrderParam[] memory params = new OrderParam[](1);
        params[0] = _op(Side.Bid, OrderType.GoodTilCancel, 50, 1000);

        vm.expectRevert();
        vm.prank(poorUser);
        book.placeOrders(mId, params);
    }

    function test_PlaceOrders_RevertOnTickOutOfRange() public {
        uint256 mId = _setupSimpleMarket();

        OrderParam[] memory params = new OrderParam[](1);
        params[0] = _op(Side.Bid, OrderType.GoodTilCancel, 100, 10);

        vm.expectRevert("OrderBook: tick out of range");
        vm.prank(user1);
        book.placeOrders(mId, params);
    }

    function test_PlaceOrders_BatchOverflowToNextBatch() public {
        uint256 mId = _setupSimpleMarket();

        // Fill batch to MAX_ORDERS_PER_BATCH - 2 using 80 users × 20 orders each
        uint256 target = book.MAX_ORDERS_PER_BATCH() - 2;
        uint256 usersNeeded = (target + 19) / 20; // ceil division
        uint256 placed;
        for (uint256 u = 0; u < usersNeeded && placed < target; u++) {
            address filler = address(uint160(0xF000 + u));
            usdt.mint(filler, 100000 ether);
            vm.prank(filler);
            usdt.approve(address(vault), type(uint256).max);
            uint256 count = target - placed > 20 ? 20 : target - placed;
            for (uint256 j = 0; j < count; j++) {
                vm.prank(filler);
                book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 50, 1);
            }
            placed += count;
        }

        // Place 4 more — overflows to batch 2
        OrderParam[] memory params = new OrderParam[](4);
        for (uint256 i = 0; i < 4; i++) {
            params[i] = _op(Side.Bid, OrderType.GoodTilCancel, 50, 1);
        }

        vm.prank(user1);
        uint256[] memory orderIds = book.placeOrders(mId, params);
        assertEq(orderIds.length, 4);

        (, , , , , , , uint32 batchId, ) = book.orders(orderIds[0]);
        assertEq(batchId, 2);
    }

    // =========================================================================
    // placeOrders — gas comparison
    // =========================================================================

    function test_PlaceOrders_GasComparison() public {
        uint256 mId = _setupSimpleMarket();

        // Method 1: 4 individual placeOrder calls
        uint256 gas1Start = gasleft();
        vm.startPrank(user1);
        book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 50, 10);
        book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 60, 5);
        book.placeOrder(mId, Side.Ask, OrderType.GoodTilCancel, 40, 8);
        book.placeOrder(mId, Side.Ask, OrderType.GoodTilCancel, 30, 3);
        vm.stopPrank();
        uint256 gas1 = gas1Start - gasleft();

        // Method 2: single placeOrders
        vm.prank(operator);
        uint256 mId2 = book.registerMarket(1, 3, block.timestamp + 3600, false);

        OrderParam[] memory params = new OrderParam[](4);
        params[0] = _op(Side.Bid, OrderType.GoodTilCancel, 50, 10);
        params[1] = _op(Side.Bid, OrderType.GoodTilCancel, 60, 5);
        params[2] = _op(Side.Ask, OrderType.GoodTilCancel, 40, 8);
        params[3] = _op(Side.Ask, OrderType.GoodTilCancel, 30, 3);

        uint256 gas2Start = gasleft();
        vm.prank(user2);
        book.placeOrders(mId2, params);
        uint256 gas2 = gas2Start - gasleft();

        emit log_named_uint("4x placeOrder gas", gas1);
        emit log_named_uint("1x placeOrders gas", gas2);
        assertLt(gas2, gas1, "placeOrders should use less gas");
    }

    // =========================================================================
    // replaceOrders — basic functionality
    // =========================================================================

    function test_ReplaceOrders_4With4() public {
        uint256 mId = _setupSimpleMarket();

        vm.startPrank(user1);
        uint256 oid1 = book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 50, 10);
        uint256 oid2 = book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 60, 5);
        uint256 oid3 = book.placeOrder(mId, Side.Ask, OrderType.GoodTilCancel, 40, 8);
        uint256 oid4 = book.placeOrder(mId, Side.Ask, OrderType.GoodTilCancel, 30, 3);
        vm.stopPrank();

        uint256[] memory cancelIds = new uint256[](4);
        cancelIds[0] = oid1; cancelIds[1] = oid2; cancelIds[2] = oid3; cancelIds[3] = oid4;

        OrderParam[] memory params = new OrderParam[](4);
        params[0] = _op(Side.Bid, OrderType.GoodTilCancel, 55, 10);
        params[1] = _op(Side.Bid, OrderType.GoodTilCancel, 65, 5);
        params[2] = _op(Side.Ask, OrderType.GoodTilCancel, 35, 8);
        params[3] = _op(Side.Ask, OrderType.GoodTilCancel, 25, 3);

        vm.prank(user1);
        uint256[] memory newIds = book.replaceOrders(cancelIds, mId, params);

        assertEq(newIds.length, 4);

        // Old orders cancelled
        for (uint256 i = 0; i < 4; i++) {
            (, , , , uint64 remainingLots, , , , ) = book.orders(cancelIds[i]);
            assertEq(remainingLots, 0);
        }

        // New orders created
        for (uint256 i = 0; i < 4; i++) {
            (address owner, Side side, , uint8 tick, uint64 oLots, , , , ) = book.orders(newIds[i]);
            assertEq(owner, user1);
            assertEq(uint8(side), uint8(params[i].side));
            assertEq(tick, params[i].tick);
            assertEq(oLots, params[i].lots);
        }

        // Tree updated
        assertEq(book.bidVolumeAt(mId, 50), 0);
        assertEq(book.bidVolumeAt(mId, 60), 0);
        assertEq(book.askVolumeAt(mId, 40), 0);
        assertEq(book.askVolumeAt(mId, 30), 0);
        assertEq(book.bidVolumeAt(mId, 55), 10);
        assertEq(book.bidVolumeAt(mId, 65), 5);
        assertEq(book.askVolumeAt(mId, 35), 8);
        assertEq(book.askVolumeAt(mId, 25), 3);
    }

    function test_ReplaceOrders_NetCollateral_DiffTicks() public {
        uint256 mId = _setupSimpleMarket();

        vm.startPrank(user1);
        uint256 oid1 = book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 50, 10);
        uint256 oid2 = book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 50, 10);
        vm.stopPrank();

        uint256 walletBefore = usdt.balanceOf(user1);

        uint256[] memory cancelIds = new uint256[](2);
        cancelIds[0] = oid1; cancelIds[1] = oid2;

        OrderParam[] memory params = new OrderParam[](2);
        params[0] = _op(Side.Bid, OrderType.GoodTilCancel, 70, 10);
        params[1] = _op(Side.Bid, OrderType.GoodTilCancel, 70, 10);

        uint256 oldTotal = _calcTotal(Side.Bid, 50, 10) * 2;
        uint256 newTotal = _calcTotal(Side.Bid, 70, 10) * 2;
        uint256 netDeposit = newTotal - oldTotal;

        vm.prank(user1);
        book.replaceOrders(cancelIds, mId, params);

        assertEq(walletBefore - usdt.balanceOf(user1), netDeposit);
        assertEq(vault.locked(user1), newTotal);
    }

    function test_ReplaceOrders_SameTicks_ZeroNetTransfer() public {
        uint256 mId = _setupSimpleMarket();

        vm.startPrank(user1);
        uint256 oid1 = book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 50, 10);
        uint256 oid2 = book.placeOrder(mId, Side.Ask, OrderType.GoodTilCancel, 50, 10);
        vm.stopPrank();

        uint256 walletBefore = usdt.balanceOf(user1);

        uint256[] memory cancelIds = new uint256[](2);
        cancelIds[0] = oid1; cancelIds[1] = oid2;

        OrderParam[] memory params = new OrderParam[](2);
        params[0] = _op(Side.Bid, OrderType.GoodTilCancel, 50, 10);
        params[1] = _op(Side.Ask, OrderType.GoodTilCancel, 50, 10);

        vm.prank(user1);
        book.replaceOrders(cancelIds, mId, params);

        assertEq(usdt.balanceOf(user1), walletBefore);
    }

    function test_ReplaceOrders_SkipsFilledAndCancelled() public {
        uint256 mId = _setupSimpleMarket();

        vm.startPrank(user1);
        uint256 oid1 = book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 50, 10);
        uint256 oid2 = book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 60, 5);
        book.cancelOrder(oid1);
        vm.stopPrank();

        uint256 walletBefore = usdt.balanceOf(user1);

        uint256[] memory cancelIds = new uint256[](2);
        cancelIds[0] = oid1; cancelIds[1] = oid2;

        OrderParam[] memory params = new OrderParam[](1);
        params[0] = _op(Side.Bid, OrderType.GoodTilCancel, 70, 5);

        uint256 refundOid2 = _calcTotal(Side.Bid, 60, 5);
        uint256 newDeposit = _calcTotal(Side.Bid, 70, 5);

        vm.prank(user1);
        book.replaceOrders(cancelIds, mId, params);

        if (newDeposit > refundOid2) {
            assertEq(walletBefore - usdt.balanceOf(user1), newDeposit - refundOid2);
        } else {
            assertEq(usdt.balanceOf(user1) - walletBefore, refundOid2 - newDeposit);
        }
    }

    function test_ReplaceOrders_RevertIfNotOwner() public {
        uint256 mId = _setupSimpleMarket();

        vm.prank(user1);
        uint256 oid1 = book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 50, 10);

        uint256[] memory cancelIds = new uint256[](1);
        cancelIds[0] = oid1;

        OrderParam[] memory params = new OrderParam[](1);
        params[0] = _op(Side.Bid, OrderType.GoodTilCancel, 50, 10);

        vm.expectRevert("OrderBook: not owner");
        vm.prank(user2);
        book.replaceOrders(cancelIds, mId, params);
    }

    function test_ReplaceOrders_RevertOnExpiredMarket() public {
        vm.prank(operator);
        uint256 mId = book.registerMarket(1, 3, block.timestamp + 60, false);

        vm.prank(user1);
        uint256 oid1 = book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 50, 10);

        vm.warp(block.timestamp + 60);

        uint256[] memory cancelIds = new uint256[](1);
        cancelIds[0] = oid1;

        OrderParam[] memory params = new OrderParam[](1);
        params[0] = _op(Side.Bid, OrderType.GoodTilCancel, 50, 10);

        vm.expectRevert("OrderBook: market expired");
        vm.prank(user1);
        book.replaceOrders(cancelIds, mId, params);
    }

    function test_ReplaceOrders_CancelOnly() public {
        uint256 mId = _setupSimpleMarket();

        vm.prank(user1);
        uint256 oid1 = book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 50, 10);

        uint256 walletBefore = usdt.balanceOf(user1);
        uint256 expectedRefund = _calcTotal(Side.Bid, 50, 10);

        uint256[] memory cancelIds = new uint256[](1);
        cancelIds[0] = oid1;

        OrderParam[] memory params = new OrderParam[](0);

        vm.prank(user1);
        uint256[] memory newIds = book.replaceOrders(cancelIds, mId, params);

        assertEq(newIds.length, 0);
        assertEq(usdt.balanceOf(user1) - walletBefore, expectedRefund);
        assertEq(vault.locked(user1), 0);
    }

    function test_ReplaceOrders_EmitsEvents() public {
        uint256 mId = _setupSimpleMarket();

        vm.prank(user1);
        uint256 oid1 = book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 50, 10);

        uint256[] memory cancelIds = new uint256[](1);
        cancelIds[0] = oid1;

        OrderParam[] memory params = new OrderParam[](1);
        params[0] = _op(Side.Bid, OrderType.GoodTilCancel, 60, 10);

        uint64 nextId = book.nextOrderId();

        vm.expectEmit(true, true, true, false);
        emit OrderBook.OrderCancelled(oid1, mId, user1);
        vm.expectEmit(true, true, true, true);
        emit OrderBook.OrderPlaced(nextId, mId, user1, Side.Bid, 60, 10, 1);

        vm.prank(user1);
        book.replaceOrders(cancelIds, mId, params);
    }

    // =========================================================================
    // replaceOrders — sell orders
    // =========================================================================

    function test_ReplaceOrders_SellOrderReplacement() public {
        (, uint256 obId) = _createMarket(3600);
        _mintTokensViaMatch(obId, 60, 20);

        uint256 yesId = token.yesTokenId(obId);
        _approveTokensForOrderBook(user1);

        vm.startPrank(user1);
        uint256 oid1 = book.placeOrder(obId, Side.SellYes, OrderType.GoodTilCancel, 50, 10);
        uint256 oid2 = book.placeOrder(obId, Side.SellYes, OrderType.GoodTilCancel, 60, 5);
        vm.stopPrank();

        assertEq(token.balanceOf(user1, yesId), 5);

        uint256[] memory cancelIds = new uint256[](2);
        cancelIds[0] = oid1; cancelIds[1] = oid2;

        OrderParam[] memory params = new OrderParam[](2);
        params[0] = _op(Side.SellYes, OrderType.GoodTilCancel, 55, 10);
        params[1] = _op(Side.SellYes, OrderType.GoodTilCancel, 65, 5);

        vm.prank(user1);
        uint256[] memory newIds = book.replaceOrders(cancelIds, obId, params);

        assertEq(newIds.length, 2);
        assertEq(token.balanceOf(user1, yesId), 5);
        assertEq(token.balanceOf(address(book), yesId), 15);

        assertEq(book.askVolumeAt(obId, 50), 0);
        assertEq(book.askVolumeAt(obId, 60), 0);
        assertEq(book.askVolumeAt(obId, 55), 10);
        assertEq(book.askVolumeAt(obId, 65), 5);
    }

    function test_ReplaceOrders_MixedBuyAndSell() public {
        (, uint256 obId) = _createMarket(3600);
        _mintTokensViaMatch(obId, 60, 20);

        _approveTokensForOrderBook(user1);

        vm.startPrank(user1);
        uint256 oid1 = book.placeOrder(obId, Side.Bid, OrderType.GoodTilCancel, 40, 10);
        uint256 oid2 = book.placeOrder(obId, Side.SellYes, OrderType.GoodTilCancel, 50, 10);
        vm.stopPrank();

        uint256[] memory cancelIds = new uint256[](2);
        cancelIds[0] = oid1; cancelIds[1] = oid2;

        OrderParam[] memory params = new OrderParam[](2);
        params[0] = _op(Side.Bid, OrderType.GoodTilCancel, 45, 10);
        params[1] = _op(Side.SellYes, OrderType.GoodTilCancel, 55, 10);

        vm.prank(user1);
        uint256[] memory newIds = book.replaceOrders(cancelIds, obId, params);

        assertEq(newIds.length, 2);

        (address owner0, Side side0, , uint8 tick0, , , , , ) = book.orders(newIds[0]);
        assertEq(owner0, user1);
        assertEq(uint8(side0), uint8(Side.Bid));
        assertEq(tick0, 45);

        (address owner1, Side side1, , uint8 tick1, , , , , ) = book.orders(newIds[1]);
        assertEq(owner1, user1);
        assertEq(uint8(side1), uint8(Side.SellYes));
        assertEq(tick1, 55);
    }

    // =========================================================================
    // replaceOrders — gas comparison
    // =========================================================================

    function test_ReplaceOrders_GasComparison() public {
        uint256 mId = _setupSimpleMarket();

        // Setup for method 1
        vm.startPrank(user1);
        uint256 oid1a = book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 50, 10);
        uint256 oid2a = book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 60, 5);
        uint256 oid3a = book.placeOrder(mId, Side.Ask, OrderType.GoodTilCancel, 40, 8);
        uint256 oid4a = book.placeOrder(mId, Side.Ask, OrderType.GoodTilCancel, 30, 3);
        vm.stopPrank();

        // Method 1: cancelOrders then placeOrders (2 calls)
        uint256[] memory cancelBatch = new uint256[](4);
        cancelBatch[0] = oid1a; cancelBatch[1] = oid2a; cancelBatch[2] = oid3a; cancelBatch[3] = oid4a;

        OrderParam[] memory newParams = new OrderParam[](4);
        newParams[0] = _op(Side.Bid, OrderType.GoodTilCancel, 55, 10);
        newParams[1] = _op(Side.Bid, OrderType.GoodTilCancel, 65, 5);
        newParams[2] = _op(Side.Ask, OrderType.GoodTilCancel, 35, 8);
        newParams[3] = _op(Side.Ask, OrderType.GoodTilCancel, 25, 3);

        uint256 gas1Start = gasleft();
        vm.startPrank(user1);
        book.cancelOrders(cancelBatch);
        book.placeOrders(mId, newParams);
        vm.stopPrank();
        uint256 gas1 = gas1Start - gasleft();

        // Setup for method 2
        vm.prank(operator);
        uint256 mId2 = book.registerMarket(1, 3, block.timestamp + 3600, false);

        vm.startPrank(user2);
        uint256 oid1b = book.placeOrder(mId2, Side.Bid, OrderType.GoodTilCancel, 50, 10);
        uint256 oid2b = book.placeOrder(mId2, Side.Bid, OrderType.GoodTilCancel, 60, 5);
        uint256 oid3b = book.placeOrder(mId2, Side.Ask, OrderType.GoodTilCancel, 40, 8);
        uint256 oid4b = book.placeOrder(mId2, Side.Ask, OrderType.GoodTilCancel, 30, 3);
        vm.stopPrank();

        // Method 2: single replaceOrders
        uint256[] memory cancelBatch2 = new uint256[](4);
        cancelBatch2[0] = oid1b; cancelBatch2[1] = oid2b; cancelBatch2[2] = oid3b; cancelBatch2[3] = oid4b;

        uint256 gas2Start = gasleft();
        vm.prank(user2);
        book.replaceOrders(cancelBatch2, mId2, newParams);
        uint256 gas2 = gas2Start - gasleft();

        emit log_named_uint("cancelOrders + placeOrders gas", gas1);
        emit log_named_uint("replaceOrders gas", gas2);
        assertLt(gas2, gas1, "replaceOrders should use less gas");
    }

    // =========================================================================
    // replaceOrders — net refund
    // =========================================================================

    function test_ReplaceOrders_NetRefund() public {
        uint256 mId = _setupSimpleMarket();

        vm.startPrank(user1);
        uint256 oid1 = book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 50, 10);
        uint256 oid2 = book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 60, 10);
        vm.stopPrank();

        uint256 walletBefore = usdt.balanceOf(user1);

        uint256[] memory cancelIds = new uint256[](2);
        cancelIds[0] = oid1; cancelIds[1] = oid2;

        OrderParam[] memory params = new OrderParam[](1);
        params[0] = _op(Side.Bid, OrderType.GoodTilCancel, 30, 5);

        uint256 totalRefund = _calcTotal(Side.Bid, 50, 10) + _calcTotal(Side.Bid, 60, 10);
        uint256 newDeposit = _calcTotal(Side.Bid, 30, 5);

        vm.prank(user1);
        book.replaceOrders(cancelIds, mId, params);

        assertEq(usdt.balanceOf(user1) - walletBefore, totalRefund - newDeposit);
        assertEq(vault.locked(user1), newDeposit);
    }

    // =========================================================================
    // Integration: placeOrders then clearBatch
    // =========================================================================

    function test_PlaceOrders_ThenClearBatch() public {
        (, uint256 obId) = _createMarket(3600);

        OrderParam[] memory bidParams = new OrderParam[](2);
        bidParams[0] = _op(Side.Bid, OrderType.GoodTilCancel, 50, 10);
        bidParams[1] = _op(Side.Bid, OrderType.GoodTilCancel, 60, 5);

        vm.prank(user1);
        book.placeOrders(obId, bidParams);

        OrderParam[] memory askParams = new OrderParam[](2);
        askParams[0] = _op(Side.Ask, OrderType.GoodTilCancel, 50, 10);
        askParams[1] = _op(Side.Ask, OrderType.GoodTilCancel, 40, 5);

        vm.prank(user2);
        book.placeOrders(obId, askParams);

        BatchResult memory result = auction.clearBatch(obId);
        assertGt(result.clearingTick, 0, "Should have a crossing");
        assertGt(result.matchedLots, 0, "Should have matched lots");
    }
}
