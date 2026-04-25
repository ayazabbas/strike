// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/ParimutuelFactory.sol";
import "../src/ParimutuelPoolManager.sol";
import "../src/ParimutuelRedemption.sol";
import "../src/ParimutuelTypes.sol";
import "../src/ParimutuelVault.sol";
import "./mocks/MockUSDT.sol";

contract ParimutuelBootstrapTest is Test {
    ParimutuelFactory public factory;
    ParimutuelPoolManager public manager;
    ParimutuelRedemption public redemption;
    ParimutuelVault public vault;
    MockUSDT public usdt;

    address public admin = address(0x1);
    address public creator = address(0x2);
    address public alice = address(0x3);
    address public feeRecipient = address(0x4);
    address public finalAdmin = address(0x5);

    function setUp() public {
        usdt = new MockUSDT();

        factory = new ParimutuelFactory(admin);
        vault = new ParimutuelVault(admin, address(usdt));
        manager = new ParimutuelPoolManager(admin, address(factory), address(vault), feeRecipient);
        redemption = new ParimutuelRedemption(admin, address(manager), address(vault));

        vm.startPrank(admin);
        factory.setPoolManager(address(manager));
        factory.grantRole(factory.MARKET_CREATOR_ROLE(), creator);
        vault.grantRole(vault.PROTOCOL_ROLE(), address(manager));
        vault.grantRole(vault.PROTOCOL_ROLE(), address(redemption));
        manager.grantRole(manager.REDEMPTION_ROLE(), address(redemption));
        vm.stopPrank();
    }

    function test_BootstrapRolesMatchDeploymentRunbook() public view {
        assertEq(factory.poolManager(), address(manager));
        assertTrue(factory.hasRole(factory.MARKET_CREATOR_ROLE(), creator));
        assertTrue(vault.hasRole(vault.PROTOCOL_ROLE(), address(manager)));
        assertTrue(vault.hasRole(vault.PROTOCOL_ROLE(), address(redemption)));
        assertTrue(manager.hasRole(manager.REDEMPTION_ROLE(), address(redemption)));
    }

    function test_FinalAdminHandoffRevokesBootstrapAdmin() public {
        address bootstrapAdmin = address(0xB007);
        ParimutuelFactory handoffFactory = new ParimutuelFactory(bootstrapAdmin);
        ParimutuelVault handoffVault = new ParimutuelVault(bootstrapAdmin, address(usdt));
        ParimutuelPoolManager handoffManager =
            new ParimutuelPoolManager(bootstrapAdmin, address(handoffFactory), address(handoffVault), feeRecipient);
        ParimutuelRedemption handoffRedemption =
            new ParimutuelRedemption(bootstrapAdmin, address(handoffManager), address(handoffVault));

        vm.startPrank(bootstrapAdmin);
        handoffFactory.setPoolManager(address(handoffManager));
        handoffFactory.grantRole(handoffFactory.MARKET_CREATOR_ROLE(), creator);
        handoffVault.grantRole(handoffVault.PROTOCOL_ROLE(), address(handoffManager));
        handoffVault.grantRole(handoffVault.PROTOCOL_ROLE(), address(handoffRedemption));
        handoffManager.grantRole(handoffManager.REDEMPTION_ROLE(), address(handoffRedemption));

        handoffFactory.grantRole(handoffFactory.DEFAULT_ADMIN_ROLE(), finalAdmin);
        handoffFactory.grantRole(handoffFactory.ADMIN_ROLE(), finalAdmin);
        handoffManager.grantRole(handoffManager.DEFAULT_ADMIN_ROLE(), finalAdmin);
        handoffManager.grantRole(handoffManager.ADMIN_ROLE(), finalAdmin);
        handoffVault.grantRole(handoffVault.DEFAULT_ADMIN_ROLE(), finalAdmin);
        handoffRedemption.grantRole(handoffRedemption.DEFAULT_ADMIN_ROLE(), finalAdmin);
        handoffRedemption.grantRole(handoffRedemption.ADMIN_ROLE(), finalAdmin);

        handoffFactory.revokeRole(handoffFactory.ADMIN_ROLE(), bootstrapAdmin);
        handoffFactory.revokeRole(handoffFactory.DEFAULT_ADMIN_ROLE(), bootstrapAdmin);
        handoffManager.revokeRole(handoffManager.ADMIN_ROLE(), bootstrapAdmin);
        handoffManager.revokeRole(handoffManager.DEFAULT_ADMIN_ROLE(), bootstrapAdmin);
        handoffVault.revokeRole(handoffVault.DEFAULT_ADMIN_ROLE(), bootstrapAdmin);
        handoffRedemption.revokeRole(handoffRedemption.ADMIN_ROLE(), bootstrapAdmin);
        handoffRedemption.revokeRole(handoffRedemption.DEFAULT_ADMIN_ROLE(), bootstrapAdmin);
        vm.stopPrank();

        assertTrue(handoffFactory.hasRole(handoffFactory.DEFAULT_ADMIN_ROLE(), finalAdmin));
        assertTrue(handoffFactory.hasRole(handoffFactory.ADMIN_ROLE(), finalAdmin));
        assertTrue(handoffManager.hasRole(handoffManager.DEFAULT_ADMIN_ROLE(), finalAdmin));
        assertTrue(handoffManager.hasRole(handoffManager.ADMIN_ROLE(), finalAdmin));
        assertTrue(handoffVault.hasRole(handoffVault.DEFAULT_ADMIN_ROLE(), finalAdmin));
        assertTrue(handoffRedemption.hasRole(handoffRedemption.DEFAULT_ADMIN_ROLE(), finalAdmin));
        assertTrue(handoffRedemption.hasRole(handoffRedemption.ADMIN_ROLE(), finalAdmin));

        assertFalse(handoffFactory.hasRole(handoffFactory.DEFAULT_ADMIN_ROLE(), bootstrapAdmin));
        assertFalse(handoffFactory.hasRole(handoffFactory.ADMIN_ROLE(), bootstrapAdmin));
        assertFalse(handoffManager.hasRole(handoffManager.DEFAULT_ADMIN_ROLE(), bootstrapAdmin));
        assertFalse(handoffManager.hasRole(handoffManager.ADMIN_ROLE(), bootstrapAdmin));
        assertFalse(handoffVault.hasRole(handoffVault.DEFAULT_ADMIN_ROLE(), bootstrapAdmin));
        assertFalse(handoffRedemption.hasRole(handoffRedemption.DEFAULT_ADMIN_ROLE(), bootstrapAdmin));
        assertFalse(handoffRedemption.hasRole(handoffRedemption.ADMIN_ROLE(), bootstrapAdmin));
    }

    function test_BootstrapSupportsCreateBuyResolveClaim() public {
        usdt.mint(alice, 1_000e18);
        vm.prank(alice);
        usdt.approve(address(manager), type(uint256).max);

        ParimutuelMarketConfig memory config = ParimutuelMarketConfig({
            closeTime: uint64(block.timestamp + 1 hours),
            outcomeCount: 3,
            resolverType: ParimutuelResolverType.Admin,
            fallbackResolverType: ParimutuelResolverType.Admin,
            curveType: ParimutuelCurveType.IndependentLog,
            curveParam: factory.INDEPENDENT_LOG_LIQUIDITY_RECOMMENDED(),
            feeBps: 50,
            metadataHash: keccak256("bootstrap-market"),
            metadataURI: "ipfs://strike/parimutuel/bootstrap",
            resolverConfig: bytes("")
        });

        vm.prank(creator);
        uint256 marketId = factory.createMarket(config);

        vm.prank(alice);
        manager.buy(marketId, 1, 100e18, 1);

        vm.warp(config.closeTime);
        factory.closeMarket(marketId);

        vm.prank(admin);
        factory.resolveToWinner(marketId, 1);

        uint256 balanceBefore = usdt.balanceOf(alice);
        vm.prank(alice);
        uint256 payout = redemption.claim(marketId);

        assertGt(payout, 0);
        assertEq(usdt.balanceOf(alice), balanceBefore + payout);
    }
}
