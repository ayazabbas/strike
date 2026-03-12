// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {MockUSDT} from "../test/mocks/MockUSDT.sol";

/// @notice Deploy MockUSDT to testnet for Strike protocol testing.
///         After deploying, set USDT_ADDRESS in .env to the output address
///         before running DeployTestnet.
contract DeployMockUSDTScript is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        console.log("Deploying MockUSDT...");
        console.log("  Chain ID:", block.chainid);
        console.log("  Deployer:", deployer);

        vm.startBroadcast(pk);

        MockUSDT usdt = new MockUSDT();

        // Mint initial supply to deployer for testing
        usdt.mint(deployer, 1_000_000 ether); // 1M USDT

        vm.stopBroadcast();

        console.log("MockUSDT deployed:", address(usdt));
        console.log("Minted 1,000,000 USDT to deployer");
        console.log("");
        console.log("Add to .env:");
        console.log(string.concat("USDT_ADDRESS=", vm.toString(address(usdt))));
    }
}
