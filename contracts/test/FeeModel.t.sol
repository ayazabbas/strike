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

    // Default params
    uint256 constant TAKER_FEE_BPS = 30; // 0.30%
    uint256 constant MAKER_REBATE_BPS = 10; // 0.10%
    uint256 constant RESOLVER_BOUNTY = 0.005 ether;
    uint256 constant PRUNER_BOUNTY = 0.0001 ether;

    function setUp() public {
        vm.prank(admin);
        fee = new FeeModel(admin, TAKER_FEE_BPS, MAKER_REBATE_BPS, RESOLVER_BOUNTY, PRUNER_BOUNTY, collector);
    }

    // -------------------------------------------------------------------------
    // Constructor / initial state
    // -------------------------------------------------------------------------

    function test_Constructor_InitialParams() public view {
        assertEq(fee.takerFeeBps(), TAKER_FEE_BPS);
        assertEq(fee.makerRebateBps(), MAKER_REBATE_BPS);
        assertEq(fee.resolverBounty(), RESOLVER_BOUNTY);
        assertEq(fee.prunerBounty(), PRUNER_BOUNTY);
        assertEq(fee.protocolFeeCollector(), collector);
    }

    function test_Constructor_RevertOnTakerFeeAbove100Pct() public {
        vm.expectRevert("FeeModel: takerFee > 100%");
        new FeeModel(admin, 10_001, 0, 0, 0, collector);
    }

    function test_Constructor_RevertOnRebateAboveTakerFee() public {
        vm.expectRevert("FeeModel: rebate > takerFee");
        new FeeModel(admin, 30, 31, 0, 0, collector);
    }

    function test_Constructor_RevertOnZeroCollector() public {
        vm.expectRevert("FeeModel: zero collector");
        new FeeModel(admin, 30, 10, 0, 0, address(0));
    }

    // -------------------------------------------------------------------------
    // calculateTakerFee
    // -------------------------------------------------------------------------

    function test_TakerFee_BasicCalculation() public view {
        // 30 bps on 1 BNB = 0.003 BNB
        uint256 f = fee.calculateTakerFee(1 ether);
        assertEq(f, 0.003 ether);
    }

    function test_TakerFee_ZeroAmount() public view {
        assertEq(fee.calculateTakerFee(0), 0);
    }

    function test_TakerFee_SmallAmount() public view {
        // 30 bps on 100 wei = 0 (rounds down)
        assertEq(fee.calculateTakerFee(100), 0);
    }

    function test_TakerFee_LargeAmount() public view {
        // 30 bps on 1000 BNB = 3 BNB
        assertEq(fee.calculateTakerFee(1000 ether), 3 ether);
    }

    function test_TakerFee_ExactDivision() public view {
        // 30 bps on 10_000 units = 30 units (0.30% of 10_000 = 30)
        assertEq(fee.calculateTakerFee(10_000), 30);
    }

    function test_TakerFee_RoundsDown() public view {
        // 30 bps on 9999 units: 9999 * 30 / 10000 = 29 (not 30)
        assertEq(fee.calculateTakerFee(9999), 29);
    }

    // -------------------------------------------------------------------------
    // calculateMakerRebate
    // -------------------------------------------------------------------------

    function test_MakerRebate_BasicCalculation() public view {
        // 10 bps on 1 BNB = 0.001 BNB
        assertEq(fee.calculateMakerRebate(1 ether), 0.001 ether);
    }

    function test_MakerRebate_ZeroAmount() public view {
        assertEq(fee.calculateMakerRebate(0), 0);
    }

    function test_MakerRebate_AlwaysLeqTakerFee() public view {
        uint256[] memory amounts = new uint256[](5);
        amounts[0] = 1;
        amounts[1] = 100;
        amounts[2] = 1 ether;
        amounts[3] = 100 ether;
        amounts[4] = type(uint128).max;

        for (uint256 i = 0; i < amounts.length; i++) {
            assertLe(fee.calculateMakerRebate(amounts[i]), fee.calculateTakerFee(amounts[i]));
        }
    }

    // -------------------------------------------------------------------------
    // calculateNetProtocolFee
    // -------------------------------------------------------------------------

    function test_NetProtocolFee_Basic() public view {
        // taker 30bps - maker 10bps = net 20bps on 1 BNB = 0.002 BNB
        assertEq(fee.calculateNetProtocolFee(1 ether), 0.002 ether);
    }

    function test_NetProtocolFee_ZeroAmount() public view {
        assertEq(fee.calculateNetProtocolFee(0), 0);
    }

    function test_NetProtocolFee_Consistency() public view {
        uint256 amount = 1 ether;
        uint256 takerFee = fee.calculateTakerFee(amount);
        uint256 rebate = fee.calculateMakerRebate(amount);
        uint256 net = fee.calculateNetProtocolFee(amount);
        assertEq(net, takerFee - rebate);
    }

    function test_NetProtocolFee_ZeroMakerRebate() public {
        // With 0 maker rebate, net = taker fee
        vm.prank(admin);
        fee.setFeeParams(30, 0);

        assertEq(fee.calculateNetProtocolFee(1 ether), fee.calculateTakerFee(1 ether));
    }

    // -------------------------------------------------------------------------
    // setFeeParams
    // -------------------------------------------------------------------------

    function test_SetFeeParams_UpdatesBoth() public {
        vm.prank(admin);
        fee.setFeeParams(50, 20);

        assertEq(fee.takerFeeBps(), 50);
        assertEq(fee.makerRebateBps(), 20);
    }

    function test_SetFeeParams_EmitsEvent() public {
        vm.expectEmit(false, false, false, true);
        emit FeeModel.FeeParamsUpdated(50, 25);

        vm.prank(admin);
        fee.setFeeParams(50, 25);
    }

    function test_SetFeeParams_AllowsZeroFees() public {
        vm.prank(admin);
        fee.setFeeParams(0, 0);

        assertEq(fee.takerFeeBps(), 0);
        assertEq(fee.makerRebateBps(), 0);
        assertEq(fee.calculateTakerFee(1 ether), 0);
        assertEq(fee.calculateMakerRebate(1 ether), 0);
    }

    function test_SetFeeParams_AllowsMaxFee() public {
        vm.prank(admin);
        fee.setFeeParams(10_000, 10_000); // 100% taker fee, 100% rebate (net 0)

        assertEq(fee.calculateTakerFee(1 ether), 1 ether);
        assertEq(fee.calculateMakerRebate(1 ether), 1 ether);
        assertEq(fee.calculateNetProtocolFee(1 ether), 0);
    }

    function test_SetFeeParams_RevertIfTakerFeeAbove100Pct() public {
        vm.expectRevert("FeeModel: takerFee > 100%");
        vm.prank(admin);
        fee.setFeeParams(10_001, 0);
    }

    function test_SetFeeParams_RevertIfRebateAboveTakerFee() public {
        vm.expectRevert("FeeModel: rebate > takerFee");
        vm.prank(admin);
        fee.setFeeParams(30, 31);
    }

    function test_SetFeeParams_RevertIfNotAdmin() public {
        vm.expectRevert();
        vm.prank(unauthorized);
        fee.setFeeParams(50, 10);
    }

    // -------------------------------------------------------------------------
    // setBounties
    // -------------------------------------------------------------------------

    function test_SetBounties_UpdatesBoth() public {
        vm.prank(admin);
        fee.setBounties(0.01 ether, 0.001 ether);

        assertEq(fee.resolverBounty(), 0.01 ether);
        assertEq(fee.prunerBounty(), 0.001 ether);
    }

    function test_SetBounties_EmitsEvent() public {
        vm.expectEmit(false, false, false, true);
        emit FeeModel.BountiesUpdated(0.01 ether, 0.001 ether);

        vm.prank(admin);
        fee.setBounties(0.01 ether, 0.001 ether);
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
        fee.setBounties(0.01 ether, 0.001 ether);
    }

    // -------------------------------------------------------------------------
    // setProtocolFeeCollector
    // -------------------------------------------------------------------------

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

    // -------------------------------------------------------------------------
    // Edge cases
    // -------------------------------------------------------------------------

    function test_FeeCalc_MaxUint128Amount() public view {
        uint256 amount = type(uint128).max; // ~3.4e38
        // Should not overflow: amount * 10_000 fits in uint256 (max ~3.4e42 < 2^256)
        uint256 takerFee = fee.calculateTakerFee(amount);
        uint256 rebate = fee.calculateMakerRebate(amount);
        assertGt(takerFee, rebate); // taker > maker
    }

    function test_BountyValues_Stored() public view {
        assertEq(fee.resolverBounty(), RESOLVER_BOUNTY);
        assertEq(fee.prunerBounty(), PRUNER_BOUNTY);
    }

    // -------------------------------------------------------------------------
    // Fuzz
    // -------------------------------------------------------------------------

    function testFuzz_TakerFee_NeverExceedsAmount(uint128 amount, uint16 bps) public {
        vm.assume(bps <= 10_000);

        vm.prank(admin);
        fee.setFeeParams(bps, 0);

        assertLe(fee.calculateTakerFee(amount), amount);
    }

    function testFuzz_RebateAlwaysLeqTakerFee(uint128 amount, uint16 takerBps, uint16 makerBps) public {
        vm.assume(takerBps <= 10_000);
        vm.assume(makerBps <= takerBps);

        vm.prank(admin);
        fee.setFeeParams(takerBps, makerBps);

        assertLe(fee.calculateMakerRebate(amount), fee.calculateTakerFee(amount));
    }

    function testFuzz_NetProtocolFeeNonNegative(uint128 amount, uint16 takerBps, uint16 makerBps) public {
        vm.assume(takerBps <= 10_000);
        vm.assume(makerBps <= takerBps);

        vm.prank(admin);
        fee.setFeeParams(takerBps, makerBps);

        // Should not revert (no underflow) because rebate <= takerFee always
        uint256 net = fee.calculateNetProtocolFee(amount);
        assertGe(net, 0);
    }
}
