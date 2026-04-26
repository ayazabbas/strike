// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {ParimutuelAIResolver} from "../src/ParimutuelAIResolver.sol";
import {ParimutuelFactory} from "../src/ParimutuelFactory.sol";
import {ParimutuelPoolManager} from "../src/ParimutuelPoolManager.sol";
import {ParimutuelPythResolver} from "../src/ParimutuelPythResolver.sol";
import {ParimutuelRedemption} from "../src/ParimutuelRedemption.sol";
import {ParimutuelVault} from "../src/ParimutuelVault.sol";

/// @notice Deploy the isolated multi-choice parimutuel market path and wire bootstrap roles.
/// @dev Required env:
///      PRIVATE_KEY or DEPLOYER_PRIVATE_KEY
///      USDT_ADDRESS
///      PYTH_ADDRESS
///      Optional env:
///      PARIMUTUEL_FINAL_ADMIN defaults to deployer
///      PARIMUTUEL_FEE_RECIPIENT defaults to final admin
///      PARIMUTUEL_MARKET_CREATOR defaults to final admin
///      PARIMUTUEL_KEEPER defaults to final admin
contract DeployParimutuelScript is Script {
    uint256 internal constant INDEPENDENT_LOG_LIQUIDITY_RECOMMENDED = 40_000e18;
    uint256 internal constant INDEPENDENT_LOG_LIQUIDITY_CONSERVATIVE = 100_000e18;

    struct Deployed {
        address factory;
        address manager;
        address vault;
        address redemption;
        address aiResolver;
        address pythResolver;
        address collateralToken;
        address admin;
        address feeRecipient;
        address marketCreator;
        address keeper;
    }

    function run() external {
        uint256 pk = _privateKey();
        address deployer = vm.addr(pk);
        address finalAdmin = vm.envOr("PARIMUTUEL_FINAL_ADMIN", deployer);
        address collateralToken = vm.envAddress("USDT_ADDRESS");
        address pythAddress = vm.envAddress("PYTH_ADDRESS");
        address feeRecipient = vm.envOr("PARIMUTUEL_FEE_RECIPIENT", finalAdmin);
        address marketCreator = vm.envOr("PARIMUTUEL_MARKET_CREATOR", finalAdmin);
        address keeper = vm.envOr("PARIMUTUEL_KEEPER", finalAdmin);

        require(finalAdmin != address(0), "DeployParimutuel: zero final admin");
        require(collateralToken != address(0), "DeployParimutuel: zero collateral");
        require(pythAddress != address(0), "DeployParimutuel: zero pyth");
        require(feeRecipient != address(0), "DeployParimutuel: zero fee recipient");
        require(marketCreator != address(0), "DeployParimutuel: zero creator");
        require(keeper != address(0), "DeployParimutuel: zero keeper");

        console.log("Deploying Strike parimutuel protocol...");
        console.log("  Chain ID:", block.chainid);
        console.log("  Deployer:", deployer);
        console.log("  Final admin:", finalAdmin);
        console.log("  Collateral:", collateralToken);
        console.log("  Pyth:", pythAddress);
        console.log("  Fee recipient:", feeRecipient);
        console.log("  Market creator:", marketCreator);
        console.log("  Keeper:", keeper);

        vm.startBroadcast(pk);

        ParimutuelFactory factory = new ParimutuelFactory(deployer);
        ParimutuelVault vault = new ParimutuelVault(deployer, collateralToken);
        ParimutuelPoolManager manager =
            new ParimutuelPoolManager(deployer, address(factory), address(vault), feeRecipient);
        ParimutuelRedemption redemption = new ParimutuelRedemption(deployer, address(manager), address(vault));
        ParimutuelAIResolver aiResolver = new ParimutuelAIResolver(address(factory), feeRecipient);
        ParimutuelPythResolver pythResolver = new ParimutuelPythResolver(pythAddress, address(factory));

        _wireRoles(
            factory, manager, vault, redemption, aiResolver, pythResolver, deployer, finalAdmin, marketCreator, keeper
        );

        vm.stopBroadcast();

        Deployed memory d = Deployed({
            factory: address(factory),
            manager: address(manager),
            vault: address(vault),
            redemption: address(redemption),
            aiResolver: address(aiResolver),
            pythResolver: address(pythResolver),
            collateralToken: collateralToken,
            admin: finalAdmin,
            feeRecipient: feeRecipient,
            marketCreator: marketCreator,
            keeper: keeper
        });

        _printJson(d);
    }

    function _wireRoles(
        ParimutuelFactory factory,
        ParimutuelPoolManager manager,
        ParimutuelVault vault,
        ParimutuelRedemption redemption,
        ParimutuelAIResolver aiResolver,
        ParimutuelPythResolver pythResolver,
        address bootstrapAdmin,
        address finalAdmin,
        address marketCreator,
        address keeper
    ) internal {
        factory.setPoolManager(address(manager));
        factory.grantRole(factory.MARKET_CREATOR_ROLE(), marketCreator);
        factory.grantRole(factory.RESOLVER_ROLE(), address(aiResolver));
        factory.grantRole(factory.RESOLVER_ROLE(), address(pythResolver));

        vault.grantRole(vault.PROTOCOL_ROLE(), address(manager));
        vault.grantRole(vault.PROTOCOL_ROLE(), address(redemption));

        manager.grantRole(manager.REDEMPTION_ROLE(), address(redemption));
        aiResolver.grantRole(aiResolver.KEEPER_ROLE(), keeper);

        if (marketCreator != finalAdmin) {
            factory.grantRole(factory.MARKET_CREATOR_ROLE(), finalAdmin);
        }

        _handoffAdmin(factory, manager, vault, redemption, aiResolver, pythResolver, bootstrapAdmin, finalAdmin);
    }

    function _handoffAdmin(
        ParimutuelFactory factory,
        ParimutuelPoolManager manager,
        ParimutuelVault vault,
        ParimutuelRedemption redemption,
        ParimutuelAIResolver aiResolver,
        ParimutuelPythResolver pythResolver,
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
        aiResolver.setAdmin(finalAdmin);
        pythResolver.setPendingAdmin(finalAdmin);

        factory.revokeRole(factory.ADMIN_ROLE(), bootstrapAdmin);
        factory.revokeRole(factory.DEFAULT_ADMIN_ROLE(), bootstrapAdmin);
        manager.revokeRole(manager.ADMIN_ROLE(), bootstrapAdmin);
        manager.revokeRole(manager.DEFAULT_ADMIN_ROLE(), bootstrapAdmin);
        vault.revokeRole(vault.DEFAULT_ADMIN_ROLE(), bootstrapAdmin);
        redemption.revokeRole(redemption.ADMIN_ROLE(), bootstrapAdmin);
        redemption.revokeRole(redemption.DEFAULT_ADMIN_ROLE(), bootstrapAdmin);
    }

    function _privateKey() internal view returns (uint256) {
        uint256 fallbackKey = vm.envOr("DEPLOYER_PRIVATE_KEY", uint256(0));
        uint256 pk = vm.envOr("PRIVATE_KEY", fallbackKey);
        require(pk != 0, "DeployParimutuel: missing private key");
        return pk;
    }

    function _printJson(Deployed memory d) internal pure {
        string memory json = string.concat(
            '{"parimutuelFactory":"',
            vm.toString(d.factory),
            '","parimutuelPoolManager":"',
            vm.toString(d.manager),
            '","parimutuelVault":"',
            vm.toString(d.vault),
            '","parimutuelRedemption":"',
            vm.toString(d.redemption),
            '","parimutuelAIResolver":"',
            vm.toString(d.aiResolver),
            '","parimutuelPythResolver":"',
            vm.toString(d.pythResolver),
            '","collateralToken":"',
            vm.toString(d.collateralToken)
        );
        json = string.concat(
            json,
            '","admin":"',
            vm.toString(d.admin),
            '","feeRecipient":"',
            vm.toString(d.feeRecipient),
            '","marketCreator":"',
            vm.toString(d.marketCreator),
            '","keeper":"',
            vm.toString(d.keeper),
            '","independentLogLiquidityRecommended":"',
            vm.toString(INDEPENDENT_LOG_LIQUIDITY_RECOMMENDED),
            '","independentLogLiquidityConservative":"',
            vm.toString(INDEPENDENT_LOG_LIQUIDITY_CONSERVATIVE),
            '"}'
        );
        console.log(json);
    }
}
