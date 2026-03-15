// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/MarketFactory.sol";
import "../src/OrderBook.sol";
import "../src/OutcomeToken.sol";
import "../src/Vault.sol";
import "../src/FeeModel.sol";
import "../src/ITypes.sol";
import "./mocks/MockUSDT.sol";

contract MarketFactoryTest is Test {
    MarketFactory public factory;
    OrderBook public book;
    OutcomeToken public token;
    Vault public vault;
    MockUSDT public usdt;

    address public admin = address(0x1);
    address public user1 = address(0x3);
    address public user2 = address(0x4);
    address public feeCollector = address(0x99);

    bytes32 public constant PRICE_ID = bytes32(uint256(0xB7C));
    int64 public constant STRIKE_PRICE = int64(50000_00000000);

    function setUp() public {
        usdt = new MockUSDT();

        vm.startPrank(admin);
        vault = new Vault(admin, address(usdt));
        token = new OutcomeToken(admin);
        FeeModel fm = new FeeModel(admin, 20, 0, 5e18, 1e17, admin);
        book = new OrderBook(admin, address(vault), address(fm), address(token));

        factory = new MarketFactory(admin, address(book), address(token), feeCollector);

        book.grantRole(book.OPERATOR_ROLE(), address(factory));
        vault.grantRole(vault.PROTOCOL_ROLE(), address(book));
        factory.grantRole(factory.MARKET_CREATOR_ROLE(), user1);
        vm.stopPrank();
    }

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

    function test_CreateMarket_Basic() public {
        vm.prank(user1);
        uint256 id = factory.createMarket(PRICE_ID, STRIKE_PRICE, 3600, 60, 1);
        assertEq(id, 1);

        (bytes32 priceId, , uint256 expiryTime, address creator, MarketState state, , , uint256 obId)
            = factory.marketMeta(id);

        assertEq(priceId, PRICE_ID);
        assertEq(expiryTime, block.timestamp + 3600);
        assertEq(creator, user1);
        assertTrue(state == MarketState.Open);
        assertEq(obId, 1);
    }

    function test_CreateMarket_EmitsEvent() public {
        vm.expectEmit(true, true, false, true);
        emit MarketFactory.MarketCreated(1, 1, PRICE_ID, STRIKE_PRICE, block.timestamp + 3600, user1);
        vm.prank(user1);
        factory.createMarket(PRICE_ID, STRIKE_PRICE, 3600, 60, 1);
    }

    function test_CreateMarket_IncrementsId() public {
        vm.startPrank(user1);
        uint256 id1 = factory.createMarket(PRICE_ID, STRIKE_PRICE, 3600, 60, 1);
        uint256 id2 = factory.createMarket(PRICE_ID, STRIKE_PRICE, 7200, 60, 1);
        vm.stopPrank();
        assertEq(id1, 1);
        assertEq(id2, 2);
    }

    function test_CreateMarket_TracksActive() public {
        vm.prank(user1);
        factory.createMarket(PRICE_ID, STRIKE_PRICE, 3600, 60, 1);
        assertEq(factory.getActiveMarketCount(), 1);
        assertEq(factory.activeMarkets(0), 1);
    }

    function test_CreateMarket_UsesDefaults() public {
        vm.prank(user1);
        uint256 id = factory.createMarket(PRICE_ID, STRIKE_PRICE, 3600, 0, 0);
        (, , , , , , , uint256 obId) = factory.marketMeta(id);
        (, , , , uint32 minLots, uint32 batchInterval, ) = book.markets(obId);
        assertEq(batchInterval, 60);
        assertEq(minLots, 1);
    }

    function test_CreateMarket_RevertIfPaused() public {
        vm.prank(admin);
        factory.pauseFactory(true);
        vm.expectRevert("MarketFactory: paused");
        vm.prank(user1);
        factory.createMarket(PRICE_ID, STRIKE_PRICE, 3600, 60, 1);
    }

    function test_CreateMarket_RevertIfNotCreatorRole() public {
        vm.expectRevert();
        vm.prank(user2);
        factory.createMarket(PRICE_ID, STRIKE_PRICE, 3600, 60, 1);
    }

    function test_CreateMarket_RevertIfZeroDuration() public {
        vm.expectRevert("MarketFactory: zero duration");
        vm.prank(user1);
        factory.createMarket(PRICE_ID, STRIKE_PRICE, 0, 0, 1);
    }

    function test_CreateMarket_RevertIfZeroPriceId() public {
        vm.expectRevert("MarketFactory: zero priceId");
        vm.prank(user1);
        factory.createMarket(bytes32(0), STRIKE_PRICE, 3600, 60, 1);
    }

    function test_CreateMarket_RevertIfDurationBelowBatchInterval() public {
        vm.expectRevert("MarketFactory: duration must exceed batchInterval");
        vm.prank(user1);
        factory.createMarket(PRICE_ID, STRIKE_PRICE, 600, 601, 1);
    }

    function test_CreateMarket_ShortDurationAllowed() public {
        // Short durations (e.g. 5 min) should be allowed — no minimum enforced
        vm.prank(user1);
        uint256 id = factory.createMarket(PRICE_ID, STRIKE_PRICE, 300, 12, 1);
        assertGt(id, 0);
    }

    function test_CloseMarket_Basic() public {
        vm.prank(user1);
        uint256 id = factory.createMarket(PRICE_ID, STRIKE_PRICE, 3600, 60, 1);
        vm.warp(block.timestamp + 3600);
        factory.closeMarket(id);

        (, , , , MarketState state, , , ) = factory.marketMeta(id);
        assertTrue(state == MarketState.Closed);
        assertEq(factory.getActiveMarketCount(), 0);
        assertEq(factory.getClosedMarketCount(), 1);
    }

    function test_CloseMarket_RevertIfNotExpired() public {
        vm.prank(user1);
        uint256 id = factory.createMarket(PRICE_ID, STRIKE_PRICE, 3600, 60, 1);
        vm.expectRevert("MarketFactory: not expired");
        factory.closeMarket(id);
    }

    function test_CloseMarket_RevertIfAlreadyClosed() public {
        vm.prank(user1);
        uint256 id = factory.createMarket(PRICE_ID, STRIKE_PRICE, 3600, 60, 1);
        vm.warp(block.timestamp + 3600);
        factory.closeMarket(id);
        vm.expectRevert("MarketFactory: not open");
        factory.closeMarket(id);
    }

    function test_CancelMarket_Basic() public {
        vm.prank(user1);
        uint256 id = factory.createMarket(PRICE_ID, STRIKE_PRICE, 3600, 60, 1);
        vm.warp(block.timestamp + 3600);
        factory.closeMarket(id);
        vm.warp(block.timestamp + 24 hours);
        factory.cancelMarket(id);

        (, , , , MarketState state, , , ) = factory.marketMeta(id);
        assertTrue(state == MarketState.Cancelled);
    }

    function test_CancelMarket_RevertIfTooEarly() public {
        vm.prank(user1);
        uint256 id = factory.createMarket(PRICE_ID, STRIKE_PRICE, 3600, 60, 1);
        vm.warp(block.timestamp + 3600);
        factory.closeMarket(id);
        vm.expectRevert("MarketFactory: too early to cancel");
        factory.cancelMarket(id);
    }

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
    }

    function test_StateTransition_FullLifecycle() public {
        vm.prank(user1);
        uint256 id = factory.createMarket(PRICE_ID, STRIKE_PRICE, 3600, 60, 1);
        assertEq(uint256(factory.getMarketState(id)), uint256(MarketState.Open));

        vm.warp(block.timestamp + 3600);
        factory.closeMarket(id);
        assertEq(uint256(factory.getMarketState(id)), uint256(MarketState.Closed));

        vm.prank(admin);
        factory.setResolving(id);
        assertEq(uint256(factory.getMarketState(id)), uint256(MarketState.Resolving));

        vm.prank(admin);
        factory.setResolved(id, true, 50000);
        assertEq(uint256(factory.getMarketState(id)), uint256(MarketState.Resolved));
    }

    function test_GetActiveMarketCount_MultipleMarkets() public {
        vm.startPrank(user1);
        factory.createMarket(PRICE_ID, STRIKE_PRICE, 3600, 60, 1);
        factory.createMarket(PRICE_ID, STRIKE_PRICE, 7200, 60, 1);
        factory.createMarket(PRICE_ID, STRIKE_PRICE, 10800, 60, 1);
        vm.stopPrank();

        assertEq(factory.getActiveMarketCount(), 3);

        vm.warp(block.timestamp + 3600);
        factory.closeMarket(1);
        assertEq(factory.getActiveMarketCount(), 2);
    }
}
