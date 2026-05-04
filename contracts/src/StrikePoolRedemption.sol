// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./StrikeCreditReserve.sol";
import "./StrikePoolManager.sol";
import "./StrikePoolVault.sol";

/// @title StrikePoolRedemption
/// @notice User-facing claim and refund surface for STRIKE pool markets.
contract StrikePoolRedemption is AccessControl, ReentrancyGuard {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    StrikePoolManager public immutable manager;
    StrikePoolVault public immutable vault;
    StrikeCreditReserve public immutable creditReserve;

    event ClaimPaid(
        uint256 indexed marketId,
        address indexed user,
        uint256 realPayout,
        uint256 creditPrincipalSettled,
        uint256 creditReturned,
        uint256 creditLost
    );
    event RefundPaid(uint256 indexed marketId, address indexed user, uint256 realRefund, uint256 creditRefundRestored);

    constructor(address admin, address manager_, address vault_, address creditReserve_) {
        require(admin != address(0), "StrikePoolRedemption: zero admin");
        require(manager_ != address(0), "StrikePoolRedemption: zero manager");
        require(vault_ != address(0), "StrikePoolRedemption: zero vault");
        require(creditReserve_ != address(0), "StrikePoolRedemption: zero credit reserve");

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);

        manager = StrikePoolManager(manager_);
        vault = StrikePoolVault(vault_);
        creditReserve = StrikeCreditReserve(creditReserve_);
    }

    function claim(uint256 marketId) external nonReentrant returns (uint256 userPayout) {
        StrikePoolManager.ClaimAmounts memory amounts = manager.consumeClaim(marketId, msg.sender);
        uint256 eventId = manager.marketCreditEventId(marketId);
        uint256 creditConsumed = amounts.creditPrincipal + amounts.creditLost;
        uint256 creditReturned = amounts.creditPrincipal + amounts.creditProfit;

        if (creditConsumed > 0 || creditReturned > 0) {
            require(eventId != 0, "StrikePoolRedemption: missing credit event");
            if (creditReturned > 0) {
                vault.transferTo(address(creditReserve), creditReturned);
            }
            creditReserve.settleCredit(eventId, msg.sender, creditConsumed, creditReturned);
        }

        userPayout = amounts.realPayout;
        if (userPayout > 0) {
            vault.transferTo(msg.sender, userPayout);
        }

        emit ClaimPaid(marketId, msg.sender, amounts.realPayout, amounts.creditPrincipal, creditReturned, amounts.creditLost);
    }

    function refund(uint256 marketId, uint8[] calldata outcomeIds) external nonReentrant returns (uint256 userRefund) {
        StrikePoolManager.RefundAmounts memory amounts = manager.consumeRefund(marketId, msg.sender, outcomeIds);

        if (amounts.creditRefund > 0) {
            uint256 eventId = manager.marketCreditEventId(marketId);
            require(eventId != 0, "StrikePoolRedemption: missing credit event");
            vault.transferTo(address(creditReserve), amounts.creditRefund);
            creditReserve.settleCredit(eventId, msg.sender, amounts.creditRefund, amounts.creditRefund);
        }

        userRefund = amounts.realRefund;
        if (userRefund > 0) {
            vault.transferTo(msg.sender, userRefund);
        }

        emit RefundPaid(marketId, msg.sender, amounts.realRefund, amounts.creditRefund);
    }
}
