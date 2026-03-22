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
}
