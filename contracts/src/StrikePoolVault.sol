// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title StrikePoolVault
/// @notice Dedicated STRIKE custody for STRIKE-denominated pool markets.
contract StrikePoolVault is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant PROTOCOL_ROLE = keccak256("PROTOCOL_ROLE");

    IERC20 public immutable strikeToken;

    event VaultTransfer(address indexed to, uint256 amount);

    constructor(address admin, address strikeToken_) {
        require(admin != address(0), "StrikePoolVault: zero admin");
        require(strikeToken_ != address(0), "StrikePoolVault: zero strike token");

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        strikeToken = IERC20(strikeToken_);
    }

    function transferTo(address to, uint256 amount) external onlyRole(PROTOCOL_ROLE) nonReentrant {
        require(to != address(0), "StrikePoolVault: zero recipient");
        require(amount > 0, "StrikePoolVault: zero amount");
        strikeToken.safeTransfer(to, amount);
        emit VaultTransfer(to, amount);
    }
}
