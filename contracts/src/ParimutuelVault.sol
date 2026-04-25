// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title ParimutuelVault
/// @notice Dedicated collateral custody for parimutuel markets.
/// @dev Accounting stays in the pool manager for now; this contract owns token custody.
contract ParimutuelVault is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant PROTOCOL_ROLE = keccak256("PROTOCOL_ROLE");

    IERC20 public immutable collateralToken;

    event VaultTransfer(address indexed to, uint256 amount);

    constructor(address admin, address collateralToken_) {
        require(admin != address(0), "ParimutuelVault: zero admin");
        require(collateralToken_ != address(0), "ParimutuelVault: zero collateral token");

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        collateralToken = IERC20(collateralToken_);
    }

    function transferTo(address to, uint256 amount) external onlyRole(PROTOCOL_ROLE) nonReentrant {
        require(to != address(0), "ParimutuelVault: zero recipient");
        require(amount > 0, "ParimutuelVault: zero amount");
        collateralToken.safeTransfer(to, amount);
        emit VaultTransfer(to, amount);
    }
}
