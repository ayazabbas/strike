// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import "../src/MockStrikeToken.sol";

/// @notice Deploys a mock STRIKE token for testnet environments that do not have real STRIKE.
contract DeployMockStrikeToken is Script {
    function run() external returns (MockStrikeToken token) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);
        token = new MockStrikeToken();
        vm.stopBroadcast();
    }
}
