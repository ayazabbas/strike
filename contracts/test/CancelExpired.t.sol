// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/OrderBook.sol";
import "../src/Vault.sol";
import "../src/FeeModel.sol";
import "../src/OutcomeToken.sol";
import "../src/ITypes.sol";
import "./mocks/MockUSDT.sol";

contract CancelExpiredTest is Test {
    OrderBook public book;
    Vault public vault;
    FeeModel public feeModel;
    OutcomeToken public token;
    MockUSDT public usdt;

    address public admin = address(0x1);
    address public operator = address(0x2);
    address public user1 = address(0x3);
    address public user2 = address(0x4);
    address public anyone = address(0x5);

    uint256 public marketId;

    function setUp() public {
        usdt = new MockUSDT();

        vm.startPrank(admin);
        vault = new Vault(admin, address(usdt));
        feeModel = new FeeModel(admin, 20, admin);
        token = new OutcomeToken(admin);
        book = new OrderBook(admin, address(vault), address(feeModel), address(token));
        book.grantRole(book.OPERATOR_ROLE(), operator);
        vault.grantRole(vault.PROTOCOL_ROLE(), address(book));
        vm.stopPrank();

        usdt.mint(user1, 10000 ether);
        usdt.mint(user2, 10000 ether);

        vm.prank(user1);
        usdt.approve(address(vault), type(uint256).max);
        vm.prank(user2);
        usdt.approve(address(vault), type(uint256).max);

        vm.prank(operator);
        marketId = book.registerMarket(1, 60, block.timestamp + 3600, false);
    }

    function test_CancelExpiredOrder_Single() public {
        vm.prank(user1);
        uint256 orderId = book.placeOrder(marketId, Side.Bid, OrderType.GoodTilCancel, 50, 10);

        uint256 balBefore = usdt.balanceOf(user1);

        // Warp past expiry
        vm.warp(block.timestamp + 3601);

        // Anyone can cancel expired orders
        vm.prank(anyone);
        book.cancelExpiredOrder(orderId);

        // Order should be zeroed
        (, , , , uint64 lots, , , , , ) = book.orders(orderId);
        assertEq(lots, 0);

        // User1 should get refund
        assertGt(usdt.balanceOf(user1), balBefore);
    }

    function test_CancelExpiredOrders_Batch() public {
        vm.prank(user1);
        uint256 id1 = book.placeOrder(marketId, Side.Bid, OrderType.GoodTilCancel, 50, 10);
        vm.prank(user2);
        uint256 id2 = book.placeOrder(marketId, Side.Ask, OrderType.GoodTilCancel, 40, 5);

        uint256 bal1Before = usdt.balanceOf(user1);
        uint256 bal2Before = usdt.balanceOf(user2);

        vm.warp(block.timestamp + 3601);

        uint256[] memory ids = new uint256[](2);
        ids[0] = id1;
        ids[1] = id2;

        vm.prank(anyone);
        book.cancelExpiredOrders(ids);

        (, , , , uint64 lots1, , , , , ) = book.orders(id1);
        (, , , , uint64 lots2, , , , , ) = book.orders(id2);
        assertEq(lots1, 0);
        assertEq(lots2, 0);

        assertGt(usdt.balanceOf(user1), bal1Before);
        assertGt(usdt.balanceOf(user2), bal2Before);
    }

    function test_CancelExpiredOrder_RevertIfNotExpired() public {
        vm.prank(user1);
        uint256 orderId = book.placeOrder(marketId, Side.Bid, OrderType.GoodTilCancel, 50, 10);

        vm.expectRevert("OrderBook: market not expired");
        vm.prank(anyone);
        book.cancelExpiredOrder(orderId);
    }

    function test_CancelExpiredOrders_SkipsNonExpired() public {
        // Create two markets: one that will expire and one that won't
        vm.prank(operator);
        uint256 market2 = book.registerMarket(1, 60, block.timestamp + 7200, false);

        vm.prank(user1);
        uint256 id1 = book.placeOrder(marketId, Side.Bid, OrderType.GoodTilCancel, 50, 10);
        vm.prank(user2);
        uint256 id2 = book.placeOrder(market2, Side.Bid, OrderType.GoodTilCancel, 50, 10);

        // Warp past first market expiry but not second
        vm.warp(block.timestamp + 3601);

        uint256[] memory ids = new uint256[](2);
        ids[0] = id1;
        ids[1] = id2;

        vm.prank(anyone);
        book.cancelExpiredOrders(ids);

        // First order should be cancelled
        (, , , , uint64 lots1, , , , , ) = book.orders(id1);
        assertEq(lots1, 0);

        // Second order should still be active (not expired)
        (, , , , uint64 lots2, , , , , ) = book.orders(id2);
        assertEq(lots2, 10);
    }

    function test_CancelExpiredOrder_RevertIfAlreadyCancelled() public {
        vm.prank(user1);
        uint256 orderId = book.placeOrder(marketId, Side.Bid, OrderType.GoodTilCancel, 50, 10);

        vm.warp(block.timestamp + 3601);

        vm.prank(anyone);
        book.cancelExpiredOrder(orderId);

        vm.expectRevert("OrderBook: already cancelled/filled");
        vm.prank(anyone);
        book.cancelExpiredOrder(orderId);
    }
}
