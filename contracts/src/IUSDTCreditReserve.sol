// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IUSDTCreditReserve {
    struct CreditEvent {
        uint64 claimStart;
        uint64 claimEnd;
        uint64 eventEnd;
        bool exists;
        bool finalized;
        uint256 fundedUsdt;
        uint256 assignedTotal;
        uint256 freeTotal;
        uint256 lockedTotal;
        uint256 redeemedTotal;
        uint256 authorizedMarketCount;
        uint256 settledConsumedTotal;
        uint256 settledPayoutTotal;
        uint256 marketWithdrawnTotal;
    }

    struct CreditAccount {
        uint256 assignedBaseline;
        uint256 freeCredit;
        uint256 lockedCredit;
        uint256 redeemedExcess;
        uint256 nonce;
    }

    function spendCredit(uint256 eventId, address user, address recipientVault, uint256 amount) external;
    function settleCredit(uint256 eventId, address user, uint256 lockedCreditConsumed, uint256 creditReturned) external;
    function lastObservedUsdtBalance() external view returns (uint256);
    function creditBalance(uint256 eventId, address user) external view returns (uint256);
    function lockedCreditBalance(uint256 eventId, address user) external view returns (uint256);
    function redeemableCredit(uint256 eventId, address user) external view returns (uint256);
}
