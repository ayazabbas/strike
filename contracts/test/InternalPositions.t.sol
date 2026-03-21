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
        factory.grantRole(factory.ADMIN_ROLE(), address(resolver));
        factory.grantRole(factory.MARKET_CREATOR_ROLE(), user1);
        vm.stopPrank();

        for (uint256 i = 0; i < 3; i++) {
            address u = [user1, user2, user3][i];
            usdt.mint(u, 100000 ether);
            vm.prank(u);
            usdt.approve(address(vault), type(uint256).max);
        }

        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
        vm.deal(user3, 10 ether);
    }

    // =========================================================================
    // Helpers
    // =========================================================================

    function _createInternalMarket(uint256 duration) internal returns (uint256 fmId, uint256 obId) {
        vm.prank(user1);
        fmId = factory.createMarketWithPositions(PRICE_ID, STRIKE_PRICE, block.timestamp + duration, 60, 1);
        (, , , , , , , uint256 _obId, ) = factory.marketMeta(fmId);
        obId = _obId;
    }

    function _createPriceUpdate(int64 price, uint64 conf, uint64 publishTime)
        internal
        view
        returns (bytes[] memory updateData)
    {
        updateData = new bytes[](1);
        updateData[0] = mockPyth.createPriceFeedUpdateData(
            PRICE_ID, price, conf, -8, price, conf,
            publishTime, publishTime > 0 ? publishTime - 1 : 0
        );
    }

    function _resolveMarket(uint256 fmId, int64 price) internal {
        (, , uint256 expiry, , , , , , ) = factory.marketMeta(fmId);
        vm.warp(expiry);
        factory.closeMarket(fmId);

        uint64 publishTime = uint64(expiry + 10);
        bytes[] memory updateData = _createPriceUpdate(price, 100_00000000, publishTime);

        vm.prank(user3);
        resolver.resolveMarket{value: 1}(fmId, updateData);
        vm.warp(block.timestamp + 90);
        resolver.finalizeResolution(fmId);
    }

    // =========================================================================
    // Market creation
    // =========================================================================

    function test_CreateMarketWithPositions_SetsFlag() public {
        (uint256 fmId, uint256 obId) = _createInternalMarket(3600);
        (, , , , , , , , bool useInternal) = factory.marketMeta(fmId);
        assertTrue(useInternal);
        (, , , , , , , bool obUseInternal) = book.markets(obId);
        assertTrue(obUseInternal);
    }

    function test_CreateMarket_DefaultNoInternalPositions() public {
        vm.prank(user1);
        uint256 fmId = factory.createMarket(PRICE_ID, STRIKE_PRICE, block.timestamp + 3600, 60, 1);
        (, , , , , , , , bool useInternal) = factory.marketMeta(fmId);
        assertFalse(useInternal);
    }

    // =========================================================================
    // Full lifecycle — internal positions
    // =========================================================================

    function test_InternalPositions_FullLifecycle_YesWins() public {
        (uint256 fmId, uint256 obId) = _createInternalMarket(3600);

        // user1 bids (buys YES), user2 asks (buys NO) at tick 60
        vm.prank(user1);
        book.placeOrder(obId, Side.Bid, OrderType.GoodTilCancel, 60, 10);
        vm.prank(user2);
        book.placeOrder(obId, Side.Ask, OrderType.GoodTilCancel, 60, 10);

        auction.clearBatch(obId);

        // No ERC1155 tokens should be minted
        assertEq(token.balanceOf(user1, token.yesTokenId(obId)), 0);
        assertEq(token.balanceOf(user2, token.noTokenId(obId)), 0);

        // Internal positions should be credited
        (uint128 yesLots, ) = vault.positions(user1, obId);
        (, uint128 noLots) = vault.positions(user2, obId);
        assertEq(yesLots, 10);
        assertEq(noLots, 10);

        // Resolve YES (price above strike)
        _resolveMarket(fmId, 60000_00000000);

        // Redeem
        uint256 balBefore = usdt.balanceOf(user1);
        vm.prank(user1);
        redemption.redeem(fmId, 10);

        assertEq(usdt.balanceOf(user1) - balBefore, 10 * LOT);

        // Position zeroed
        (yesLots, ) = vault.positions(user1, obId);
        assertEq(yesLots, 0);
    }

    function test_InternalPositions_FullLifecycle_NoWins() public {
        (uint256 fmId, uint256 obId) = _createInternalMarket(3600);

        vm.prank(user1);
        book.placeOrder(obId, Side.Bid, OrderType.GoodTilCancel, 60, 10);
        vm.prank(user2);
        book.placeOrder(obId, Side.Ask, OrderType.GoodTilCancel, 60, 10);

        auction.clearBatch(obId);

        // Resolve NO (price below strike)
        _resolveMarket(fmId, 40000_00000000);

        uint256 balBefore = usdt.balanceOf(user2);
        vm.prank(user2);
        redemption.redeem(fmId, 10);

        assertEq(usdt.balanceOf(user2) - balBefore, 10 * LOT);
    }

    // =========================================================================
    // Sell orders with internal positions
    // =========================================================================

    function test_InternalPositions_SellYes() public {
        (, uint256 obId) = _createInternalMarket(3600);

        // Create initial positions
        vm.prank(user1);
        book.placeOrder(obId, Side.Bid, OrderType.GoodTilCancel, 50, 10);
        vm.prank(user2);
        book.placeOrder(obId, Side.Ask, OrderType.GoodTilCancel, 50, 10);
        auction.clearBatch(obId);

        // user1 has 10 YES internal positions. Sell them.
        vm.prank(user1);
        book.placeOrder(obId, Side.SellYes, OrderType.GoodTilCancel, 50, 10);

        // user3 bids to buy
        vm.prank(user3);
        book.placeOrder(obId, Side.Bid, OrderType.GoodTilCancel, 50, 10);

        auction.clearBatch(obId);

        // user3 should now have YES positions
        (uint128 yesLots, ) = vault.positions(user3, obId);
        assertEq(yesLots, 10);

        // user1 should have 0 YES positions
        (uint128 u1Yes, ) = vault.positions(user1, obId);
        assertEq(u1Yes, 0);
    }

    function test_InternalPositions_SellNo() public {
        (, uint256 obId) = _createInternalMarket(3600);

        // Create initial positions
        vm.prank(user1);
        book.placeOrder(obId, Side.Bid, OrderType.GoodTilCancel, 50, 10);
        vm.prank(user2);
        book.placeOrder(obId, Side.Ask, OrderType.GoodTilCancel, 50, 10);
        auction.clearBatch(obId);

        // user2 has 10 NO internal positions. Sell them.
        vm.prank(user2);
        book.placeOrder(obId, Side.SellNo, OrderType.GoodTilCancel, 50, 10);

        // user3 asks to buy NO
        vm.prank(user3);
        book.placeOrder(obId, Side.Ask, OrderType.GoodTilCancel, 50, 10);

        auction.clearBatch(obId);

        // user3 should now have NO positions
        (, uint128 noLots) = vault.positions(user3, obId);
        assertEq(noLots, 10);

        // user2 should have 0 NO positions
        (, uint128 u2No) = vault.positions(user2, obId);
        assertEq(u2No, 0);
    }

    // =========================================================================
    // Cancel sell order returns position
    // =========================================================================

    function test_InternalPositions_CancelSellOrder() public {
        (, uint256 obId) = _createInternalMarket(3600);

        // Create initial positions
        vm.prank(user1);
        book.placeOrder(obId, Side.Bid, OrderType.GoodTilCancel, 50, 10);
        vm.prank(user2);
        book.placeOrder(obId, Side.Ask, OrderType.GoodTilCancel, 50, 10);
        auction.clearBatch(obId);

        // user1 sells YES
        vm.prank(user1);
        uint256 sellOrderId = book.placeOrder(obId, Side.SellYes, OrderType.GoodTilCancel, 50, 5);

        // Position should be partially locked
        (uint128 yesLots, ) = vault.positions(user1, obId);
        assertEq(yesLots, 5); // 10 - 5 locked

        // Cancel
        vm.prank(user1);
        book.cancelOrder(sellOrderId);

        // Position should be restored
        (yesLots, ) = vault.positions(user1, obId);
        assertEq(yesLots, 10);
    }

    // =========================================================================
    // Pool solvency with internal positions
    // =========================================================================

    function test_InternalPositions_PoolSolvency() public {
        (uint256 fmId, uint256 obId) = _createInternalMarket(3600);

        // Create positions
        vm.prank(user1);
        book.placeOrder(obId, Side.Bid, OrderType.GoodTilCancel, 50, 10);
        vm.prank(user2);
        book.placeOrder(obId, Side.Ask, OrderType.GoodTilCancel, 50, 10);
        auction.clearBatch(obId);

        uint256 poolBal = vault.marketPool(obId);
        assertEq(poolBal, 10 * LOT);

        // Resolve YES
        _resolveMarket(fmId, 60000_00000000);

        // Redeem all
        vm.prank(user1);
        redemption.redeem(fmId, 10);

        assertEq(vault.marketPool(obId), 0);
    }
}
