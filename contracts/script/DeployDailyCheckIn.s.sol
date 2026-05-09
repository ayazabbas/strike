// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/DailyCheckIn.sol";

contract DeployDailyCheckInScript is Script {
    function run() external returns (DailyCheckIn checkIn) {
        vm.startBroadcast();
        checkIn = new DailyCheckIn();
        vm.stopBroadcast();
    }
}
