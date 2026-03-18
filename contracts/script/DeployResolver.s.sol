// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import "../src/PythResolver.sol";
import "../src/MarketFactory.sol";

contract DeployResolver is Script {
    function run() external {
        address factoryAddr = 0xf3ad14f117348dE4886c29764FDcAf9c62794535; // MarketFactory (BSC testnet v1)

        vm.startBroadcast();
        PythResolver resolver = new PythResolver(
            0xd7308b14BF4008e7C7196eC35610B1427C5702EA,  // Pyth Core (BSC testnet)
            factoryAddr
        );
        console.log("PythResolver deployed:", address(resolver));

        // Grant ADMIN_ROLE on factory so resolver can call setResolving/setResolved
        MarketFactory factory = MarketFactory(factoryAddr);
        factory.grantRole(factory.ADMIN_ROLE(), address(resolver));
        console.log("Granted ADMIN_ROLE on MarketFactory to PythResolver");

        vm.stopBroadcast();
    }
}
