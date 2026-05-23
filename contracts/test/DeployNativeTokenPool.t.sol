// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../script/DeployNativeTokenPool.s.sol";
import "../src/NativeTokenPoolAIResolver.sol";

contract DeployNativeTokenPoolHarness is DeployNativeTokenPoolScript {
    function deployWithCustomParams(
        address finalAdmin,
        address treasury,
        address feeRecipient,
        address keeper,
        uint256 defaultModelId,
        uint256 creatorBondWei,
        uint256 challengerBondWei,
        uint16 platformFeeBps
    )
        external
        returns (
            NativeTokenParimutuelFactory factory,
            NativeTokenPoolManager manager,
            NativeTokenPoolVault vault,
            NativeTokenPoolRedemption redemption,
            NativeTokenPoolAIResolver resolver
        )
    {
        factory = new NativeTokenParimutuelFactory(address(this), treasury);
        vault = new NativeTokenPoolVault(address(this));
        manager = new NativeTokenPoolManager(address(this), address(factory), address(vault), feeRecipient);
        redemption = new NativeTokenPoolRedemption(address(this), address(manager), address(vault));
        resolver = new NativeTokenPoolAIResolver(address(factory), defaultModelId);

        _wireProtocolRoles(factory, manager, vault, redemption, resolver, keeper);
        _applyParams(factory, creatorBondWei, challengerBondWei, platformFeeBps);
        _handoffAdmin(factory, manager, vault, redemption, resolver, address(this), finalAdmin);
    }
}

contract DeployNativeTokenPoolScriptTest is Test {
    function test_CustomParamsApplyBeforeNonDeployerAdminHandoff() public {
        DeployNativeTokenPoolHarness harness = new DeployNativeTokenPoolHarness();
        address finalAdmin = address(0xA11CE);
        address treasury = address(0xB0B);
        address feeRecipient = address(0xFEE);
        address keeper = address(0xC0FFEE);
        uint256 defaultModelId = 2;
        uint256 creatorBondWei = 0.2 ether;
        uint256 challengerBondWei = 0.03 ether;
        uint16 platformFeeBps = 350;

        (
            NativeTokenParimutuelFactory factory,
            NativeTokenPoolManager manager,
            NativeTokenPoolVault vault,
            NativeTokenPoolRedemption redemption,
            NativeTokenPoolAIResolver resolver
        ) = harness.deployWithCustomParams(
            finalAdmin,
            treasury,
            feeRecipient,
            keeper,
            defaultModelId,
            creatorBondWei,
            challengerBondWei,
            platformFeeBps
        );

        assertEq(factory.creatorBondAmount(), creatorBondWei);
        assertEq(factory.challengerBondAmount(), challengerBondWei);
        assertEq(factory.platformFeeBps(), platformFeeBps);
        assertEq(factory.poolManager(), address(manager));
        assertEq(resolver.defaultModelId(), defaultModelId);
        assertTrue(factory.hasRole(factory.RESOLVER_ROLE(), address(resolver)));
        assertTrue(resolver.hasRole(resolver.KEEPER_ROLE(), keeper));
        assertTrue(vault.hasRole(vault.PROTOCOL_ROLE(), address(manager)));
        assertTrue(vault.hasRole(vault.PROTOCOL_ROLE(), address(redemption)));
        assertTrue(manager.hasRole(manager.REDEMPTION_ROLE(), address(redemption)));

        assertTrue(factory.hasRole(factory.DEFAULT_ADMIN_ROLE(), finalAdmin));
        assertTrue(factory.hasRole(factory.ADMIN_ROLE(), finalAdmin));
        assertTrue(manager.hasRole(manager.DEFAULT_ADMIN_ROLE(), finalAdmin));
        assertTrue(manager.hasRole(manager.ADMIN_ROLE(), finalAdmin));
        assertTrue(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), finalAdmin));
        assertTrue(redemption.hasRole(redemption.DEFAULT_ADMIN_ROLE(), finalAdmin));
        assertTrue(redemption.hasRole(redemption.ADMIN_ROLE(), finalAdmin));
        assertEq(resolver.admin(), finalAdmin);

        assertFalse(factory.hasRole(factory.DEFAULT_ADMIN_ROLE(), address(harness)));
        assertFalse(factory.hasRole(factory.ADMIN_ROLE(), address(harness)));
        assertFalse(manager.hasRole(manager.DEFAULT_ADMIN_ROLE(), address(harness)));
        assertFalse(manager.hasRole(manager.ADMIN_ROLE(), address(harness)));
        assertFalse(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), address(harness)));
        assertFalse(redemption.hasRole(redemption.DEFAULT_ADMIN_ROLE(), address(harness)));
        assertFalse(redemption.hasRole(redemption.ADMIN_ROLE(), address(harness)));
    }
}
