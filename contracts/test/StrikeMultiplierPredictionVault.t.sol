// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/StrikeMultiplierPredictionVault.sol";
import "./mocks/MockUSDT.sol";

contract StrikeMultiplierPredictionVaultTest is Test {
    StrikeMultiplierPredictionVault vault;
    MockUSDT usdt;

    address admin = address(0xA11CE);
    address manager = address(0xBEEF);
    address contributorA = address(0xCA);
    address contributorB = address(0xCB);
    address predictorA = address(0xA1);
    address predictorB = address(0xB2);
    address predictorC = address(0xC3);
    address recipient = address(0x777);
    address stranger = address(0xBAD);

    uint256 constant USDT = 1e6;
    bytes32 constant EVENT_ID = keccak256("world-cup-final");
    bytes32 constant EVENT_TWO = keccak256("world-cup-semi");

    function setUp() public {
        usdt = new MockUSDT();
        vault = new StrikeMultiplierPredictionVault(address(usdt), admin, manager);

        _mintAndApprove(contributorA, 1_000 * USDT);
        _mintAndApprove(contributorB, 1_000 * USDT);
        _mintAndApprove(predictorA, 1_000 * USDT);
        _mintAndApprove(predictorB, 1_000 * USDT);
        _mintAndApprove(predictorC, 1_000 * USDT);

        vm.prank(manager);
        vault.createEvent(EVENT_ID);
    }

    function testContributionAndWithdrawShareMath() public {
        _contribute(contributorA, 100 * USDT);
        assertEq(vault.totalBackstopPool(), 100 * USDT);
        assertEq(vault.totalBackstopShares(), 100 * USDT);
        assertEq(vault.backstopSharesOf(contributorA), 100 * USDT);

        vm.prank(manager);
        vault.acceptPrediction(keccak256("p1"), EVENT_ID, predictorA, 10 * USDT, 15 * USDT);
        _settle(EVENT_ID, _ids());

        assertEq(vault.totalBackstopPool(), 110 * USDT);
        assertEq(vault.previewWithdraw(50 * USDT), 55 * USDT);

        uint256 before = usdt.balanceOf(contributorA);
        vm.prank(contributorA);
        vault.withdraw(50 * USDT, 55 * USDT);

        assertEq(usdt.balanceOf(contributorA) - before, 55 * USDT);
        assertEq(vault.totalBackstopPool(), 55 * USDT);
        assertEq(vault.totalBackstopShares(), 50 * USDT);
    }

    function testAcceptPredictionTransfersUSDTAndRecordsReceipt() public {
        _contribute(contributorA, 200 * USDT);

        bytes32 predictionId = keccak256("accepted");
        uint256 beforePredictor = usdt.balanceOf(predictorA);
        vm.prank(manager);
        vault.acceptPrediction(predictionId, EVENT_ID, predictorA, 20 * USDT, 25 * USDT);

        assertEq(beforePredictor - usdt.balanceOf(predictorA), 20 * USDT);
        assertEq(usdt.balanceOf(address(vault)), 220 * USDT);
        assertEq(vault.totalPredictionPoolEscrowed(), 20 * USDT);
        assertEq(vault.reservedBackstopCoverage(), 5 * USDT);

        (
            bytes32 eventId,
            address predictor,
            uint256 predictionAmount,
            uint256 potentialPayout,
            uint256 requiredCoverage,
            StrikeMultiplierPredictionVault.PredictionStatus status
        ) = vault.predictionReceipts(predictionId);
        assertEq(eventId, EVENT_ID);
        assertEq(predictor, predictorA);
        assertEq(predictionAmount, 20 * USDT);
        assertEq(potentialPayout, 25 * USDT);
        assertEq(requiredCoverage, 5 * USDT);
        assertEq(uint256(status), uint256(StrikeMultiplierPredictionVault.PredictionStatus.Accepted));
    }

    function testRejectUncoveredPredictionWhenNoBackstopPool() public {
        vm.expectRevert(StrikeMultiplierPredictionVault.CoverageUnavailable.selector);
        vm.prank(manager);
        vault.acceptPrediction(keccak256("uncovered"), EVENT_ID, predictorA, 10 * USDT, 11 * USDT);
    }

    function testRejectPerPredictionCoverageAboveFivePercent() public {
        _contribute(contributorA, 100 * USDT);

        vm.expectRevert(StrikeMultiplierPredictionVault.CoverageUnavailable.selector);
        vm.prank(manager);
        vault.acceptPrediction(keccak256("too-large"), EVENT_ID, predictorA, 10 * USDT, 16 * USDT);
    }

    function testRejectGlobalCoverageAboveFortyPercent() public {
        _contribute(contributorA, 100 * USDT);

        for (uint256 i = 0; i < 8; i++) {
            vm.prank(manager);
            vault.acceptPrediction(bytes32(uint256(i + 1)), EVENT_ID, predictorA, 10 * USDT, 15 * USDT);
        }

        vm.expectRevert(StrikeMultiplierPredictionVault.CoverageUnavailable.selector);
        vm.prank(manager);
        vault.acceptPrediction(bytes32(uint256(99)), EVENT_ID, predictorA, 10 * USDT, 15 * USDT);
    }

    function testRejectPredictionsAbovePerEventCap() public {
        uint256 maxPerEvent = vault.MAX_PREDICTIONS_PER_EVENT();

        for (uint256 i = 0; i < maxPerEvent; i++) {
            vm.prank(manager);
            vault.acceptPrediction(bytes32(uint256(i + 1)), EVENT_ID, predictorA, 1 * USDT, 1 * USDT);
        }

        vm.expectRevert(StrikeMultiplierPredictionVault.EventPredictionLimitExceeded.selector);
        vm.prank(manager);
        vault.acceptPrediction(bytes32(uint256(maxPerEvent + 1)), EVENT_ID, predictorA, 1 * USDT, 1 * USDT);
    }

    function testRejectPredictionsAboveGlobalCap() public {
        uint256 maxTotal = vault.MAX_TOTAL_PREDICTIONS();
        uint256 maxPerEvent = vault.MAX_PREDICTIONS_PER_EVENT();

        for (uint256 i = 0; i < maxTotal; i++) {
            bytes32 eventId = bytes32(uint256(10_000 + (i / maxPerEvent)));
            if (i % maxPerEvent == 0) {
                _createEvent(eventId);
            }

            vm.prank(manager);
            vault.acceptPrediction(bytes32(uint256(i + 1)), eventId, predictorA, 1 * USDT, 1 * USDT);
        }

        bytes32 extraEvent = bytes32(uint256(99_999));
        _createEvent(extraEvent);
        vm.expectRevert(StrikeMultiplierPredictionVault.TotalPredictionLimitExceeded.selector);
        vm.prank(manager);
        vault.acceptPrediction(bytes32(uint256(maxTotal + 1)), extraEvent, predictorA, 1 * USDT, 1 * USDT);
    }

    function testRejectSettlementWinnersAboveCap() public {
        bytes32[] memory winners = new bytes32[](vault.MAX_SETTLEMENT_WINNERS() + 1);

        vm.expectRevert(StrikeMultiplierPredictionVault.SettlementWinnersLimitExceeded.selector);
        _settle(EVENT_ID, winners);
    }

    function testNoWinnersSendsFullPredictionPoolToBackstopContributors() public {
        _contribute(contributorA, 100 * USDT);
        _contribute(contributorB, 300 * USDT);

        vm.prank(manager);
        vault.acceptPrediction(keccak256("p1"), EVENT_ID, predictorA, 40 * USDT, 45 * USDT);
        vm.prank(manager);
        vault.acceptPrediction(keccak256("p2"), EVENT_ID, predictorB, 60 * USDT, 65 * USDT);

        _settle(EVENT_ID, _ids());

        assertEq(vault.totalBackstopPool(), 500 * USDT);
        assertEq(vault.totalPredictionPoolEscrowed(), 0);
        assertEq(vault.totalClaimablePayouts(), 0);
        assertEq(vault.recoverableUSDT(), 0);
        assertEq(vault.previewWithdraw(vault.backstopSharesOf(contributorA)), 125 * USDT);
        assertEq(vault.previewWithdraw(vault.backstopSharesOf(contributorB)), 375 * USDT);
    }

    function testWinnersPaidFromPredictionPoolWhenEnough() public {
        _contribute(contributorA, 200 * USDT);
        bytes32 winner = keccak256("winner");
        bytes32 loser = keccak256("loser");

        vm.prank(manager);
        vault.acceptPrediction(winner, EVENT_ID, predictorA, 60 * USDT, 70 * USDT);
        vm.prank(manager);
        vault.acceptPrediction(loser, EVENT_ID, predictorB, 60 * USDT, 65 * USDT);

        _settle(EVENT_ID, _ids(winner));

        assertEq(vault.totalBackstopPool(), 250 * USDT);
        assertEq(vault.totalClaimablePayouts(), 70 * USDT);

        uint256 before = usdt.balanceOf(predictorA);
        vm.prank(predictorA);
        vault.claimPredictionPayout(winner);

        assertEq(usdt.balanceOf(predictorA) - before, 70 * USDT);
        assertEq(vault.totalClaimablePayouts(), 0);
    }

    function testWinnersPaidWithBonusBackstopDrawdownWhenPoolInsufficient() public {
        _contribute(contributorA, 200 * USDT);
        bytes32 winner = keccak256("covered-winner");

        vm.prank(manager);
        vault.acceptPrediction(winner, EVENT_ID, predictorA, 20 * USDT, 30 * USDT);

        _settle(EVENT_ID, _ids(winner));

        assertEq(vault.totalBackstopPool(), 190 * USDT);
        assertEq(vault.totalClaimablePayouts(), 30 * USDT);

        uint256 before = usdt.balanceOf(predictorA);
        vm.prank(predictorA);
        vault.claimPredictionPayout(winner);

        assertEq(usdt.balanceOf(predictorA) - before, 30 * USDT);
        assertEq(usdt.balanceOf(address(vault)), 190 * USDT);
    }

    function testSettlementDrawdownPreservesRemainingReservedCoverage() public {
        _contribute(contributorA, 200 * USDT);
        _createEvent(EVENT_TWO);

        bytes32 drawingWinner = keccak256("drawdown-winner");
        bytes32 stillOpenPrediction = keccak256("still-open-prediction");

        vm.prank(manager);
        vault.acceptPrediction(drawingWinner, EVENT_ID, predictorA, 20 * USDT, 30 * USDT);
        vm.prank(manager);
        vault.acceptPrediction(stillOpenPrediction, EVENT_TWO, predictorB, 60 * USDT, 70 * USDT);

        assertEq(vault.reservedBackstopCoverage(), 20 * USDT);

        _settle(EVENT_ID, _ids(drawingWinner));

        assertEq(vault.totalBackstopPool(), 190 * USDT);
        assertEq(vault.reservedBackstopCoverage(), 10 * USDT);
        assertLe(vault.reservedBackstopCoverage(), vault.totalBackstopPool());
        assertEq(vault.totalClaimablePayouts(), 30 * USDT);
    }

    function testSettlementDrawdownDoesNotReapplyAdmissionCaps() public {
        _contribute(contributorA, 200 * USDT);
        _createEvent(EVENT_TWO);

        bytes32 winner = keccak256("covered-drawdown-winner");
        bytes32 openPrediction = keccak256("open-after-drawdown");

        vm.prank(manager);
        vault.acceptPrediction(winner, EVENT_ID, predictorA, 20 * USDT, 30 * USDT);
        vm.prank(manager);
        vault.acceptPrediction(openPrediction, EVENT_TWO, predictorB, 70 * USDT, 80 * USDT);

        assertEq(vault.totalBackstopPool(), 200 * USDT);
        assertEq(vault.reservedBackstopCoverage(), 20 * USDT);

        _settle(EVENT_ID, _ids(winner));

        assertEq(vault.totalBackstopPool(), 190 * USDT);
        assertEq(vault.reservedBackstopCoverage(), 10 * USDT);
        assertLe(vault.reservedBackstopCoverage(), vault.totalBackstopPool());
    }

    function testCancelledEventFullRefundAndReserveRelease() public {
        _contribute(contributorA, 200 * USDT);
        bytes32 predictionId = keccak256("refund");

        vm.prank(manager);
        vault.acceptPrediction(predictionId, EVENT_ID, predictorA, 25 * USDT, 30 * USDT);
        assertEq(vault.reservedBackstopCoverage(), 5 * USDT);

        vm.prank(manager);
        vault.cancelEvent(EVENT_ID);
        assertEq(vault.reservedBackstopCoverage(), 0);
        assertEq(vault.totalRefundablePredictions(), 25 * USDT);
        assertEq(vault.totalPredictionPoolEscrowed(), 0);
        assertEq(vault.recoverableUSDT(), 0);
        assertEq(usdt.balanceOf(address(vault)), 225 * USDT);

        uint256 before = usdt.balanceOf(predictorA);
        vm.prank(predictorA);
        vault.claimRefund(predictionId);

        assertEq(usdt.balanceOf(predictorA) - before, 25 * USDT);
        assertEq(vault.totalRefundablePredictions(), 0);
        assertEq(vault.totalPredictionPoolEscrowed(), 0);
        assertEq(vault.recoverableUSDT(), 0);
        assertEq(usdt.balanceOf(address(vault)), 200 * USDT);
    }

    function testClaimDoubleSpendPrevention() public {
        _contribute(contributorA, 200 * USDT);
        bytes32 winner = keccak256("single-claim");

        vm.prank(manager);
        vault.acceptPrediction(winner, EVENT_ID, predictorA, 20 * USDT, 25 * USDT);
        _settle(EVENT_ID, _ids(winner));

        vm.prank(predictorA);
        vault.claimPredictionPayout(winner);

        vm.expectRevert(StrikeMultiplierPredictionVault.InvalidPredictionStatus.selector);
        vm.prank(predictorA);
        vault.claimPredictionPayout(winner);
    }

    function testRefundDoubleSpendPrevention() public {
        _contribute(contributorA, 200 * USDT);
        bytes32 predictionId = keccak256("single-refund");

        vm.prank(manager);
        vault.acceptPrediction(predictionId, EVENT_ID, predictorA, 20 * USDT, 25 * USDT);
        vm.prank(manager);
        vault.cancelEvent(EVENT_ID);

        vm.prank(predictorA);
        vault.claimRefund(predictionId);

        vm.expectRevert(StrikeMultiplierPredictionVault.InvalidPredictionStatus.selector);
        vm.prank(predictorA);
        vault.claimRefund(predictionId);
    }

    function testWithdrawalCannotImpairExistingReservedCoverage() public {
        _contribute(contributorA, 100 * USDT);

        vm.prank(manager);
        vault.acceptPrediction(keccak256("p1"), EVENT_ID, predictorA, 10 * USDT, 15 * USDT);

        assertEq(vault.maxWithdrawableAmount(), 0);

        vm.expectRevert(StrikeMultiplierPredictionVault.WithdrawalImpairsCoverage.selector);
        vm.prank(contributorA);
        vault.withdraw(1 * USDT, 0);
    }

    function testSomeWithdrawalAllowedWhilePreservingCoverageCaps() public {
        _contribute(contributorA, 200 * USDT);

        vm.prank(manager);
        vault.acceptPrediction(keccak256("p1"), EVENT_ID, predictorA, 10 * USDT, 15 * USDT);

        assertEq(vault.maxWithdrawableAmount(), 100 * USDT);
        vm.prank(contributorA);
        vault.withdraw(100 * USDT, 100 * USDT);

        assertEq(vault.totalBackstopPool(), 100 * USDT);
        assertEq(vault.reservedBackstopCoverage(), 5 * USDT);
    }

    function testNoPlatformFeeOrSkimmingStateExists() public {
        _contribute(contributorA, 100 * USDT);
        bytes32 winner = keccak256("winner-no-fee");

        vm.prank(manager);
        vault.acceptPrediction(winner, EVENT_ID, predictorA, 20 * USDT, 25 * USDT);
        _settle(EVENT_ID, _ids(winner));

        vm.prank(predictorA);
        vault.claimPredictionPayout(winner);

        assertEq(vault.totalBackstopPool(), 95 * USDT);
        assertEq(vault.totalClaimablePayouts(), 0);
        assertEq(vault.totalPredictionPoolEscrowed(), 0);
        assertEq(vault.totalRefundablePredictions(), 0);
        assertEq(vault.recoverableUSDT(), 0);

        vm.expectRevert(StrikeMultiplierPredictionVault.InsufficientRecoverableBalance.selector);
        vm.prank(admin);
        vault.recoverERC20(address(usdt), recipient, 1);
    }

    function testRejectDuplicateWinningPredictionIds() public {
        _contribute(contributorA, 200 * USDT);
        bytes32 winner = keccak256("duplicate-winner");

        vm.prank(manager);
        vault.acceptPrediction(winner, EVENT_ID, predictorA, 20 * USDT, 25 * USDT);

        bytes32[] memory winners = new bytes32[](2);
        winners[0] = winner;
        winners[1] = winner;

        vm.expectRevert(StrikeMultiplierPredictionVault.DuplicateWinningPrediction.selector);
        _settle(EVENT_ID, winners);
    }

    function testSettleInvalidLifecycleUsesSettleableError() public {
        vm.prank(manager);
        vault.cancelEvent(EVENT_ID);

        vm.expectRevert(StrikeMultiplierPredictionVault.EventNotSettleable.selector);
        _settle(EVENT_ID, _ids());
    }

    function testEventManagerFunctionsAreRoleBound() public {
        bytes32 eventId = keccak256("role-bound-event");

        vm.expectRevert();
        vm.prank(stranger);
        vault.createEvent(eventId);

        _createEvent(eventId);

        vm.expectRevert();
        vm.prank(stranger);
        vault.pauseEvent(eventId);

        vm.prank(manager);
        vault.pauseEvent(eventId);

        vm.expectRevert();
        vm.prank(stranger);
        vault.resumeEvent(eventId);

        vm.prank(manager);
        vault.resumeEvent(eventId);

        vm.expectRevert();
        vm.prank(stranger);
        vault.cancelEvent(eventId);

        vm.expectRevert();
        vm.prank(stranger);
        vault.settleEvent(eventId, _ids());

        _settle(eventId, _ids());

        vm.expectRevert();
        vm.prank(stranger);
        vault.finalizeEvent(eventId);
    }

    function testAdminAndPauserFunctionsAreRoleBound() public {
        vm.expectRevert();
        vm.prank(stranger);
        vault.pause();

        vm.prank(admin);
        vault.pause();

        vm.expectRevert();
        vm.prank(stranger);
        vault.unpause();

        vm.prank(admin);
        vault.unpause();

        vm.expectRevert();
        vm.prank(stranger);
        vault.recoverERC20(address(usdt), recipient, 1);
    }

    function _createEvent(bytes32 eventId) internal {
        vm.prank(manager);
        vault.createEvent(eventId);
    }

    function _contribute(address contributor, uint256 amount) internal {
        vm.prank(contributor);
        vault.contribute(amount, 0);
    }

    function _settle(bytes32 eventId, bytes32[] memory winners) internal {
        vm.prank(manager);
        vault.settleEvent(eventId, winners);
    }

    function _ids() internal pure returns (bytes32[] memory ids) {
        ids = new bytes32[](0);
    }

    function _ids(bytes32 a) internal pure returns (bytes32[] memory ids) {
        ids = new bytes32[](1);
        ids[0] = a;
    }

    function _mintAndApprove(address account, uint256 amount) internal {
        usdt.mint(account, amount);
        vm.prank(account);
        usdt.approve(address(vault), type(uint256).max);
    }
}
