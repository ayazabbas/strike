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

contract IntegrationTest is Test {
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

    function _createZeroFeeAuction() internal returns (BatchAuction) {
        vm.startPrank(admin);
        BatchAuction za = new BatchAuction(admin, address(book), address(vault), address(token));
        book.grantRole(book.OPERATOR_ROLE(), address(za));
        vault.grantRole(vault.PROTOCOL_ROLE(), address(za));
        token.grantRole(token.MINTER_ROLE(), address(za));
        vm.stopPrank();
        return za;
    }

    function _getObId(uint256 fmId) internal view returns (uint256) {
        (, , , , , , , uint256 obId) = factory.marketMeta(fmId);
        return obId;
    }

    function _createMarket(uint256 duration) internal returns (uint256) {
        vm.prank(user1);
        return factory.createMarket(PRICE_ID, STRIKE_PRICE, block.timestamp + duration, 60, 1);
    }

    function _placeOrder(
        address user,
        uint256 obMarketId,
        Side side,
        uint256 tick,
        uint256 lots
    ) internal returns (uint256 orderId) {
        vm.prank(user);
        orderId = book.placeOrder(obMarketId, side, OrderType.GoodTilCancel, tick, lots);
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

    // =========================================================================
    // Full lifecycle
    // =========================================================================

    function test_FullLifecycle() public {
        uint256 fmId = _createMarket(3600);
        uint256 obId = _getObId(fmId);

        _placeOrder(user1, obId, Side.Bid, 60, 10);
        _placeOrder(user2, obId, Side.Ask, 50, 10);

        BatchResult memory result = auction.clearBatch(obId);

        assertGe(result.clearingTick, 50);
        assertLe(result.clearingTick, 60);
        assertGt(result.matchedLots, 0);

        (, , uint256 expiry, , , , , ) = factory.marketMeta(fmId);
        vm.warp(expiry);
        factory.closeMarket(fmId);
        assertEq(uint256(factory.getMarketState(fmId)), uint256(MarketState.Closed));

        uint64 publishTime = uint64(expiry + 10);
        bytes[] memory updateData = _createPriceUpdate(50000_00000000, 100_00000000, publishTime);

        vm.prank(user3);
        resolver.resolveMarket{value: 1}(fmId, updateData);
        assertEq(uint256(factory.getMarketState(fmId)), uint256(MarketState.Resolving));

        vm.roll(block.number + 3);
        resolver.finalizeResolution(fmId);
        assertEq(uint256(factory.getMarketState(fmId)), uint256(MarketState.Resolved));
    }

    // =========================================================================
    // Multi-user trading
    // =========================================================================

    function test_MultiUser_ThreeTraders() public {
        uint256 fmId = _createMarket(3600);
        uint256 obId = _getObId(fmId);

        _placeOrder(user1, obId, Side.Bid, 60, 10);
        _placeOrder(user2, obId, Side.Bid, 55, 5);
        _placeOrder(user3, obId, Side.Ask, 50, 8);

        BatchResult memory result = auction.clearBatch(obId);
        assertGt(result.matchedLots, 0);
    }

    // =========================================================================
    // Cancellation
    // =========================================================================

    function test_Cancellation_NoResolution() public {
        uint256 fmId = _createMarket(3600);
        (, , uint256 expiry, , , , , ) = factory.marketMeta(fmId);
        vm.warp(expiry);
        factory.closeMarket(fmId);

        vm.warp(block.timestamp + 24 hours);
        factory.cancelMarket(fmId);

        assertEq(uint256(factory.getMarketState(fmId)), uint256(MarketState.Cancelled));
    }

    // =========================================================================
    // Challenge
    // =========================================================================

    function test_Challenge_TwoResolvers() public {
        uint256 fmId = _createMarket(3600);
        (, , uint256 expiry, , , , , ) = factory.marketMeta(fmId);
        vm.warp(expiry);
        factory.closeMarket(fmId);

        uint64 pt1 = uint64(expiry + 30);
        bytes[] memory data1 = _createPriceUpdate(50000_00000000, 100_00000000, pt1);
        vm.prank(user2);
        resolver.resolveMarket{value: 1}(fmId, data1);

        uint64 pt2 = uint64(expiry + 5);
        bytes[] memory data2 = _createPriceUpdate(48000_00000000, 100_00000000, pt2);
        vm.prank(user3);
        resolver.resolveMarket{value: 1}(fmId, data2);

        (int64 price, uint256 pt, , address res, ) = resolver.pendingResolutions(fmId);
        assertEq(price, 48000_00000000);
        assertEq(pt, pt2);
        assertEq(res, user3);

        vm.roll(block.number + 3);
        resolver.finalizeResolution(fmId);
    }

    // =========================================================================
    // Redemption E2E
    // =========================================================================

    function test_Redemption_E2E() public {
        BatchAuction za = _createZeroFeeAuction();
        uint256 fmId = _createMarket(3600);
        uint256 obId = _getObId(fmId);
        (, , uint256 expiry, , , , , ) = factory.marketMeta(fmId);

        vm.prank(user1);
        book.placeOrder(obId, Side.Bid, OrderType.GoodTilCancel, 60, 10);
        vm.prank(user2);
        book.placeOrder(obId, Side.Ask, OrderType.GoodTilCancel, 60, 10);

        za.clearBatch(obId);

        assertEq(vault.marketPool(obId), 10 * LOT);
        assertEq(token.balanceOf(user1, token.yesTokenId(obId)), 10);
        assertEq(token.balanceOf(user2, token.noTokenId(obId)), 10);

        vm.warp(expiry);
        factory.closeMarket(fmId);

        uint64 publishTime = uint64(expiry + 10);
        bytes[] memory updateData = _createPriceUpdate(50000_00000000, 100_00000000, publishTime);
        vm.prank(user3);
        resolver.resolveMarket{value: 1}(fmId, updateData);

        vm.roll(block.number + 3);
        resolver.finalizeResolution(fmId);

        uint256 user1BalBefore = usdt.balanceOf(user1);
        vm.prank(user1);
        redemption.redeem(fmId, 10);

        assertEq(usdt.balanceOf(user1) - user1BalBefore, 10 * LOT);
        assertEq(vault.marketPool(obId), 0);
    }

    // =========================================================================
    // NO-wins redemption
    // =========================================================================

    function test_Redemption_NOWins() public {
        BatchAuction za = _createZeroFeeAuction();
        uint256 fmId = _createMarket(3600);
        uint256 obId = _getObId(fmId);
        (, , uint256 expiry, , , , , ) = factory.marketMeta(fmId);

        vm.prank(user1);
        book.placeOrder(obId, Side.Bid, OrderType.GoodTilCancel, 60, 10);
        vm.prank(user2);
        book.placeOrder(obId, Side.Ask, OrderType.GoodTilCancel, 60, 10);

        za.clearBatch(obId);

        assertEq(vault.marketPool(obId), 10 * LOT);
        assertEq(token.balanceOf(user2, token.noTokenId(obId)), 10);

        vm.warp(expiry);
        factory.closeMarket(fmId);

        uint64 publishTime = uint64(expiry + 10);
        bytes[] memory updateData = _createPriceUpdate(40000_00000000, 100_00000000, publishTime);
        vm.prank(user3);
        resolver.resolveMarket{value: 1}(fmId, updateData);
        vm.roll(block.number + 3);
        resolver.finalizeResolution(fmId);

        (, , , , , bool outcomeYes, , ) = factory.marketMeta(fmId);
        assertFalse(outcomeYes);

        uint256 user2BalBefore = usdt.balanceOf(user2);
        vm.prank(user2);
        redemption.redeem(fmId, 10);

        assertEq(usdt.balanceOf(user2) - user2BalBefore, 10 * LOT);
        assertEq(vault.marketPool(obId), 0);
    }

    // =========================================================================
    // Cancelled market
    // =========================================================================

    function test_Redemption_CancelledMarket_NoRedemption() public {
        BatchAuction za = _createZeroFeeAuction();
        uint256 fmId = _createMarket(3600);
        uint256 obId = _getObId(fmId);
        (, , uint256 expiry, , , , , ) = factory.marketMeta(fmId);

        vm.prank(user1);
        book.placeOrder(obId, Side.Bid, OrderType.GoodTilCancel, 60, 5);
        vm.prank(user2);
        book.placeOrder(obId, Side.Ask, OrderType.GoodTilCancel, 60, 5);

        za.clearBatch(obId);

        vm.warp(expiry);
        factory.closeMarket(fmId);
        vm.warp(block.timestamp + 24 hours);
        factory.cancelMarket(fmId);

        vm.expectRevert("Redemption: not resolved");
        vm.prank(user1);
        redemption.redeem(fmId, 5);
    }

    // =========================================================================
    // GTC multi-batch partial fill
    // =========================================================================

    function test_GTC_MultiBatchPartialFill() public {
        BatchAuction za = _createZeroFeeAuction();
        uint256 fmId = _createMarket(3600);
        uint256 obId = _getObId(fmId);

        vm.prank(user1);
        uint256 bidId = book.placeOrder(obId, Side.Bid, OrderType.GoodTilCancel, 50, 20);

        vm.prank(user2);
        book.placeOrder(obId, Side.Ask, OrderType.GoodTilCancel, 50, 5);

        assertEq(za.clearBatch(obId).matchedLots, 5);

        (, , , , uint64 remainingLots, , , , ) = book.orders(bidId);
        assertEq(remainingLots, 15);
        assertEq(token.balanceOf(user1, token.yesTokenId(obId)), 5);

        // Batch 2
        vm.prank(user3);
        book.placeOrder(obId, Side.Ask, OrderType.GoodTilCancel, 50, 15);

        assertEq(za.clearBatch(obId).matchedLots, 15);

        (, , , , uint64 finalLots, , , , ) = book.orders(bidId);
        assertEq(finalLots, 0);
        assertEq(token.balanceOf(user1, token.yesTokenId(obId)), 20);
    }

    // =========================================================================
    // Edge cases
    // =========================================================================

    function test_MarketCreation_RegistersInOrderBook() public {
        uint256 fmId = _createMarket(3600);
        uint256 obId = _getObId(fmId);
        (uint32 mId, bool active, , , , , ) = book.markets(obId);
        assertEq(mId, obId);
        assertTrue(active);
    }

    function test_CloseMarket_DeactivatesOrderBook() public {
        uint256 fmId = _createMarket(3600);
        (, , uint256 expiry, , , , , uint256 obId) = factory.marketMeta(fmId);
        vm.warp(expiry);
        factory.closeMarket(fmId);
        (, bool active, , , , , ) = book.markets(obId);
        assertFalse(active);
    }

    function test_CannotPlaceOrderAfterClose() public {
        uint256 fmId = _createMarket(3600);
        (, , uint256 expiry, , , , , uint256 obId) = factory.marketMeta(fmId);
        vm.warp(expiry);
        factory.closeMarket(fmId);

        vm.expectRevert("OrderBook: market not active");
        vm.prank(user1);
        book.placeOrder(obId, Side.Bid, OrderType.GoodTilCancel, 50, 10);
    }

    function test_CancelMarket_FromOpenState() public {
        uint256 fmId = _createMarket(3600);
        (, , uint256 expiry, , , , , ) = factory.marketMeta(fmId);
        vm.warp(expiry + 24 hours);
        factory.cancelMarket(fmId);
        assertEq(uint256(factory.getMarketState(fmId)), uint256(MarketState.Cancelled));
    }

    function test_MultipleBatches_BeforeClose() public {
        BatchAuction za = _createZeroFeeAuction();
        uint256 fmId = _createMarket(3600);
        uint256 obId = _getObId(fmId);

        _placeOrder(user1, obId, Side.Bid, 60, 10);
        _placeOrder(user2, obId, Side.Ask, 50, 10);

        za.clearBatch(obId);

        _placeOrder(user1, obId, Side.Bid, 55, 5);
        _placeOrder(user3, obId, Side.Ask, 45, 5);

        BatchResult memory r2 = za.clearBatch(obId);
        assertGt(r2.matchedLots, 0);
    }
}
