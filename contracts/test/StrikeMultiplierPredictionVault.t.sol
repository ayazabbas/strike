// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/StrikeMultiplierPredictionVault.sol";
import "./mocks/MockUSDT.sol";

contract StrikeMultiplierPredictionVaultTest is Test {
    StrikeMultiplierPredictionVault vault;
    MockUSDT usdt;

    uint256 managerPrivateKey = 0xBEEF;
    uint256 strangerPrivateKey = 0xBAD;

    address admin = address(0xA11CE);
    address manager = vm.addr(managerPrivateKey);
    address contributorA = address(0xCA);
    address contributorB = address(0xCB);
    address predictorA = address(0xA1);
    address predictorB = address(0xB2);
    address predictorC = address(0xC3);
    address recipient = address(0x777);
    address stranger = vm.addr(strangerPrivateKey);

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

    function testSubmitPredictionWithQuoteTransfersUSDTAndRecordsReceipt() public {
        _contribute(contributorA, 200 * USDT);

        bytes32 predictionId = keccak256("quoted-accepted");
        uint256 predictionAmount = 20 * USDT;
        uint256 potentialPayout = 25 * USDT;
        uint256 expiresAt = block.timestamp + 1 hours;
        bytes memory signature = _quoteSignature(
            managerPrivateKey, predictionId, EVENT_ID, predictorA, predictionAmount, potentialPayout, expiresAt
        );

        uint256 beforePredictor = usdt.balanceOf(predictorA);
        vm.prank(predictorA);
        vault.submitPredictionWithQuote(predictionId, EVENT_ID, predictionAmount, potentialPayout, expiresAt, signature);

        assertEq(beforePredictor - usdt.balanceOf(predictorA), predictionAmount);
        assertEq(usdt.balanceOf(address(vault)), 220 * USDT);
        assertEq(vault.totalPredictionPoolEscrowed(), predictionAmount);
        assertEq(vault.reservedBackstopCoverage(), 5 * USDT);

        (
            bytes32 eventId,
            address predictor,
            uint256 recordedPredictionAmount,
            uint256 recordedPotentialPayout,
            uint256 requiredCoverage,
            StrikeMultiplierPredictionVault.PredictionStatus status
        ) = vault.predictionReceipts(predictionId);
        assertEq(eventId, EVENT_ID);
        assertEq(predictor, predictorA);
        assertEq(recordedPredictionAmount, predictionAmount);
        assertEq(recordedPotentialPayout, potentialPayout);
        assertEq(requiredCoverage, 5 * USDT);
        assertEq(uint256(status), uint256(StrikeMultiplierPredictionVault.PredictionStatus.Accepted));
    }

    function testSubmitPredictionWithQuoteRejectsExpiredQuote() public {
        _contribute(contributorA, 200 * USDT);

        bytes32 predictionId = keccak256("expired-quote");
        uint256 expiresAt = block.timestamp - 1;
        bytes memory signature =
            _quoteSignature(managerPrivateKey, predictionId, EVENT_ID, predictorA, 20 * USDT, 25 * USDT, expiresAt);

        vm.expectRevert(StrikeMultiplierPredictionVault.ExpiredPredictionQuote.selector);
        vm.prank(predictorA);
        vault.submitPredictionWithQuote(predictionId, EVENT_ID, 20 * USDT, 25 * USDT, expiresAt, signature);
    }

    function testSubmitPredictionWithQuoteRejectsWrongSigner() public {
        _contribute(contributorA, 200 * USDT);

        bytes32 predictionId = keccak256("wrong-signer-quote");
        uint256 expiresAt = block.timestamp + 1 hours;
        bytes memory signature =
            _quoteSignature(strangerPrivateKey, predictionId, EVENT_ID, predictorA, 20 * USDT, 25 * USDT, expiresAt);

        vm.expectRevert(StrikeMultiplierPredictionVault.InvalidPredictionQuoteSigner.selector);
        vm.prank(predictorA);
        vault.submitPredictionWithQuote(predictionId, EVENT_ID, 20 * USDT, 25 * USDT, expiresAt, signature);
    }

    function testSubmitPredictionWithQuoteBindsSignedFields() public {
        _contribute(contributorA, 200 * USDT);
        _createEvent(EVENT_TWO);

        bytes32 predictionId = keccak256("bound-quote");
        uint256 predictionAmount = 20 * USDT;
        uint256 potentialPayout = 25 * USDT;
        uint256 expiresAt = block.timestamp + 1 hours;
        bytes memory signature = _quoteSignature(
            managerPrivateKey, predictionId, EVENT_ID, predictorA, predictionAmount, potentialPayout, expiresAt
        );

        vm.expectRevert(StrikeMultiplierPredictionVault.InvalidPredictionQuoteSigner.selector);
        vm.prank(predictorB);
        vault.submitPredictionWithQuote(predictionId, EVENT_ID, predictionAmount, potentialPayout, expiresAt, signature);

        vm.expectRevert(StrikeMultiplierPredictionVault.InvalidPredictionQuoteSigner.selector);
        vm.prank(predictorA);
        vault.submitPredictionWithQuote(
            predictionId, EVENT_ID, predictionAmount + 1, potentialPayout, expiresAt, signature
        );

        vm.expectRevert(StrikeMultiplierPredictionVault.InvalidPredictionQuoteSigner.selector);
        vm.prank(predictorA);
        vault.submitPredictionWithQuote(
            predictionId, EVENT_ID, predictionAmount, potentialPayout + 1, expiresAt, signature
        );

        vm.expectRevert(StrikeMultiplierPredictionVault.InvalidPredictionQuoteSigner.selector);
        vm.prank(predictorA);
        vault.submitPredictionWithQuote(
            predictionId, EVENT_TWO, predictionAmount, potentialPayout, expiresAt, signature
        );

        vm.expectRevert(StrikeMultiplierPredictionVault.InvalidPredictionQuoteSigner.selector);
        vm.prank(predictorA);
        vault.submitPredictionWithQuote(
            keccak256("tampered-prediction-id"), EVENT_ID, predictionAmount, potentialPayout, expiresAt, signature
        );
    }

    function testSubmitPredictionWithQuoteRejectsReplayByPredictionId() public {
        _contribute(contributorA, 200 * USDT);

        bytes32 predictionId = keccak256("replayed-quote");
        uint256 predictionAmount = 20 * USDT;
        uint256 potentialPayout = 25 * USDT;
        uint256 expiresAt = block.timestamp + 1 hours;
        bytes memory signature = _quoteSignature(
            managerPrivateKey, predictionId, EVENT_ID, predictorA, predictionAmount, potentialPayout, expiresAt
        );

        vm.prank(predictorA);
        vault.submitPredictionWithQuote(predictionId, EVENT_ID, predictionAmount, potentialPayout, expiresAt, signature);

        vm.expectRevert(StrikeMultiplierPredictionVault.PredictionExists.selector);
        vm.prank(predictorA);
        vault.submitPredictionWithQuote(predictionId, EVENT_ID, predictionAmount, potentialPayout, expiresAt, signature);
    }

    function testCrossEventTicketCanSubmitAsSingleVaultPredictionAndClaim() public {
        _contribute(contributorA, 200 * USDT);

        bytes32 backendRealEventA = keccak256("backend-real-event-france-vs-brazil");
        bytes32 backendRealEventB = keccak256("backend-real-event-spain-vs-germany");
        bytes32 vaultEventId = keccak256("ticket-vault-event-cross-event-claim");
        bytes32 contractPredictionId = keccak256("ticket-contract-prediction-cross-event-claim");
        assertTrue(backendRealEventA != backendRealEventB);
        assertTrue(vaultEventId != backendRealEventA);
        assertTrue(vaultEventId != backendRealEventB);

        _createEvent(vaultEventId);

        uint256 predictionAmount = 20 * USDT;
        uint256 potentialPayout = 25 * USDT;
        uint256 expiresAt = block.timestamp + 1 hours;
        bytes memory signature = _quoteSignature(
            managerPrivateKey,
            contractPredictionId,
            vaultEventId,
            predictorA,
            predictionAmount,
            potentialPayout,
            expiresAt
        );

        vm.prank(predictorA);
        vault.submitPredictionWithQuote(
            contractPredictionId, vaultEventId, predictionAmount, potentialPayout, expiresAt, signature
        );

        assertEq(vault.predictionIdsLength(), 1);
        assertEq(vault.eventPredictionIdsLength(vaultEventId), 1);
        assertEq(vault.eventPredictionIdAt(vaultEventId, 0), contractPredictionId);

        (StrikeMultiplierPredictionVault.EventStatus realEventAStatus,,,,,,,,) =
            vault.predictionEvents(backendRealEventA);
        (StrikeMultiplierPredictionVault.EventStatus realEventBStatus,,,,,,,,) =
            vault.predictionEvents(backendRealEventB);
        assertEq(uint256(realEventAStatus), uint256(StrikeMultiplierPredictionVault.EventStatus.None));
        assertEq(uint256(realEventBStatus), uint256(StrikeMultiplierPredictionVault.EventStatus.None));

        (
            bytes32 recordedVaultEventId,
            address predictor,
            uint256 recordedPredictionAmount,
            uint256 recordedPotentialPayout,,
            StrikeMultiplierPredictionVault.PredictionStatus status
        ) = vault.predictionReceipts(contractPredictionId);
        assertEq(recordedVaultEventId, vaultEventId);
        assertEq(predictor, predictorA);
        assertEq(recordedPredictionAmount, predictionAmount);
        assertEq(recordedPotentialPayout, potentialPayout);
        assertEq(uint256(status), uint256(StrikeMultiplierPredictionVault.PredictionStatus.Accepted));

        _settle(vaultEventId, _ids(contractPredictionId));

        uint256 before = usdt.balanceOf(predictorA);
        vm.prank(predictorA);
        vault.claimPredictionPayout(contractPredictionId);

        assertEq(usdt.balanceOf(predictorA) - before, potentialPayout);
        assertEq(vault.totalClaimablePayouts(), 0);
    }

    function testCrossEventTicketCanRefundFromSingleVaultEvent() public {
        _contribute(contributorA, 200 * USDT);

        bytes32 backendRealEventA = keccak256("backend-real-event-cancelled-leg");
        bytes32 backendRealEventB = keccak256("backend-real-event-still-pending-leg");
        bytes32 vaultEventId = keccak256("ticket-vault-event-cross-event-refund");
        bytes32 contractPredictionId = keccak256("ticket-contract-prediction-cross-event-refund");
        assertTrue(backendRealEventA != backendRealEventB);

        _createEvent(vaultEventId);

        vm.prank(manager);
        vault.acceptPrediction(contractPredictionId, vaultEventId, predictorA, 20 * USDT, 25 * USDT);

        vm.prank(manager);
        vault.cancelEvent(vaultEventId);

        (StrikeMultiplierPredictionVault.EventStatus realEventAStatus,,,,,,,,) =
            vault.predictionEvents(backendRealEventA);
        (StrikeMultiplierPredictionVault.EventStatus realEventBStatus,,,,,,,,) =
            vault.predictionEvents(backendRealEventB);
        assertEq(uint256(realEventAStatus), uint256(StrikeMultiplierPredictionVault.EventStatus.None));
        assertEq(uint256(realEventBStatus), uint256(StrikeMultiplierPredictionVault.EventStatus.None));

        uint256 before = usdt.balanceOf(predictorA);
        vm.prank(predictorA);
        vault.claimRefund(contractPredictionId);

        assertEq(usdt.balanceOf(predictorA) - before, 20 * USDT);
        assertEq(vault.totalRefundablePredictions(), 0);
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

    function testTicketAsVaultEventLimitConstantsAreDeploymentCaps() public view {
        assertEq(vault.MAX_TOTAL_PREDICTIONS(), 1_000);
        assertEq(vault.MAX_PREDICTIONS_PER_EVENT(), 128);
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

    function _quoteSignature(
        uint256 signerPrivateKey,
        bytes32 predictionId,
        bytes32 eventId,
        address predictor,
        uint256 predictionAmount,
        uint256 potentialPayout,
        uint256 expiresAt
    ) internal view returns (bytes memory) {
        bytes32 digest = vault.getSubmitPredictionQuoteDigest(
            predictionId, eventId, predictor, predictionAmount, potentialPayout, expiresAt
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, digest);
        return abi.encodePacked(r, s, v);
    }
}
