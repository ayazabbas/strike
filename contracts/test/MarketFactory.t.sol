// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/MarketFactory.sol";
import "../src/OrderBook.sol";
import "../src/OutcomeToken.sol";
import "../src/Vault.sol";
import "../src/ITypes.sol";

contract MarketFactoryTest is Test {
    MarketFactory public factory;
    OrderBook public book;
    OutcomeToken public token;
    Vault public vault;

    address public admin = address(0x1);
    address public user1 = address(0x3);
    address public user2 = address(0x4);
    address public feeCollector = address(0x99);

    bytes32 public constant PRICE_ID = bytes32(uint256(0xB7C));

    function setUp() public {
        vm.startPrank(admin);

        vault = new Vault(admin);
        token = new OutcomeToken(admin);
        book = new OrderBook(admin, address(vault));

        factory = new MarketFactory(admin, address(book), address(token), feeCollector);

        // Grant factory OPERATOR_ROLE on OrderBook so it can registerMarket/deactivateMarket
        book.grantRole(book.OPERATOR_ROLE(), address(factory));
        // Grant book PROTOCOL_ROLE on Vault
        vault.grantRole(vault.PROTOCOL_ROLE(), address(book));

        vm.stopPrank();

        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
    }

    // =========================================================================
    // Constructor
    // =========================================================================

    function test_Constructor_SetsImmutables() public view {
        assertEq(address(factory.orderBook()), address(book));
        assertEq(address(factory.outcomeToken()), address(token));
        assertEq(factory.feeCollector(), feeCollector);
    }

    function test_Constructor_RevertZeroOrderBook() public {
        vm.expectRevert("MarketFactory: zero orderBook");
        new MarketFactory(admin, address(0), address(token), feeCollector);
    }

    function test_Constructor_RevertZeroOutcomeToken() public {
        vm.expectRevert("MarketFactory: zero outcomeToken");
        new MarketFactory(admin, address(book), address(0), feeCollector);
    }

    function test_Constructor_RevertZeroFeeCollector() public {
        vm.expectRevert("MarketFactory: zero feeCollector");
        new MarketFactory(admin, address(book), address(token), address(0));
    }

    // =========================================================================
    // createMarket
    // =========================================================================

    function test_CreateMarket_Basic() public {
        vm.prank(user1);
        uint256 id = factory.createMarket{value: 0.01 ether}(PRICE_ID, 3600, 60, 1);

        assertEq(id, 1);

        (
            bytes32 priceId,
            uint256 expiryTime,
            uint256 bond,
            address creator,
            MarketState state,
            ,
            ,
            uint256 obId
        ) = factory.marketMeta(id);

        assertEq(priceId, PRICE_ID);
        assertEq(expiryTime, block.timestamp + 3600);
        assertEq(bond, 0.01 ether);
        assertEq(creator, user1);
        assertTrue(state == MarketState.Open);
        assertEq(obId, 1);
    }

    function test_CreateMarket_EmitsEvent() public {
        vm.expectEmit(true, true, false, true);
        emit MarketFactory.MarketCreated(1, 1, PRICE_ID, block.timestamp + 3600, user1);

        vm.prank(user1);
        factory.createMarket{value: 0.01 ether}(PRICE_ID, 3600, 60, 1);
    }

    function test_CreateMarket_IncrementsId() public {
        vm.startPrank(user1);
        uint256 id1 = factory.createMarket{value: 0.01 ether}(PRICE_ID, 3600, 60, 1);
        uint256 id2 = factory.createMarket{value: 0.01 ether}(PRICE_ID, 7200, 60, 1);
        vm.stopPrank();

        assertEq(id1, 1);
        assertEq(id2, 2);
    }

    function test_CreateMarket_TracksActive() public {
        vm.prank(user1);
        factory.createMarket{value: 0.01 ether}(PRICE_ID, 3600, 60, 1);

        assertEq(factory.getActiveMarketCount(), 1);
        assertEq(factory.activeMarkets(0), 1);
    }

    function test_CreateMarket_RefundsExcessBond() public {
        uint256 balBefore = user1.balance;

        vm.prank(user1);
        factory.createMarket{value: 0.05 ether}(PRICE_ID, 3600, 60, 1);

        // Should have been charged only 0.01 ether
        assertEq(user1.balance, balBefore - 0.01 ether);
    }

    function test_CreateMarket_UsesDefaults() public {
        vm.prank(user1);
        uint256 id = factory.createMarket{value: 0.01 ether}(PRICE_ID, 3600, 0, 0);

        (, , , , , , , uint256 obId) = factory.marketMeta(id);
        (, , , , uint256 minLots, uint256 batchInterval, ) = book.markets(obId);

        assertEq(batchInterval, 60); // default
        assertEq(minLots, 1); // default
    }

    function test_CreateMarket_RevertIfPaused() public {
        vm.prank(admin);
        factory.pauseFactory(true);

        vm.expectRevert("MarketFactory: paused");
        vm.prank(user1);
        factory.createMarket{value: 0.01 ether}(PRICE_ID, 3600, 60, 1);
    }

    function test_CreateMarket_RevertIfInsufficientBond() public {
        vm.expectRevert("MarketFactory: insufficient bond");
        vm.prank(user1);
        factory.createMarket{value: 0.001 ether}(PRICE_ID, 3600, 60, 1);
    }

    function test_CreateMarket_RevertIfZeroDuration() public {
        vm.expectRevert("MarketFactory: zero duration");
        vm.prank(user1);
        factory.createMarket{value: 0.01 ether}(PRICE_ID, 0, 60, 1);
    }

    function test_CreateMarket_RevertIfZeroPriceId() public {
        vm.expectRevert("MarketFactory: zero priceId");
        vm.prank(user1);
        factory.createMarket{value: 0.01 ether}(bytes32(0), 3600, 60, 1);
    }

    function test_CreateMarket_RevertIfDurationTooShort() public {
        vm.expectRevert("MarketFactory: duration must exceed batchInterval");
        vm.prank(user1);
        factory.createMarket{value: 0.01 ether}(PRICE_ID, 30, 60, 1); // duration < batchInterval
    }

    // =========================================================================
    // closeMarket
    // =========================================================================

    function test_CloseMarket_Basic() public {
        vm.prank(user1);
        uint256 id = factory.createMarket{value: 0.01 ether}(PRICE_ID, 3600, 60, 1);

        vm.warp(block.timestamp + 3600);
        factory.closeMarket(id);

        (, , , , MarketState state, , , ) = factory.marketMeta(id);
        assertTrue(state == MarketState.Closed);
        assertEq(factory.getActiveMarketCount(), 0);
        assertEq(factory.getClosedMarketCount(), 1);
    }

    function test_CloseMarket_RevertIfNotExpired() public {
        vm.prank(user1);
        uint256 id = factory.createMarket{value: 0.01 ether}(PRICE_ID, 3600, 60, 1);

        vm.expectRevert("MarketFactory: not expired");
        factory.closeMarket(id);
    }

    function test_CloseMarket_RevertIfAlreadyClosed() public {
        vm.prank(user1);
        uint256 id = factory.createMarket{value: 0.01 ether}(PRICE_ID, 3600, 60, 1);

        vm.warp(block.timestamp + 3600);
        factory.closeMarket(id);

        vm.expectRevert("MarketFactory: not open");
        factory.closeMarket(id);
    }

    // =========================================================================
    // cancelMarket
    // =========================================================================

    function test_CancelMarket_Basic() public {
        vm.prank(user1);
        uint256 id = factory.createMarket{value: 0.01 ether}(PRICE_ID, 3600, 60, 1);

        vm.warp(block.timestamp + 3600);
        factory.closeMarket(id);

        // Wait 24h after expiry
        vm.warp(block.timestamp + 24 hours);
        uint256 balBefore = user1.balance;

        factory.cancelMarket(id);

        (, , , , MarketState state, , , ) = factory.marketMeta(id);
        assertTrue(state == MarketState.Cancelled);

        // Bond returned to creator
        assertEq(user1.balance, balBefore + 0.01 ether);
    }

    function test_CancelMarket_RevertIfTooEarly() public {
        vm.prank(user1);
        uint256 id = factory.createMarket{value: 0.01 ether}(PRICE_ID, 3600, 60, 1);

        vm.warp(block.timestamp + 3600);
        factory.closeMarket(id);

        vm.expectRevert("MarketFactory: too early to cancel");
        factory.cancelMarket(id);
    }

    // =========================================================================
    // Admin controls
    // =========================================================================

    function test_PauseFactory() public {
        vm.prank(admin);
        factory.pauseFactory(true);
        assertTrue(factory.paused());

        vm.prank(admin);
        factory.pauseFactory(false);
        assertFalse(factory.paused());
    }

    function test_SetDefaultParams() public {
        vm.prank(admin);
        factory.setDefaultParams(120, 5);

        assertEq(factory.defaultBatchInterval(), 120);
        assertEq(factory.defaultMinLots(), 5);
    }

    function test_SetCreationBond() public {
        vm.prank(admin);
        factory.setCreationBond(0.05 ether);

        assertEq(factory.creationBond(), 0.05 ether);
    }

    function test_SetFeeCollector() public {
        address newCollector = address(0x88);
        vm.prank(admin);
        factory.setFeeCollector(newCollector);

        assertEq(factory.feeCollector(), newCollector);
    }

    function test_SetFeeCollector_RevertZero() public {
        vm.expectRevert("MarketFactory: zero collector");
        vm.prank(admin);
        factory.setFeeCollector(address(0));
    }

    function test_AdminControls_RevertIfNotAdmin() public {
        vm.expectRevert();
        vm.prank(user1);
        factory.pauseFactory(true);

        vm.expectRevert();
        vm.prank(user1);
        factory.setDefaultParams(120, 5);

        vm.expectRevert();
        vm.prank(user1);
        factory.setCreationBond(0.05 ether);
    }

    // =========================================================================
    // State machine
    // =========================================================================

    function test_StateTransition_FullLifecycle() public {
        vm.prank(user1);
        uint256 id = factory.createMarket{value: 0.01 ether}(PRICE_ID, 3600, 60, 1);

        // Open
        assertEq(uint256(factory.getMarketState(id)), uint256(MarketState.Open));

        // Close
        vm.warp(block.timestamp + 3600);
        factory.closeMarket(id);
        assertEq(uint256(factory.getMarketState(id)), uint256(MarketState.Closed));

        // Resolving
        vm.prank(admin);
        factory.setResolving(id);
        assertEq(uint256(factory.getMarketState(id)), uint256(MarketState.Resolving));

        // Resolved
        vm.prank(admin);
        factory.setResolved(id, true, 50000);
        assertEq(uint256(factory.getMarketState(id)), uint256(MarketState.Resolved));
    }

    // =========================================================================
    // View helpers
    // =========================================================================

    function test_GetActiveMarketCount_MultipleMarkets() public {
        vm.startPrank(user1);
        factory.createMarket{value: 0.01 ether}(PRICE_ID, 3600, 60, 1);
        factory.createMarket{value: 0.01 ether}(PRICE_ID, 7200, 60, 1);
        factory.createMarket{value: 0.01 ether}(PRICE_ID, 10800, 60, 1);
        vm.stopPrank();

        assertEq(factory.getActiveMarketCount(), 3);

        // Close first market
        vm.warp(block.timestamp + 3600);
        factory.closeMarket(1);
        assertEq(factory.getActiveMarketCount(), 2);
    }
}
