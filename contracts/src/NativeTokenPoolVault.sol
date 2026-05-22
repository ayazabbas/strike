// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title NativeTokenPoolVault
/// @notice Custody surface for arbitrary ERC20/BEP20 Flap Token Pools.
contract NativeTokenPoolVault is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant PROTOCOL_ROLE = keccak256("PROTOCOL_ROLE");

    event NativeTokenVaultTransfer(address indexed token, address indexed to, uint256 amount);

    constructor(address admin) {
        require(admin != address(0), "NativeTokenPoolVault: zero admin");
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    function transferTo(address token, address to, uint256 amount) external onlyRole(PROTOCOL_ROLE) nonReentrant {
        require(token != address(0), "NativeTokenPoolVault: zero token");
        require(to != address(0), "NativeTokenPoolVault: zero recipient");
        require(to != address(this), "NativeTokenPoolVault: self transfer");
        require(amount > 0, "NativeTokenPoolVault: zero amount");
        IERC20 collateralToken = IERC20(token);
        uint256 vaultBalanceBefore = collateralToken.balanceOf(address(this));
        uint256 recipientBalanceBefore = collateralToken.balanceOf(to);
        collateralToken.safeTransfer(to, amount);
        require(
            vaultBalanceBefore - collateralToken.balanceOf(address(this)) == amount,
            "NativeTokenPoolVault: vault debit mismatch"
        );
        require(
            collateralToken.balanceOf(to) - recipientBalanceBefore == amount,
            "NativeTokenPoolVault: recipient transfer shortfall"
        );
        emit NativeTokenVaultTransfer(token, to, amount);
    }
}
