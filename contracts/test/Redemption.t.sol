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

contract RedemptionTest is Test {
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
        // Zero-fee for clean accounting
        feeModel = new FeeModel(admin, 0, feeCollector);
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

    function _createPriceUpdate(int64 price, uint64 conf, uint64 publishTime)
        internal view returns (bytes[] memory updateData)
    {
        updateData = new bytes[](1);
        updateData[0] = mockPyth.createPriceFeedUpdateData(
            PRICE_ID, price, conf, -8, price, conf,
            publishTime, publishTime > 0 ? publishTime - 1 : 0
        );
    }

    function _createAndFillMarket() internal returns (uint256 fmId, uint256 obId) {
        vm.prank(user1);
        fmId = factory.createMarket(PRICE_ID, STRIKE_PRICE, block.timestamp + 3600, 60, 1);
        (, , , , , , , uint256 _obId, , ) = factory.marketMeta(fmId);
        obId = _obId;

        // user1 bids (buys YES), user2 asks (buys NO) at tick 60
        vm.prank(user1);
        book.placeOrder(obId, Side.Bid, OrderType.GoodTilCancel, 60, 10);
        vm.prank(user2);
        book.placeOrder(obId, Side.Ask, OrderType.GoodTilCancel, 60, 10);

        auction.clearBatch(obId);
    }

    function _resolveMarket(uint256 fmId, int64 price) internal {
        (, , uint256 expiry, , , , , , , ) = factory.marketMeta(fmId);
        vm.warp(expiry);
        factory.closeMarket(fmId);

        uint64 publishTime = uint64(expiry + 10);
        bytes[] memory updateData = _createPriceUpdate(price, 100_00000000, publishTime);

        vm.prank(user3);
        resolver.resolveMarket{value: 1}(fmId, updateData);

        vm.warp(block.timestamp + 90);
        resolver.finalizeResolution(fmId);
    }

    function test_Redeem_YesWins() public {
        (uint256 fmId, uint256 obId) = _createAndFillMarket();

        // Resolve YES (price above strike)
        _resolveMarket(fmId, 60000_00000000);

        (, , , , , bool outcomeYes, , , , ) = factory.marketMeta(fmId);
        assertTrue(outcomeYes);

        uint256 balBefore = usdt.balanceOf(user1);
        uint256 yesTokens = token.balanceOf(user1, token.yesTokenId(obId));
        assertEq(yesTokens, 10);

        vm.prank(user1);
        redemption.redeem(fmId, 10);

        assertEq(usdt.balanceOf(user1) - balBefore, 10 * LOT);
        assertEq(token.balanceOf(user1, token.yesTokenId(obId)), 0);
    }

    function test_Redeem_NoWins() public {
        (uint256 fmId, uint256 obId) = _createAndFillMarket();

        // Resolve NO (price below strike)
        _resolveMarket(fmId, 40000_00000000);

        (, , , , , bool outcomeYes, , , , ) = factory.marketMeta(fmId);
        assertFalse(outcomeYes);

        uint256 balBefore = usdt.balanceOf(user2);
        uint256 noTokens = token.balanceOf(user2, token.noTokenId(obId));
        assertEq(noTokens, 10);

        vm.prank(user2);
        redemption.redeem(fmId, 10);

        assertEq(usdt.balanceOf(user2) - balBefore, 10 * LOT);
        assertEq(token.balanceOf(user2, token.noTokenId(obId)), 0);
    }

    function test_Redeem_RevertOnUnresolvedMarket() public {
        (uint256 fmId, ) = _createAndFillMarket();

        vm.expectRevert("Redemption: not resolved");
        vm.prank(user1);
        redemption.redeem(fmId, 10);
    }

    function test_Redeem_RevertWithZeroAmount() public {
        (uint256 fmId, ) = _createAndFillMarket();
        _resolveMarket(fmId, 60000_00000000);

        vm.expectRevert("Redemption: zero amount");
        vm.prank(user1);
        redemption.redeem(fmId, 0);
    }
}
