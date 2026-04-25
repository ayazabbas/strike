// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/ParimutuelFactory.sol";
import "../src/ParimutuelPoolManager.sol";
import "../src/ParimutuelTypes.sol";
import "../src/ParimutuelVault.sol";
import "./mocks/MockUSDT.sol";

contract FeeOnTransferUSDT is MockUSDT {
    uint256 public constant FEE_BPS = 100;

    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0)) {
            uint256 fee = value * FEE_BPS / 10_000;
            super._update(from, address(0), fee);
            super._update(from, to, value - fee);
            return;
        }

        super._update(from, to, value);
    }
}

contract ParimutuelPoolManagerTest is Test {
    ParimutuelFactory public factory;
    ParimutuelPoolManager public manager;
    ParimutuelVault public vault;
    MockUSDT public usdt;

    address public admin = address(0x1);
    address public creator = address(0x2);
    address public alice = address(0x3);
    address public bob = address(0x4);
    address public feeRecipient = address(0x5);

    function setUp() public {
        factory = new ParimutuelFactory(admin);
        usdt = new MockUSDT();
        vault = new ParimutuelVault(admin, address(usdt));
        manager = new ParimutuelPoolManager(admin, address(factory), address(vault), feeRecipient);

        vm.startPrank(admin);
        factory.setPoolManager(address(manager));
        factory.grantRole(factory.MARKET_CREATOR_ROLE(), creator);
        vault.grantRole(vault.PROTOCOL_ROLE(), address(manager));
        vm.stopPrank();

        usdt.mint(alice, 1_000_000e18);
        usdt.mint(bob, 1_000_000e18);

        vm.prank(alice);
        usdt.approve(address(manager), type(uint256).max);
        vm.prank(bob);
        usdt.approve(address(manager), type(uint256).max);
    }

    function _flatConfig(uint16 feeBps) internal view returns (ParimutuelMarketConfig memory config) {
        config = ParimutuelMarketConfig({
            closeTime: uint64(block.timestamp + 1 hours),
            outcomeCount: 3,
            resolverType: ParimutuelResolverType.Admin,
            fallbackResolverType: ParimutuelResolverType.Admin,
            curveType: ParimutuelCurveType.Flat,
            curveParam: 0,
            feeBps: feeBps,
            metadataHash: keccak256("flat-market"),
            metadataURI: "ipfs://strike/parimutuel/flat",
            resolverConfig: bytes("")
        });
    }

    function _piecewiseConfig() internal view returns (ParimutuelMarketConfig memory config) {
        config = ParimutuelMarketConfig({
            closeTime: uint64(block.timestamp + 1 hours),
            outcomeCount: 3,
            resolverType: ParimutuelResolverType.Admin,
            fallbackResolverType: ParimutuelResolverType.Admin,
            curveType: ParimutuelCurveType.PiecewiseBand,
            curveParam: 0,
            feeBps: 0,
            metadataHash: keccak256("piecewise-market"),
            metadataURI: "ipfs://strike/parimutuel/piecewise",
            resolverConfig: bytes("")
        });
    }

    function _logConfig(uint16 feeBps, uint128 liquidityParam)
        internal
        view
        returns (ParimutuelMarketConfig memory config)
    {
        config = ParimutuelMarketConfig({
            closeTime: uint64(block.timestamp + 1 hours),
            outcomeCount: 3,
            resolverType: ParimutuelResolverType.Admin,
            fallbackResolverType: ParimutuelResolverType.Admin,
            curveType: ParimutuelCurveType.IndependentLog,
            curveParam: liquidityParam,
            feeBps: feeBps,
            metadataHash: keccak256("log-market"),
            metadataURI: "ipfs://strike/parimutuel/log",
            resolverConfig: bytes("")
        });
    }

    function _createMarket(ParimutuelMarketConfig memory config) internal returns (uint256 marketId) {
        vm.prank(creator);
        marketId = factory.createMarket(config);
    }

    function test_QuoteBuy_RevertWhenManagerNotRegistered() public {
        ParimutuelPoolManager unregisteredManager =
            new ParimutuelPoolManager(admin, address(factory), address(vault), feeRecipient);
        uint256 marketId = _createMarket(_flatConfig(0));

        vm.expectRevert("ParimutuelPoolManager: manager not registered");
        unregisteredManager.quoteBuy(marketId, 0, 1e18);
    }

    function test_BuyMany_MaxOutcomeHedge_TracksSelectedOutcomes() public {
        ParimutuelMarketConfig memory config = _flatConfig(0);
        config.outcomeCount = 8;
        uint256 marketId = _createMarket(config);

        ParimutuelBuyParam[] memory buys = new ParimutuelBuyParam[](3);
        buys[0] = ParimutuelBuyParam({outcomeId: 0, amountIn: 10e18});
        buys[1] = ParimutuelBuyParam({outcomeId: 3, amountIn: 20e18});
        buys[2] = ParimutuelBuyParam({outcomeId: 7, amountIn: 30e18});

        vm.prank(alice);
        uint256 rewardSharesOut = manager.buyMany(marketId, buys, 60e18);

        assertEq(rewardSharesOut, 60e18);
        assertEq(manager.marketTotalPrincipal(marketId), 60e18);

        ParimutuelPosition memory outcome0 = manager.getUserPosition(marketId, alice, 0);
        ParimutuelPosition memory outcome3 = manager.getUserPosition(marketId, alice, 3);
        ParimutuelPosition memory outcome7 = manager.getUserPosition(marketId, alice, 7);
        assertEq(outcome0.principal, 10e18);
        assertEq(outcome3.principal, 20e18);
        assertEq(outcome7.principal, 30e18);
    }

    function test_QuoteBuy_FlatCurve_NetEqualsRewardShares() public {
        uint256 marketId = _createMarket(_flatConfig(100));

        (uint256 feeAmount, uint256 principalAdded, uint256 rewardSharesOut) = manager.quoteBuy(marketId, 1, 200e18);

        assertEq(feeAmount, 2e18);
        assertEq(principalAdded, 198e18);
        assertEq(rewardSharesOut, 198e18);
    }

    function test_BuyMany_RevertIfCollateralTransferShortfall() public {
        FeeOnTransferUSDT taxedUsdt = new FeeOnTransferUSDT();
        ParimutuelFactory taxedFactory = new ParimutuelFactory(admin);
        ParimutuelVault taxedVault = new ParimutuelVault(admin, address(taxedUsdt));
        ParimutuelPoolManager taxedManager =
            new ParimutuelPoolManager(admin, address(taxedFactory), address(taxedVault), feeRecipient);

        vm.startPrank(admin);
        taxedFactory.setPoolManager(address(taxedManager));
        taxedFactory.grantRole(taxedFactory.MARKET_CREATOR_ROLE(), creator);
        taxedVault.grantRole(taxedVault.PROTOCOL_ROLE(), address(taxedManager));
        vm.stopPrank();

        taxedUsdt.mint(alice, 100e18);
        vm.prank(alice);
        taxedUsdt.approve(address(taxedManager), type(uint256).max);

        vm.prank(creator);
        uint256 marketId = taxedFactory.createMarket(_flatConfig(0));

        vm.expectRevert("ParimutuelPoolManager: collateral transfer shortfall");
        vm.prank(alice);
        taxedManager.buy(marketId, 0, 10e18, 10e18);

        assertEq(taxedUsdt.balanceOf(address(taxedVault)), 0);
        assertEq(taxedManager.marketTotalPrincipal(marketId), 0);
    }

    function test_BuyMany_FlatCurve_TracksPrincipalAndRewardShares() public {
        uint256 marketId = _createMarket(_flatConfig(100));

        ParimutuelBuyParam[] memory buys = new ParimutuelBuyParam[](2);
        buys[0] = ParimutuelBuyParam({outcomeId: 0, amountIn: 100e18});
        buys[1] = ParimutuelBuyParam({outcomeId: 2, amountIn: 50e18});

        vm.prank(alice);
        uint256 totalRewardSharesOut = manager.buyMany(marketId, buys, 148_500000000000000000);

        assertEq(totalRewardSharesOut, 148_500000000000000000);
        assertEq(manager.marketTotalPrincipal(marketId), 148_500000000000000000);
        assertEq(manager.accruedFees(), 1_500000000000000000);
        assertEq(usdt.balanceOf(address(manager)), 0);
        assertEq(usdt.balanceOf(address(vault)), 150e18);

        ParimutuelOutcomePool memory outcome0 = manager.getOutcomePool(marketId, 0);
        ParimutuelOutcomePool memory outcome2 = manager.getOutcomePool(marketId, 2);
        ParimutuelPosition memory user0 = manager.getUserPosition(marketId, alice, 0);
        ParimutuelPosition memory user2 = manager.getUserPosition(marketId, alice, 2);

        assertEq(outcome0.principal, 99e18);
        assertEq(outcome0.rewardShares, 99e18);
        assertEq(outcome2.principal, 49_500000000000000000);
        assertEq(outcome2.rewardShares, 49_500000000000000000);
        assertEq(user0.principal, 99e18);
        assertEq(user0.rewardShares, 99e18);
        assertEq(user2.principal, 49_500000000000000000);
        assertEq(user2.rewardShares, 49_500000000000000000);
    }

    function test_QuoteBuyMany_SequentiallyPricesAgainstUpdatedPoolState() public {
        uint256 marketId = _createMarket(_flatConfig(0));

        ParimutuelBuyParam[] memory buys = new ParimutuelBuyParam[](2);
        buys[0] = ParimutuelBuyParam({outcomeId: 1, amountIn: 40e18});
        buys[1] = ParimutuelBuyParam({outcomeId: 1, amountIn: 60e18});

        (
            uint256 totalAmountIn,
            uint256 totalFeeAmount,
            uint256 totalPrincipalAdded,
            uint256 totalRewardSharesOut,
            uint256[] memory rewardSharesByBuy
        ) = manager.quoteBuyMany(marketId, buys);

        assertEq(totalAmountIn, 100e18);
        assertEq(totalFeeAmount, 0);
        assertEq(totalPrincipalAdded, 100e18);
        assertEq(totalRewardSharesOut, 100e18);
        assertEq(rewardSharesByBuy.length, 2);
        assertEq(rewardSharesByBuy[0], 40e18);
        assertEq(rewardSharesByBuy[1], 60e18);
    }

    function test_QuoteBuy_RevertWhenBelowMinimumBuyAmount() public {
        uint256 marketId = _createMarket(_logConfig(0, 40_000e18));

        uint256 minBuyAmountIn = manager.MIN_BUY_AMOUNT_IN();

        vm.expectRevert("ParimutuelPoolManager: below min buy");
        manager.quoteBuy(marketId, 0, minBuyAmountIn - 1);
    }

    function test_QuoteBuy_MinimumBuyAmountProducesRewardShares() public {
        uint256 marketId = _createMarket(_logConfig(0, 40_000e18));

        uint256 minBuyAmountIn = manager.MIN_BUY_AMOUNT_IN();
        (, uint256 principalAdded, uint256 rewardSharesOut) = manager.quoteBuy(marketId, 0, minBuyAmountIn);

        assertEq(principalAdded, minBuyAmountIn);
        assertGt(rewardSharesOut, 0);
    }

    function test_QuoteBuy_RevertWhenFeeConsumesPrincipal() public {
        uint256 marketId = _createMarket(_flatConfig(10_000));

        vm.expectRevert("ParimutuelPoolManager: zero principal");
        manager.quoteBuy(marketId, 0, 1e18);
    }

    function test_QuoteBuy_IndependentLogCurve_UsesCurveParam() public {
        uint256 marketId = _createMarket(_logConfig(0, 40_000e18));

        (uint256 feeAmount, uint256 principalAdded, uint256 rewardSharesOut) = manager.quoteBuy(marketId, 0, 10_000e18);

        assertEq(feeAmount, 0);
        assertEq(principalAdded, 10_000e18);
        assertApproxEqAbs(rewardSharesOut, 8_925_742052568390230651, 1e6);
    }

    function test_BuyMany_IndependentLogCurve_SequentiallyPricesSameOutcome() public {
        uint256 marketId = _createMarket(_logConfig(0, 40_000e18));

        ParimutuelBuyParam[] memory buys = new ParimutuelBuyParam[](2);
        buys[0] = ParimutuelBuyParam({outcomeId: 0, amountIn: 5_000e18});
        buys[1] = ParimutuelBuyParam({outcomeId: 0, amountIn: 5_000e18});

        (,,,, uint256[] memory rewardSharesByBuy) = manager.quoteBuyMany(marketId, buys);

        uint256 oneShotExpected = 8_925_742052568390230651;
        assertApproxEqAbs(rewardSharesByBuy[0] + rewardSharesByBuy[1], oneShotExpected, 1e9);

        vm.prank(alice);
        uint256 totalRewardSharesOut = manager.buyMany(marketId, buys, oneShotExpected - 1e9);

        assertApproxEqAbs(totalRewardSharesOut, oneShotExpected, 1e9);

        ParimutuelOutcomePool memory outcome0 = manager.getOutcomePool(marketId, 0);
        ParimutuelPosition memory user0 = manager.getUserPosition(marketId, alice, 0);

        assertEq(outcome0.principal, 10_000e18);
        assertApproxEqAbs(outcome0.rewardShares, oneShotExpected, 1e9);
        assertEq(user0.principal, 10_000e18);
        assertApproxEqAbs(user0.rewardShares, oneShotExpected, 1e9);
    }

    function test_PiecewiseCurve_ConfiguresBandsAndQuotes() public {
        uint256 marketId = _createMarket(_piecewiseConfig());

        ParimutuelPiecewiseBand[] memory bands = new ParimutuelPiecewiseBand[](2);
        bands[0] = ParimutuelPiecewiseBand({upperBound: 100e18, rateBps: 10_000});
        bands[1] = ParimutuelPiecewiseBand({upperBound: 200e18, rateBps: 5_000});

        vm.prank(admin);
        manager.configurePiecewiseBands(marketId, bands, 2_500);

        (uint256 feeAmount, uint256 principalAdded, uint256 rewardSharesOut) = manager.quoteBuy(marketId, 0, 150e18);

        assertEq(feeAmount, 0);
        assertEq(principalAdded, 150e18);
        assertEq(rewardSharesOut, 125e18);
    }

    function test_PreviewClaim_SplitsLosingPoolsByRewardShares() public {
        uint256 marketId = _createMarket(_flatConfig(0));

        ParimutuelBuyParam[] memory aliceBuys = new ParimutuelBuyParam[](1);
        aliceBuys[0] = ParimutuelBuyParam({outcomeId: 1, amountIn: 100e18});
        vm.prank(alice);
        manager.buyMany(marketId, aliceBuys, 100e18);

        ParimutuelBuyParam[] memory bobWinnerBuys = new ParimutuelBuyParam[](1);
        bobWinnerBuys[0] = ParimutuelBuyParam({outcomeId: 1, amountIn: 300e18});
        vm.prank(bob);
        manager.buyMany(marketId, bobWinnerBuys, 300e18);

        ParimutuelBuyParam[] memory bobLoserBuys = new ParimutuelBuyParam[](1);
        bobLoserBuys[0] = ParimutuelBuyParam({outcomeId: 0, amountIn: 200e18});
        vm.prank(bob);
        manager.buyMany(marketId, bobLoserBuys, 200e18);

        vm.warp(block.timestamp + 1 hours);
        factory.closeMarket(marketId);

        vm.prank(admin);
        factory.resolveToWinner(marketId, 1);

        (uint256 alicePrincipalBack, uint256 aliceBonus, uint256 alicePayout) = manager.previewClaim(marketId, alice);
        (,, uint256 bobPayout) = manager.previewClaim(marketId, bob);

        assertEq(alicePrincipalBack, 100e18);
        assertEq(aliceBonus, 50e18);
        assertEq(alicePayout, 150e18);
        assertEq(bobPayout, 450e18);
    }

    function test_PreviewRefund_InvalidMarket_ReturnsPrincipal() public {
        uint256 marketId = _createMarket(_flatConfig(0));

        ParimutuelBuyParam[] memory buys = new ParimutuelBuyParam[](2);
        buys[0] = ParimutuelBuyParam({outcomeId: 0, amountIn: 25e18});
        buys[1] = ParimutuelBuyParam({outcomeId: 2, amountIn: 35e18});

        vm.prank(alice);
        manager.buyMany(marketId, buys, 60e18);

        vm.warp(block.timestamp + 1 hours);
        factory.closeMarket(marketId);

        vm.prank(admin);
        factory.resolveInvalid(marketId);

        uint8[] memory outcomeIds = new uint8[](2);
        outcomeIds[0] = 0;
        outcomeIds[1] = 2;

        uint256 refundAmount = manager.previewRefund(marketId, alice, outcomeIds);

        assertEq(refundAmount, 60e18);
    }

    function test_WithdrawFees_PaysOutFromVault() public {
        uint256 marketId = _createMarket(_flatConfig(100));

        ParimutuelBuyParam[] memory buys = new ParimutuelBuyParam[](1);
        buys[0] = ParimutuelBuyParam({outcomeId: 0, amountIn: 200e18});

        vm.prank(alice);
        manager.buyMany(marketId, buys, 198e18);

        uint256 feeRecipientBalanceBefore = usdt.balanceOf(feeRecipient);
        vm.prank(admin);
        manager.withdrawFees(2e18);

        assertEq(manager.accruedFees(), 0);
        assertEq(usdt.balanceOf(feeRecipient), feeRecipientBalanceBefore + 2e18);
        assertEq(usdt.balanceOf(address(vault)), 198e18);
    }
}
