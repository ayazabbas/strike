// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/// @title Vault
/// @notice Holds BNB (native currency) as collateral for the Strike CLOB protocol.
///
///         Accounting
///         ----------
///         balance[user]  — total BNB deposited by/for the user
///         locked[user]   — subset of balance reserved for open orders
///         available      = balance - locked
///
///         Access control
///         --------------
///         PROTOCOL_ROLE  — granted to OrderBook / BatchAuction contracts
///                          Can call lock(), unlock(), transferCollateral()
///
///         Emergency mode
///         --------------
///         Admin triggers emergencyMode; after EMERGENCY_TIMELOCK seconds any user
///         can call emergencyWithdraw() to pull all their funds out.
contract Vault is ReentrancyGuard, AccessControl {
    bytes32 public constant PROTOCOL_ROLE = keccak256("PROTOCOL_ROLE");

    uint256 public constant EMERGENCY_TIMELOCK = 7 days;

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    mapping(address => uint256) public balance;
    mapping(address => uint256) public locked;

    /// @notice marketId => BNB held in escrow for outcome token redemption
    mapping(uint256 => uint256) public marketPool;

    bool public emergencyMode;
    uint256 public emergencyActivatedAt;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event Locked(address indexed user, uint256 amount);
    event Unlocked(address indexed user, uint256 amount);
    event CollateralTransferred(address indexed from, address indexed to, uint256 amount);
    event AddedToMarketPool(uint256 indexed marketId, uint256 amount);
    event RedeemedFromPool(uint256 indexed marketId, address indexed to, uint256 amount);
    event EmergencyModeActivated(uint256 timestamp);
    event EmergencyWithdrawn(address indexed user, uint256 amount);

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    // -------------------------------------------------------------------------
    // Deposit / Withdraw
    // -------------------------------------------------------------------------

    /// @notice Deposit BNB into the vault. Credits msg.value to msg.sender's balance.
    function deposit() external payable {
        require(msg.value > 0, "Vault: zero deposit");
        balance[msg.sender] += msg.value;
        emit Deposited(msg.sender, msg.value);
    }

    /// @notice Withdraw `amount` of available (unlocked) BNB.
    /// @param amount Amount to withdraw in wei.
    function withdraw(uint256 amount) external nonReentrant {
        require(amount > 0, "Vault: zero amount");
        uint256 avail = available(msg.sender);
        require(avail >= amount, "Vault: insufficient available balance");

        balance[msg.sender] -= amount;

        (bool ok,) = msg.sender.call{value: amount}("");
        require(ok, "Vault: transfer failed");

        emit Withdrawn(msg.sender, amount);
    }

    // -------------------------------------------------------------------------
    // Lock / Unlock (protocol only)
    // -------------------------------------------------------------------------

    /// @notice Lock `amount` of user's available balance (e.g. on order placement).
    /// @param user   The account whose collateral to lock.
    /// @param amount Amount to lock in wei.
    function lock(address user, uint256 amount) external onlyRole(PROTOCOL_ROLE) {
        require(amount > 0, "Vault: zero amount");
        require(available(user) >= amount, "Vault: insufficient available balance");
        locked[user] += amount;
        emit Locked(user, amount);
    }

    /// @notice Unlock `amount` of user's locked balance (e.g. on cancel or fill).
    /// @param user   The account whose collateral to unlock.
    /// @param amount Amount to unlock in wei.
    function unlock(address user, uint256 amount) external onlyRole(PROTOCOL_ROLE) {
        require(amount > 0, "Vault: zero amount");
        require(locked[user] >= amount, "Vault: insufficient locked balance");
        locked[user] -= amount;
        emit Unlocked(user, amount);
    }

    /// @notice Transfer collateral between accounts (e.g. on fill settlement).
    ///         Moves locked funds from `from` to available funds of `to`.
    /// @param from   Debited account (must have >= amount locked).
    /// @param to     Credited account.
    /// @param amount Amount in wei.
    function transferCollateral(address from, address to, uint256 amount) external onlyRole(PROTOCOL_ROLE) {
        require(amount > 0, "Vault: zero amount");
        require(locked[from] >= amount, "Vault: insufficient locked balance");

        locked[from] -= amount;
        balance[from] -= amount;
        balance[to] += amount;

        emit CollateralTransferred(from, to, amount);
    }

    // -------------------------------------------------------------------------
    // Settlement (combined operation for gas efficiency)
    // -------------------------------------------------------------------------

    /// @notice Combined settlement for BatchAuction.claimFills().
    ///         Moves filled collateral to market pool, protocol fee to collector,
    ///         and unlocks unfilled collateral — all in a single call.
    /// @param user          The order owner.
    /// @param marketId      Market pool to credit.
    /// @param toPool        Amount going to market pool.
    /// @param feeCollector  Protocol fee recipient.
    /// @param protocolFee   Amount going to fee collector.
    /// @param unlockAmount  Amount to unlock (unfilled collateral).
    function settleFill(
        address user,
        uint256 marketId,
        uint256 toPool,
        address feeCollector,
        uint256 protocolFee,
        uint256 unlockAmount
    ) external onlyRole(PROTOCOL_ROLE) {
        uint256 totalDeduct = toPool + protocolFee + unlockAmount;
        require(locked[user] >= totalDeduct, "Vault: insufficient locked balance");

        // Single write to locked (instead of 3 separate decrements)
        locked[user] -= totalDeduct;

        if (toPool > 0) {
            balance[user] -= toPool;
            marketPool[marketId] += toPool;
            emit AddedToMarketPool(marketId, toPool);
        }

        if (protocolFee > 0) {
            balance[user] -= protocolFee;
            balance[feeCollector] += protocolFee;
            emit CollateralTransferred(user, feeCollector, protocolFee);
        }

        if (unlockAmount > 0) {
            emit Unlocked(user, unlockAmount);
        }
    }

    // -------------------------------------------------------------------------
    // Market pool (outcome token redemption escrow)
    // -------------------------------------------------------------------------

    /// @notice Move locked collateral from a user into a market's redemption pool.
    /// @param user     The user whose locked funds to debit.
    /// @param marketId Market pool to credit.
    /// @param amount   Amount in wei.
    function addToMarketPool(address user, uint256 marketId, uint256 amount) external onlyRole(PROTOCOL_ROLE) {
        require(amount > 0, "Vault: zero amount");
        require(locked[user] >= amount, "Vault: insufficient locked balance");

        locked[user] -= amount;
        balance[user] -= amount;
        marketPool[marketId] += amount;

        emit AddedToMarketPool(marketId, amount);
    }

    /// @notice Pay out from a market's redemption pool to a user.
    /// @param marketId Market pool to debit.
    /// @param to       Recipient address.
    /// @param amount   Amount in wei.
    function redeemFromPool(uint256 marketId, address to, uint256 amount) external onlyRole(PROTOCOL_ROLE) nonReentrant {
        require(amount > 0, "Vault: zero amount");
        require(marketPool[marketId] >= amount, "Vault: insufficient market pool");

        marketPool[marketId] -= amount;

        (bool ok,) = to.call{value: amount}("");
        require(ok, "Vault: transfer failed");

        emit RedeemedFromPool(marketId, to, amount);
    }

    // -------------------------------------------------------------------------
    // Emergency withdrawal
    // -------------------------------------------------------------------------

    /// @notice Admin activates emergency mode. After EMERGENCY_TIMELOCK has elapsed
    ///         any user can call emergencyWithdraw() to recover all their funds.
    function activateEmergency() external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(!emergencyMode, "Vault: already in emergency mode");
        emergencyMode = true;
        emergencyActivatedAt = block.timestamp;
        emit EmergencyModeActivated(block.timestamp);
    }

    /// @notice Users can withdraw ALL their funds once emergency mode is active
    ///         and the timelock has elapsed.
    function emergencyWithdraw() external nonReentrant {
        require(emergencyMode, "Vault: not in emergency mode");
        require(block.timestamp >= emergencyActivatedAt + EMERGENCY_TIMELOCK, "Vault: timelock not elapsed");

        uint256 total = balance[msg.sender];
        require(total > 0, "Vault: no balance");

        balance[msg.sender] = 0;
        locked[msg.sender] = 0;

        (bool ok,) = msg.sender.call{value: total}("");
        require(ok, "Vault: transfer failed");

        emit EmergencyWithdrawn(msg.sender, total);
    }

    // -------------------------------------------------------------------------
    // View helpers
    // -------------------------------------------------------------------------

    /// @notice Returns the user's available (unlocked) balance.
    function available(address user) public view returns (uint256) {
        return balance[user] - locked[user];
    }

    // -------------------------------------------------------------------------
    // Receive BNB (e.g. from protocol fee distribution)
    // -------------------------------------------------------------------------

    receive() external payable {
        revert("Vault: use deposit()");
    }
}
