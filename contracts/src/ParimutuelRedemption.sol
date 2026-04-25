// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./ParimutuelPoolManager.sol";
import "./ParimutuelVault.sol";

/// @title ParimutuelRedemption
/// @notice User-facing claim and refund surface for parimutuel markets.
contract ParimutuelRedemption is AccessControl, ReentrancyGuard {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    ParimutuelPoolManager public immutable manager;
    ParimutuelVault public immutable vault;

    event ClaimPaid(uint256 indexed marketId, address indexed user, uint256 payout);
    event RefundPaid(uint256 indexed marketId, address indexed user, uint256 refundAmount);

    constructor(address admin, address manager_, address vault_) {
        require(admin != address(0), "ParimutuelRedemption: zero admin");
        require(manager_ != address(0), "ParimutuelRedemption: zero manager");
        require(vault_ != address(0), "ParimutuelRedemption: zero vault");

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);

        manager = ParimutuelPoolManager(manager_);
        vault = ParimutuelVault(vault_);
    }

    function claim(uint256 marketId) external nonReentrant returns (uint256 payout) {
        payout = manager.consumeClaim(marketId, msg.sender);
        vault.transferTo(msg.sender, payout);
        emit ClaimPaid(marketId, msg.sender, payout);
    }

    function refund(uint256 marketId, uint8[] calldata outcomeIds) external nonReentrant returns (uint256 refundAmount) {
        refundAmount = manager.consumeRefund(marketId, msg.sender, outcomeIds);
        vault.transferTo(msg.sender, refundAmount);
        emit RefundPaid(marketId, msg.sender, refundAmount);
    }
}
