// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "@pythnetwork/pyth-sdk-solidity/MockPyth.sol";
import "../src/PythResolver.sol";
import "../src/MarketFactory.sol";
import "../src/OrderBook.sol";
import "../src/OutcomeToken.sol";
import "../src/Vault.sol";
import "../src/ITypes.sol";

contract PythResolverTest is Test {
    PythResolver public resolver;
    MarketFactory public factory;
    MockPyth public mockPyth;
    OrderBook public book;
    OutcomeToken public token;
    Vault public vault;

    address public admin = address(0x1);
    address public resolver1 = address(0x10);
    address public resolver2 = address(0x11);
    address public user1 = address(0x3);

    bytes32 public constant PRICE_ID = bytes32(uint256(0xB7C));
    uint256 public marketId;
    uint256 public expiryTime;

    function setUp() public {
        vm.startPrank(admin);

        vault = new Vault(admin);
        token = new OutcomeToken(admin);
        book = new OrderBook(admin, address(vault));

        mockPyth = new MockPyth(300, 1); // 300s valid, 1 wei fee

        factory = new MarketFactory(admin, address(book), address(token), address(0x99));

        // Grant factory OPERATOR_ROLE on OrderBook
        book.grantRole(book.OPERATOR_ROLE(), address(factory));
        vault.grantRole(vault.PROTOCOL_ROLE(), address(book));

        resolver = new PythResolver(address(mockPyth), address(factory));

        // Grant resolver ADMIN_ROLE on factory
        factory.grantRole(factory.ADMIN_ROLE(), address(resolver));

        vm.stopPrank();

        vm.deal(resolver1, 100 ether);
        vm.deal(resolver2, 100 ether);
        vm.deal(user1, 100 ether);

        // Create a market
        vm.prank(user1);
        marketId = factory.createMarket{value: 0.01 ether}(PRICE_ID, 3600, 60, 1);

        (, expiryTime, , , , , , ) = factory.marketMeta(marketId);
    }

    // =========================================================================
    // Helpers
    // =========================================================================

    function _createUpdateData(int64 price, uint64 conf, uint64 publishTime)
        internal
        view
        returns (bytes[] memory)
    {
        bytes[] memory data = new bytes[](1);
        data[0] = mockPyth.createPriceFeedUpdateData(
            PRICE_ID,
            price,
            conf,
            -8, // expo
            price, // emaPrice
            conf,
            publishTime,
            publishTime - 1
        );
        return data;
    }

    function _closeMarket() internal {
        vm.warp(expiryTime);
        factory.closeMarket(marketId);
    }

    // =========================================================================
    // resolveMarket
    // =========================================================================

    function test_ResolveMarket_Basic() public {
        _closeMarket();

        uint64 publishTime = uint64(expiryTime + 10);
        bytes[] memory data = _createUpdateData(50000_00000000, 100_00000000, publishTime);

        vm.prank(resolver1);
        resolver.resolveMarket{value: 1}(marketId, data);

        (int64 price, uint256 pt, uint256 resolvedBlock, address res, bool fin) =
            resolver.pendingResolutions(marketId);

        assertEq(price, 50000_00000000);
        assertEq(pt, publishTime);
        assertEq(resolvedBlock, block.number);
        assertEq(res, resolver1);
        assertFalse(fin);

        // Market should be in Resolving state
        assertEq(uint256(factory.getMarketState(marketId)), uint256(MarketState.Resolving));
    }

    function test_ResolveMarket_AutoCloses() public {
        // Don't manually close — resolver should auto-close
        vm.warp(expiryTime);

        uint64 publishTime = uint64(expiryTime + 10);
        bytes[] memory data = _createUpdateData(50000_00000000, 100_00000000, publishTime);

        vm.prank(resolver1);
        resolver.resolveMarket{value: 1}(marketId, data);

        assertEq(uint256(factory.getMarketState(marketId)), uint256(MarketState.Resolving));
    }

    function test_ResolveMarket_RevertIfNotClosed() public {
        // Market is still Open, not expired
        uint64 publishTime = uint64(expiryTime + 10);
        bytes[] memory data = _createUpdateData(50000_00000000, 100_00000000, publishTime);

        vm.expectRevert("PythResolver: not closed");
        vm.prank(resolver1);
        resolver.resolveMarket{value: 1}(marketId, data);
    }

    function test_ResolveMarket_RevertIfConfidenceTooWide() public {
        _closeMarket();

        // Price = 50000, conf = 1000 (2%) > 1% threshold
        // conf threshold = 50000 * 100 / 10000 = 500
        // conf = 1000 > 500 → should revert
        uint64 publishTime = uint64(expiryTime + 10);
        bytes[] memory data = _createUpdateData(50000, 1000, publishTime);

        vm.expectRevert("PythResolver: confidence too wide");
        vm.prank(resolver1);
        resolver.resolveMarket{value: 1}(marketId, data);
    }

    function test_ResolveMarket_RevertIfStaleData() public {
        _closeMarket();

        // Publish time before expiry and outside all windows
        uint64 publishTime = uint64(expiryTime - 100);
        bytes[] memory data = _createUpdateData(50000_00000000, 100_00000000, publishTime);

        vm.expectRevert("PythResolver: no valid price in any window");
        vm.prank(resolver1);
        resolver.resolveMarket{value: 1}(marketId, data);
    }

    function test_ResolveMarket_FallbackWindow() public {
        _closeMarket();

        // Publish time in window 2 (between 60-120s after expiry)
        uint64 publishTime = uint64(expiryTime + 90);
        bytes[] memory data = _createUpdateData(50000_00000000, 100_00000000, publishTime);

        vm.prank(resolver1);
        resolver.resolveMarket{value: 1}(marketId, data);

        (int64 price, , , , ) = resolver.pendingResolutions(marketId);
        assertEq(price, 50000_00000000);
    }

    function test_ResolveMarket_FallbackWindow5_RevertIfOutside() public {
        _closeMarket();

        // Publish time beyond all 5 windows (>300s after expiry)
        uint64 publishTime = uint64(expiryTime + 301);
        bytes[] memory data = _createUpdateData(50000_00000000, 100_00000000, publishTime);

        vm.expectRevert("PythResolver: no valid price in any window");
        vm.prank(resolver1);
        resolver.resolveMarket{value: 1}(marketId, data);
    }

    // =========================================================================
    // Challenge
    // =========================================================================

    function test_Challenge_EarlierPublishTimeWins() public {
        _closeMarket();

        // First resolution at publishTime = expiry + 30
        uint64 pt1 = uint64(expiryTime + 30);
        bytes[] memory data1 = _createUpdateData(50000_00000000, 100_00000000, pt1);

        vm.prank(resolver1);
        resolver.resolveMarket{value: 1}(marketId, data1);

        // Challenge with earlier publishTime = expiry + 10
        uint64 pt2 = uint64(expiryTime + 10);
        bytes[] memory data2 = _createUpdateData(48000_00000000, 100_00000000, pt2);

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
        bytes[] memory data1 = _createUpdateData(50000_00000000, 100_00000000, pt1);

        vm.prank(resolver1);
        resolver.resolveMarket{value: 1}(marketId, data1);

        // Try to challenge with later publishTime — should fail
        uint64 pt2 = uint64(expiryTime + 20);
        bytes[] memory data2 = _createUpdateData(48000_00000000, 100_00000000, pt2);

        vm.expectRevert("PythResolver: not earlier");
        vm.prank(resolver2);
        resolver.resolveMarket{value: 1}(marketId, data2);
    }

    function test_Challenge_RevertAfterFinality() public {
        _closeMarket();

        uint64 pt1 = uint64(expiryTime + 10);
        bytes[] memory data1 = _createUpdateData(50000_00000000, 100_00000000, pt1);

        vm.prank(resolver1);
        resolver.resolveMarket{value: 1}(marketId, data1);

        // Advance past finality
        vm.roll(block.number + 3);

        uint64 pt2 = uint64(expiryTime + 5);
        bytes[] memory data2 = _createUpdateData(48000_00000000, 100_00000000, pt2);

        vm.expectRevert("PythResolver: finality passed");
        vm.prank(resolver2);
        resolver.resolveMarket{value: 1}(marketId, data2);
    }

    // =========================================================================
    // finalizeResolution
    // =========================================================================

    function test_FinalizeResolution_Basic() public {
        _closeMarket();

        uint64 publishTime = uint64(expiryTime + 10);
        bytes[] memory data = _createUpdateData(50000_00000000, 100_00000000, publishTime);

        vm.prank(resolver1);
        resolver.resolveMarket{value: 1}(marketId, data);

        // Advance past finality gate
        vm.roll(block.number + 3);

        uint256 resolver1BalBefore = resolver1.balance;
        resolver.finalizeResolution(marketId);

        // Market should be Resolved
        assertEq(uint256(factory.getMarketState(marketId)), uint256(MarketState.Resolved));

        // Resolver should have received bounty
        assertEq(resolver1.balance, resolver1BalBefore + 0.01 ether);

        // Check finalized flag
        (, , , , bool fin) = resolver.pendingResolutions(marketId);
        assertTrue(fin);
    }

    function test_FinalizeResolution_PositivePrice_YesWins() public {
        _closeMarket();

        uint64 publishTime = uint64(expiryTime + 10);
        bytes[] memory data = _createUpdateData(50000_00000000, 100_00000000, publishTime);

        vm.prank(resolver1);
        resolver.resolveMarket{value: 1}(marketId, data);

        vm.roll(block.number + 3);
        resolver.finalizeResolution(marketId);

        (, , , , , bool outcomeYes, , ) = factory.marketMeta(marketId);
        assertTrue(outcomeYes);
    }

    function test_FinalizeResolution_NegativePrice_NoWins() public {
        _closeMarket();

        uint64 publishTime = uint64(expiryTime + 10);
        // Negative price
        bytes[] memory data = _createUpdateData(-50000_00000000, 100_00000000, publishTime);

        vm.prank(resolver1);
        resolver.resolveMarket{value: 1}(marketId, data);

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
        bytes[] memory data = _createUpdateData(50000_00000000, 100_00000000, publishTime);

        vm.prank(resolver1);
        resolver.resolveMarket{value: 1}(marketId, data);

        vm.expectRevert("PythResolver: finality not reached");
        resolver.finalizeResolution(marketId);
    }

    function test_FinalizeResolution_RevertIfAlreadyFinalized() public {
        _closeMarket();

        uint64 publishTime = uint64(expiryTime + 10);
        bytes[] memory data = _createUpdateData(50000_00000000, 100_00000000, publishTime);

        vm.prank(resolver1);
        resolver.resolveMarket{value: 1}(marketId, data);

        vm.roll(block.number + 3);
        resolver.finalizeResolution(marketId);

        vm.expectRevert("PythResolver: already finalized");
        resolver.finalizeResolution(marketId);
    }

    // =========================================================================
    // Constructor validation
    // =========================================================================

    function test_Constructor_RevertZeroPyth() public {
        vm.expectRevert("PythResolver: zero pyth");
        new PythResolver(address(0), address(factory));
    }

    function test_Constructor_RevertZeroFactory() public {
        vm.expectRevert("PythResolver: zero factory");
        new PythResolver(address(mockPyth), address(0));
    }
}
