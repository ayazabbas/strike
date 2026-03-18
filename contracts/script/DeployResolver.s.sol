// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import "../src/PythResolver.sol";

contract DeployResolver is Script {
    function run() external {
        vm.startBroadcast();
        PythResolver resolver = new PythResolver(
            0xd7308b14BF4008e7C7196eC35610B1427C5702EA,  // Pyth Core (BSC testnet)
            0xf3ad14f117348dE4886c29764FDcAf9c62794535   // MarketFactory (BSC testnet v1)
        );
        console.log("PythResolver deployed:", address(resolver));
        vm.stopBroadcast();
    }
}
