// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/Vault.sol";
import "./mocks/MockUSDT.sol";

contract VaultTest is Test {
    Vault public vault;
    MockUSDT public usdt;

    address public admin = address(0x1);
    address public protocol = address(0x2);
    address public user1 = address(0x3);
    address public user2 = address(0x4);
    address public unauthorized = address(0x5);

    function setUp() public {
        usdt = new MockUSDT();

        vm.startPrank(admin);
        vault = new Vault(admin, address(usdt));
        vault.grantRole(vault.PROTOCOL_ROLE(), protocol);
        vm.stopPrank();

        usdt.mint(user1, 1000 ether);
        usdt.mint(user2, 1000 ether);

        vm.prank(user1);
        usdt.approve(address(vault), type(uint256).max);
        vm.prank(user2);
        usdt.approve(address(vault), type(uint256).max);
    }

    function test_DepositFor_Basic() public {
        vm.prank(protocol);
        vault.depositFor(user1, 1 ether);
        assertEq(vault.balance(user1), 1 ether);
        assertEq(vault.available(user1), 1 ether);
    }

    function test_DepositFor_EmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit Vault.Deposited(user1, 1 ether);
        vm.prank(protocol);
        vault.depositFor(user1, 1 ether);
    }

    function test_DepositFor_Accumulates() public {
        vm.startPrank(protocol);
        vault.depositFor(user1, 1 ether);
        vault.depositFor(user1, 2 ether);
        vm.stopPrank();
        assertEq(vault.balance(user1), 3 ether);
    }

    function test_DepositFor_MultipleUsers() public {
        vm.startPrank(protocol);
        vault.depositFor(user1, 1 ether);
        vault.depositFor(user2, 5 ether);
        vm.stopPrank();
        assertEq(vault.balance(user1), 1 ether);
        assertEq(vault.balance(user2), 5 ether);
    }

    function test_DepositFor_RevertOnZero() public {
        vm.expectRevert("Vault: zero deposit");
        vm.prank(protocol);
        vault.depositFor(user1, 0);
    }

    function test_DepositFor_VaultHoldsUSDT() public {
        vm.prank(protocol);
        vault.depositFor(user1, 3 ether);
        assertEq(usdt.balanceOf(address(vault)), 3 ether);
    }

    function test_DepositFor_RevertIfNotProtocol() public {
        vm.expectRevert();
        vm.prank(unauthorized);
        vault.depositFor(user1, 1 ether);
    }

    function test_WithdrawTo_Basic() public {
        vm.prank(protocol);
        vault.depositFor(user1, 5 ether);
        uint256 before = usdt.balanceOf(user1);
        vm.prank(protocol);
        vault.withdrawTo(user1, 2 ether);
        assertEq(vault.balance(user1), 3 ether);
        assertEq(usdt.balanceOf(user1) - before, 2 ether);
    }

    function test_WithdrawTo_Full() public {
        vm.prank(protocol);
        vault.depositFor(user1, 1 ether);
        vm.prank(protocol);
        vault.withdrawTo(user1, 1 ether);
        assertEq(vault.balance(user1), 0);
    }

    function test_WithdrawTo_EmitsEvent() public {
        vm.prank(protocol);
        vault.depositFor(user1, 2 ether);
        vm.expectEmit(true, false, false, true);
        emit Vault.Withdrawn(user1, 1 ether);
        vm.prank(protocol);
        vault.withdrawTo(user1, 1 ether);
    }

    function test_WithdrawTo_RevertOnZeroAmount() public {
        vm.prank(protocol);
        vault.depositFor(user1, 1 ether);
        vm.expectRevert("Vault: zero amount");
        vm.prank(protocol);
        vault.withdrawTo(user1, 0);
    }

    function test_WithdrawTo_RevertIfInsufficientAvailable() public {
        vm.prank(protocol);
        vault.depositFor(user1, 1 ether);
        vm.expectRevert("Vault: insufficient available balance");
        vm.prank(protocol);
        vault.withdrawTo(user1, 2 ether);
    }

    function test_WithdrawTo_RevertIfAllLocked() public {
        vm.prank(protocol);
        vault.depositFor(user1, 1 ether);
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

    function test_Withdraw_Basic() public {
        vm.prank(protocol);
        vault.depositFor(user1, 5 ether);

        uint256 before = usdt.balanceOf(user1);
        vm.prank(user1);
        vault.withdraw(2 ether);

        assertEq(vault.balance(user1), 3 ether);
        assertEq(vault.available(user1), 3 ether);
        assertEq(usdt.balanceOf(user1) - before, 2 ether);
    }

    function test_Withdraw_RevertIfInsufficientAvailable() public {
        vm.prank(protocol);
        vault.depositFor(user1, 1 ether);
        vm.prank(protocol);
        vault.lock(user1, 1 ether);

        vm.expectRevert("Vault: insufficient available balance");
        vm.prank(user1);
        vault.withdraw(1 wei);
    }

    function test_Withdraw_RevertOnZeroAmount() public {
        vm.expectRevert("Vault: zero amount");
        vm.prank(user1);
        vault.withdraw(0);
    }

    function test_Withdraw_EmitsEvent() public {
        vm.prank(protocol);
        vault.depositFor(user1, 2 ether);

        vm.expectEmit(true, false, false, true);
        emit Vault.Withdrawn(user1, 1 ether);
        vm.prank(user1);
        vault.withdraw(1 ether);
    }

    function test_Lock_Basic() public {
        vm.prank(protocol);
        vault.depositFor(user1, 5 ether);
        vm.prank(protocol);
        vault.lock(user1, 3 ether);
        assertEq(vault.locked(user1), 3 ether);
        assertEq(vault.available(user1), 2 ether);
        assertEq(vault.balance(user1), 5 ether);
    }

    function test_Lock_EmitsEvent() public {
        vm.prank(protocol);
        vault.depositFor(user1, 2 ether);
        vm.expectEmit(true, false, false, true);
        emit Vault.Locked(user1, 1 ether);
        vm.prank(protocol);
        vault.lock(user1, 1 ether);
    }

    function test_Lock_RevertOnZeroAmount() public {
        vm.prank(protocol);
        vault.depositFor(user1, 1 ether);
        vm.expectRevert("Vault: zero amount");
        vm.prank(protocol);
        vault.lock(user1, 0);
    }

    function test_Lock_RevertIfInsufficientAvailable() public {
        vm.prank(protocol);
        vault.depositFor(user1, 1 ether);
        vm.expectRevert("Vault: insufficient available balance");
        vm.prank(protocol);
        vault.lock(user1, 2 ether);
    }

    function test_Unlock_Basic() public {
        vm.prank(protocol);
        vault.depositFor(user1, 5 ether);
        vm.prank(protocol);
        vault.lock(user1, 5 ether);
        vm.prank(protocol);
        vault.unlock(user1, 2 ether);
        assertEq(vault.locked(user1), 3 ether);
        assertEq(vault.available(user1), 2 ether);
    }

    function test_Unlock_Full() public {
        vm.prank(protocol);
        vault.depositFor(user1, 3 ether);
        vm.prank(protocol);
        vault.lock(user1, 3 ether);
        vm.prank(protocol);
        vault.unlock(user1, 3 ether);
        assertEq(vault.locked(user1), 0);
        assertEq(vault.available(user1), 3 ether);
    }

    function test_Unlock_RevertOnZeroAmount() public {
        vm.prank(protocol);
        vault.depositFor(user1, 1 ether);
        vm.prank(protocol);
        vault.lock(user1, 1 ether);
        vm.expectRevert("Vault: zero amount");
        vm.prank(protocol);
        vault.unlock(user1, 0);
    }

    function test_Unlock_RevertIfInsufficientLocked() public {
        vm.prank(protocol);
        vault.depositFor(user1, 2 ether);
        vm.prank(protocol);
        vault.lock(user1, 1 ether);
        vm.expectRevert("Vault: insufficient locked balance");
        vm.prank(protocol);
        vault.unlock(user1, 2 ether);
    }

    function test_Emergency_ActivatesMode() public {
        vm.prank(admin);
        vault.activateEmergency();
        assertTrue(vault.emergencyMode());
    }

    function test_Emergency_CannotActivateTwice() public {
        vm.prank(admin);
        vault.activateEmergency();
        vm.expectRevert("Vault: already in emergency mode");
        vm.prank(admin);
        vault.activateEmergency();
    }

    function test_EmergencyWithdraw_AfterTimelock() public {
        vm.prank(protocol);
        vault.depositFor(user1, 5 ether);
        vm.prank(protocol);
        vault.lock(user1, 2 ether);
        vm.prank(admin);
        vault.activateEmergency();
        vm.warp(block.timestamp + vault.EMERGENCY_TIMELOCK() + 1);
        uint256 before = usdt.balanceOf(user1);
        vm.prank(user1);
        vault.emergencyWithdraw();
        assertEq(vault.balance(user1), 0);
        assertEq(vault.locked(user1), 0);
        assertEq(usdt.balanceOf(user1) - before, 5 ether);
    }

    function test_EmergencyWithdraw_RevertIfNotInEmergency() public {
        vm.expectRevert("Vault: not in emergency mode");
        vm.prank(user1);
        vault.emergencyWithdraw();
    }

    function test_EmergencyWithdraw_RevertBeforeTimelock() public {
        vm.prank(protocol);
        vault.depositFor(user1, 1 ether);
        vm.prank(admin);
        vault.activateEmergency();
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
        vm.prank(user1);
        vault.emergencyWithdraw();
    }

    function test_EmergencyDrainPool_Basic() public {
        // Fund a market pool via settleFill
        vm.prank(protocol);
        vault.depositFor(user1, 10 ether);
        vm.prank(protocol);
        vault.lock(user1, 5 ether);
        vm.prank(protocol);
        vault.settleFill(user1, 1, 5 ether, admin, 0, 0, false);
        assertEq(vault.marketPool(1), 5 ether);

        // Activate emergency
        vm.prank(admin);
        vault.activateEmergency();
        vm.warp(block.timestamp + vault.EMERGENCY_TIMELOCK() + 1);

        uint256 balBefore = usdt.balanceOf(admin);
        vm.prank(admin);
        vault.emergencyDrainPool(1, admin);

        assertEq(vault.marketPool(1), 0);
        assertEq(usdt.balanceOf(admin) - balBefore, 5 ether);
    }

    function test_EmergencyDrainPool_RevertIfNotAdmin() public {
        vm.prank(admin);
        vault.activateEmergency();
        vm.warp(block.timestamp + vault.EMERGENCY_TIMELOCK() + 1);

        vm.expectRevert();
        vm.prank(unauthorized);
        vault.emergencyDrainPool(1, unauthorized);
    }

    function test_EmergencyDrainPool_RevertIfNotEmergency() public {
        vm.expectRevert("Vault: not in emergency mode");
        vm.prank(admin);
        vault.emergencyDrainPool(1, admin);
    }

    function test_EmergencyDrainPool_RevertBeforeTimelock() public {
        vm.prank(protocol);
        vault.depositFor(user1, 5 ether);
        vm.prank(protocol);
        vault.lock(user1, 5 ether);
        vm.prank(protocol);
        vault.settleFill(user1, 1, 5 ether, admin, 0, 0, false);

        vm.prank(admin);
        vault.activateEmergency();
        vm.warp(block.timestamp + 3 days);

        vm.expectRevert("Vault: timelock not elapsed");
        vm.prank(admin);
        vault.emergencyDrainPool(1, admin);
    }

    function test_EmergencyDrainPool_RevertIfEmptyPool() public {
        vm.prank(admin);
        vault.activateEmergency();
        vm.warp(block.timestamp + vault.EMERGENCY_TIMELOCK() + 1);

        vm.expectRevert("Vault: empty market pool");
        vm.prank(admin);
        vault.emergencyDrainPool(1, admin);
    }

    function test_EmergencyDrainPool_RevertZeroRecipient() public {
        vm.prank(admin);
        vault.activateEmergency();
        vm.warp(block.timestamp + vault.EMERGENCY_TIMELOCK() + 1);

        vm.expectRevert("Vault: zero recipient");
        vm.prank(admin);
        vault.emergencyDrainPool(1, address(0));
    }

    function test_Available_ZeroWithNoDeposit() public view {
        assertEq(vault.available(user1), 0);
    }

    function testFuzz_DepositAndWithdraw(uint96 amount) public {
        vm.assume(amount > 0 && amount <= 500 ether);
        vm.prank(protocol);
        vault.depositFor(user1, amount);
        assertEq(vault.balance(user1), amount);
        vm.prank(protocol);
        vault.withdrawTo(user1, amount);
        assertEq(vault.balance(user1), 0);
    }
}
