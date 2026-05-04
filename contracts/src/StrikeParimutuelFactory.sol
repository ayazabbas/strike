// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "./ParimutuelFactory.sol";

/// @title StrikeParimutuelFactory
/// @notice Isolated STRIKE-denominated pool market factory.
/// @dev Inherits the existing parimutuel lifecycle without modifying the USDT deployment path.
contract StrikeParimutuelFactory is ParimutuelFactory {
    constructor(address admin) ParimutuelFactory(admin) {}
}
