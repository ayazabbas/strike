// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MockUSDT
/// @notice ERC20 with public mint for testing. 18 decimals (like BSC USDT).
contract MockUSDT is ERC20 {
    constructor() ERC20("Mock USDT", "USDT") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
