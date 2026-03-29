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

contract SellOrdersTest is Test {
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
    address public user1 = address(0x3); // seller
    address public user2 = address(0x4); // buyer
    address public user3 = address(0x5); // counterparty
    address public feeCollector = address(0x99);

    bytes32 public constant PRICE_ID = bytes32(uint256(0xB7C));
    int64 public constant STRIKE_PRICE = int64(50000_00000000);
    uint256 public constant LOT = 1e16;

    function setUp() public {
        usdt = new MockUSDT();

        vm.startPrank(admin);
        vault = new Vault(admin, address(usdt));
        token = new OutcomeToken(admin);
        // Zero-fee model for clean accounting in tests
        feeModel = new FeeModel(admin, 0, feeCollector);
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

        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
        vm.deal(user3, 10 ether);
    }

    // =========================================================================
    // Helpers
    // =========================================================================

    function _createMarket(uint256 duration) internal returns (uint256 fmId, uint256 obId) {
        vm.prank(user1);
        fmId = factory.createMarket(PRICE_ID, STRIKE_PRICE, block.timestamp + duration, 60, 1);
        (, , , , , , , uint256 _obId, , ) = factory.marketMeta(fmId);
        obId = _obId;
    }

    /// @dev Create a matching bid+ask at same tick to generate tokens for user.
    ///      Returns: user1 gets YES tokens, user3 gets NO tokens.
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
    // Placement tests
    // =========================================================================

    function test_PlaceSellYesOrder_locksTokens() public {
        (uint256 fmId, uint256 obId) = _createMarket(3600);
        _mintTokensViaMatch(obId, 60, 10);

        // user1 now has 10 YES tokens
        uint256 yesId = token.yesTokenId(obId);
        assertEq(token.balanceOf(user1, yesId), 10);

        // Approve OrderBook and place sell YES
        _approveTokensForOrderBook(user1);
        vm.prank(user1);
        uint256 orderId = book.placeOrder(obId, Side.SellYes, OrderType.GoodTilCancel, 60, 10);

        // Tokens transferred from user1 to OrderBook
        assertEq(token.balanceOf(user1, yesId), 0);
        assertEq(token.balanceOf(address(book), yesId), 10);

        // Order exists
        (address owner, Side side, , , uint64 lots, , , , , ) = book.orders(orderId);
        assertEq(owner, user1);
        assertEq(uint8(side), uint8(Side.SellYes));
        assertEq(lots, 10);
    }

    function test_PlaceSellNoOrder_locksTokens() public {
        (uint256 fmId, uint256 obId) = _createMarket(3600);
        _mintTokensViaMatch(obId, 60, 10);

        // user3 now has 10 NO tokens
        uint256 noId = token.noTokenId(obId);
        assertEq(token.balanceOf(user3, noId), 10);

        _approveTokensForOrderBook(user3);
        vm.prank(user3);
        uint256 orderId = book.placeOrder(obId, Side.SellNo, OrderType.GoodTilCancel, 60, 10);

        assertEq(token.balanceOf(user3, noId), 0);
        assertEq(token.balanceOf(address(book), noId), 10);

        (address owner, Side side, , , uint64 lots, , , , , ) = book.orders(orderId);
        assertEq(owner, user3);
        assertEq(uint8(side), uint8(Side.SellNo));
        assertEq(lots, 10);
    }

    function test_SellYes_RevertOnInsufficientTokenBalance() public {
        (uint256 fmId, uint256 obId) = _createMarket(3600);
        // user2 has no YES tokens
        _approveTokensForOrderBook(user2);
        vm.expectRevert();
        vm.prank(user2);
        book.placeOrder(obId, Side.SellYes, OrderType.GoodTilCancel, 50, 10);
    }

    // =========================================================================
    // Cancellation tests
    // =========================================================================

    function test_CancelSellYesOrder_returnsTokens() public {
        (uint256 fmId, uint256 obId) = _createMarket(3600);
        _mintTokensViaMatch(obId, 60, 10);

        uint256 yesId = token.yesTokenId(obId);
        _approveTokensForOrderBook(user1);
        vm.prank(user1);
        uint256 orderId = book.placeOrder(obId, Side.SellYes, OrderType.GoodTilCancel, 60, 10);
        assertEq(token.balanceOf(user1, yesId), 0);

        vm.prank(user1);
        book.cancelOrder(orderId);

        assertEq(token.balanceOf(user1, yesId), 10);
        assertEq(token.balanceOf(address(book), yesId), 0);
    }

    function test_CancelSellNoOrder_returnsTokens() public {
        (uint256 fmId, uint256 obId) = _createMarket(3600);
        _mintTokensViaMatch(obId, 60, 10);

        uint256 noId = token.noTokenId(obId);
        _approveTokensForOrderBook(user3);
        vm.prank(user3);
        uint256 orderId = book.placeOrder(obId, Side.SellNo, OrderType.GoodTilCancel, 60, 10);
        assertEq(token.balanceOf(user3, noId), 0);

        vm.prank(user3);
        book.cancelOrder(orderId);

        assertEq(token.balanceOf(user3, noId), 10);
    }

    function test_BatchCancelSellOrders_returnsTokens() public {
        (uint256 fmId, uint256 obId) = _createMarket(3600);
        _mintTokensViaMatch(obId, 60, 20);

        uint256 yesId = token.yesTokenId(obId);
        _approveTokensForOrderBook(user1);

        vm.startPrank(user1);
        uint256 oid1 = book.placeOrder(obId, Side.SellYes, OrderType.GoodTilCancel, 50, 10);
        uint256 oid2 = book.placeOrder(obId, Side.SellYes, OrderType.GoodTilCancel, 60, 10);

        uint256[] memory ids = new uint256[](2);
        ids[0] = oid1;
        ids[1] = oid2;
        book.cancelOrders(ids);
        vm.stopPrank();

        assertEq(token.balanceOf(user1, yesId), 20);
    }

    // =========================================================================
    // Settlement tests — SellYes vs Bid
    // =========================================================================

    function test_ClearBatch_SellYes_vs_Bid() public {
        (uint256 fmId, uint256 obId) = _createMarket(3600);
        // Generate 10 YES tokens for user1
        _mintTokensViaMatch(obId, 60, 10);

        uint256 yesId = token.yesTokenId(obId);
        assertEq(token.balanceOf(user1, yesId), 10);

        uint256 poolBefore = vault.marketPool(obId);

        // user1 sells 10 YES at tick 50
        _approveTokensForOrderBook(user1);
        vm.prank(user1);
        book.placeOrder(obId, Side.SellYes, OrderType.GoodTilCancel, 50, 10);

        // user2 bids at tick 50 (wants to buy YES)
        vm.prank(user2);
        book.placeOrder(obId, Side.Bid, OrderType.GoodTilCancel, 50, 10);

        uint256 sellerUsdtBefore = usdt.balanceOf(user1);
        BatchResult memory result = auction.clearBatch(obId);

        assertEq(result.clearingTick, 50);
        assertEq(result.matchedLots, 10);

        // Seller (user1) gets USDT payout: 10 * LOT * 50/100
        uint256 expectedPayout = (10 * LOT * 50) / 100;
        assertEq(usdt.balanceOf(user1) - sellerUsdtBefore, expectedPayout);

        // Buyer (user2) gets YES tokens (minted via normal path)
        assertEq(token.balanceOf(user2, yesId), 10);

        // Seller's YES tokens burned from OrderBook
        assertEq(token.balanceOf(address(book), yesId), 0);

        // Pool balance: still solvent (net zero from sell+buy)
        // Pool had poolBefore. Sell drew expectedPayout. Buy added 10*LOT*50/100. Net = 0.
        assertEq(vault.marketPool(obId), poolBefore);
    }

    // =========================================================================
    // Settlement tests — SellNo vs Ask
    // =========================================================================

    function test_ClearBatch_SellNo_vs_Ask() public {
        (uint256 fmId, uint256 obId) = _createMarket(3600);
        _mintTokensViaMatch(obId, 60, 10);

        uint256 noId = token.noTokenId(obId);
        assertEq(token.balanceOf(user3, noId), 10);

        uint256 poolBefore = vault.marketPool(obId);

        // user3 sells 10 NO at tick 50 (SellNo sits on bid side, wants (100-50)/100 per lot)
        _approveTokensForOrderBook(user3);
        vm.prank(user3);
        book.placeOrder(obId, Side.SellNo, OrderType.GoodTilCancel, 50, 10);

        // user2 places Ask at tick 50 (buys NO for (100-50)/100 per lot)
        vm.prank(user2);
        book.placeOrder(obId, Side.Ask, OrderType.GoodTilCancel, 50, 10);

        uint256 sellerUsdtBefore = usdt.balanceOf(user3);
        BatchResult memory result = auction.clearBatch(obId);

        assertEq(result.clearingTick, 50);
        assertEq(result.matchedLots, 10);

        // Seller gets (100-50)/100 * LOT_SIZE payout per lot
        uint256 expectedPayout = (10 * LOT * 50) / 100;
        assertEq(usdt.balanceOf(user3) - sellerUsdtBefore, expectedPayout);

        // Buyer gets NO tokens (minted via normal path)
        assertEq(token.balanceOf(user2, noId), 10);

        // NO tokens burned from OrderBook
        assertEq(token.balanceOf(address(book), noId), 0);

        // Pool remains solvent
        assertEq(vault.marketPool(obId), poolBefore);
    }

    // =========================================================================
    // Mixed regular + sell orders
    // =========================================================================

    function test_ClearBatch_Mixed_RegularAndSell() public {
        (uint256 fmId, uint256 obId) = _createMarket(3600);
        // Create some YES tokens
        _mintTokensViaMatch(obId, 50, 10);

        uint256 yesId = token.yesTokenId(obId);

        // Sell 5 YES at tick 40
        _approveTokensForOrderBook(user1);
        vm.prank(user1);
        book.placeOrder(obId, Side.SellYes, OrderType.GoodTilCancel, 40, 5);

        // Regular Ask at tick 40 from user3 (different from initial market)
        vm.prank(user3);
        book.placeOrder(obId, Side.Ask, OrderType.GoodTilCancel, 40, 5);

        // Bid for 10 at tick 40
        vm.prank(user2);
        book.placeOrder(obId, Side.Bid, OrderType.GoodTilCancel, 40, 10);

        BatchResult memory result = auction.clearBatch(obId);

        assertEq(result.clearingTick, 40);
        assertEq(result.matchedLots, 10);

        // Buyer got 10 YES tokens total (5 from sell, 5 from regular ask -> new mints)
        assertEq(token.balanceOf(user2, yesId), 10);
    }

    // =========================================================================
    // Pool solvency — full lifecycle
    // =========================================================================

    function test_ClearBatch_SellYes_PoolSolvency() public {
        (uint256 fmId, uint256 obId) = _createMarket(3600);
        (, , uint256 expiry, , , , , , , ) = factory.marketMeta(fmId);

        // Step 1: Create original pair — user1 bids, user3 asks at tick 50
        _mintTokensViaMatch(obId, 50, 10);
        // user1 has 10 YES, user3 has 10 NO
        // pool has 10 * LOT = 10e17

        assertEq(vault.marketPool(obId), 10 * LOT);

        // Step 2: user1 sells YES tokens to user2 via sell order
        _approveTokensForOrderBook(user1);
        vm.prank(user1);
        book.placeOrder(obId, Side.SellYes, OrderType.GoodTilCancel, 50, 10);

        vm.prank(user2);
        book.placeOrder(obId, Side.Bid, OrderType.GoodTilCancel, 50, 10);

        auction.clearBatch(obId);

        // user2 now has 10 YES, user3 has 10 NO. Pool still = 10 * LOT.
        assertEq(token.balanceOf(user2, token.yesTokenId(obId)), 10);
        assertEq(vault.marketPool(obId), 10 * LOT);

        // Step 3: Resolve market — YES wins (price above strike)
        vm.warp(expiry);
        factory.closeMarket(fmId);
        uint64 publishTime = uint64(expiry + 10);
        bytes[] memory updateData = _createPriceUpdate(55000_00000000, 100_00000000, publishTime);
        vm.prank(user2);
        resolver.resolveMarket{value: 1}(fmId, updateData);
        vm.warp(block.timestamp + 90);
        resolver.finalizeResolution(fmId);

        // Step 4: user2 (YES holder) redeems LOT_SIZE per token
        uint256 user2Before = usdt.balanceOf(user2);
        vm.prank(user2);
        redemption.redeem(fmId, 10);

        assertEq(usdt.balanceOf(user2) - user2Before, 10 * LOT);
        assertEq(vault.marketPool(obId), 0);
    }

    function test_SellNo_PoolSolvency() public {
        (uint256 fmId, uint256 obId) = _createMarket(3600);
        (, , uint256 expiry, , , , , , , ) = factory.marketMeta(fmId);

        // Create pair: user1 gets YES, user3 gets NO
        _mintTokensViaMatch(obId, 50, 10);
        assertEq(vault.marketPool(obId), 10 * LOT);

        // user3 sells NO to user2
        _approveTokensForOrderBook(user3);
        vm.prank(user3);
        book.placeOrder(obId, Side.SellNo, OrderType.GoodTilCancel, 50, 10);

        vm.prank(user2);
        book.placeOrder(obId, Side.Ask, OrderType.GoodTilCancel, 50, 10);

        auction.clearBatch(obId);

        assertEq(token.balanceOf(user2, token.noTokenId(obId)), 10);
        assertEq(vault.marketPool(obId), 10 * LOT);

        // Resolve NO wins (price below strike)
        vm.warp(expiry);
        factory.closeMarket(fmId);
        uint64 publishTime = uint64(expiry + 10);
        bytes[] memory updateData = _createPriceUpdate(45000_00000000, 100_00000000, publishTime);
        vm.prank(user1);
        resolver.resolveMarket{value: 1}(fmId, updateData);
        vm.warp(block.timestamp + 90);
        resolver.finalizeResolution(fmId);

        // user2 (NO holder) redeems
        uint256 user2Before = usdt.balanceOf(user2);
        vm.prank(user2);
        redemption.redeem(fmId, 10);
        assertEq(usdt.balanceOf(user2) - user2Before, 10 * LOT);
        assertEq(vault.marketPool(obId), 0);
    }

    // =========================================================================
    // Non-fill and rollover tests
    // =========================================================================

    function test_ClearBatch_SellYes_PriceBelowClearing_NotFilled() public {
        (uint256 fmId, uint256 obId) = _createMarket(3600);
        _mintTokensViaMatch(obId, 60, 10);

        uint256 yesId = token.yesTokenId(obId);
        _approveTokensForOrderBook(user1);

        // user1 sells YES at tick 40 (won't sell for less than 40)
        vm.prank(user1);
        uint256 sellId = book.placeOrder(obId, Side.SellYes, OrderType.GoodTilBatch, 40, 10);

        // user2 bids at tick 30 (willing to pay at most 30)
        vm.prank(user2);
        book.placeOrder(obId, Side.Bid, OrderType.GoodTilBatch, 30, 10);

        // No crossing — clearing tick = 0
        BatchResult memory result = auction.clearBatch(obId);
        assertEq(result.clearingTick, 0);

        // GTB sell order: tokens returned to user1
        assertEq(token.balanceOf(user1, yesId), 10);
    }

    function test_SellYes_GTC_Rollover() public {
        (uint256 fmId, uint256 obId) = _createMarket(3600);
        _mintTokensViaMatch(obId, 60, 10);

        _approveTokensForOrderBook(user1);
        vm.prank(user1);
        uint256 sellId = book.placeOrder(obId, Side.SellYes, OrderType.GoodTilCancel, 50, 10);

        // Batch 1: no bids — GTC rolls over
        auction.clearBatch(obId);
        (, , , , uint64 lots1, , , , , ) = book.orders(sellId);
        assertEq(lots1, 10); // still alive

        // Tokens still in OrderBook custody
        assertEq(token.balanceOf(address(book), token.yesTokenId(obId)), 10);

        // Batch 2: bid arrives
        vm.prank(user2);
        book.placeOrder(obId, Side.Bid, OrderType.GoodTilCancel, 50, 10);

        BatchResult memory result = auction.clearBatch(obId);
        assertEq(result.matchedLots, 10);

        // Buyer got YES tokens
        assertEq(token.balanceOf(user2, token.yesTokenId(obId)), 10);
    }

    // =========================================================================
    // Partial fill
    // =========================================================================

    function test_SellYes_PartialFill() public {
        (uint256 fmId, uint256 obId) = _createMarket(3600);
        _mintTokensViaMatch(obId, 60, 20);

        uint256 yesId = token.yesTokenId(obId);
        _approveTokensForOrderBook(user1);
        vm.prank(user1);
        uint256 sellId = book.placeOrder(obId, Side.SellYes, OrderType.GoodTilCancel, 50, 20);

        // Only 10 lots demanded
        vm.prank(user2);
        book.placeOrder(obId, Side.Bid, OrderType.GoodTilCancel, 50, 10);

        uint256 sellerBefore = usdt.balanceOf(user1);
        auction.clearBatch(obId);

        // 10 lots filled, 10 remaining
        (, , , , uint64 remaining, , , , , ) = book.orders(sellId);
        assertEq(remaining, 10);

        // Seller received payout for 10 lots
        uint256 payout = (10 * LOT * 50) / 100;
        assertEq(usdt.balanceOf(user1) - sellerBefore, payout);

        // 10 tokens still locked in OrderBook
        assertEq(token.balanceOf(address(book), yesId), 10);

        // Buyer got 10 YES
        assertEq(token.balanceOf(user2, yesId), 10);
    }

    // =========================================================================
    // Segment tree volume
    // =========================================================================

    function test_SellYes_AddsToAskTree() public {
        (uint256 fmId, uint256 obId) = _createMarket(3600);
        _mintTokensViaMatch(obId, 60, 10);

        _approveTokensForOrderBook(user1);
        vm.prank(user1);
        book.placeOrder(obId, Side.SellYes, OrderType.GoodTilCancel, 50, 10);

        // SellYes at tick 50 should appear on ask tree
        assertEq(book.askVolumeAt(obId, 50), 10);
        assertEq(book.bidVolumeAt(obId, 50), 0);
    }

    function test_SellNo_AddsToBidTree() public {
        (uint256 fmId, uint256 obId) = _createMarket(3600);
        _mintTokensViaMatch(obId, 60, 10);

        _approveTokensForOrderBook(user3);
        vm.prank(user3);
        book.placeOrder(obId, Side.SellNo, OrderType.GoodTilCancel, 50, 10);

        // SellNo at tick 50 should appear on bid tree
        assertEq(book.bidVolumeAt(obId, 50), 10);
        assertEq(book.askVolumeAt(obId, 50), 0);
    }

    // =========================================================================
    // Edge: sell at market expiry
    // =========================================================================

    function test_SellYes_RevertOnExpiredMarket() public {
        (uint256 fmId, uint256 obId) = _createMarket(3600);
        _mintTokensViaMatch(obId, 60, 10);

        _approveTokensForOrderBook(user1);

        // Warp past expiry
        vm.warp(block.timestamp + 3601);
        vm.expectRevert("OrderBook: market expired");
        vm.prank(user1);
        book.placeOrder(obId, Side.SellYes, OrderType.GoodTilCancel, 50, 10);
    }
}
