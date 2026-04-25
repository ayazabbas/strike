// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/ParimutuelFactory.sol";
import "../src/ParimutuelTypes.sol";

contract ParimutuelFactoryTest is Test {
    ParimutuelFactory public factory;

    address public admin = address(0x1);
    address public creator = address(0x2);
    address public user = address(0x3);

    function setUp() public {
        factory = new ParimutuelFactory(admin);

        vm.startPrank(admin);
        factory.grantRole(factory.MARKET_CREATOR_ROLE(), creator);
        vm.stopPrank();
    }

    function _defaultConfig() internal view returns (ParimutuelMarketConfig memory config) {
        config = ParimutuelMarketConfig({
            closeTime: uint64(block.timestamp + 1 hours),
            outcomeCount: 3,
            resolverType: ParimutuelResolverType.AI,
            fallbackResolverType: ParimutuelResolverType.Admin,
            curveType: ParimutuelCurveType.IndependentLog,
            curveParam: factory.INDEPENDENT_LOG_LIQUIDITY_RECOMMENDED(),
            feeBps: 50,
            metadataHash: keccak256("market-metadata"),
            metadataURI: "ipfs://strike/parimutuel/1",
            resolverConfig: abi.encode("model:sonnet")
        });
    }

    function test_CreateMarket_Basic() public {
        ParimutuelMarketConfig memory config = _defaultConfig();

        vm.prank(creator);
        uint256 marketId = factory.createMarket(config);

        assertEq(marketId, 1);

        ParimutuelMarket memory market = factory.getMarket(marketId);
        assertEq(market.marketId, 1);
        assertEq(market.creator, creator);
        assertEq(market.closeTime, config.closeTime);
        assertEq(market.outcomeCount, config.outcomeCount);
        assertEq(uint8(market.state), uint8(ParimutuelMarketState.Open));
        assertEq(uint8(market.resolverType), uint8(ParimutuelResolverType.AI));
        assertEq(uint8(market.fallbackResolverType), uint8(ParimutuelResolverType.Admin));
        assertEq(uint8(market.curveType), uint8(ParimutuelCurveType.IndependentLog));
        assertEq(market.curveParam, config.curveParam);
        assertEq(market.feeBps, config.feeBps);
        assertEq(market.metadataHash, config.metadataHash);
        assertEq(market.metadataURI, config.metadataURI);
        assertEq(factory.nextMarketId(), 2);
    }

    function test_CreateMarket_RevertOnInvalidOutcomeCount() public {
        ParimutuelMarketConfig memory config = _defaultConfig();
        config.outcomeCount = 1;

        vm.expectRevert("ParimutuelFactory: invalid outcomeCount");
        vm.prank(creator);
        factory.createMarket(config);

        config.outcomeCount = 9;
        vm.expectRevert("ParimutuelFactory: invalid outcomeCount");
        vm.prank(creator);
        factory.createMarket(config);
    }

    function test_CreateMarket_RevertOnNonAdminFallback() public {
        ParimutuelMarketConfig memory config = _defaultConfig();
        config.fallbackResolverType = ParimutuelResolverType.Pyth;

        vm.expectRevert("ParimutuelFactory: fallback must be admin");
        vm.prank(creator);
        factory.createMarket(config);
    }

    function test_CreateMarket_RevertOnInvalidFee() public {
        ParimutuelMarketConfig memory config = _defaultConfig();
        config.feeBps = 10_001;

        vm.expectRevert("ParimutuelFactory: invalid fee");
        vm.prank(creator);
        factory.createMarket(config);
    }

    function test_CreateMarket_RevertOnInvalidCurveParamForFlatAndPiecewise() public {
        ParimutuelMarketConfig memory config = _defaultConfig();
        config.curveType = ParimutuelCurveType.Flat;
        config.curveParam = 1;

        vm.expectRevert("ParimutuelFactory: invalid curve param");
        vm.prank(creator);
        factory.createMarket(config);

        config.curveType = ParimutuelCurveType.PiecewiseBand;
        vm.expectRevert("ParimutuelFactory: invalid curve param");
        vm.prank(creator);
        factory.createMarket(config);
    }

    function test_CreateMarket_IndependentLogLiquidityBoundsAndPresets() public {
        assertEq(factory.INDEPENDENT_LOG_LIQUIDITY_RECOMMENDED(), 40_000e18);
        assertEq(factory.INDEPENDENT_LOG_LIQUIDITY_CONSERVATIVE(), 100_000e18);

        ParimutuelMarketConfig memory config = _defaultConfig();
        config.curveParam = factory.INDEPENDENT_LOG_LIQUIDITY_MIN() - 1;

        vm.expectRevert("ParimutuelFactory: invalid log liquidity");
        vm.prank(creator);
        factory.createMarket(config);

        config.curveParam = factory.INDEPENDENT_LOG_LIQUIDITY_MAX() + 1;
        vm.expectRevert("ParimutuelFactory: invalid log liquidity");
        vm.prank(creator);
        factory.createMarket(config);

        config.curveParam = factory.INDEPENDENT_LOG_LIQUIDITY_MIN();
        vm.prank(creator);
        uint256 minMarketId = factory.createMarket(config);
        assertEq(factory.getMarket(minMarketId).curveParam, factory.INDEPENDENT_LOG_LIQUIDITY_MIN());

        config.curveParam = factory.INDEPENDENT_LOG_LIQUIDITY_MAX();
        vm.prank(creator);
        uint256 maxMarketId = factory.createMarket(config);
        assertEq(factory.getMarket(maxMarketId).curveParam, factory.INDEPENDENT_LOG_LIQUIDITY_MAX());
    }

    function test_SetPoolManager_AdminOnlyAndRejectsZero() public {
        address poolManager = address(0xBEEF);

        vm.expectRevert();
        vm.prank(user);
        factory.setPoolManager(poolManager);

        vm.expectRevert("ParimutuelFactory: zero pool manager");
        vm.prank(admin);
        factory.setPoolManager(address(0));

        vm.prank(admin);
        factory.setPoolManager(poolManager);

        assertEq(factory.poolManager(), poolManager);

        vm.expectRevert("ParimutuelFactory: pool manager already set");
        vm.prank(admin);
        factory.setPoolManager(address(0xCAFE));
    }

    function test_CreateMarket_AllowsMaxOutcomeCount() public {
        ParimutuelMarketConfig memory config = _defaultConfig();
        config.outcomeCount = 8;

        vm.prank(creator);
        uint256 marketId = factory.createMarket(config);

        ParimutuelMarket memory market = factory.getMarket(marketId);
        assertEq(market.outcomeCount, 8);

        vm.warp(config.closeTime);
        factory.closeMarket(marketId);

        vm.prank(admin);
        factory.resolveToWinner(marketId, 7);

        assertEq(factory.getMarket(marketId).winningOutcomeId, 7);
    }

    function test_FallbackToAdmin_FromPythResolving() public {
        ParimutuelMarketConfig memory config = _defaultConfig();
        config.resolverType = ParimutuelResolverType.Pyth;
        config.resolverConfig = abi.encode("BTC/USD", int256(100_000e8));

        vm.prank(creator);
        uint256 marketId = factory.createMarket(config);

        vm.warp(config.closeTime);
        factory.closeMarket(marketId);

        vm.prank(admin);
        factory.requestResolution(marketId);
        assertEq(uint8(factory.currentResolverType(marketId)), uint8(ParimutuelResolverType.Pyth));

        vm.prank(admin);
        factory.fallbackToAdmin(marketId);

        ParimutuelMarket memory market = factory.getMarket(marketId);
        assertTrue(market.adminFallbackActivated);
        assertEq(uint8(market.state), uint8(ParimutuelMarketState.Resolving));
        assertEq(uint8(factory.currentResolverType(marketId)), uint8(ParimutuelResolverType.Admin));
    }

    function test_CloseMarket_AfterExpiry() public {
        ParimutuelMarketConfig memory config = _defaultConfig();

        vm.prank(creator);
        uint256 marketId = factory.createMarket(config);

        vm.warp(config.closeTime);
        factory.closeMarket(marketId);

        assertEq(uint8(factory.getMarketState(marketId)), uint8(ParimutuelMarketState.Closed));
    }

    function test_RequestResolution_AdminOnly() public {
        ParimutuelMarketConfig memory config = _defaultConfig();

        vm.prank(creator);
        uint256 marketId = factory.createMarket(config);

        vm.warp(config.closeTime);
        factory.closeMarket(marketId);

        vm.expectRevert();
        vm.prank(user);
        factory.requestResolution(marketId);

        vm.prank(admin);
        factory.requestResolution(marketId);

        assertEq(uint8(factory.getMarketState(marketId)), uint8(ParimutuelMarketState.Resolving));
        assertEq(uint8(factory.currentResolverType(marketId)), uint8(ParimutuelResolverType.AI));
    }

    function test_FallbackToAdmin_ChangesEffectiveResolver() public {
        ParimutuelMarketConfig memory config = _defaultConfig();

        vm.prank(creator);
        uint256 marketId = factory.createMarket(config);

        vm.warp(config.closeTime);
        factory.closeMarket(marketId);

        vm.prank(admin);
        factory.fallbackToAdmin(marketId);

        ParimutuelMarket memory market = factory.getMarket(marketId);
        assertTrue(market.adminFallbackActivated);
        assertEq(uint8(factory.getMarketState(marketId)), uint8(ParimutuelMarketState.Resolving));
        assertEq(uint8(factory.currentResolverType(marketId)), uint8(ParimutuelResolverType.Admin));
    }

    function test_ResolveToWinner_Basic() public {
        ParimutuelMarketConfig memory config = _defaultConfig();

        vm.prank(creator);
        uint256 marketId = factory.createMarket(config);

        vm.warp(config.closeTime);
        factory.closeMarket(marketId);

        vm.prank(admin);
        factory.resolveToWinner(marketId, 2);

        ParimutuelMarket memory market = factory.getMarket(marketId);
        assertEq(uint8(market.state), uint8(ParimutuelMarketState.Resolved));
        assertTrue(market.hasWinner);
        assertEq(market.winningOutcomeId, 2);
    }

    function test_ResolveToWinner_RevertOnInvalidOutcome() public {
        ParimutuelMarketConfig memory config = _defaultConfig();

        vm.prank(creator);
        uint256 marketId = factory.createMarket(config);

        vm.warp(config.closeTime);
        factory.closeMarket(marketId);

        vm.expectRevert("ParimutuelFactory: invalid winningOutcomeId");
        vm.prank(admin);
        factory.resolveToWinner(marketId, 3);
    }

    function test_ResolveInvalid_Basic() public {
        ParimutuelMarketConfig memory config = _defaultConfig();

        vm.prank(creator);
        uint256 marketId = factory.createMarket(config);

        vm.warp(config.closeTime);
        factory.closeMarket(marketId);

        vm.prank(admin);
        factory.resolveInvalid(marketId);

        assertEq(uint8(factory.getMarketState(marketId)), uint8(ParimutuelMarketState.Invalid));
    }

    function test_CancelMarket_Basic() public {
        ParimutuelMarketConfig memory config = _defaultConfig();

        vm.prank(creator);
        uint256 marketId = factory.createMarket(config);

        vm.prank(admin);
        factory.cancelMarket(marketId);

        assertEq(uint8(factory.getMarketState(marketId)), uint8(ParimutuelMarketState.Cancelled));
    }

    function test_PauseFactory_BlocksCreation() public {
        ParimutuelMarketConfig memory config = _defaultConfig();

        vm.prank(admin);
        factory.pauseFactory(true);

        vm.expectRevert("ParimutuelFactory: paused");
        vm.prank(creator);
        factory.createMarket(config);
    }
}
