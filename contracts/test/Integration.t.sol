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

contract IntegrationTest is Test {
    // Contracts
    MarketFactory public factory;
    PythResolver public resolver;
    OrderBook public book;
    BatchAuction public auction;
    OutcomeToken public token;
    Vault public vault;
    FeeModel public feeModel;
    Redemption public redemption;
    MockPyth public mockPyth;

    // Actors
    address public admin = address(0x1);
    address public operator = address(0x2);
    address public user1 = address(0x3);
    address public user2 = address(0x4);
    address public user3 = address(0x5);
    address public feeCollector = address(0x99);

    bytes32 public constant PRICE_ID = bytes32(uint256(0xB7C));
    int64 public constant STRIKE_PRICE = int64(50000_00000000);
    uint256 public constant LOT = 1e15;

    function setUp() public {
        vm.startPrank(admin);

        // Deploy core
        vault = new Vault(admin);
        token = new OutcomeToken(admin);
        feeModel = new FeeModel(admin, 30, 10, 0.001 ether, 0.0001 ether, feeCollector);
        book = new OrderBook(admin, address(vault));
        auction = new BatchAuction(admin, address(book), address(vault), address(feeModel), address(token));

        // 120s valid period, 1 wei fee per update
        mockPyth = new MockPyth(120, 1);

        factory = new MarketFactory(admin, address(book), address(token), feeCollector);
        resolver = new PythResolver(address(mockPyth), address(factory));
        redemption = new Redemption(address(factory), address(token), address(vault));

        // Grant roles
        book.grantRole(book.OPERATOR_ROLE(), operator);
        book.grantRole(book.OPERATOR_ROLE(), address(auction));
        book.grantRole(book.OPERATOR_ROLE(), address(factory));
        vault.grantRole(vault.PROTOCOL_ROLE(), address(book));
        vault.grantRole(vault.PROTOCOL_ROLE(), address(auction));
        vault.grantRole(vault.PROTOCOL_ROLE(), address(redemption));
        token.grantRole(token.MINTER_ROLE(), address(auction));
        token.grantRole(token.MINTER_ROLE(), address(redemption));
        // PythResolver needs ADMIN_ROLE to call setResolving/setResolved/payResolverBounty
        factory.grantRole(factory.ADMIN_ROLE(), address(resolver));

        vm.stopPrank();

        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        vm.deal(user3, 100 ether);
    }

    // =========================================================================
    // Helpers
    // =========================================================================

    function _createMarket(uint256 duration) internal returns (uint256) {
        vm.prank(user1);
        return factory.createMarket{value: 0.01 ether}(PRICE_ID, STRIKE_PRICE, duration, 60, 1);
    }

    function _depositAndPlace(
        address user,
        uint256 obMarketId,
        Side side,
        uint256 tick,
        uint256 lots
    ) internal returns (uint256 orderId) {
        uint256 collateral;
        if (side == Side.Bid) {
            collateral = (lots * LOT * tick) / 100;
        } else {
            collateral = (lots * LOT * (100 - tick)) / 100;
        }

        vm.prank(user);
        vault.deposit{value: collateral}();

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
            PRICE_ID,
            price,
            conf,
            -8,           // expo
            price,        // emaPrice
            conf,         // emaConf
            publishTime,
            publishTime > 0 ? publishTime - 1 : 0
        );
    }

    // =========================================================================
    // Full lifecycle: create → trade → clear → close → resolve → redeem
    // =========================================================================

    function test_FullLifecycle() public {
        // 1. Create market
        uint256 fmId = _createMarket(3600);
        (, , , , , , , , uint256 obId) = factory.marketMeta(fmId);

        // 2. Place orders: user1 bids at 60, user2 asks at 50
        uint256 bid1 = _depositAndPlace(user1, obId, Side.Bid, 60, 10);
        uint256 ask1 = _depositAndPlace(user2, obId, Side.Ask, 50, 10);

        // 3. Clear batch
        vm.prank(operator);
        BatchResult memory result = auction.clearBatch(obId);

        // Should match at a tick between 50-60
        assertGe(result.clearingTick, 50);
        assertLe(result.clearingTick, 60);
        assertGt(result.matchedLots, 0);

        // 4. Claim fills
        auction.claimFills(bid1);
        auction.claimFills(ask1);

        // 5. Close market
        (, , uint256 expiry, , , , , , ) = factory.marketMeta(fmId);
        vm.warp(expiry);
        factory.closeMarket(fmId);
        assertEq(uint256(factory.getMarketState(fmId)), uint256(MarketState.Closed));

        // 6. Resolve market
        uint64 publishTime = uint64(expiry + 10);
        bytes[] memory updateData = _createPriceUpdate(50000_00000000, 100_00000000, publishTime);

        vm.prank(user3);
        resolver.resolveMarket{value: 1}(fmId, updateData);
        assertEq(uint256(factory.getMarketState(fmId)), uint256(MarketState.Resolving));

        // 7. Finalize after 3 blocks
        vm.roll(block.number + 3);
        resolver.finalizeResolution(fmId);
        assertEq(uint256(factory.getMarketState(fmId)), uint256(MarketState.Resolved));
    }

    // =========================================================================
    // Multi-user trading
    // =========================================================================

    function test_MultiUser_ThreeTraders() public {
        uint256 fmId = _createMarket(3600);
        (, , , , , , , , uint256 obId) = factory.marketMeta(fmId);

        // user1 bids at 60 (10 lots)
        uint256 bid1 = _depositAndPlace(user1, obId, Side.Bid, 60, 10);
        // user2 bids at 55 (5 lots)
        uint256 bid2 = _depositAndPlace(user2, obId, Side.Bid, 55, 5);
        // user3 asks at 50 (8 lots)
        uint256 ask1 = _depositAndPlace(user3, obId, Side.Ask, 50, 8);

        // Clear batch
        vm.prank(operator);
        BatchResult memory result = auction.clearBatch(obId);

        assertGt(result.matchedLots, 0);

        // All users claim fills
        auction.claimFills(bid1);
        auction.claimFills(bid2);
        auction.claimFills(ask1);
    }

    // =========================================================================
    // Cancellation: no resolution in 24h → refunds
    // =========================================================================

    function test_Cancellation_NoResolution() public {
        uint256 fmId = _createMarket(3600);

        // Close market
        (, , uint256 expiry, , , , , , ) = factory.marketMeta(fmId);
        vm.warp(expiry);
        factory.closeMarket(fmId);

        // Wait 24h without resolution
        vm.warp(block.timestamp + 24 hours);

        uint256 creatorBalBefore = user1.balance;
        factory.cancelMarket(fmId);

        assertEq(uint256(factory.getMarketState(fmId)), uint256(MarketState.Cancelled));
        // Bond returned
        assertEq(user1.balance, creatorBalBefore + 0.01 ether);
    }

    // =========================================================================
    // Challenge: two resolvers, earliest publishTime wins
    // =========================================================================

    function test_Challenge_TwoResolvers() public {
        uint256 fmId = _createMarket(3600);

        (, , uint256 expiry, , , , , , ) = factory.marketMeta(fmId);
        vm.warp(expiry);
        factory.closeMarket(fmId);

        // Resolver1 submits at publishTime = expiry + 30
        uint64 pt1 = uint64(expiry + 30);
        bytes[] memory data1 = _createPriceUpdate(50000_00000000, 100_00000000, pt1);
        vm.prank(user2);
        resolver.resolveMarket{value: 1}(fmId, data1);

        // Resolver2 challenges with earlier publishTime = expiry + 5
        uint64 pt2 = uint64(expiry + 5);
        bytes[] memory data2 = _createPriceUpdate(48000_00000000, 100_00000000, pt2);
        vm.prank(user3);
        resolver.resolveMarket{value: 1}(fmId, data2);

        // Verify challenger won
        (int64 price, uint256 pt, , address res, ) = resolver.pendingResolutions(fmId);
        assertEq(price, 48000_00000000);
        assertEq(pt, pt2);
        assertEq(res, user3);

        // Finalize — bounty goes to challenger
        vm.roll(block.number + 3);
        uint256 user3BalBefore = user3.balance;
        resolver.finalizeResolution(fmId);
        assertEq(user3.balance, user3BalBefore + 0.01 ether);
    }

    // =========================================================================
    // Gas snapshots
    // =========================================================================

    function test_GasSnapshot_PlaceOrder() public {
        uint256 fmId = _createMarket(3600);
        (, , , , , , , , uint256 obId) = factory.marketMeta(fmId);

        uint256 collateral = (10 * LOT * 50) / 100;
        vm.prank(user1);
        vault.deposit{value: collateral}();

        vm.prank(user1);
        uint256 gasBefore = gasleft();
        book.placeOrder(obId, Side.Bid, OrderType.GoodTilCancel, 50, 10);
        uint256 gasUsed = gasBefore - gasleft();
        emit log_named_uint("placeOrder gas", gasUsed);
    }

    function test_GasSnapshot_CancelOrder() public {
        uint256 fmId = _createMarket(3600);
        (, , , , , , , , uint256 obId) = factory.marketMeta(fmId);

        uint256 orderId = _depositAndPlace(user1, obId, Side.Bid, 50, 10);

        vm.prank(user1);
        uint256 gasBefore = gasleft();
        book.cancelOrder(orderId);
        uint256 gasUsed = gasBefore - gasleft();
        emit log_named_uint("cancelOrder gas", gasUsed);
    }

    function test_GasSnapshot_ClearBatch() public {
        uint256 fmId = _createMarket(3600);
        (, , , , , , , , uint256 obId) = factory.marketMeta(fmId);

        _depositAndPlace(user1, obId, Side.Bid, 60, 10);
        _depositAndPlace(user2, obId, Side.Ask, 50, 10);

        vm.prank(operator);
        uint256 gasBefore = gasleft();
        auction.clearBatch(obId);
        uint256 gasUsed = gasBefore - gasleft();
        emit log_named_uint("clearBatch gas", gasUsed);
    }

    function test_GasSnapshot_ClaimFills() public {
        uint256 fmId = _createMarket(3600);
        (, , , , , , , , uint256 obId) = factory.marketMeta(fmId);

        uint256 bid1 = _depositAndPlace(user1, obId, Side.Bid, 60, 10);
        _depositAndPlace(user2, obId, Side.Ask, 50, 10);

        vm.prank(operator);
        auction.clearBatch(obId);

        uint256 gasBefore = gasleft();
        auction.claimFills(bid1);
        uint256 gasUsed = gasBefore - gasleft();
        emit log_named_uint("claimFills gas", gasUsed);
    }

    function test_GasSnapshot_ResolveMarket() public {
        uint256 fmId = _createMarket(3600);

        (, , uint256 expiry, , , , , , ) = factory.marketMeta(fmId);
        vm.warp(expiry);
        factory.closeMarket(fmId);

        uint64 publishTime = uint64(expiry + 10);
        bytes[] memory updateData = _createPriceUpdate(50000_00000000, 100_00000000, publishTime);

        vm.prank(user1);
        uint256 gasBefore = gasleft();
        resolver.resolveMarket{value: 1}(fmId, updateData);
        uint256 gasUsed = gasBefore - gasleft();
        emit log_named_uint("resolveMarket gas", gasUsed);
    }

    // =========================================================================
    // Edge cases
    // =========================================================================

    function test_MarketCreation_RegistersInOrderBook() public {
        uint256 fmId = _createMarket(3600);
        (, , , , , , , , uint256 obId) = factory.marketMeta(fmId);

        (uint32 mId, bool active, , , , , ) = book.markets(obId);
        assertEq(mId, obId);
        assertTrue(active);
    }

    function test_CloseMarket_DeactivatesOrderBook() public {
        uint256 fmId = _createMarket(3600);
        (, , uint256 expiry, , , , , , uint256 obId) = factory.marketMeta(fmId);

        vm.warp(expiry);
        factory.closeMarket(fmId);

        (, bool active, , , , , ) = book.markets(obId);
        assertFalse(active);
    }

    function test_CannotPlaceOrderAfterClose() public {
        uint256 fmId = _createMarket(3600);
        (, , uint256 expiry, , , , , , uint256 obId) = factory.marketMeta(fmId);

        vm.warp(expiry);
        factory.closeMarket(fmId);

        uint256 collateral = (10 * LOT * 50) / 100;
        vm.prank(user1);
        vault.deposit{value: collateral}();

        vm.expectRevert("OrderBook: market not active");
        vm.prank(user1);
        book.placeOrder(obId, Side.Bid, OrderType.GoodTilCancel, 50, 10);
    }

    function test_CancelMarket_FromOpenState() public {
        uint256 fmId = _createMarket(3600);
        (, , uint256 expiry, , , , , , ) = factory.marketMeta(fmId);

        // Wait past expiry + 24h without closing
        vm.warp(expiry + 24 hours);

        uint256 balBefore = user1.balance;
        factory.cancelMarket(fmId);

        assertEq(uint256(factory.getMarketState(fmId)), uint256(MarketState.Cancelled));
        assertEq(user1.balance, balBefore + 0.01 ether);
    }

    function test_MultipleBatches_BeforeClose() public {
        uint256 fmId = _createMarket(3600);
        (, , , , , , , , uint256 obId) = factory.marketMeta(fmId);

        // Batch 1
        uint256 bid1 = _depositAndPlace(user1, obId, Side.Bid, 60, 10);
        uint256 ask1 = _depositAndPlace(user2, obId, Side.Ask, 50, 10);

        vm.prank(operator);
        auction.clearBatch(obId);

        auction.claimFills(bid1);
        auction.claimFills(ask1);

        // Advance past batch interval (60s) before next clear
        vm.warp(block.timestamp + 60);

        // Batch 2 — new orders
        uint256 bid2 = _depositAndPlace(user1, obId, Side.Bid, 55, 5);
        uint256 ask2 = _depositAndPlace(user3, obId, Side.Ask, 45, 5);

        vm.prank(operator);
        BatchResult memory r2 = auction.clearBatch(obId);

        assertGt(r2.matchedLots, 0);
        auction.claimFills(bid2);
        auction.claimFills(ask2);
    }

    // =========================================================================
    // PythResolver role — resolution fails without ADMIN_ROLE
    // =========================================================================

    function test_PythResolver_FailsWithoutAdminRole() public {
        // Deploy a resolver without granting ADMIN_ROLE on factory
        PythResolver badResolver = new PythResolver(address(mockPyth), address(factory));

        uint256 fmId = _createMarket(3600);
        (, , uint256 expiry, , , , , , ) = factory.marketMeta(fmId);
        vm.warp(expiry);
        factory.closeMarket(fmId);

        uint64 publishTime = uint64(expiry + 10);
        bytes[] memory updateData = _createPriceUpdate(50000_00000000, 100_00000000, publishTime);

        // Should revert because badResolver doesn't have ADMIN_ROLE on factory
        vm.expectRevert();
        vm.prank(user1);
        badResolver.resolveMarket{value: 1}(fmId, updateData);
    }

    // =========================================================================
    // Redemption e2e: create → trade → clear → claim → resolve → redeem
    // =========================================================================

    function test_Redemption_E2E() public {
        // Use a zero-fee model for clean redemption math
        vm.startPrank(admin);
        FeeModel zeroFee = new FeeModel(admin, 0, 0, 0.001 ether, 0.0001 ether, feeCollector);
        BatchAuction zeroAuction = new BatchAuction(admin, address(book), address(vault), address(zeroFee), address(token));
        book.grantRole(book.OPERATOR_ROLE(), address(zeroAuction));
        vault.grantRole(vault.PROTOCOL_ROLE(), address(zeroAuction));
        token.grantRole(token.MINTER_ROLE(), address(zeroAuction));
        vm.stopPrank();

        // 1. Create market
        uint256 fmId = _createMarket(3600);
        (, , uint256 expiry, , , , , , uint256 obId) = factory.marketMeta(fmId);

        // 2. Place matching orders at tick 60
        uint256 bidCollateral = (10 * LOT * 60) / 100;
        uint256 askCollateral = (10 * LOT * 40) / 100;

        vm.prank(user1);
        vault.deposit{value: bidCollateral}();
        vm.prank(user1);
        uint256 bid1 = book.placeOrder(obId, Side.Bid, OrderType.GoodTilCancel, 60, 10);

        vm.prank(user2);
        vault.deposit{value: askCollateral}();
        vm.prank(user2);
        uint256 ask1 = book.placeOrder(obId, Side.Ask, OrderType.GoodTilCancel, 60, 10);

        // 3. Clear batch
        vm.prank(operator);
        BatchResult memory result = zeroAuction.clearBatch(obId);
        assertEq(result.matchedLots, 10);

        // 4. Claim fills — tokens minted, collateral to pool
        zeroAuction.claimFills(bid1);
        zeroAuction.claimFills(ask1);

        // With zero fees: pool = bidCollateral + askCollateral = 10 * LOT
        assertEq(vault.marketPool(obId), 10 * LOT);

        // user1 has 10 YES tokens, user2 has 10 NO tokens
        assertEq(token.balanceOf(user1, token.yesTokenId(obId)), 10);
        assertEq(token.balanceOf(user2, token.noTokenId(obId)), 10);

        // 5. Close and resolve market (YES wins with positive price)
        vm.warp(expiry);
        factory.closeMarket(fmId);

        uint64 publishTime = uint64(expiry + 10);
        bytes[] memory updateData = _createPriceUpdate(50000_00000000, 100_00000000, publishTime);
        vm.prank(user3);
        resolver.resolveMarket{value: 1}(fmId, updateData);

        vm.roll(block.number + 3);
        resolver.finalizeResolution(fmId);
        assertEq(uint256(factory.getMarketState(fmId)), uint256(MarketState.Resolved));

        // 6. Redeem — user1 redeems 10 YES tokens for 10 * LOT_SIZE BNB
        uint256 user1BalBefore = user1.balance;
        vm.prank(user1);
        redemption.redeem(fmId, 10);

        uint256 expectedPayout = 10 * LOT;
        assertEq(user1.balance - user1BalBefore, expectedPayout);
        assertEq(vault.marketPool(obId), 0);
    }
}
