// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "@pythnetwork/pyth-sdk-solidity/MockPyth.sol";
import "../src/PythResolver.sol";
import "../src/MarketFactory.sol";
import "../src/OrderBook.sol";
import "../src/OutcomeToken.sol";
import "../src/Vault.sol";
import "../src/FeeModel.sol";
import "../src/ITypes.sol";
import "./mocks/MockUSDT.sol";

contract PythResolverTest is Test {
    PythResolver public resolver;
    MarketFactory public factory;
    MockPyth public mockPyth;
    OrderBook public book;
    OutcomeToken public token;
    Vault public vault;
    MockUSDT public usdt;

    address public admin = address(0x1);
    address public resolver1 = address(0x10);
    address public resolver2 = address(0x11);
    address public user1 = address(0x3);

    bytes32 public constant PRICE_ID = bytes32(uint256(0xB7C));
    int64 public constant STRIKE_PRICE = int64(50000_00000000);
    uint256 public marketId;
    uint256 public expiryTime;

    function setUp() public {
        usdt = new MockUSDT();

        vm.startPrank(admin);
        vault = new Vault(admin, address(usdt));
        token = new OutcomeToken(admin);
        FeeModel fm = new FeeModel(admin, 20, 0, 5e18, 1e17, admin);
        book = new OrderBook(admin, address(vault), address(fm));

        mockPyth = new MockPyth(120, 1);

        factory = new MarketFactory(admin, address(book), address(token), address(0x99));

        book.grantRole(book.OPERATOR_ROLE(), address(factory));
        vault.grantRole(vault.PROTOCOL_ROLE(), address(book));

        resolver = new PythResolver(address(mockPyth), address(factory));

        factory.grantRole(factory.ADMIN_ROLE(), address(resolver));
        factory.grantRole(factory.MARKET_CREATOR_ROLE(), user1);
        vm.stopPrank();

        vm.deal(resolver1, 100 ether);
        vm.deal(resolver2, 100 ether);
        vm.deal(user1, 100 ether);

        vm.prank(user1);
        marketId = factory.createMarket(PRICE_ID, STRIKE_PRICE, 3600, 60, 1);
        (, , expiryTime, , , , , ) = factory.marketMeta(marketId);
    }

    function _createPriceUpdate(bytes32 priceId, int64 price, uint64 conf, uint64 publishTime)
        internal view returns (bytes[] memory updateData)
    {
        updateData = new bytes[](1);
        updateData[0] = mockPyth.createPriceFeedUpdateData(
            priceId, price, conf, -8, price, conf,
            publishTime, publishTime > 0 ? publishTime - 1 : 0
        );
    }

    function _closeMarket() internal {
        vm.warp(expiryTime);
        factory.closeMarket(marketId);
    }

    function test_ResolveMarket_Basic() public {
        _closeMarket();
        uint64 publishTime = uint64(expiryTime + 10);
        bytes[] memory updateData = _createPriceUpdate(PRICE_ID, 50000_00000000, 100_00000000, publishTime);

        vm.prank(resolver1);
        resolver.resolveMarket{value: 1}(marketId, updateData);

        (int64 price, uint256 pt, uint256 resolvedBlock, address res, bool fin) =
            resolver.pendingResolutions(marketId);

        assertEq(price, 50000_00000000);
        assertEq(pt, publishTime);
        assertEq(resolvedBlock, block.number);
        assertEq(res, resolver1);
        assertFalse(fin);
        assertEq(uint256(factory.getMarketState(marketId)), uint256(MarketState.Resolving));
    }

    function test_ResolveMarket_AutoCloses() public {
        vm.warp(expiryTime);
        uint64 publishTime = uint64(expiryTime + 10);
        bytes[] memory updateData = _createPriceUpdate(PRICE_ID, 50000_00000000, 100_00000000, publishTime);

        vm.prank(resolver1);
        resolver.resolveMarket{value: 1}(marketId, updateData);
        assertEq(uint256(factory.getMarketState(marketId)), uint256(MarketState.Resolving));
    }

    function test_ResolveMarket_RevertIfNotClosed() public {
        uint64 publishTime = uint64(expiryTime + 10);
        bytes[] memory updateData = _createPriceUpdate(PRICE_ID, 50000_00000000, 100_00000000, publishTime);

        vm.expectRevert("PythResolver: not closed");
        vm.prank(resolver1);
        resolver.resolveMarket{value: 1}(marketId, updateData);
    }

    function test_ResolveMarket_RevertIfConfidenceTooWide() public {
        _closeMarket();
        uint64 publishTime = uint64(expiryTime + 10);
        bytes[] memory updateData = _createPriceUpdate(PRICE_ID, 50000, 1000, publishTime);

        vm.expectRevert("PythResolver: confidence too wide");
        vm.prank(resolver1);
        resolver.resolveMarket{value: 1}(marketId, updateData);
    }

    function test_ResolveMarket_RevertIfInsufficientFee() public {
        _closeMarket();
        uint64 publishTime = uint64(expiryTime + 10);
        bytes[] memory updateData = _createPriceUpdate(PRICE_ID, 50000_00000000, 100_00000000, publishTime);

        vm.expectRevert("PythResolver: insufficient fee");
        vm.prank(resolver1);
        resolver.resolveMarket{value: 0}(marketId, updateData);
    }

    function test_Challenge_EarlierPublishTimeWins() public {
        _closeMarket();

        uint64 pt1 = uint64(expiryTime + 30);
        bytes[] memory data1 = _createPriceUpdate(PRICE_ID, 50000_00000000, 100_00000000, pt1);
        vm.prank(resolver1);
        resolver.resolveMarket{value: 1}(marketId, data1);

        uint64 pt2 = uint64(expiryTime + 10);
        bytes[] memory data2 = _createPriceUpdate(PRICE_ID, 48000_00000000, 100_00000000, pt2);
        vm.prank(resolver2);
        resolver.resolveMarket{value: 1}(marketId, data2);

        (int64 price, uint256 pt, , address res, ) = resolver.pendingResolutions(marketId);
        assertEq(price, 48000_00000000);
        assertEq(pt, pt2);
        assertEq(res, resolver2);
    }

    function test_Challenge_RevertIfNotEarlier() public {
        _closeMarket();
        uint64 pt1 = uint64(expiryTime + 10);
        bytes[] memory data1 = _createPriceUpdate(PRICE_ID, 50000_00000000, 100_00000000, pt1);
        vm.prank(resolver1);
        resolver.resolveMarket{value: 1}(marketId, data1);

        uint64 pt2 = uint64(expiryTime + 20);
        bytes[] memory data2 = _createPriceUpdate(PRICE_ID, 48000_00000000, 100_00000000, pt2);
        vm.expectRevert("PythResolver: not earlier");
        vm.prank(resolver2);
        resolver.resolveMarket{value: 1}(marketId, data2);
    }

    function test_Challenge_RevertAfterFinality() public {
        _closeMarket();
        uint64 pt1 = uint64(expiryTime + 10);
        bytes[] memory data1 = _createPriceUpdate(PRICE_ID, 50000_00000000, 100_00000000, pt1);
        vm.prank(resolver1);
        resolver.resolveMarket{value: 1}(marketId, data1);

        vm.roll(block.number + 3);

        uint64 pt2 = uint64(expiryTime + 5);
        bytes[] memory data2 = _createPriceUpdate(PRICE_ID, 48000_00000000, 100_00000000, pt2);
        vm.expectRevert("PythResolver: finality passed");
        vm.prank(resolver2);
        resolver.resolveMarket{value: 1}(marketId, data2);
    }

    function test_FinalizeResolution_Basic() public {
        _closeMarket();
        uint64 publishTime = uint64(expiryTime + 10);
        bytes[] memory updateData = _createPriceUpdate(PRICE_ID, 50000_00000000, 100_00000000, publishTime);

        vm.prank(resolver1);
        resolver.resolveMarket{value: 1}(marketId, updateData);

        vm.roll(block.number + 3);
        resolver.finalizeResolution(marketId);

        assertEq(uint256(factory.getMarketState(marketId)), uint256(MarketState.Resolved));
        (, , , , bool fin) = resolver.pendingResolutions(marketId);
        assertTrue(fin);
    }

    function test_FinalizeResolution_AboveStrike_YesWins() public {
        _closeMarket();
        uint64 publishTime = uint64(expiryTime + 10);
        bytes[] memory updateData = _createPriceUpdate(PRICE_ID, 60000_00000000, 100_00000000, publishTime);

        vm.prank(resolver1);
        resolver.resolveMarket{value: 1}(marketId, updateData);
        vm.roll(block.number + 3);
        resolver.finalizeResolution(marketId);

        (, , , , , bool outcomeYes, , ) = factory.marketMeta(marketId);
        assertTrue(outcomeYes);
    }

    function test_FinalizeResolution_BelowStrike_NoWins() public {
        _closeMarket();
        uint64 publishTime = uint64(expiryTime + 10);
        bytes[] memory updateData = _createPriceUpdate(PRICE_ID, 40000_00000000, 100_00000000, publishTime);

        vm.prank(resolver1);
        resolver.resolveMarket{value: 1}(marketId, updateData);
        vm.roll(block.number + 3);
        resolver.finalizeResolution(marketId);

        (, , , , , bool outcomeYes, , ) = factory.marketMeta(marketId);
        assertFalse(outcomeYes);
    }

    function test_FinalizeResolution_RevertIfNoResolution() public {
        vm.expectRevert("PythResolver: no pending resolution");
        resolver.finalizeResolution(marketId);
    }

    function test_FinalizeResolution_RevertIfFinalityNotReached() public {
        _closeMarket();
        uint64 publishTime = uint64(expiryTime + 10);
        bytes[] memory updateData = _createPriceUpdate(PRICE_ID, 50000_00000000, 100_00000000, publishTime);
        vm.prank(resolver1);
        resolver.resolveMarket{value: 1}(marketId, updateData);

        vm.expectRevert("PythResolver: finality not reached");
        resolver.finalizeResolution(marketId);
    }

    function test_FinalizeResolution_RevertIfAlreadyFinalized() public {
        _closeMarket();
        uint64 publishTime = uint64(expiryTime + 10);
        bytes[] memory updateData = _createPriceUpdate(PRICE_ID, 50000_00000000, 100_00000000, publishTime);
        vm.prank(resolver1);
        resolver.resolveMarket{value: 1}(marketId, updateData);
        vm.roll(block.number + 3);
        resolver.finalizeResolution(marketId);

        vm.expectRevert("PythResolver: already finalized");
        resolver.finalizeResolution(marketId);
    }

    function test_GetPythUpdateFee() public {
        bytes[] memory updateData = _createPriceUpdate(PRICE_ID, 50000_00000000, 100_00000000, uint64(block.timestamp));
        uint256 fee = resolver.getPythUpdateFee(updateData);
        assertEq(fee, 1);
    }

    function test_Constructor_RevertZeroPyth() public {
        vm.expectRevert("PythResolver: zero pyth");
        new PythResolver(address(0), address(factory));
    }

    function test_Constructor_RevertZeroFactory() public {
        vm.expectRevert("PythResolver: zero factory");
        new PythResolver(address(mockPyth), address(0));
    }

    function testFuzz_Resolution_StrikeBoundary(int64 price, uint64 conf) public {
        price = int64(bound(int256(price), 40000_00000000, 60000_00000000));
        conf = uint64(bound(uint64(conf), 0, uint64(uint256(uint64(price)) / 100)));

        _closeMarket();

        uint64 publishTime = uint64(expiryTime + 10);
        bytes[] memory updateData = _createPriceUpdate(PRICE_ID, price, conf, publishTime);

        vm.prank(resolver1);
        resolver.resolveMarket{value: 1}(marketId, updateData);

        vm.roll(block.number + 3);
        resolver.finalizeResolution(marketId);

        (, , , , MarketState state, bool outcomeYes, int64 settlementPrice, ) = factory.marketMeta(marketId);
        assertEq(uint256(state), uint256(MarketState.Resolved));
        assertEq(settlementPrice, price);

        if (price >= STRIKE_PRICE) {
            assertTrue(outcomeYes);
        } else {
            assertFalse(outcomeYes);
        }
    }
}
