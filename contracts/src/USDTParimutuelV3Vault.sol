// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title USDTParimutuelV3Vault
/// @notice USDT custody for credit-enabled V3 parimutuel markets.
contract USDTParimutuelV3Vault is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant PROTOCOL_ROLE = keccak256("PROTOCOL_ROLE");

    IERC20 public immutable usdt;

    event VaultTransfer(address indexed to, uint256 amount);

    error ZeroAddress();
    error ZeroAmount();

    constructor(address admin, address usdt_) {
        if (admin == address(0) || usdt_ == address(0)) revert ZeroAddress();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        usdt = IERC20(usdt_);
    }

    function transferTo(address to, uint256 amount) external onlyRole(PROTOCOL_ROLE) nonReentrant {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        usdt.safeTransfer(to, amount);
        emit VaultTransfer(to, amount);
    }
}
