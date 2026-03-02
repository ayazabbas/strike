// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {OutcomeToken} from "../src/OutcomeToken.sol";
import {Vault} from "../src/Vault.sol";
import {FeeModel} from "../src/FeeModel.sol";

/// @notice Deploy Phase 1A core primitives.
contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address feeCollector = vm.envOr("FEE_COLLECTOR", deployer);

        console.log("Deploying Phase 1A contracts...");
        console.log("  Chain ID:", block.chainid);
        console.log("  Deployer:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        OutcomeToken outcomeToken = new OutcomeToken(deployer);
        Vault vault = new Vault(deployer);
        FeeModel feeModel = new FeeModel(
            deployer,
            30, // 0.30% taker fee
            10, // 0.10% maker rebate
            0.005 ether, // resolver bounty
            0.0001 ether, // pruner bounty
            feeCollector
        );

        vm.stopBroadcast();

        console.log("OutcomeToken deployed at:", address(outcomeToken));
        console.log("Vault deployed at:", address(vault));
        console.log("FeeModel deployed at:", address(feeModel));
    }
}
