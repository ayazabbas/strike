// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MockStrikeToken
/// @notice ERC20 with public mint for local tests and testnet deployments.
contract MockStrikeToken is ERC20 {
    constructor() ERC20("Mock STRIKE", "STRIKE") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
