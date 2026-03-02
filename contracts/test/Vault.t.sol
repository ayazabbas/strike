// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/Vault.sol";

/// @dev A contract that tries to reenter the Vault during withdrawal.
contract ReentrancyAttacker {
    Vault public vault;
    uint256 public attackCount;

    constructor(address payable _vault) {
        vault = Vault(_vault);
    }

    receive() external payable {
        if (attackCount < 3 && address(vault).balance > 0) {
            attackCount++;
            vault.withdraw(1 ether);
        }
    }

    function attack() external {
        vault.withdraw(1 ether);
    }
}

contract VaultTest is Test {
    Vault public vault;

    address public admin = address(0x1);
    address public protocol = address(0x2);
    address public user1 = address(0x3);
    address public user2 = address(0x4);
    address public unauthorized = address(0x5);

    function setUp() public {
        vm.startPrank(admin);
        vault = new Vault(admin);
        vault.grantRole(vault.PROTOCOL_ROLE(), protocol);
        vm.stopPrank();

        // Fund test accounts
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
    }

    // -------------------------------------------------------------------------
    // Deposit
    // -------------------------------------------------------------------------

    function test_Deposit_Basic() public {
        vm.prank(user1);
        vault.deposit{value: 1 ether}();

        assertEq(vault.balance(user1), 1 ether);
        assertEq(vault.available(user1), 1 ether);
    }

    function test_Deposit_EmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit Vault.Deposited(user1, 1 ether);

        vm.prank(user1);
        vault.deposit{value: 1 ether}();
    }

    function test_Deposit_Accumulates() public {
        vm.startPrank(user1);
        vault.deposit{value: 1 ether}();
        vault.deposit{value: 2 ether}();
        vm.stopPrank();

        assertEq(vault.balance(user1), 3 ether);
    }

    function test_Deposit_MultipleUsers() public {
        vm.prank(user1);
        vault.deposit{value: 1 ether}();

        vm.prank(user2);
        vault.deposit{value: 5 ether}();

        assertEq(vault.balance(user1), 1 ether);
        assertEq(vault.balance(user2), 5 ether);
    }

    function test_Deposit_RevertOnZero() public {
        vm.expectRevert("Vault: zero deposit");
        vm.prank(user1);
        vault.deposit{value: 0}();
    }

    function test_Deposit_VaultHoldsBNB() public {
        vm.prank(user1);
        vault.deposit{value: 3 ether}();

        assertEq(address(vault).balance, 3 ether);
    }

    // -------------------------------------------------------------------------
    // Withdraw
    // -------------------------------------------------------------------------

    function test_Withdraw_Basic() public {
        vm.prank(user1);
        vault.deposit{value: 5 ether}();

        uint256 before = user1.balance;
        vm.prank(user1);
        vault.withdraw(2 ether);

        assertEq(vault.balance(user1), 3 ether);
        assertEq(user1.balance, before + 2 ether);
    }

    function test_Withdraw_Full() public {
        vm.prank(user1);
        vault.deposit{value: 1 ether}();

        vm.prank(user1);
        vault.withdraw(1 ether);

        assertEq(vault.balance(user1), 0);
    }

    function test_Withdraw_EmitsEvent() public {
        vm.prank(user1);
        vault.deposit{value: 2 ether}();

        vm.expectEmit(true, false, false, true);
        emit Vault.Withdrawn(user1, 1 ether);

        vm.prank(user1);
        vault.withdraw(1 ether);
    }

    function test_Withdraw_RevertOnZeroAmount() public {
        vm.prank(user1);
        vault.deposit{value: 1 ether}();

        vm.expectRevert("Vault: zero amount");
        vm.prank(user1);
        vault.withdraw(0);
    }

    function test_Withdraw_RevertIfInsufficientAvailable() public {
        vm.prank(user1);
        vault.deposit{value: 1 ether}();

        vm.expectRevert("Vault: insufficient available balance");
        vm.prank(user1);
        vault.withdraw(2 ether);
    }

    function test_Withdraw_RevertIfAllLocked() public {
        vm.prank(user1);
        vault.deposit{value: 1 ether}();

        vm.prank(protocol);
        vault.lock(user1, 1 ether);

        vm.expectRevert("Vault: insufficient available balance");
        vm.prank(user1);
        vault.withdraw(1 wei);
    }

    // -------------------------------------------------------------------------
    // Lock
    // -------------------------------------------------------------------------

    function test_Lock_Basic() public {
        vm.prank(user1);
        vault.deposit{value: 5 ether}();

        vm.prank(protocol);
        vault.lock(user1, 3 ether);

        assertEq(vault.locked(user1), 3 ether);
        assertEq(vault.available(user1), 2 ether);
        assertEq(vault.balance(user1), 5 ether); // balance unchanged
    }

    function test_Lock_EmitsEvent() public {
        vm.prank(user1);
        vault.deposit{value: 2 ether}();

        vm.expectEmit(true, false, false, true);
        emit Vault.Locked(user1, 1 ether);

        vm.prank(protocol);
        vault.lock(user1, 1 ether);
    }

    function test_Lock_Accumulates() public {
        vm.prank(user1);
        vault.deposit{value: 10 ether}();

        vm.startPrank(protocol);
        vault.lock(user1, 3 ether);
        vault.lock(user1, 4 ether);
        vm.stopPrank();

        assertEq(vault.locked(user1), 7 ether);
        assertEq(vault.available(user1), 3 ether);
    }

    function test_Lock_RevertOnZeroAmount() public {
        vm.prank(user1);
        vault.deposit{value: 1 ether}();

        vm.expectRevert("Vault: zero amount");
        vm.prank(protocol);
        vault.lock(user1, 0);
    }

    function test_Lock_RevertIfInsufficientAvailable() public {
        vm.prank(user1);
        vault.deposit{value: 1 ether}();

        vm.expectRevert("Vault: insufficient available balance");
        vm.prank(protocol);
        vault.lock(user1, 2 ether);
    }

    function test_Lock_RevertIfNotProtocol() public {
        vm.prank(user1);
        vault.deposit{value: 1 ether}();

        vm.expectRevert();
        vm.prank(unauthorized);
        vault.lock(user1, 1 ether);
    }

    // -------------------------------------------------------------------------
    // Unlock
    // -------------------------------------------------------------------------

    function test_Unlock_Basic() public {
        vm.prank(user1);
        vault.deposit{value: 5 ether}();

        vm.prank(protocol);
        vault.lock(user1, 5 ether);

        vm.prank(protocol);
        vault.unlock(user1, 2 ether);

        assertEq(vault.locked(user1), 3 ether);
        assertEq(vault.available(user1), 2 ether);
    }

    function test_Unlock_EmitsEvent() public {
        vm.prank(user1);
        vault.deposit{value: 2 ether}();

        vm.prank(protocol);
        vault.lock(user1, 2 ether);

        vm.expectEmit(true, false, false, true);
        emit Vault.Unlocked(user1, 1 ether);

        vm.prank(protocol);
        vault.unlock(user1, 1 ether);
    }

    function test_Unlock_Full() public {
        vm.prank(user1);
        vault.deposit{value: 3 ether}();

        vm.prank(protocol);
        vault.lock(user1, 3 ether);

        vm.prank(protocol);
        vault.unlock(user1, 3 ether);

        assertEq(vault.locked(user1), 0);
        assertEq(vault.available(user1), 3 ether);
    }

    function test_Unlock_RevertOnZeroAmount() public {
        vm.prank(user1);
        vault.deposit{value: 1 ether}();

        vm.prank(protocol);
        vault.lock(user1, 1 ether);

        vm.expectRevert("Vault: zero amount");
        vm.prank(protocol);
        vault.unlock(user1, 0);
    }

    function test_Unlock_RevertIfInsufficientLocked() public {
        vm.prank(user1);
        vault.deposit{value: 2 ether}();

        vm.prank(protocol);
        vault.lock(user1, 1 ether);

        vm.expectRevert("Vault: insufficient locked balance");
        vm.prank(protocol);
        vault.unlock(user1, 2 ether);
    }

    function test_Unlock_RevertIfNotProtocol() public {
        vm.expectRevert();
        vm.prank(unauthorized);
        vault.unlock(user1, 1 ether);
    }

    // -------------------------------------------------------------------------
    // transferCollateral
    // -------------------------------------------------------------------------

    function test_TransferCollateral_Basic() public {
        vm.prank(user1);
        vault.deposit{value: 10 ether}();

        vm.prank(protocol);
        vault.lock(user1, 5 ether);

        vm.prank(protocol);
        vault.transferCollateral(user1, user2, 5 ether);

        assertEq(vault.balance(user1), 5 ether);
        assertEq(vault.locked(user1), 0);
        assertEq(vault.balance(user2), 5 ether);
        assertEq(vault.available(user2), 5 ether);
    }

    function test_TransferCollateral_EmitsEvent() public {
        vm.prank(user1);
        vault.deposit{value: 3 ether}();

        vm.prank(protocol);
        vault.lock(user1, 3 ether);

        vm.expectEmit(true, true, false, true);
        emit Vault.CollateralTransferred(user1, user2, 3 ether);

        vm.prank(protocol);
        vault.transferCollateral(user1, user2, 3 ether);
    }

    function test_TransferCollateral_RevertIfInsufficientLocked() public {
        vm.prank(user1);
        vault.deposit{value: 5 ether}();

        vm.prank(protocol);
        vault.lock(user1, 3 ether);

        vm.expectRevert("Vault: insufficient locked balance");
        vm.prank(protocol);
        vault.transferCollateral(user1, user2, 4 ether);
    }

    function test_TransferCollateral_RevertIfNotProtocol() public {
        vm.expectRevert();
        vm.prank(unauthorized);
        vault.transferCollateral(user1, user2, 1 ether);
    }

    // -------------------------------------------------------------------------
    // Emergency withdrawal
    // -------------------------------------------------------------------------

    function test_Emergency_ActivatesMode() public {
        vm.prank(admin);
        vault.activateEmergency();

        assertTrue(vault.emergencyMode());
        assertApproxEqAbs(vault.emergencyActivatedAt(), block.timestamp, 1);
    }

    function test_Emergency_EmitsEvent() public {
        vm.expectEmit(false, false, false, true);
        emit Vault.EmergencyModeActivated(block.timestamp);

        vm.prank(admin);
        vault.activateEmergency();
    }

    function test_Emergency_CannotActivateTwice() public {
        vm.prank(admin);
        vault.activateEmergency();

        vm.expectRevert("Vault: already in emergency mode");
        vm.prank(admin);
        vault.activateEmergency();
    }

    function test_Emergency_RevertIfNotAdmin() public {
        vm.expectRevert();
        vm.prank(unauthorized);
        vault.activateEmergency();
    }

    function test_EmergencyWithdraw_AfterTimelock() public {
        vm.prank(user1);
        vault.deposit{value: 5 ether}();

        // Lock some to test that locked balance is also released
        vm.prank(protocol);
        vault.lock(user1, 2 ether);

        vm.prank(admin);
        vault.activateEmergency();

        // Warp past timelock
        vm.warp(block.timestamp + vault.EMERGENCY_TIMELOCK() + 1);

        uint256 before = user1.balance;
        vm.prank(user1);
        vault.emergencyWithdraw();

        assertEq(vault.balance(user1), 0);
        assertEq(vault.locked(user1), 0);
        assertEq(user1.balance, before + 5 ether);
    }

    function test_EmergencyWithdraw_EmitsEvent() public {
        vm.prank(user1);
        vault.deposit{value: 1 ether}();

        vm.prank(admin);
        vault.activateEmergency();

        vm.warp(block.timestamp + vault.EMERGENCY_TIMELOCK() + 1);

        vm.expectEmit(true, false, false, true);
        emit Vault.EmergencyWithdrawn(user1, 1 ether);

        vm.prank(user1);
        vault.emergencyWithdraw();
    }

    function test_EmergencyWithdraw_RevertIfNotInEmergency() public {
        vm.prank(user1);
        vault.deposit{value: 1 ether}();

        vm.expectRevert("Vault: not in emergency mode");
        vm.prank(user1);
        vault.emergencyWithdraw();
    }

    function test_EmergencyWithdraw_RevertBeforeTimelock() public {
        vm.prank(user1);
        vault.deposit{value: 1 ether}();

        vm.prank(admin);
        vault.activateEmergency();

        // Only 3 days elapsed, timelock is 7 days
        vm.warp(block.timestamp + 3 days);

        vm.expectRevert("Vault: timelock not elapsed");
        vm.prank(user1);
        vault.emergencyWithdraw();
    }

    function test_EmergencyWithdraw_RevertIfNoBalance() public {
        vm.prank(admin);
        vault.activateEmergency();

        vm.warp(block.timestamp + vault.EMERGENCY_TIMELOCK() + 1);

        vm.expectRevert("Vault: no balance");
        vm.prank(user1); // user1 has no deposit
        vault.emergencyWithdraw();
    }

    // -------------------------------------------------------------------------
    // Reentrancy protection
    // -------------------------------------------------------------------------

    function test_Reentrancy_WithdrawProtected() public {
        // Deploy attacker and fund it in the vault
        ReentrancyAttacker attacker = new ReentrancyAttacker(payable(address(vault)));
        vm.deal(address(attacker), 10 ether);

        // Deposit on behalf of the attacker contract
        vm.prank(address(attacker));
        vault.deposit{value: 1 ether}();

        // Fund vault with more BNB so there's something to steal
        vm.deal(address(vault), 10 ether);

        // Attack should revert due to ReentrancyGuard
        vm.expectRevert();
        attacker.attack();

        // Balance should be unchanged (attack failed)
        assertEq(vault.balance(address(attacker)), 1 ether);
    }

    // -------------------------------------------------------------------------
    // available() view
    // -------------------------------------------------------------------------

    function test_Available_UnlockedEqualsBalance() public {
        vm.prank(user1);
        vault.deposit{value: 4 ether}();

        assertEq(vault.available(user1), 4 ether);
    }

    function test_Available_PartiallyLocked() public {
        vm.prank(user1);
        vault.deposit{value: 10 ether}();

        vm.prank(protocol);
        vault.lock(user1, 3 ether);

        assertEq(vault.available(user1), 7 ether);
    }

    function test_Available_ZeroWithNoDeposit() public view {
        assertEq(vault.available(user1), 0);
    }

    // -------------------------------------------------------------------------
    // Fuzz
    // -------------------------------------------------------------------------

    function testFuzz_DepositAndWithdraw(uint96 amount) public {
        vm.assume(amount > 0);
        vm.deal(user1, amount);

        vm.prank(user1);
        vault.deposit{value: amount}();
        assertEq(vault.balance(user1), amount);

        vm.prank(user1);
        vault.withdraw(amount);
        assertEq(vault.balance(user1), 0);
    }
}
