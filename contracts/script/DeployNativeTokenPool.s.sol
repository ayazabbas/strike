// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {NativeTokenParimutuelFactory} from "../src/NativeTokenParimutuelFactory.sol";
import {NativeTokenPoolManager} from "../src/NativeTokenPoolManager.sol";
import {NativeTokenPoolRedemption} from "../src/NativeTokenPoolRedemption.sol";
import {NativeTokenPoolVault} from "../src/NativeTokenPoolVault.sol";

/// @notice Deploy the isolated arbitrary-ERC20/BEP20 Flap Token Pools protocol and wire bootstrap roles.
/// @dev Required env:
///      PRIVATE_KEY or DEPLOYER_PRIVATE_KEY
///      NATIVE_TOKEN_POOL_TREASURY
///      Optional env:
///      NATIVE_TOKEN_POOL_FINAL_ADMIN defaults to deployer
///      NATIVE_TOKEN_POOL_FEE_RECIPIENT defaults to final admin
///      NATIVE_TOKEN_POOL_RESOLVER defaults to final admin
///      NATIVE_TOKEN_POOL_CREATOR_BOND_WEI defaults to 0.05 BNB
///      NATIVE_TOKEN_POOL_CHALLENGER_BOND_WEI defaults to 0.01 BNB
///      NATIVE_TOKEN_POOL_PLATFORM_FEE_BPS defaults to 200
contract DeployNativeTokenPoolScript is Script {
    uint256 internal constant DEFAULT_CREATOR_BOND_WEI = 0.05 ether;
    uint256 internal constant DEFAULT_CHALLENGER_BOND_WEI = 0.01 ether;
    uint16 internal constant DEFAULT_PLATFORM_FEE_BPS = 200;

    struct Deployed {
        address factory;
        address manager;
        address vault;
        address redemption;
        address admin;
        address treasury;
        address feeRecipient;
        address resolver;
        uint256 creatorBondWei;
        uint256 challengerBondWei;
        uint16 platformFeeBps;
    }

    function run() external {
        uint256 pk = _privateKey();
        address deployer = vm.addr(pk);
        address finalAdmin = vm.envOr("NATIVE_TOKEN_POOL_FINAL_ADMIN", deployer);
        address treasury = vm.envAddress("NATIVE_TOKEN_POOL_TREASURY");
        address feeRecipient = vm.envOr("NATIVE_TOKEN_POOL_FEE_RECIPIENT", finalAdmin);
        address resolver = vm.envOr("NATIVE_TOKEN_POOL_RESOLVER", finalAdmin);
        uint256 creatorBondWei = vm.envOr("NATIVE_TOKEN_POOL_CREATOR_BOND_WEI", DEFAULT_CREATOR_BOND_WEI);
        uint256 challengerBondWei = vm.envOr("NATIVE_TOKEN_POOL_CHALLENGER_BOND_WEI", DEFAULT_CHALLENGER_BOND_WEI);
        uint256 platformFeeBpsRaw = vm.envOr("NATIVE_TOKEN_POOL_PLATFORM_FEE_BPS", uint256(DEFAULT_PLATFORM_FEE_BPS));

        require(finalAdmin != address(0), "DeployNativeTokenPool: zero final admin");
        require(treasury != address(0), "DeployNativeTokenPool: zero treasury");
        require(feeRecipient != address(0), "DeployNativeTokenPool: zero fee recipient");
        require(resolver != address(0), "DeployNativeTokenPool: zero resolver");
        require(creatorBondWei > 0, "DeployNativeTokenPool: zero creator bond");
        require(challengerBondWei > 0, "DeployNativeTokenPool: zero challenger bond");
        require(platformFeeBpsRaw < 10_000, "DeployNativeTokenPool: invalid fee bps");
        uint16 platformFeeBps = uint16(platformFeeBpsRaw);

        console.log("Deploying Flap Token Pools protocol...");
        console.log("  Chain ID:", block.chainid);
        console.log("  Deployer:", deployer);
        console.log("  Final admin:", finalAdmin);
        console.log("  Treasury:", treasury);
        console.log("  Fee recipient:", feeRecipient);
        console.log("  Resolver:", resolver);
        console.log("  Creator bond wei:", creatorBondWei);
        console.log("  Challenger bond wei:", challengerBondWei);
        console.log("  Platform fee bps:", platformFeeBps);

        vm.startBroadcast(pk);

        NativeTokenParimutuelFactory factory = new NativeTokenParimutuelFactory(deployer, treasury);
        NativeTokenPoolVault vault = new NativeTokenPoolVault(deployer);
        NativeTokenPoolManager manager =
            new NativeTokenPoolManager(deployer, address(factory), address(vault), feeRecipient);
        NativeTokenPoolRedemption redemption = new NativeTokenPoolRedemption(deployer, address(manager), address(vault));

        _wireRoles(factory, manager, vault, redemption, deployer, finalAdmin, resolver);
        _applyParams(factory, creatorBondWei, challengerBondWei, platformFeeBps);

        vm.stopBroadcast();

        Deployed memory d = Deployed({
            factory: address(factory),
            manager: address(manager),
            vault: address(vault),
            redemption: address(redemption),
            admin: finalAdmin,
            treasury: treasury,
            feeRecipient: feeRecipient,
            resolver: resolver,
            creatorBondWei: creatorBondWei,
            challengerBondWei: challengerBondWei,
            platformFeeBps: platformFeeBps
        });

        _printJson(d);
    }

    function _wireRoles(
        NativeTokenParimutuelFactory factory,
        NativeTokenPoolManager manager,
        NativeTokenPoolVault vault,
        NativeTokenPoolRedemption redemption,
        address bootstrapAdmin,
        address finalAdmin,
        address resolver
    ) internal {
        factory.setPoolManager(address(manager));
        factory.grantRole(factory.RESOLVER_ROLE(), resolver);

        vault.grantRole(vault.PROTOCOL_ROLE(), address(manager));
        vault.grantRole(vault.PROTOCOL_ROLE(), address(redemption));

        manager.grantRole(manager.REDEMPTION_ROLE(), address(redemption));

        _handoffAdmin(factory, manager, vault, redemption, bootstrapAdmin, finalAdmin);
    }

    function _handoffAdmin(
        NativeTokenParimutuelFactory factory,
        NativeTokenPoolManager manager,
        NativeTokenPoolVault vault,
        NativeTokenPoolRedemption redemption,
        address bootstrapAdmin,
        address finalAdmin
    ) internal {
        if (finalAdmin == bootstrapAdmin) {
            return;
        }

        factory.grantRole(factory.DEFAULT_ADMIN_ROLE(), finalAdmin);
        factory.grantRole(factory.ADMIN_ROLE(), finalAdmin);
        manager.grantRole(manager.DEFAULT_ADMIN_ROLE(), finalAdmin);
        manager.grantRole(manager.ADMIN_ROLE(), finalAdmin);
        vault.grantRole(vault.DEFAULT_ADMIN_ROLE(), finalAdmin);
        redemption.grantRole(redemption.DEFAULT_ADMIN_ROLE(), finalAdmin);
        redemption.grantRole(redemption.ADMIN_ROLE(), finalAdmin);

        factory.revokeRole(factory.ADMIN_ROLE(), bootstrapAdmin);
        factory.revokeRole(factory.DEFAULT_ADMIN_ROLE(), bootstrapAdmin);
        manager.revokeRole(manager.ADMIN_ROLE(), bootstrapAdmin);
        manager.revokeRole(manager.DEFAULT_ADMIN_ROLE(), bootstrapAdmin);
        vault.revokeRole(vault.DEFAULT_ADMIN_ROLE(), bootstrapAdmin);
        redemption.revokeRole(redemption.ADMIN_ROLE(), bootstrapAdmin);
        redemption.revokeRole(redemption.DEFAULT_ADMIN_ROLE(), bootstrapAdmin);
    }

    function _applyParams(
        NativeTokenParimutuelFactory factory,
        uint256 creatorBondWei,
        uint256 challengerBondWei,
        uint16 platformFeeBps
    ) internal {
        if (creatorBondWei != DEFAULT_CREATOR_BOND_WEI || challengerBondWei != DEFAULT_CHALLENGER_BOND_WEI) {
            factory.setBondParams(creatorBondWei, challengerBondWei);
        }
        if (platformFeeBps != DEFAULT_PLATFORM_FEE_BPS) {
            factory.setPlatformFeeBps(platformFeeBps);
        }
    }

    function _privateKey() internal view returns (uint256) {
        uint256 fallbackKey = vm.envOr("DEPLOYER_PRIVATE_KEY", uint256(0));
        uint256 pk = vm.envOr("PRIVATE_KEY", fallbackKey);
        require(pk != 0, "DeployNativeTokenPool: missing private key");
        return pk;
    }

    function _printJson(Deployed memory d) internal pure {
        string memory json = string.concat(
            '{"nativeTokenParimutuelFactory":"',
            vm.toString(d.factory),
            '","nativeTokenPoolManager":"',
            vm.toString(d.manager),
            '","nativeTokenPoolVault":"',
            vm.toString(d.vault),
            '","nativeTokenPoolRedemption":"',
            vm.toString(d.redemption),
            '","admin":"',
            vm.toString(d.admin)
        );
        json = string.concat(
            json,
            '","treasury":"',
            vm.toString(d.treasury),
            '","feeRecipient":"',
            vm.toString(d.feeRecipient),
            '","resolver":"',
            vm.toString(d.resolver),
            '","creatorBondWei":"',
            vm.toString(d.creatorBondWei),
            '","challengerBondWei":"',
            vm.toString(d.challengerBondWei),
            '","platformFeeBps":"',
            vm.toString(d.platformFeeBps),
            '"}'
        );
        console.log(json);
    }
}
