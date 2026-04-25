// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/ParimutuelFactory.sol";
import "../src/ParimutuelPoolManager.sol";
import "../src/ParimutuelRedemption.sol";
import "../src/ParimutuelTypes.sol";
import "../src/ParimutuelVault.sol";
import "./mocks/MockUSDT.sol";

contract ParimutuelRedemptionTest is Test {
    ParimutuelFactory public factory;
    ParimutuelPoolManager public manager;
    ParimutuelRedemption public redemption;
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
        redemption = new ParimutuelRedemption(admin, address(manager), address(vault));

        vm.startPrank(admin);
        factory.setPoolManager(address(manager));
        factory.grantRole(factory.MARKET_CREATOR_ROLE(), creator);
        manager.grantRole(manager.REDEMPTION_ROLE(), address(redemption));
        vault.grantRole(vault.PROTOCOL_ROLE(), address(manager));
        vault.grantRole(vault.PROTOCOL_ROLE(), address(redemption));
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

    function _createMarket(ParimutuelMarketConfig memory config) internal returns (uint256 marketId) {
        vm.prank(creator);
        marketId = factory.createMarket(config);
    }

    function test_Claim_RevertIfRedemptionContractMissingManagerRole() public {
        ParimutuelRedemption untrustedRedemption = new ParimutuelRedemption(admin, address(manager), address(vault));
        uint256 marketId = _createMarket(_flatConfig(0));

        ParimutuelBuyParam[] memory buys = new ParimutuelBuyParam[](1);
        buys[0] = ParimutuelBuyParam({outcomeId: 1, amountIn: 100e18});
        vm.prank(alice);
        manager.buyMany(marketId, buys, 100e18);

        vm.warp(block.timestamp + 1 hours);
        factory.closeMarket(marketId);

        vm.prank(admin);
        factory.resolveToWinner(marketId, 1);

        vm.expectRevert();
        vm.prank(alice);
        untrustedRedemption.claim(marketId);
    }

    function test_Claim_AllWinnersDrainPrincipalWithoutRoundingDust() public {
        uint256 marketId = _createMarket(_flatConfig(0));

        ParimutuelBuyParam[] memory aliceBuys = new ParimutuelBuyParam[](1);
        aliceBuys[0] = ParimutuelBuyParam({outcomeId: 1, amountIn: 1e18});
        vm.prank(alice);
        manager.buyMany(marketId, aliceBuys, 1e18);

        ParimutuelBuyParam[] memory bobWinnerBuys = new ParimutuelBuyParam[](1);
        bobWinnerBuys[0] = ParimutuelBuyParam({outcomeId: 1, amountIn: 2e18});
        vm.prank(bob);
        manager.buyMany(marketId, bobWinnerBuys, 2e18);

        ParimutuelBuyParam[] memory bobLoserBuys = new ParimutuelBuyParam[](1);
        bobLoserBuys[0] = ParimutuelBuyParam({outcomeId: 0, amountIn: 1e18});
        vm.prank(bob);
        manager.buyMany(marketId, bobLoserBuys, 1e18);

        vm.warp(block.timestamp + 1 hours);
        factory.closeMarket(marketId);

        vm.prank(admin);
        factory.resolveToWinner(marketId, 1);

        vm.prank(alice);
        uint256 alicePayout = redemption.claim(marketId);
        assertEq(alicePayout, 1_333_333_333_333_333_333);

        vm.prank(bob);
        uint256 bobPayout = redemption.claim(marketId);
        assertEq(bobPayout, 2_666_666_666_666_666_667);

        assertEq(usdt.balanceOf(address(vault)), 0);
        assertEq(manager.marketTotalPrincipal(marketId), 0);
    }

    function test_Claim_AllWinnersDrainVaultExceptFeesThenFeesWithdraw() public {
        uint256 marketId = _createMarket(_flatConfig(50));

        ParimutuelBuyParam[] memory aliceWinnerBuys = new ParimutuelBuyParam[](1);
        aliceWinnerBuys[0] = ParimutuelBuyParam({outcomeId: 1, amountIn: 100e18});
        vm.prank(alice);
        manager.buyMany(marketId, aliceWinnerBuys, 1);

        ParimutuelBuyParam[] memory bobWinnerBuys = new ParimutuelBuyParam[](1);
        bobWinnerBuys[0] = ParimutuelBuyParam({outcomeId: 1, amountIn: 200e18});
        vm.prank(bob);
        manager.buyMany(marketId, bobWinnerBuys, 1);

        ParimutuelBuyParam[] memory bobLoserBuys = new ParimutuelBuyParam[](1);
        bobLoserBuys[0] = ParimutuelBuyParam({outcomeId: 0, amountIn: 100e18});
        vm.prank(bob);
        manager.buyMany(marketId, bobLoserBuys, 1);

        assertEq(usdt.balanceOf(address(vault)), 400e18);
        assertEq(manager.accruedFees(), 2e18);

        vm.warp(block.timestamp + 1 hours);
        factory.closeMarket(marketId);

        vm.prank(admin);
        factory.resolveToWinner(marketId, 1);

        vm.prank(alice);
        redemption.claim(marketId);
        vm.prank(bob);
        redemption.claim(marketId);

        assertEq(manager.marketTotalPrincipal(marketId), 0);
        assertEq(usdt.balanceOf(address(vault)), manager.accruedFees());
        assertEq(usdt.balanceOf(address(vault)), 2e18);

        uint256 accruedFees = manager.accruedFees();
        vm.prank(admin);
        manager.withdrawFees(accruedFees);

        assertEq(usdt.balanceOf(address(vault)), 0);
        assertEq(usdt.balanceOf(feeRecipient), 2e18);
    }

    function test_Claim_OrderPermutationPaysSameTotalAndNoDustStranded() public {
        uint256 aliceFirstMarketId = _createMarket(_flatConfig(0));
        _fundRoundingClaimScenario(aliceFirstMarketId);
        _resolveWinner(aliceFirstMarketId, 1);

        vm.prank(alice);
        uint256 aliceFirstPayout = redemption.claim(aliceFirstMarketId);
        vm.prank(bob);
        uint256 bobSecondPayout = redemption.claim(aliceFirstMarketId);

        assertEq(aliceFirstPayout + bobSecondPayout, 4e18);
        assertEq(usdt.balanceOf(address(vault)), 0);
        assertEq(manager.marketTotalPrincipal(aliceFirstMarketId), 0);

        uint256 bobFirstMarketId = _createMarket(_flatConfig(0));
        _fundRoundingClaimScenario(bobFirstMarketId);
        _resolveWinner(bobFirstMarketId, 1);

        vm.prank(bob);
        uint256 bobFirstPayout = redemption.claim(bobFirstMarketId);
        vm.prank(alice);
        uint256 aliceSecondPayout = redemption.claim(bobFirstMarketId);

        assertEq(bobFirstPayout + aliceSecondPayout, 4e18);
        assertEq(usdt.balanceOf(address(vault)), 0);
        assertEq(manager.marketTotalPrincipal(bobFirstMarketId), 0);
    }

    function test_Claim_UserWithWinningAndLosingPositionsReceivesOnlyWinningPayout() public {
        uint256 marketId = _createMarket(_flatConfig(0));

        ParimutuelBuyParam[] memory aliceBuys = new ParimutuelBuyParam[](2);
        aliceBuys[0] = ParimutuelBuyParam({outcomeId: 1, amountIn: 100e18});
        aliceBuys[1] = ParimutuelBuyParam({outcomeId: 0, amountIn: 50e18});
        vm.prank(alice);
        manager.buyMany(marketId, aliceBuys, 150e18);

        ParimutuelBuyParam[] memory bobBuys = new ParimutuelBuyParam[](1);
        bobBuys[0] = ParimutuelBuyParam({outcomeId: 0, amountIn: 150e18});
        vm.prank(bob);
        manager.buyMany(marketId, bobBuys, 150e18);

        _resolveWinner(marketId, 1);

        uint256 balanceBefore = usdt.balanceOf(alice);
        vm.prank(alice);
        uint256 payout = redemption.claim(marketId);

        assertEq(payout, 300e18);
        assertEq(usdt.balanceOf(alice), balanceBefore + 300e18);
        assertEq(usdt.balanceOf(address(vault)), 0);
        assertEq(manager.marketTotalPrincipal(marketId), 0);
    }

    function test_Claim_PaysThroughRedemptionContract() public {
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

        uint256 aliceBalanceBefore = usdt.balanceOf(alice);
        vm.prank(alice);
        uint256 payout = redemption.claim(marketId);

        assertEq(payout, 150e18);
        assertEq(usdt.balanceOf(alice), aliceBalanceBefore + 150e18);
        assertEq(usdt.balanceOf(address(vault)), 450e18);

        ParimutuelPosition memory aliceWinnerPosition = manager.getUserPosition(marketId, alice, 1);
        assertEq(aliceWinnerPosition.principal, 0);
        assertEq(aliceWinnerPosition.rewardShares, 0);
    }

    function test_ResolveToWinner_RevertIfWinningOutcomeHasNoLiquidity() public {
        uint256 marketId = _createMarket(_flatConfig(0));

        ParimutuelBuyParam[] memory buys = new ParimutuelBuyParam[](1);
        buys[0] = ParimutuelBuyParam({outcomeId: 0, amountIn: 25e18});
        vm.prank(alice);
        manager.buyMany(marketId, buys, 25e18);

        vm.warp(block.timestamp + 1 hours);
        factory.closeMarket(marketId);

        vm.expectRevert("ParimutuelFactory: empty winning outcome");
        vm.prank(admin);
        factory.resolveToWinner(marketId, 1);

        vm.prank(admin);
        factory.resolveInvalid(marketId);
    }

    function test_Refund_RevertOnDuplicateOutcomeIds() public {
        uint256 marketId = _createMarket(_flatConfig(0));

        ParimutuelBuyParam[] memory buys = new ParimutuelBuyParam[](1);
        buys[0] = ParimutuelBuyParam({outcomeId: 0, amountIn: 25e18});

        vm.prank(alice);
        manager.buyMany(marketId, buys, 25e18);

        vm.warp(block.timestamp + 1 hours);
        factory.closeMarket(marketId);

        vm.prank(admin);
        factory.resolveInvalid(marketId);

        uint8[] memory outcomeIds = new uint8[](2);
        outcomeIds[0] = 0;
        outcomeIds[1] = 0;

        vm.expectRevert("ParimutuelPoolManager: duplicate outcomeId");
        vm.prank(alice);
        redemption.refund(marketId, outcomeIds);
    }

    function test_Refund_AllRefundsLeaveOnlyAccruedFeesThenFeesWithdraw() public {
        uint256 marketId = _createMarket(_flatConfig(50));

        ParimutuelBuyParam[] memory aliceBuys = new ParimutuelBuyParam[](2);
        aliceBuys[0] = ParimutuelBuyParam({outcomeId: 0, amountIn: 25e18});
        aliceBuys[1] = ParimutuelBuyParam({outcomeId: 2, amountIn: 35e18});
        vm.prank(alice);
        manager.buyMany(marketId, aliceBuys, 1);

        ParimutuelBuyParam[] memory bobBuys = new ParimutuelBuyParam[](1);
        bobBuys[0] = ParimutuelBuyParam({outcomeId: 1, amountIn: 40e18});
        vm.prank(bob);
        manager.buyMany(marketId, bobBuys, 1);

        vm.warp(block.timestamp + 1 hours);
        factory.closeMarket(marketId);

        vm.prank(admin);
        factory.resolveInvalid(marketId);

        uint8[] memory aliceOutcomeIds = new uint8[](2);
        aliceOutcomeIds[0] = 0;
        aliceOutcomeIds[1] = 2;
        vm.prank(alice);
        redemption.refund(marketId, aliceOutcomeIds);

        uint8[] memory bobOutcomeIds = new uint8[](1);
        bobOutcomeIds[0] = 1;
        vm.prank(bob);
        redemption.refund(marketId, bobOutcomeIds);

        assertEq(manager.marketTotalPrincipal(marketId), 0);
        assertEq(usdt.balanceOf(address(vault)), manager.accruedFees());
        assertEq(manager.accruedFees(), 0.5e18);

        uint256 accruedFees = manager.accruedFees();
        vm.prank(admin);
        manager.withdrawFees(accruedFees);

        assertEq(usdt.balanceOf(address(vault)), 0);
        assertEq(usdt.balanceOf(feeRecipient), 0.5e18);
    }

    function _fundRoundingClaimScenario(uint256 marketId) internal {
        ParimutuelBuyParam[] memory aliceBuys = new ParimutuelBuyParam[](1);
        aliceBuys[0] = ParimutuelBuyParam({outcomeId: 1, amountIn: 1e18});
        vm.prank(alice);
        manager.buyMany(marketId, aliceBuys, 1e18);

        ParimutuelBuyParam[] memory bobWinnerBuys = new ParimutuelBuyParam[](1);
        bobWinnerBuys[0] = ParimutuelBuyParam({outcomeId: 1, amountIn: 2e18});
        vm.prank(bob);
        manager.buyMany(marketId, bobWinnerBuys, 2e18);

        ParimutuelBuyParam[] memory bobLoserBuys = new ParimutuelBuyParam[](1);
        bobLoserBuys[0] = ParimutuelBuyParam({outcomeId: 0, amountIn: 1e18});
        vm.prank(bob);
        manager.buyMany(marketId, bobLoserBuys, 1e18);
    }

    function _resolveWinner(uint256 marketId, uint8 winningOutcomeId) internal {
        vm.warp(block.timestamp + 1 hours);
        factory.closeMarket(marketId);

        vm.prank(admin);
        factory.resolveToWinner(marketId, winningOutcomeId);
    }

    function test_Refund_PaysThroughRedemptionContract() public {
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

        uint256 balanceBefore = usdt.balanceOf(alice);
        vm.prank(alice);
        uint256 refundAmount = redemption.refund(marketId, outcomeIds);

        assertEq(refundAmount, 60e18);
        assertEq(usdt.balanceOf(alice), balanceBefore + 60e18);
        assertEq(usdt.balanceOf(address(vault)), 0);

        ParimutuelPosition memory outcome0 = manager.getUserPosition(marketId, alice, 0);
        ParimutuelPosition memory outcome2 = manager.getUserPosition(marketId, alice, 2);
        assertEq(outcome0.principal, 0);
        assertEq(outcome2.principal, 0);
    }
}
