// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title DailyCheckIn
/// @notice Lightweight on-chain daily check-in tracker. Days are UTC days expressed as block.timestamp / 1 days.
contract DailyCheckIn {
    error AlreadyCheckedIn(uint256 day);

    event CheckedIn(address indexed user, uint256 indexed day, uint256 timestamp);

    mapping(address => mapping(uint256 => bool)) private _checkedIn;

    function currentDay() public view returns (uint256) {
        return block.timestamp / 1 days;
    }

    function hasCheckedIn(address user, uint256 day) external view returns (bool) {
        return _checkedIn[user][day];
    }

    function checkIn() external {
        uint256 day = currentDay();
        if (_checkedIn[msg.sender][day]) revert AlreadyCheckedIn(day);

        _checkedIn[msg.sender][day] = true;
        emit CheckedIn(msg.sender, day, block.timestamp);
    }
}
