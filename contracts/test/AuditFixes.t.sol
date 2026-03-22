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
}
