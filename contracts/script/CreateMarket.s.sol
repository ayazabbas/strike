// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {MarketFactory} from "../src/MarketFactory.sol";
import {IPyth} from "@pythnetwork/pyth-sdk-solidity/IPyth.sol";

/// @notice Helper script to create a market manually (for testing/demo)
/// @dev Usage: forge script script/CreateMarket.s.sol --rpc-url $BSC_TESTNET_RPC_URL --broadcast
contract CreateMarketScript is Script {
    // Pyth price feed IDs
    bytes32 constant BTC_USD = 0xe62df6c8b4a85fe1a67db44dc12de5db330f7ac66b72dc658afedf0f4a415b43;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address factoryAddress = vm.envAddress("FACTORY_ADDRESS");

        // Market parameters
        bytes32 priceId = BTC_USD;
        uint256 duration = 1 hours;

        console.log("Creating market...");
        console.log("  Factory:", factoryAddress);
        console.log("  Duration:", duration);

        // NOTE: In production, pythUpdateData would be fetched from Hermes API
        // For testnet, you need to provide real Pyth update data
        // This script is a template - actual update data must be fetched off-chain

        vm.startBroadcast(deployerPrivateKey);

        // Placeholder - actual implementation would fetch from Pyth Hermes API
        // bytes[] memory pythUpdateData = fetchFromHermes(priceId);
        // uint256 fee = IPyth(pyth).getUpdateFee(pythUpdateData);
        // MarketFactory(factoryAddress).createMarket{value: fee}(priceId, duration, pythUpdateData);

        vm.stopBroadcast();

        console.log("Market creation requires Pyth update data from Hermes API");
        console.log("Use the frontend or a TypeScript script to fetch and submit");
    }
}
