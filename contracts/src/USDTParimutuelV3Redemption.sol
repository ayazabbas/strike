// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./USDTParimutuelV3Manager.sol";
import "./USDTParimutuelV3Vault.sol";

/// @title USDTParimutuelV3Redemption
/// @notice User-facing claims and refunds for USDT parimutuel V3 markets.
contract USDTParimutuelV3Redemption is AccessControl, ReentrancyGuard {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    USDTParimutuelV3Manager public immutable manager;
    USDTParimutuelV3Vault public immutable vault;

    event ClaimPaid(uint256 indexed marketId, address indexed user, uint256 realPayout, uint256 creditPayout);
    event RefundPaid(uint256 indexed marketId, address indexed user, uint256 realRefund, uint256 creditRefund);

    error ZeroAddress();

    constructor(address admin, address manager_, address vault_) {
        if (admin == address(0) || manager_ == address(0) || vault_ == address(0)) revert ZeroAddress();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);

        manager = USDTParimutuelV3Manager(manager_);
        vault = USDTParimutuelV3Vault(vault_);
    }

    function claim(uint256 marketId, address[] calldata creditUsersToSettle)
        external
        nonReentrant
        returns (uint256 realPayout, uint256 creditPayout)
    {
        if (creditUsersToSettle.length > 0) {
            manager.settleLosingCredit(marketId, creditUsersToSettle);
        }

        USDTParimutuelV3Manager.ClaimAmounts memory amounts = manager.consumeClaim(marketId, msg.sender);
        realPayout = amounts.realPayout;
        creditPayout = amounts.creditPayout;

        if (realPayout > 0) {
            vault.transferTo(msg.sender, realPayout);
        }

        emit ClaimPaid(marketId, msg.sender, realPayout, creditPayout);
    }

    function refund(uint256 marketId, uint8[] calldata outcomeIds)
        external
        nonReentrant
        returns (uint256 realRefund, uint256 creditRefund)
    {
        USDTParimutuelV3Manager.RefundAmounts memory amounts = manager.consumeRefund(marketId, msg.sender, outcomeIds);
        realRefund = amounts.realRefund;
        creditRefund = amounts.creditRefund;

        if (realRefund > 0) {
            vault.transferTo(msg.sender, realRefund);
        }

        emit RefundPaid(marketId, msg.sender, realRefund, creditRefund);
    }
}
