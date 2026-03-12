// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Vault
/// @notice Holds ERC20 collateral (USDT) as internal escrow for the Strike CLOB protocol.
contract Vault is ReentrancyGuard, AccessControl {
    using SafeERC20 for IERC20;

    bytes32 public constant PROTOCOL_ROLE = keccak256("PROTOCOL_ROLE");
    uint256 public constant EMERGENCY_TIMELOCK = 7 days;

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    IERC20 public immutable collateralToken;

    mapping(address => uint256) public balance;
    mapping(address => uint256) public locked;
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
    event EmergencyPoolDrained(uint256 indexed marketId, address indexed recipient, uint256 amount);

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor(address admin, address _collateralToken) {
        require(_collateralToken != address(0), "Vault: zero collateral token");
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        collateralToken = IERC20(_collateralToken);
    }

    // -------------------------------------------------------------------------
    // Deposit / Withdraw (protocol only)
    // -------------------------------------------------------------------------

    function depositFor(address user, uint256 amount) external onlyRole(PROTOCOL_ROLE) {
        require(amount > 0, "Vault: zero deposit");
        collateralToken.safeTransferFrom(user, address(this), amount);
        balance[user] += amount;
        emit Deposited(user, amount);
    }

    function withdrawTo(address user, uint256 amount) external onlyRole(PROTOCOL_ROLE) nonReentrant {
        require(amount > 0, "Vault: zero amount");
        uint256 avail = available(user);
        require(avail >= amount, "Vault: insufficient available balance");
        balance[user] -= amount;
        collateralToken.safeTransfer(user, amount);
        emit Withdrawn(user, amount);
    }

    // -------------------------------------------------------------------------
    // Lock / Unlock (protocol only)
    // -------------------------------------------------------------------------

    function lock(address user, uint256 amount) external onlyRole(PROTOCOL_ROLE) {
        require(amount > 0, "Vault: zero amount");
        require(available(user) >= amount, "Vault: insufficient available balance");
        locked[user] += amount;
        emit Locked(user, amount);
    }

    function unlock(address user, uint256 amount) external onlyRole(PROTOCOL_ROLE) {
        require(amount > 0, "Vault: zero amount");
        require(locked[user] >= amount, "Vault: insufficient locked balance");
        locked[user] -= amount;
        emit Unlocked(user, amount);
    }

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

    function settleFill(
        address user,
        uint256 marketId,
        uint256 toPool,
        address feeCollector,
        uint256 protocolFee,
        uint256 unlockAmount,
        bool withdrawUser
    ) external onlyRole(PROTOCOL_ROLE) nonReentrant {
        uint256 totalDeduct = toPool + protocolFee + unlockAmount;
        require(locked[user] >= totalDeduct, "Vault: insufficient locked balance");
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
            if (withdrawUser) {
                balance[user] -= unlockAmount;
                collateralToken.safeTransfer(user, unlockAmount);
                emit Withdrawn(user, unlockAmount);
            }
        }
    }

    // -------------------------------------------------------------------------
    // Market pool
    // -------------------------------------------------------------------------

    function addToMarketPool(address user, uint256 marketId, uint256 amount) external onlyRole(PROTOCOL_ROLE) {
        require(amount > 0, "Vault: zero amount");
        require(locked[user] >= amount, "Vault: insufficient locked balance");
        locked[user] -= amount;
        balance[user] -= amount;
        marketPool[marketId] += amount;
        emit AddedToMarketPool(marketId, amount);
    }

    function redeemFromPool(uint256 marketId, address to, uint256 amount) external onlyRole(PROTOCOL_ROLE) nonReentrant {
        require(amount > 0, "Vault: zero amount");
        require(marketPool[marketId] >= amount, "Vault: insufficient market pool");
        marketPool[marketId] -= amount;
        collateralToken.safeTransfer(to, amount);
        emit RedeemedFromPool(marketId, to, amount);
    }

    // -------------------------------------------------------------------------
    // Emergency withdrawal
    // -------------------------------------------------------------------------

    function activateEmergency() external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(!emergencyMode, "Vault: already in emergency mode");
        emergencyMode = true;
        emergencyActivatedAt = block.timestamp;
        emit EmergencyModeActivated(block.timestamp);
    }

    function emergencyDrainPool(uint256 marketId, address recipient) external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        require(emergencyMode, "Vault: not in emergency mode");
        require(block.timestamp >= emergencyActivatedAt + EMERGENCY_TIMELOCK, "Vault: timelock not elapsed");
        require(recipient != address(0), "Vault: zero recipient");
        uint256 amount = marketPool[marketId];
        require(amount > 0, "Vault: empty market pool");
        marketPool[marketId] = 0;
        collateralToken.safeTransfer(recipient, amount);
        emit EmergencyPoolDrained(marketId, recipient, amount);
    }

    function emergencyWithdraw() external nonReentrant {
        require(emergencyMode, "Vault: not in emergency mode");
        require(block.timestamp >= emergencyActivatedAt + EMERGENCY_TIMELOCK, "Vault: timelock not elapsed");
        uint256 total = balance[msg.sender];
        require(total > 0, "Vault: no balance");
        balance[msg.sender] = 0;
        locked[msg.sender] = 0;
        collateralToken.safeTransfer(msg.sender, total);
        emit EmergencyWithdrawn(msg.sender, total);
    }

    // -------------------------------------------------------------------------
    // View helpers
    // -------------------------------------------------------------------------

    function available(address user) public view returns (uint256) {
        return balance[user] - locked[user];
    }
}
