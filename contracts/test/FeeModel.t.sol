// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/FeeModel.sol";

contract FeeModelTest is Test {
    FeeModel public fee;

    address public admin = address(0x1);
    address public collector = address(0x2);
    address public unauthorized = address(0x3);
    address public newCollector = address(0x4);

    uint256 constant FEE_BPS = 20;
    uint256 constant CLEARING_BOUNTY_BPS = 0;
    uint256 constant RESOLVER_BOUNTY = 5e18;
    uint256 constant PRUNER_BOUNTY = 1e17;

    function setUp() public {
        vm.prank(admin);
        fee = new FeeModel(admin, FEE_BPS, CLEARING_BOUNTY_BPS, RESOLVER_BOUNTY, PRUNER_BOUNTY, collector);
    }

    function test_Constructor_InitialParams() public view {
        assertEq(fee.feeBps(), FEE_BPS);
        assertEq(fee.clearingBountyBps(), CLEARING_BOUNTY_BPS);
        assertEq(fee.resolverBounty(), RESOLVER_BOUNTY);
        assertEq(fee.prunerBounty(), PRUNER_BOUNTY);
        assertEq(fee.protocolFeeCollector(), collector);
    }

    function test_Constructor_RevertOnFeeAbove100Pct() public {
        vm.expectRevert("FeeModel: fee > 100%");
        new FeeModel(admin, 10_001, 0, 0, 0, collector);
    }

    function test_Constructor_RevertOnBountyAbove100Pct() public {
        vm.expectRevert("FeeModel: bounty > 100%");
        new FeeModel(admin, 20, 10_001, 0, 0, collector);
    }

    function test_Constructor_RevertOnZeroCollector() public {
        vm.expectRevert("FeeModel: zero collector");
        new FeeModel(admin, 20, 0, 0, 0, address(0));
    }

    function test_Fee_BasicCalculation() public view {
        assertEq(fee.calculateFee(1 ether), 0.002 ether);
    }

    function test_Fee_ZeroAmount() public view {
        assertEq(fee.calculateFee(0), 0);
    }

    function test_Fee_SmallAmount() public view {
        assertEq(fee.calculateFee(100), 0);
    }

    function test_Fee_LargeAmount() public view {
        assertEq(fee.calculateFee(1000 ether), 2 ether);
    }

    function test_Fee_ExactDivision() public view {
        assertEq(fee.calculateFee(10_000), 20);
    }

    function test_Fee_RoundsDown() public view {
        assertEq(fee.calculateFee(9999), 19);
    }

    function test_SetFeeBps_Updates() public {
        vm.prank(admin);
        fee.setFeeBps(50);
        assertEq(fee.feeBps(), 50);
    }

    function test_SetFeeBps_EmitsEvent() public {
        vm.expectEmit(false, false, false, true);
        emit FeeModel.FeeBpsUpdated(50);
        vm.prank(admin);
        fee.setFeeBps(50);
    }

    function test_SetFeeBps_AllowsZero() public {
        vm.prank(admin);
        fee.setFeeBps(0);
        assertEq(fee.calculateFee(1 ether), 0);
    }

    function test_SetFeeBps_AllowsMax() public {
        vm.prank(admin);
        fee.setFeeBps(10_000);
        assertEq(fee.calculateFee(1 ether), 1 ether);
    }

    function test_SetFeeBps_RevertIfAbove100Pct() public {
        vm.expectRevert("FeeModel: fee > 100%");
        vm.prank(admin);
        fee.setFeeBps(10_001);
    }

    function test_SetFeeBps_RevertIfNotAdmin() public {
        vm.expectRevert();
        vm.prank(unauthorized);
        fee.setFeeBps(50);
    }

    function test_SetClearingBounty_Updates() public {
        vm.prank(admin);
        fee.setClearingBounty(100);
        assertEq(fee.clearingBountyBps(), 100);
    }

    function test_SetClearingBounty_EmitsEvent() public {
        vm.expectEmit(false, false, false, true);
        emit FeeModel.ClearingBountyUpdated(100);
        vm.prank(admin);
        fee.setClearingBounty(100);
    }

    function test_SetClearingBounty_RevertIfAbove100Pct() public {
        vm.expectRevert("FeeModel: bounty > 100%");
        vm.prank(admin);
        fee.setClearingBounty(10_001);
    }

    function test_SetBounties_UpdatesBoth() public {
        vm.prank(admin);
        fee.setBounties(10e18, 1e18);
        assertEq(fee.resolverBounty(), 10e18);
        assertEq(fee.prunerBounty(), 1e18);
    }

    function test_SetBounties_EmitsEvent() public {
        vm.expectEmit(false, false, false, true);
        emit FeeModel.BountiesUpdated(10e18, 1e18);
        vm.prank(admin);
        fee.setBounties(10e18, 1e18);
    }

    function test_SetBounties_AllowsZero() public {
        vm.prank(admin);
        fee.setBounties(0, 0);
        assertEq(fee.resolverBounty(), 0);
        assertEq(fee.prunerBounty(), 0);
    }

    function test_SetBounties_RevertIfNotAdmin() public {
        vm.expectRevert();
        vm.prank(unauthorized);
        fee.setBounties(10e18, 1e18);
    }

    function test_SetCollector_UpdatesAddress() public {
        vm.prank(admin);
        fee.setProtocolFeeCollector(newCollector);
        assertEq(fee.protocolFeeCollector(), newCollector);
    }

    function test_SetCollector_EmitsEvent() public {
        vm.expectEmit(true, false, false, false);
        emit FeeModel.ProtocolFeeCollectorUpdated(newCollector);
        vm.prank(admin);
        fee.setProtocolFeeCollector(newCollector);
    }

    function test_SetCollector_RevertOnZeroAddress() public {
        vm.expectRevert("FeeModel: zero collector");
        vm.prank(admin);
        fee.setProtocolFeeCollector(address(0));
    }

    function test_SetCollector_RevertIfNotAdmin() public {
        vm.expectRevert();
        vm.prank(unauthorized);
        fee.setProtocolFeeCollector(newCollector);
    }

    function testFuzz_Fee_NeverExceedsAmount(uint128 amount, uint16 bps) public {
        vm.assume(bps <= 10_000);
        vm.prank(admin);
        fee.setFeeBps(bps);
        assertLe(fee.calculateFee(amount), amount);
    }
}
