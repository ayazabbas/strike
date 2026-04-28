// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import "../src/PythResolver.sol";
import "../src/MarketFactory.sol";

contract DeployResolver is Script {
    function run() external {
        address factoryAddr = 0xB4a9D6Dc1cAE195e276638ef9Cc20e797Cb3f839; // MarketFactory (current canonical Strike testnet)

        vm.startBroadcast();
        PythResolver resolver = new PythResolver(
            0x5744Cbf430D99456a0A8771208b674F27f8EF0Fb,  // Pyth Stable (BNB testnet)
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
