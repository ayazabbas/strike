// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/Vault.sol";

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
    // depositFor (protocol only)
    // -------------------------------------------------------------------------

    function test_DepositFor_Basic() public {
        vm.deal(protocol, 10 ether);
        vm.prank(protocol);
        vault.depositFor{value: 1 ether}(user1);

        assertEq(vault.balance(user1), 1 ether);
        assertEq(vault.available(user1), 1 ether);
    }

    function test_DepositFor_EmitsEvent() public {
        vm.deal(protocol, 10 ether);

        vm.expectEmit(true, false, false, true);
        emit Vault.Deposited(user1, 1 ether);

        vm.prank(protocol);
        vault.depositFor{value: 1 ether}(user1);
    }

    function test_DepositFor_Accumulates() public {
        vm.deal(protocol, 10 ether);
        vm.startPrank(protocol);
        vault.depositFor{value: 1 ether}(user1);
        vault.depositFor{value: 2 ether}(user1);
        vm.stopPrank();

        assertEq(vault.balance(user1), 3 ether);
    }

    function test_DepositFor_MultipleUsers() public {
        vm.deal(protocol, 10 ether);
        vm.startPrank(protocol);
        vault.depositFor{value: 1 ether}(user1);
        vault.depositFor{value: 5 ether}(user2);
        vm.stopPrank();

        assertEq(vault.balance(user1), 1 ether);
        assertEq(vault.balance(user2), 5 ether);
    }

    function test_DepositFor_RevertOnZero() public {
        vm.expectRevert("Vault: zero deposit");
        vm.prank(protocol);
        vault.depositFor{value: 0}(user1);
    }

    function test_DepositFor_VaultHoldsBNB() public {
        vm.deal(protocol, 10 ether);
        vm.prank(protocol);
        vault.depositFor{value: 3 ether}(user1);

        assertEq(address(vault).balance, 3 ether);
    }

    function test_DepositFor_RevertIfNotProtocol() public {
        vm.deal(unauthorized, 10 ether);
        vm.expectRevert();
        vm.prank(unauthorized);
        vault.depositFor{value: 1 ether}(user1);
    }

    // -------------------------------------------------------------------------
    // withdrawTo (protocol only)
    // -------------------------------------------------------------------------

    function test_WithdrawTo_Basic() public {
        vm.deal(protocol, 10 ether);
        vm.prank(protocol);
        vault.depositFor{value: 5 ether}(user1);

        uint256 before = user1.balance;
        vm.prank(protocol);
        vault.withdrawTo(user1, 2 ether);

        assertEq(vault.balance(user1), 3 ether);
        assertEq(user1.balance, before + 2 ether);
    }

    function test_WithdrawTo_Full() public {
        vm.deal(protocol, 10 ether);
        vm.prank(protocol);
        vault.depositFor{value: 1 ether}(user1);

        vm.prank(protocol);
        vault.withdrawTo(user1, 1 ether);

        assertEq(vault.balance(user1), 0);
    }

    function test_WithdrawTo_EmitsEvent() public {
        vm.deal(protocol, 10 ether);
        vm.prank(protocol);
        vault.depositFor{value: 2 ether}(user1);

        vm.expectEmit(true, false, false, true);
        emit Vault.Withdrawn(user1, 1 ether);

        vm.prank(protocol);
        vault.withdrawTo(user1, 1 ether);
    }

    function test_WithdrawTo_RevertOnZeroAmount() public {
        vm.deal(protocol, 10 ether);
        vm.prank(protocol);
        vault.depositFor{value: 1 ether}(user1);

        vm.expectRevert("Vault: zero amount");
        vm.prank(protocol);
        vault.withdrawTo(user1, 0);
    }

    function test_WithdrawTo_RevertIfInsufficientAvailable() public {
        vm.deal(protocol, 10 ether);
        vm.prank(protocol);
        vault.depositFor{value: 1 ether}(user1);

        vm.expectRevert("Vault: insufficient available balance");
        vm.prank(protocol);
        vault.withdrawTo(user1, 2 ether);
    }

    function test_WithdrawTo_RevertIfAllLocked() public {
        vm.deal(protocol, 10 ether);
        vm.prank(protocol);
        vault.depositFor{value: 1 ether}(user1);

        vm.prank(protocol);
        vault.lock(user1, 1 ether);

        vm.expectRevert("Vault: insufficient available balance");
        vm.prank(protocol);
        vault.withdrawTo(user1, 1 wei);
    }

    function test_WithdrawTo_RevertIfNotProtocol() public {
        vm.expectRevert();
        vm.prank(unauthorized);
        vault.withdrawTo(user1, 1 ether);
    }

    // -------------------------------------------------------------------------
    // Lock
    // -------------------------------------------------------------------------

    function test_Lock_Basic() public {
        vm.deal(protocol, 10 ether);
        vm.prank(protocol);
        vault.depositFor{value: 5 ether}(user1);

        vm.prank(protocol);
        vault.lock(user1, 3 ether);

        assertEq(vault.locked(user1), 3 ether);
        assertEq(vault.available(user1), 2 ether);
        assertEq(vault.balance(user1), 5 ether); // balance unchanged
    }

    function test_Lock_EmitsEvent() public {
        vm.deal(protocol, 10 ether);
        vm.prank(protocol);
        vault.depositFor{value: 2 ether}(user1);

        vm.expectEmit(true, false, false, true);
        emit Vault.Locked(user1, 1 ether);

        vm.prank(protocol);
        vault.lock(user1, 1 ether);
    }

    function test_Lock_Accumulates() public {
        vm.deal(protocol, 20 ether);
        vm.prank(protocol);
        vault.depositFor{value: 10 ether}(user1);

        vm.startPrank(protocol);
        vault.lock(user1, 3 ether);
        vault.lock(user1, 4 ether);
        vm.stopPrank();

        assertEq(vault.locked(user1), 7 ether);
        assertEq(vault.available(user1), 3 ether);
    }

    function test_Lock_RevertOnZeroAmount() public {
        vm.deal(protocol, 10 ether);
        vm.prank(protocol);
        vault.depositFor{value: 1 ether}(user1);

        vm.expectRevert("Vault: zero amount");
        vm.prank(protocol);
        vault.lock(user1, 0);
    }

    function test_Lock_RevertIfInsufficientAvailable() public {
        vm.deal(protocol, 10 ether);
        vm.prank(protocol);
        vault.depositFor{value: 1 ether}(user1);

        vm.expectRevert("Vault: insufficient available balance");
        vm.prank(protocol);
        vault.lock(user1, 2 ether);
    }

    function test_Lock_RevertIfNotProtocol() public {
        vm.deal(protocol, 10 ether);
        vm.prank(protocol);
        vault.depositFor{value: 1 ether}(user1);

        vm.expectRevert();
        vm.prank(unauthorized);
        vault.lock(user1, 1 ether);
    }

    // -------------------------------------------------------------------------
    // Unlock
    // -------------------------------------------------------------------------

    function test_Unlock_Basic() public {
        vm.deal(protocol, 10 ether);
        vm.prank(protocol);
        vault.depositFor{value: 5 ether}(user1);

        vm.prank(protocol);
        vault.lock(user1, 5 ether);

        vm.prank(protocol);
        vault.unlock(user1, 2 ether);

        assertEq(vault.locked(user1), 3 ether);
        assertEq(vault.available(user1), 2 ether);
    }

    function test_Unlock_EmitsEvent() public {
        vm.deal(protocol, 10 ether);
        vm.prank(protocol);
        vault.depositFor{value: 2 ether}(user1);

        vm.prank(protocol);
        vault.lock(user1, 2 ether);

        vm.expectEmit(true, false, false, true);
        emit Vault.Unlocked(user1, 1 ether);

        vm.prank(protocol);
        vault.unlock(user1, 1 ether);
    }

    function test_Unlock_Full() public {
        vm.deal(protocol, 10 ether);
        vm.prank(protocol);
        vault.depositFor{value: 3 ether}(user1);

        vm.prank(protocol);
        vault.lock(user1, 3 ether);

        vm.prank(protocol);
        vault.unlock(user1, 3 ether);

        assertEq(vault.locked(user1), 0);
        assertEq(vault.available(user1), 3 ether);
    }

    function test_Unlock_RevertOnZeroAmount() public {
        vm.deal(protocol, 10 ether);
        vm.prank(protocol);
        vault.depositFor{value: 1 ether}(user1);

        vm.prank(protocol);
        vault.lock(user1, 1 ether);

        vm.expectRevert("Vault: zero amount");
        vm.prank(protocol);
        vault.unlock(user1, 0);
    }

    function test_Unlock_RevertIfInsufficientLocked() public {
        vm.deal(protocol, 10 ether);
        vm.prank(protocol);
        vault.depositFor{value: 2 ether}(user1);

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
        vm.deal(protocol, 20 ether);
        vm.prank(protocol);
        vault.depositFor{value: 10 ether}(user1);

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
        vm.deal(protocol, 10 ether);
        vm.prank(protocol);
        vault.depositFor{value: 3 ether}(user1);

        vm.prank(protocol);
        vault.lock(user1, 3 ether);

        vm.expectEmit(true, true, false, true);
        emit Vault.CollateralTransferred(user1, user2, 3 ether);

        vm.prank(protocol);
        vault.transferCollateral(user1, user2, 3 ether);
    }

    function test_TransferCollateral_RevertIfInsufficientLocked() public {
        vm.deal(protocol, 10 ether);
        vm.prank(protocol);
        vault.depositFor{value: 5 ether}(user1);

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
        vm.deal(protocol, 10 ether);
        vm.prank(protocol);
        vault.depositFor{value: 5 ether}(user1);

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
        vm.deal(protocol, 10 ether);
        vm.prank(protocol);
        vault.depositFor{value: 1 ether}(user1);

        vm.prank(admin);
        vault.activateEmergency();

        vm.warp(block.timestamp + vault.EMERGENCY_TIMELOCK() + 1);

        vm.expectEmit(true, false, false, true);
        emit Vault.EmergencyWithdrawn(user1, 1 ether);

        vm.prank(user1);
        vault.emergencyWithdraw();
    }

    function test_EmergencyWithdraw_RevertIfNotInEmergency() public {
        vm.deal(protocol, 10 ether);
        vm.prank(protocol);
        vault.depositFor{value: 1 ether}(user1);

        vm.expectRevert("Vault: not in emergency mode");
        vm.prank(user1);
        vault.emergencyWithdraw();
    }

    function test_EmergencyWithdraw_RevertBeforeTimelock() public {
        vm.deal(protocol, 10 ether);
        vm.prank(protocol);
        vault.depositFor{value: 1 ether}(user1);

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
    // available() view
    // -------------------------------------------------------------------------

    function test_Available_UnlockedEqualsBalance() public {
        vm.deal(protocol, 10 ether);
        vm.prank(protocol);
        vault.depositFor{value: 4 ether}(user1);

        assertEq(vault.available(user1), 4 ether);
    }

    function test_Available_PartiallyLocked() public {
        vm.deal(protocol, 20 ether);
        vm.prank(protocol);
        vault.depositFor{value: 10 ether}(user1);

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
        vm.deal(protocol, uint256(amount) * 2);

        vm.prank(protocol);
        vault.depositFor{value: amount}(user1);
        assertEq(vault.balance(user1), amount);

        vm.prank(protocol);
        vault.withdrawTo(user1, amount);
        assertEq(vault.balance(user1), 0);
    }
}
