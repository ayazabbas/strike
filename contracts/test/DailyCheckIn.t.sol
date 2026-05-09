// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/DailyCheckIn.sol";

contract DailyCheckInTest is Test {
    event CheckedIn(address indexed user, uint256 indexed day, uint256 timestamp);

    DailyCheckIn checkIn;
    address user = address(0xA11CE);

    function setUp() public {
        checkIn = new DailyCheckIn();
    }

    function testCheckInRecordsCurrentUtcDay() public {
        vm.warp(1_771_197_200); // 2026-02-14 12:00 UTC-ish
        uint256 day = block.timestamp / 1 days;

        vm.expectEmit(true, true, false, true);
        emit CheckedIn(user, day, block.timestamp);

        vm.prank(user);
        checkIn.checkIn();

        assertTrue(checkIn.hasCheckedIn(user, day));
        assertEq(checkIn.currentDay(), day);
    }

    function testCannotCheckInTwiceOnSameDay() public {
        vm.warp(1_771_197_200);
        uint256 day = block.timestamp / 1 days;

        vm.startPrank(user);
        checkIn.checkIn();

        vm.expectRevert(abi.encodeWithSelector(DailyCheckIn.AlreadyCheckedIn.selector, day));
        checkIn.checkIn();
        vm.stopPrank();
    }

    function testCanCheckInAgainNextUtcDay() public {
        vm.warp(1_771_197_200);
        uint256 firstDay = block.timestamp / 1 days;

        vm.prank(user);
        checkIn.checkIn();

        vm.warp((firstDay + 1) * 1 days);
        uint256 nextDay = block.timestamp / 1 days;

        vm.prank(user);
        checkIn.checkIn();

        assertTrue(checkIn.hasCheckedIn(user, firstDay));
        assertTrue(checkIn.hasCheckedIn(user, nextDay));
    }
}
