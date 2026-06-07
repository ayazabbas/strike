// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {StrikeMultiplierPredictionVault} from "../src/StrikeMultiplierPredictionVault.sol";

/// @notice Dry-run-first deployment helper for Strike Multiplier Prediction escrow.
/// @dev Broadcast/mainnet deployment requires explicit approval. Run without --broadcast first.
contract DeployStrikeMultiplierPredictionVaultScript is Script {
    address internal constant DEFAULT_USDT = 0x55d398326f99059fF775485246999027B3197955;

    struct Deployed {
        address vault;
        address usdt;
        address admin;
        address eventManager;
    }

    function run() external {
        uint256 pk = _privateKey();
        address deployer = vm.addr(pk);
        Deployed memory d;
        d.usdt = vm.envOr("MULTIPLIER_USDT", DEFAULT_USDT);
        d.admin = vm.envOr("MULTIPLIER_VAULT_ADMIN", deployer);
        d.eventManager = vm.envOr("MULTIPLIER_EVENT_MANAGER", d.admin);

        _requireNonzero(d.usdt, "DeployMultiplier: USDT is zero");
        _requireNonzero(d.admin, "DeployMultiplier: admin is zero");
        _requireNonzero(d.eventManager, "DeployMultiplier: event manager is zero");

        console.log("Deploying StrikeMultiplierPredictionVault (dry-run unless --broadcast is supplied)...");
        console.log("  Chain ID:", block.chainid);
        console.log("  Deployer:", deployer);
        console.log("  USDT:", d.usdt);
        console.log("  Admin:", d.admin);
        console.log("  Event manager:", d.eventManager);

        vm.startBroadcast(pk);
        StrikeMultiplierPredictionVault vault = new StrikeMultiplierPredictionVault(d.usdt, deployer, d.eventManager);
        if (d.admin != deployer) {
            vault.grantRole(vault.DEFAULT_ADMIN_ROLE(), d.admin);
            vault.grantRole(vault.PAUSER_ROLE(), d.admin);
            vault.renounceRole(vault.PAUSER_ROLE(), deployer);
            vault.renounceRole(vault.DEFAULT_ADMIN_ROLE(), deployer);
        }
        vm.stopBroadcast();

        d.vault = address(vault);
        _printJson(d, deployer, vault);
    }

    function _privateKey() internal view returns (uint256) {
        uint256 pk = vm.envOr("DEPLOYER_PRIVATE_KEY", uint256(0));
        if (pk == 0) pk = vm.envOr("PRIVATE_KEY", uint256(0));
        require(pk != 0, "DeployMultiplier: set DEPLOYER_PRIVATE_KEY or PRIVATE_KEY for dry-run");
        return pk;
    }

    function _requireNonzero(address value, string memory message) internal pure {
        require(value != address(0), message);
    }

    function _printJson(Deployed memory d, address deployer, StrikeMultiplierPredictionVault vault) internal view {
        console.log("{");
        console.log('  "chainId": %s,', block.chainid);
        console.log('  "deployer": "%s",', deployer);
        console.log('  "usdt": "%s",', d.usdt);
        console.log('  "admin": "%s",', d.admin);
        console.log('  "eventManager": "%s",', d.eventManager);
        console.log('  "vault": "%s",', d.vault);
        console.log('  "MAX_PREDICTIONS_PER_EVENT": %s,', vault.MAX_PREDICTIONS_PER_EVENT());
        console.log('  "MAX_TOTAL_PREDICTIONS": %s,', vault.MAX_TOTAL_PREDICTIONS());
        console.log('  "MAX_SETTLEMENT_WINNERS": %s,', vault.MAX_SETTLEMENT_WINNERS());
        console.log('  "PER_PREDICTION_COVERAGE_BPS": %s,', vault.PER_PREDICTION_COVERAGE_BPS());
        console.log('  "GLOBAL_COVERAGE_BPS": %s', vault.GLOBAL_COVERAGE_BPS());
        console.log("}");
    }
}
