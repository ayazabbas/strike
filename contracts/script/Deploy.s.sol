// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {MarketFactory} from "../src/MarketFactory.sol";

contract DeployScript is Script {
    // Pyth contract addresses
    address constant PYTH_BSC_TESTNET = 0x5744Cbf430D99456a0A8771208b674F27f8EF0Fb;
    address constant PYTH_BSC_MAINNET = 0x4D7E825f80bDf85e913E0DD2A2D54927e9dE1594;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address feeCollector = vm.envAddress("FEE_COLLECTOR");

        // Default to testnet
        address pythAddress = PYTH_BSC_TESTNET;
        if (block.chainid == 56) {
            pythAddress = PYTH_BSC_MAINNET;
        }

        console.log("Deploying MarketFactory...");
        console.log("  Chain ID:", block.chainid);
        console.log("  Pyth:", pythAddress);
        console.log("  Fee Collector:", feeCollector);

        vm.startBroadcast(deployerPrivateKey);

        MarketFactory factory = new MarketFactory(pythAddress, feeCollector);

        vm.stopBroadcast();

        console.log("MarketFactory deployed at:", address(factory));
        console.log("Market implementation:", factory.marketImplementation());
    }
}
