// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/DailyCheckIn.sol";

contract DeployDailyCheckInScript is Script {
    function run() external returns (DailyCheckIn checkIn) {
        uint256 pk = _privateKey();
        vm.startBroadcast(pk);
        checkIn = new DailyCheckIn();
        vm.stopBroadcast();
    }

    function _privateKey() internal view returns (uint256) {
        uint256 fallbackKey = vm.envOr("DEPLOYER_PRIVATE_KEY", uint256(0));
        uint256 pk = vm.envOr("PRIVATE_KEY", fallbackKey);
        require(pk != 0, "DeployDailyCheckIn: missing private key");
        return pk;
    }
}
