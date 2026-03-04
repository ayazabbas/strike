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
    int64 public constant STRIKE_PRICE = int64(50000_00000000); // $50,000 with expo=-8
    uint256 public marketId;
    uint256 public expiryTime;

    function setUp() public {
        vm.startPrank(admin);

        vault = new Vault(admin);
        token = new OutcomeToken(admin);
        book = new OrderBook(admin, address(vault));

        // 120s valid period, 1 wei fee per update
        mockPyth = new MockPyth(120, 1);

        factory = new MarketFactory(admin, address(book), address(token), address(0x99));

        // Grant factory OPERATOR_ROLE on OrderBook
        book.grantRole(book.OPERATOR_ROLE(), address(factory));
        vault.grantRole(vault.PROTOCOL_ROLE(), address(book));

        resolver = new PythResolver(address(mockPyth), address(factory));

        // PythResolver needs ADMIN_ROLE to call setResolving/setResolved/payResolverBounty
        factory.grantRole(factory.ADMIN_ROLE(), address(resolver));

        vm.stopPrank();

        vm.deal(resolver1, 100 ether);
        vm.deal(resolver2, 100 ether);
        vm.deal(user1, 100 ether);

        // Create a market
        vm.prank(user1);
        marketId = factory.createMarket{value: 0.01 ether}(PRICE_ID, STRIKE_PRICE, 3600, 60, 1);

        (, , expiryTime, , , , , , ) = factory.marketMeta(marketId);
    }

    // =========================================================================
    // Helpers
    // =========================================================================

    /// @dev Create a Pyth Core mock price update for testing.
    function _createPriceUpdate(bytes32 priceId, int64 price, uint64 conf, uint64 publishTime)
        internal
        view
        returns (bytes[] memory updateData)
    {
        updateData = new bytes[](1);
        updateData[0] = mockPyth.createPriceFeedUpdateData(
            priceId,
            price,
            conf,
            -8,           // expo: 8 decimal places
            price,        // emaPrice
            conf,         // emaConf
            publishTime,
            publishTime > 0 ? publishTime - 1 : 0 // prevPublishTime
        );
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

        // Market should be in Resolving state
        assertEq(uint256(factory.getMarketState(marketId)), uint256(MarketState.Resolving));
    }

    function test_ResolveMarket_AutoCloses() public {
        // Don't manually close — resolver should auto-close when expired
        vm.warp(expiryTime);

        uint64 publishTime = uint64(expiryTime + 10);
        bytes[] memory updateData = _createPriceUpdate(PRICE_ID, 50000_00000000, 100_00000000, publishTime);

        vm.prank(resolver1);
        resolver.resolveMarket{value: 1}(marketId, updateData);

        assertEq(uint256(factory.getMarketState(marketId)), uint256(MarketState.Resolving));
    }

    function test_ResolveMarket_RevertIfNotClosed() public {
        // Market is still Open, not expired
        uint64 publishTime = uint64(expiryTime + 10);
        bytes[] memory updateData = _createPriceUpdate(PRICE_ID, 50000_00000000, 100_00000000, publishTime);

        vm.expectRevert("PythResolver: not closed");
        vm.prank(resolver1);
        resolver.resolveMarket{value: 1}(marketId, updateData);
    }

    function test_ResolveMarket_RevertIfConfidenceTooWide() public {
        _closeMarket();

        // Price = 50000, conf = 1000 (2%) > 1% threshold
        uint64 publishTime = uint64(expiryTime + 10);
        bytes[] memory updateData = _createPriceUpdate(PRICE_ID, 50000, 1000, publishTime);

        vm.expectRevert("PythResolver: confidence too wide");
        vm.prank(resolver1);
        resolver.resolveMarket{value: 1}(marketId, updateData);
    }

    function test_ResolveMarket_RevertIfStaleData() public {
        _closeMarket();

        // Publish time before expiry — outside the valid window [expiry, expiry+300]
        uint64 publishTime = uint64(expiryTime - 100);
        bytes[] memory updateData = _createPriceUpdate(PRICE_ID, 50000_00000000, 100_00000000, publishTime);

        // parsePriceFeedUpdates will revert because publishTime < expiryTime (minPublishTime)
        vm.expectRevert();
        vm.prank(resolver1);
        resolver.resolveMarket{value: 1}(marketId, updateData);
    }

    function test_ResolveMarket_FallbackWindow() public {
        _closeMarket();

        // Publish time in window 2 (between 60-120s after expiry)
        uint64 publishTime = uint64(expiryTime + 90);
        bytes[] memory updateData = _createPriceUpdate(PRICE_ID, 50000_00000000, 100_00000000, publishTime);

        vm.prank(resolver1);
        resolver.resolveMarket{value: 1}(marketId, updateData);

        (int64 price, , , , ) = resolver.pendingResolutions(marketId);
        assertEq(price, 50000_00000000);
    }

    function test_ResolveMarket_FallbackWindow5_RevertIfOutside() public {
        _closeMarket();

        // Publish time beyond all 5 windows (>300s after expiry)
        uint64 publishTime = uint64(expiryTime + 301);
        bytes[] memory updateData = _createPriceUpdate(PRICE_ID, 50000_00000000, 100_00000000, publishTime);

        // parsePriceFeedUpdates reverts with PriceFeedNotFoundWithinRange
        vm.expectRevert();
        vm.prank(resolver1);
        resolver.resolveMarket{value: 1}(marketId, updateData);
    }

    function test_ResolveMarket_NoConfidence_SkipsCheck() public {
        _closeMarket();

        uint64 publishTime = uint64(expiryTime + 10);
        // conf = 0 → confidence check is skipped
        bytes[] memory updateData = _createPriceUpdate(PRICE_ID, 50000_00000000, 0, publishTime);

        vm.prank(resolver1);
        resolver.resolveMarket{value: 1}(marketId, updateData);

        (int64 price, , , , ) = resolver.pendingResolutions(marketId);
        assertEq(price, 50000_00000000);
    }

    function test_ResolveMarket_RevertIfInsufficientFee() public {
        _closeMarket();

        uint64 publishTime = uint64(expiryTime + 10);
        bytes[] memory updateData = _createPriceUpdate(PRICE_ID, 50000_00000000, 100_00000000, publishTime);

        vm.expectRevert("PythResolver: insufficient fee");
        vm.prank(resolver1);
        resolver.resolveMarket{value: 0}(marketId, updateData);
    }

    // =========================================================================
    // Challenge
    // =========================================================================

    function test_Challenge_EarlierPublishTimeWins() public {
        _closeMarket();

        // First resolution at publishTime = expiry + 30
        uint64 pt1 = uint64(expiryTime + 30);
        bytes[] memory data1 = _createPriceUpdate(PRICE_ID, 50000_00000000, 100_00000000, pt1);

        vm.prank(resolver1);
        resolver.resolveMarket{value: 1}(marketId, data1);

        // Challenge with earlier publishTime = expiry + 10
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

        // Try to challenge with later publishTime — should fail
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

        // Advance past finality
        vm.roll(block.number + 3);

        uint64 pt2 = uint64(expiryTime + 5);
        bytes[] memory data2 = _createPriceUpdate(PRICE_ID, 48000_00000000, 100_00000000, pt2);

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
        bytes[] memory updateData = _createPriceUpdate(PRICE_ID, 50000_00000000, 100_00000000, publishTime);

        vm.prank(resolver1);
        resolver.resolveMarket{value: 1}(marketId, updateData);

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

    function test_FinalizeResolution_AboveStrike_YesWins() public {
        _closeMarket();

        uint64 publishTime = uint64(expiryTime + 10);
        bytes[] memory updateData = _createPriceUpdate(PRICE_ID, 60000_00000000, 100_00000000, publishTime);

        vm.prank(resolver1);
        resolver.resolveMarket{value: 1}(marketId, updateData);

        vm.roll(block.number + 3);
        resolver.finalizeResolution(marketId);

        (, , , , , , bool outcomeYes, , ) = factory.marketMeta(marketId);
        assertTrue(outcomeYes);
    }

    function test_FinalizeResolution_AtStrike_YesWins() public {
        _closeMarket();

        uint64 publishTime = uint64(expiryTime + 10);
        // Price exactly at strike → YES wins (>= check)
        bytes[] memory updateData = _createPriceUpdate(PRICE_ID, STRIKE_PRICE, 100_00000000, publishTime);

        vm.prank(resolver1);
        resolver.resolveMarket{value: 1}(marketId, updateData);

        vm.roll(block.number + 3);
        resolver.finalizeResolution(marketId);

        (, , , , , , bool outcomeYes, , ) = factory.marketMeta(marketId);
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

        (, , , , , , bool outcomeYes, , ) = factory.marketMeta(marketId);
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

    // =========================================================================
    // getPythUpdateFee
    // =========================================================================

    function test_GetPythUpdateFee() public {
        bytes[] memory updateData = _createPriceUpdate(PRICE_ID, 50000_00000000, 100_00000000, uint64(block.timestamp));
        uint256 fee = resolver.getPythUpdateFee(updateData);
        assertEq(fee, 1); // MockPyth charges 1 wei per update
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
