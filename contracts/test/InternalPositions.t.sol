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

contract InternalPositionsTest is Test {
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
        feeModel = new FeeModel(admin, 0, admin); // zero fee for simplicity
        book = new OrderBook(admin, address(vault), address(feeModel), address(token));
        auction = new BatchAuction(admin, address(book), address(vault), address(token));

        mockPyth = new MockPyth(120, 1);
        factory = new MarketFactory(admin, address(book), address(token));
        resolver = new PythResolver(address(mockPyth), address(factory));
        redemption = new Redemption(address(factory), address(token), address(vault));

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

        address[3] memory users = [user1, user2, user3];
        for (uint256 i = 0; i < 3; i++) {
            usdt.mint(users[i], 100000 ether);
            vm.prank(users[i]);
            usdt.approve(address(vault), type(uint256).max);
            vm.deal(users[i], 10 ether);
        }
    }

    function _createInternalMarket(uint256 duration) internal returns (uint256 fmId, uint256 obId) {
        vm.prank(user1);
        fmId = factory.createMarketWithPositions(PRICE_ID, STRIKE_PRICE, block.timestamp + duration, 60, 1);
        (, , , , , , , uint256 _obId, ) = factory.marketMeta(fmId);
        obId = _obId;
    }

    function _resolveMarket(uint256 fmId, int64 price) internal {
        (, , uint256 expiry, , , , , , ) = factory.marketMeta(fmId);
        vm.warp(expiry);
        factory.closeMarket(fmId);

        uint64 publishTime = uint64(expiry + 10);
        bytes[] memory updateData = new bytes[](1);
        updateData[0] = mockPyth.createPriceFeedUpdateData(
            PRICE_ID, price, 100_00000000, -8, price, 100_00000000,
            publishTime, publishTime - 1
        );
        vm.prank(user3);
        resolver.resolveMarket{value: 1}(fmId, updateData);
        vm.warp(block.timestamp + 90);
        resolver.finalizeResolution(fmId);
    }

    // =========================================================================
    // Basic buy + fill → positions credited (no ERC1155)
    // =========================================================================

    function test_InternalPositions_BuyFill() public {
        (uint256 fmId, uint256 obId) = _createInternalMarket(3600);

        // user1 buys YES at tick 60, user2 buys NO at tick 60
        vm.prank(user1);
        book.placeOrder(obId, Side.Bid, OrderType.GoodTilCancel, 60, 10);
        vm.prank(user2);
        book.placeOrder(obId, Side.Ask, OrderType.GoodTilCancel, 60, 10);

        auction.clearBatch(obId);

        // No ERC1155 tokens minted
        assertEq(token.balanceOf(user1, token.yesTokenId(obId)), 0);
        assertEq(token.balanceOf(user2, token.noTokenId(obId)), 0);

        // Internal positions credited
        (uint128 y1, uint128 n1) = vault.positions(user1, obId);
        assertEq(y1, 10);
        assertEq(n1, 0);

        (uint128 y2, uint128 n2) = vault.positions(user2, obId);
        assertEq(y2, 0);
        assertEq(n2, 10);

        // Pool has correct balance
        assertEq(vault.marketPool(obId), 10 * LOT);
    }

    // =========================================================================
    // Sell via internal positions
    // =========================================================================

    function test_InternalPositions_SellYes() public {
        (uint256 fmId, uint256 obId) = _createInternalMarket(3600);

        // Step 1: Create positions via matching
        vm.prank(user1);
        book.placeOrder(obId, Side.Bid, OrderType.GoodTilCancel, 50, 10);
        vm.prank(user2);
        book.placeOrder(obId, Side.Ask, OrderType.GoodTilCancel, 50, 10);
        auction.clearBatch(obId);

        (uint128 y1, ) = vault.positions(user1, obId);
        assertEq(y1, 10);

        // Step 2: user1 sells YES tokens
        vm.prank(user1);
        book.placeOrder(obId, Side.SellYes, OrderType.GoodTilCancel, 50, 5);

        // Positions should be locked
        (uint128 y1After, ) = vault.positions(user1, obId);
        assertEq(y1After, 5); // 10 - 5 locked
        (uint128 ly1, ) = vault.lockedPositions(user1, obId);
        assertEq(ly1, 5);

        // Step 3: user3 buys YES (counterparty to sell)
        vm.prank(user3);
        book.placeOrder(obId, Side.Bid, OrderType.GoodTilCancel, 50, 5);
        auction.clearBatch(obId);

        // user1's locked positions consumed, user3 gets YES positions
        (uint128 ly1After, ) = vault.lockedPositions(user1, obId);
        assertEq(ly1After, 0);

        (uint128 y3, ) = vault.positions(user3, obId);
        assertEq(y3, 5);
    }

    // =========================================================================
    // Redemption with internal positions
    // =========================================================================

    function test_InternalPositions_Redeem_YesWins() public {
        (uint256 fmId, uint256 obId) = _createInternalMarket(3600);

        vm.prank(user1);
        book.placeOrder(obId, Side.Bid, OrderType.GoodTilCancel, 60, 10);
        vm.prank(user2);
        book.placeOrder(obId, Side.Ask, OrderType.GoodTilCancel, 60, 10);
        auction.clearBatch(obId);

        // Resolve YES wins
        _resolveMarket(fmId, 60000_00000000);

        uint256 balBefore = usdt.balanceOf(user1);
        vm.prank(user1);
        redemption.redeem(fmId, 10);

        assertEq(usdt.balanceOf(user1) - balBefore, 10 * LOT);

        // Positions zeroed
        (uint128 y1, ) = vault.positions(user1, obId);
        assertEq(y1, 0);
    }

    function test_InternalPositions_Redeem_NoWins() public {
        (uint256 fmId, uint256 obId) = _createInternalMarket(3600);

        vm.prank(user1);
        book.placeOrder(obId, Side.Bid, OrderType.GoodTilCancel, 60, 10);
        vm.prank(user2);
        book.placeOrder(obId, Side.Ask, OrderType.GoodTilCancel, 60, 10);
        auction.clearBatch(obId);

        // Resolve NO wins
        _resolveMarket(fmId, 40000_00000000);

        uint256 balBefore = usdt.balanceOf(user2);
        vm.prank(user2);
        redemption.redeem(fmId, 10);

        assertEq(usdt.balanceOf(user2) - balBefore, 10 * LOT);

        // Positions zeroed
        (, uint128 n2) = vault.positions(user2, obId);
        assertEq(n2, 0);
    }

    // =========================================================================
    // Cancel sell order returns positions
    // =========================================================================

    function test_InternalPositions_CancelSell() public {
        (uint256 fmId, uint256 obId) = _createInternalMarket(3600);

        // Create positions
        vm.prank(user1);
        book.placeOrder(obId, Side.Bid, OrderType.GoodTilCancel, 50, 10);
        vm.prank(user2);
        book.placeOrder(obId, Side.Ask, OrderType.GoodTilCancel, 50, 10);
        auction.clearBatch(obId);

        // Place sell order
        vm.prank(user1);
        uint256 sellOrderId = book.placeOrder(obId, Side.SellYes, OrderType.GoodTilCancel, 50, 5);

        (uint128 y1, ) = vault.positions(user1, obId);
        assertEq(y1, 5); // 5 locked

        // Cancel
        vm.prank(user1);
        book.cancelOrder(sellOrderId);

        // Positions returned
        (uint128 y1After, ) = vault.positions(user1, obId);
        assertEq(y1After, 10);
        (uint128 ly1, ) = vault.lockedPositions(user1, obId);
        assertEq(ly1, 0);
    }

    // =========================================================================
    // ERC1155 markets still work (backwards compat)
    // =========================================================================

    function test_ERC1155Market_StillWorks() public {
        // Use createMarket (not createMarketWithPositions) → ERC1155 mode
        vm.prank(user1);
        uint256 fmId = factory.createMarket(PRICE_ID, STRIKE_PRICE, block.timestamp + 3600, 60, 1);
        (, , , , , , , uint256 obId, ) = factory.marketMeta(fmId);

        vm.prank(user1);
        book.placeOrder(obId, Side.Bid, OrderType.GoodTilCancel, 60, 10);
        vm.prank(user2);
        book.placeOrder(obId, Side.Ask, OrderType.GoodTilCancel, 60, 10);

        auction.clearBatch(obId);

        // ERC1155 tokens minted
        assertEq(token.balanceOf(user1, token.yesTokenId(obId)), 10);
        assertEq(token.balanceOf(user2, token.noTokenId(obId)), 10);

        // No internal positions
        (uint128 y1, uint128 n1) = vault.positions(user1, obId);
        assertEq(y1, 0);
        assertEq(n1, 0);
    }

    // =========================================================================
    // Pool solvency with internal positions
    // =========================================================================

    function test_InternalPositions_PoolSolvency() public {
        (uint256 fmId, uint256 obId) = _createInternalMarket(3600);

        vm.prank(user1);
        book.placeOrder(obId, Side.Bid, OrderType.GoodTilCancel, 60, 10);
        vm.prank(user2);
        book.placeOrder(obId, Side.Ask, OrderType.GoodTilCancel, 60, 10);
        auction.clearBatch(obId);

        uint256 pool = vault.marketPool(obId);
        assertEq(pool, 10 * LOT);

        // Resolve and redeem all
        _resolveMarket(fmId, 60000_00000000);

        vm.prank(user1);
        redemption.redeem(fmId, 10);

        assertEq(vault.marketPool(obId), 0);
    }
}
