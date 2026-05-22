// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./NativeTokenPoolManager.sol";
import "./NativeTokenPoolVault.sol";

/// @title NativeTokenPoolRedemption
/// @notice User-facing claim and refund surface for Flap Token Pools.
contract NativeTokenPoolRedemption is AccessControl, ReentrancyGuard {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    NativeTokenPoolManager public immutable manager;
    NativeTokenPoolVault public immutable vault;

    event NativeTokenPoolClaimPaid(
        uint256 indexed marketId, address indexed user, address indexed token, uint256 payout
    );
    event NativeTokenPoolRefundPaid(
        uint256 indexed marketId, address indexed user, address indexed token, uint256 refundAmount
    );

    constructor(address admin, address manager_, address vault_) {
        require(admin != address(0), "NativeTokenPoolRedemption: zero admin");
        require(manager_ != address(0), "NativeTokenPoolRedemption: zero manager");
        require(vault_ != address(0), "NativeTokenPoolRedemption: zero vault");

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        manager = NativeTokenPoolManager(manager_);
        vault = NativeTokenPoolVault(vault_);
    }

    function claim(uint256 marketId) external nonReentrant returns (uint256 payout) {
        address token;
        (token, payout) = manager.consumeClaim(marketId, msg.sender);
        vault.transferTo(token, msg.sender, payout);
        emit NativeTokenPoolClaimPaid(marketId, msg.sender, token, payout);
    }

    function refund(uint256 marketId, uint8[] calldata outcomeIds)
        external
        nonReentrant
        returns (uint256 refundAmount)
    {
        address token;
        (token, refundAmount) = manager.consumeRefund(marketId, msg.sender, outcomeIds);
        vault.transferTo(token, msg.sender, refundAmount);
        emit NativeTokenPoolRefundPaid(marketId, msg.sender, token, refundAmount);
    }
}
