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

    function _createZeroFeeAuction() internal returns (BatchAuction) {
        vm.startPrank(admin);
        FeeModel zeroFee = new FeeModel(admin, 0, 0, 0.001 ether, 0.0001 ether, feeCollector);
        BatchAuction zeroAuction = new BatchAuction(admin, address(book), address(vault), address(zeroFee), address(token));
        book.grantRole(book.OPERATOR_ROLE(), address(zeroAuction));
        vault.grantRole(vault.PROTOCOL_ROLE(), address(zeroAuction));
        token.grantRole(token.MINTER_ROLE(), address(zeroAuction));
        vm.stopPrank();
        return zeroAuction;
    }

    function _getObId(uint256 fmId) internal view returns (uint256) {
        (, , , , , , , , uint256 obId) = factory.marketMeta(fmId);
        return obId;
    }

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

    // -------------------------------------------------------------------------
    // Order-ID array helpers
    // -------------------------------------------------------------------------

    function _noIds() internal pure returns (uint256[] memory) {
        return new uint256[](0);
    }

    function _ids(uint256 a, uint256 b) internal pure returns (uint256[] memory arr) {
        arr = new uint256[](2);
        arr[0] = a;
        arr[1] = b;
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
        BatchResult memory result = auction.clearBatch(obId, _noIds());

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
        BatchResult memory result = auction.clearBatch(obId, _noIds());

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
        auction.clearBatch(obId, _noIds());
        uint256 gasUsed = gasBefore - gasleft();
        emit log_named_uint("clearBatch gas", gasUsed);
    }

    function test_GasSnapshot_ClaimFills() public {
        uint256 fmId = _createMarket(3600);
        (, , , , , , , , uint256 obId) = factory.marketMeta(fmId);

        uint256 bid1 = _depositAndPlace(user1, obId, Side.Bid, 60, 10);
        _depositAndPlace(user2, obId, Side.Ask, 50, 10);

        vm.prank(operator);
        auction.clearBatch(obId, _noIds());

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
        auction.clearBatch(obId, _noIds());

        auction.claimFills(bid1);
        auction.claimFills(ask1);

        // Advance past batch interval (60s) before next clear
        vm.warp(block.timestamp + 60);

        // Batch 2 — new orders
        uint256 bid2 = _depositAndPlace(user1, obId, Side.Bid, 55, 5);
        uint256 ask2 = _depositAndPlace(user3, obId, Side.Ask, 45, 5);

        vm.prank(operator);
        BatchResult memory r2 = auction.clearBatch(obId, _noIds());

        assertGt(r2.matchedLots, 0);
        auction.claimFills(bid2);
        auction.claimFills(ask2);
    }

    // =========================================================================
    // NO-wins redemption
    // =========================================================================

    function test_Redemption_NOWins() public {
        BatchAuction zeroAuction = _createZeroFeeAuction();
        uint256 fmId = _createMarket(3600);
        uint256 obId = _getObId(fmId);
        (, , uint256 expiry, , , , , , ) = factory.marketMeta(fmId);

        // Place matching orders at tick 60
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

        vm.prank(operator);
        zeroAuction.clearBatch(obId, _noIds());
        zeroAuction.claimFills(bid1);
        zeroAuction.claimFills(ask1);

        assertEq(vault.marketPool(obId), 10 * LOT);
        assertEq(token.balanceOf(user2, token.noTokenId(obId)), 10);

        // Resolve with price BELOW strike → NO wins
        vm.warp(expiry);
        factory.closeMarket(fmId);

        uint64 publishTime = uint64(expiry + 10);
        bytes[] memory updateData = _createPriceUpdate(40000_00000000, 100_00000000, publishTime);
        vm.prank(user3);
        resolver.resolveMarket{value: 1}(fmId, updateData);
        vm.roll(block.number + 3);
        resolver.finalizeResolution(fmId);

        (, , , , , , bool outcomeYes, , ) = factory.marketMeta(fmId);
        assertFalse(outcomeYes, "NO should win when price < strike");

        // user2 redeems 10 NO tokens for 10 * LOT BNB
        uint256 user2BalBefore = user2.balance;
        vm.prank(user2);
        redemption.redeem(fmId, 10);

        assertEq(user2.balance - user2BalBefore, 10 * LOT);
        assertEq(vault.marketPool(obId), 0);
    }

    // =========================================================================
    // Cancelled market — both YES and NO holders get collateral back
    // =========================================================================

    function test_Redemption_CancelledMarket_NoRedemption() public {
        BatchAuction zeroAuction = _createZeroFeeAuction();
        uint256 fmId = _createMarket(3600);
        uint256 obId = _getObId(fmId);
        (, , uint256 expiry, , , , , , ) = factory.marketMeta(fmId);

        // Trade so tokens exist
        uint256 bid1 = _depositAndPlace(user1, obId, Side.Bid, 60, 5);
        uint256 ask1 = _depositAndPlace(user2, obId, Side.Ask, 60, 5);

        vm.prank(operator);
        zeroAuction.clearBatch(obId, _noIds());
        zeroAuction.claimFills(bid1);
        zeroAuction.claimFills(ask1);

        // Close + wait 24h + cancel
        vm.warp(expiry);
        factory.closeMarket(fmId);
        vm.warp(block.timestamp + 24 hours);
        factory.cancelMarket(fmId);

        assertEq(uint256(factory.getMarketState(fmId)), uint256(MarketState.Cancelled));

        // Redemption should revert on cancelled market
        vm.expectRevert("Redemption: not resolved");
        vm.prank(user1);
        redemption.redeem(fmId, 5);
    }

    // =========================================================================
    // payResolverBounty — revert on non-resolved market
    // =========================================================================

    function test_PayResolverBounty_RevertIfNotResolved() public {
        uint256 fmId = _createMarket(3600);

        // Market is Open — should revert
        vm.prank(admin);
        vm.expectRevert("MarketFactory: not resolved");
        factory.payResolverBounty(fmId, user1);

        // Close it
        (, , uint256 expiry, , , , , , ) = factory.marketMeta(fmId);
        vm.warp(expiry);
        factory.closeMarket(fmId);

        // Market is Closed — should still revert
        vm.prank(admin);
        vm.expectRevert("MarketFactory: not resolved");
        factory.payResolverBounty(fmId, user1);
    }

    // =========================================================================
    // GTC multi-batch partial fill
    // =========================================================================

    function test_GTC_MultiBatchPartialFill() public {
        BatchAuction zeroAuction = _createZeroFeeAuction();
        uint256 fmId = _createMarket(3600);
        uint256 obId = _getObId(fmId);

        // Place GTC bid for 20 lots at tick 50
        vm.prank(user1);
        vault.deposit{value: (20 * LOT * 50) / 100}();
        vm.prank(user1);
        uint256 bidId = book.placeOrder(obId, Side.Bid, OrderType.GoodTilCancel, 50, 20);

        // Batch 1: ask for 5 lots at tick 50 → partial fill (5 of 20)
        vm.prank(user2);
        vault.deposit{value: (5 * LOT * 50) / 100}();
        vm.prank(user2);
        uint256 ask1 = book.placeOrder(obId, Side.Ask, OrderType.GoodTilCancel, 50, 5);

        vm.prank(operator);
        assertEq(zeroAuction.clearBatch(obId, _noIds()).matchedLots, 5);

        zeroAuction.claimFills(bidId);
        zeroAuction.claimFills(ask1);

        // Bid should have 15 lots remaining in book
        (, , , , uint64 remainingLots, , , , ) = book.orders(bidId);
        assertEq(remainingLots, 15, "GTC order should have 15 lots remaining");
        assertEq(token.balanceOf(user1, token.yesTokenId(obId)), 5);

        // Batch 2: ask for 15 lots at tick 50 → fills remainder
        vm.warp(block.timestamp + 60);

        vm.prank(user3);
        vault.deposit{value: (15 * LOT * 50) / 100}();
        vm.prank(user3);
        uint256 ask2 = book.placeOrder(obId, Side.Ask, OrderType.GoodTilCancel, 50, 15);

        vm.prank(operator);
        assertEq(zeroAuction.clearBatch(obId, _noIds()).matchedLots, 15);

        zeroAuction.claimFills(bidId);
        zeroAuction.claimFills(ask2);

        // Bid should be fully filled now
        (, , , , uint64 finalLots, , , , ) = book.orders(bidId);
        assertEq(finalLots, 0, "GTC order should be fully filled");
        assertEq(token.balanceOf(user1, token.yesTokenId(obId)), 20);
    }

    // =========================================================================
    // PythResolver admin transfer
    // =========================================================================

    function test_PythResolver_AdminTransfer() public {
        assertEq(resolver.admin(), admin);

        // Non-admin can't set pending
        vm.prank(user1);
        vm.expectRevert("PythResolver: not admin");
        resolver.setPendingAdmin(user1);

        // Admin sets pending
        vm.prank(admin);
        resolver.setPendingAdmin(user2);
        assertEq(resolver.pendingAdmin(), user2);

        // Wrong person can't accept
        vm.prank(user1);
        vm.expectRevert("PythResolver: not pending admin");
        resolver.acceptAdmin();

        // Pending admin accepts
        vm.prank(user2);
        resolver.acceptAdmin();
        assertEq(resolver.admin(), user2);
        assertEq(resolver.pendingAdmin(), address(0));
    }

    // =========================================================================
    // PythResolver confThreshold validation
    // =========================================================================

    function test_PythResolver_ConfThresholdValidation() public {
        vm.prank(admin);
        vm.expectRevert("PythResolver: bps exceeds 10000");
        resolver.setConfThreshold(10001);

        // 10000 should be ok
        vm.prank(admin);
        resolver.setConfThreshold(10000);
        assertEq(resolver.confThresholdBps(), 10000);
    }

    // =========================================================================
    // MarketFactory minLots validation
    // =========================================================================

    function test_MarketFactory_MinLotsValidation() public {
        vm.prank(admin);
        vm.expectRevert("MarketFactory: zero minLots");
        factory.setDefaultParams(60, 0);
    }

    // =========================================================================
    // ResolverBountyPaid event
    // =========================================================================

    function test_ResolverBountyPaid_EmitsEvent() public {
        uint256 fmId = _createMarket(3600);
        (, , uint256 expiry, , , , , , ) = factory.marketMeta(fmId);

        vm.warp(expiry);
        factory.closeMarket(fmId);

        uint64 publishTime = uint64(expiry + 10);
        bytes[] memory updateData = _createPriceUpdate(50000_00000000, 100_00000000, publishTime);
        vm.prank(user2);
        resolver.resolveMarket{value: 1}(fmId, updateData);

        vm.roll(block.number + 3);

        vm.expectEmit(true, true, false, true);
        emit MarketFactory.ResolverBountyPaid(fmId, user2, 0.01 ether);

        resolver.finalizeResolution(fmId);
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
        BatchAuction zeroAuction = _createZeroFeeAuction();

        // 1. Create market
        uint256 fmId = _createMarket(3600);
        uint256 obId = _getObId(fmId);
        (, , uint256 expiry, , , , , , ) = factory.marketMeta(fmId);

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
        BatchResult memory result = zeroAuction.clearBatch(obId, _noIds());
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
