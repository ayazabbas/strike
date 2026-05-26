// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/USDTCreditReserve.sol";
import "../src/WorldCupWinnerMarket.sol";
import "./mocks/MockUSDT.sol";
import "./mocks/MockWorldCupResolver.sol";

contract WorldCupWinnerMarketTest is Test {
    uint256 internal constant EVENT_ID = 202606;
    uint256 internal signerKey = 0xA11CE;

    address internal admin = address(0x1);
    address internal feeRecipient = address(0x9);
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);
    address internal charlie = address(0xC0FFEE);

    MockUSDT internal usdt;
    USDTCreditReserve internal reserve;
    MockWorldCupResolver internal resolver;
    WorldCupWinnerMarket internal market;

    function setUp() public {
        usdt = new MockUSDT();
        reserve = new USDTCreditReserve(admin, address(usdt));
        resolver = new MockWorldCupResolver();
        market = new WorldCupWinnerMarket(
            admin, address(usdt), address(reserve), address(resolver), EVENT_ID, feeRecipient, 0
        );

        vm.startPrank(admin);
        reserve.grantRole(reserve.CREDIT_SIGNER_ROLE(), vm.addr(signerKey));
        reserve.createEvent(
            EVENT_ID, uint64(block.timestamp), uint64(block.timestamp + 2 days), uint64(block.timestamp + 10 days)
        );
        reserve.setAuthorizedMarket(EVENT_ID, address(market), true);
        vm.stopPrank();

        usdt.mint(admin, 1_000_000e18);
        vm.startPrank(admin);
        usdt.approve(address(reserve), type(uint256).max);
        reserve.fundEvent(EVENT_ID, 10_000e18);
        vm.stopPrank();

        usdt.mint(alice, 1_000e18);
        usdt.mint(bob, 1_000e18);
        usdt.mint(charlie, 1_000e18);
        vm.prank(alice);
        usdt.approve(address(market), type(uint256).max);
        vm.prank(bob);
        usdt.approve(address(market), type(uint256).max);
        vm.prank(charlie);
        usdt.approve(address(market), type(uint256).max);
    }

    function test_BuyChecksActiveFlaggedEliminatedAndOtherOutcome() public {
        resolver.setStatus(0, false, false, false);
        resolver.setStatus(1, true, false, false);
        resolver.setStatus(2, false, false, true);

        vm.prank(alice);
        market.buyWithUsdt(0, 100e18, 0);

        vm.expectRevert(WorldCupWinnerMarket.EliminatedOutcome.selector);
        vm.prank(alice);
        market.buyWithUsdt(1, 100e18, 0);

        vm.expectRevert(WorldCupWinnerMarket.FlaggedOutcome.selector);
        vm.prank(alice);
        market.buyWithUsdt(2, 100e18, 0);

        vm.expectRevert(WorldCupWinnerMarket.InvalidOutcome.selector);
        vm.prank(alice);
        market.buyWithUsdt(42, 100e18, 0);

        resolver.setShouldRevert(true);
        vm.expectRevert(bytes("resolver paused"));
        vm.prank(alice);
        market.buyWithUsdt(0, 100e18, 0);
    }

    function test_RoundMultiplierRewardsEarlierBuyMoreForSamePrincipal() public {
        vm.prank(alice);
        uint256 earlyShares = market.buyWithUsdt(0, 100e18, 0);

        vm.prank(admin);
        market.setRound(WorldCupRound.RoundOf32);

        vm.prank(bob);
        uint256 laterShares = market.buyWithUsdt(0, 100e18, 0);

        assertEq(earlyShares, 400e18);
        assertEq(laterShares, 100e18);
        assertGt(earlyShares, laterShares);

        vm.expectRevert(WorldCupWinnerMarket.InvalidRoundTransition.selector);
        vm.prank(admin);
        market.setRound(WorldCupRound.PreTournament);
    }

    function test_CloseBettingBlocksBuys() public {
        vm.prank(admin);
        market.closeBetting();

        vm.expectRevert(WorldCupWinnerMarket.MarketNotOpen.selector);
        vm.prank(alice);
        market.buyWithUsdt(0, 100e18, 0);
    }

    function test_CreditBuyRejectsNonZeroFeeMarketsToAvoidStrandedCreditFees() public {
        WorldCupWinnerMarket feeMarket = new WorldCupWinnerMarket(
            admin, address(usdt), address(reserve), address(resolver), EVENT_ID, feeRecipient, 100
        );
        vm.prank(admin);
        reserve.setAuthorizedMarket(EVENT_ID, address(feeMarket), true);
        _claimCredit(bob, 100e18);

        vm.expectRevert(WorldCupWinnerMarket.CreditFeesUnsupported.selector);
        vm.prank(bob);
        feeMarket.buyWithCredit(0, 100e18, 0);
    }

    function test_MixedSettlementCreditLoserFundsRealWinner() public {
        _claimCredit(bob, 100e18);

        vm.prank(alice);
        market.buyWithUsdt(0, 100e18, 0);
        vm.prank(bob);
        market.buyWithCredit(1, 100e18, 0);

        _adminResolve(0);

        address[] memory creditUsers = new address[](1);
        creditUsers[0] = bob;
        uint256 aliceBefore = usdt.balanceOf(alice);
        vm.prank(alice);
        market.claim(creditUsers);

        assertEq(usdt.balanceOf(alice), aliceBefore + 200e18);
        assertEq(usdt.balanceOf(address(market)), 0);
        assertEq(reserve.creditBalance(EVENT_ID, bob), 0);
        assertEq(reserve.lockedCreditBalance(EVENT_ID, bob), 0);
    }

    function test_ManyLosingCreditUsersDoNotBlockRealWinnerClaimAndCanSettleLater() public {
        vm.prank(alice);
        market.buyWithUsdt(0, 100e18, 0);

        address firstLoser = address(0);
        for (uint160 i = 1; i <= 8; i++) {
            address loser = address(0x3000 + i);
            if (i == 1) firstLoser = loser;
            _claimCredit(loser, 100e18);
            vm.prank(loser);
            market.buyWithCredit(1, 100e18, 0);
        }

        _adminResolve(0);

        uint256 aliceBefore = usdt.balanceOf(alice);
        vm.prank(alice);
        market.claim(new address[](0));

        assertEq(usdt.balanceOf(alice), aliceBefore + 900e18);
        assertEq(reserve.lockedCreditBalance(EVENT_ID, firstLoser), 100e18);

        address[] memory users = new address[](1);
        users[0] = firstLoser;
        market.settleLosingCredit(users);
        assertEq(reserve.lockedCreditBalance(EVENT_ID, firstLoser), 0);
        assertEq(reserve.creditBalance(EVENT_ID, firstLoser), 0);
    }

    function test_ManyLosingCreditUsersDoNotBlockCreditWinnerClaim() public {
        _claimCredit(alice, 100e18);
        vm.prank(alice);
        market.buyWithCredit(0, 100e18, 0);

        for (uint160 i = 1; i <= 8; i++) {
            address loser = address(0x4000 + i);
            _claimCredit(loser, 100e18);
            vm.prank(loser);
            market.buyWithCredit(1, 100e18, 0);
        }

        _adminResolve(0);

        uint256 aliceBefore = usdt.balanceOf(alice);
        vm.prank(alice);
        market.claim(new address[](0));

        assertEq(usdt.balanceOf(alice), aliceBefore);
        assertEq(reserve.creditBalance(EVENT_ID, alice), 900e18);
        assertEq(reserve.lockedCreditBalance(EVENT_ID, alice), 0);
    }

    function test_CreditWinnerReceivesReserveCreditNotUsdtTransfer() public {
        _claimCredit(bob, 100e18);

        vm.prank(bob);
        market.buyWithCredit(0, 100e18, 0);
        vm.prank(alice);
        market.buyWithUsdt(1, 100e18, 0);

        _adminResolve(0);

        uint256 bobUsdtBefore = usdt.balanceOf(bob);
        vm.prank(bob);
        market.claim(new address[](0));

        assertEq(usdt.balanceOf(bob), bobUsdtBefore);
        assertEq(reserve.creditBalance(EVENT_ID, bob), 200e18);
        assertEq(reserve.lockedCreditBalance(EVENT_ID, bob), 0);
        assertEq(usdt.balanceOf(address(market)), 0);
    }

    function test_AdminFallbackRequiresClosedMarket() public {
        vm.prank(alice);
        market.buyWithUsdt(7, 100e18, 0);

        vm.expectRevert(WorldCupWinnerMarket.MarketNotClosed.selector);
        vm.prank(admin);
        market.adminResolve(7, "fallback");

        vm.prank(admin);
        market.closeBetting();
        vm.prank(admin);
        market.adminResolve(7, "fallback");

        assertEq(uint8(market.state()), uint8(WorldCupWinnerMarketState.Resolved));
        assertEq(market.winningOutcomeId(), 7);
        assertTrue(market.hasWinner());
    }

    function test_ResolveFromFlapBlocksOtherAndResolvesSingleNamedWinner() public {
        vm.prank(admin);
        market.closeBetting();

        resolver.setStatus(42, true, true, false);
        vm.expectRevert(WorldCupWinnerMarket.OtherWinner.selector);
        market.resolveFromFlap();

        resolver.setStatus(42, false, false, false);
        resolver.setStatus(12, true, true, false);
        market.resolveFromFlap();

        assertEq(market.winningOutcomeId(), 12);
    }

    function test_ResolveFromFlapBlocksFlaggedAmbiguousAndNoWinnerStates() public {
        vm.prank(admin);
        market.closeBetting();

        resolver.setStatus(3, true, true, true);
        vm.expectRevert(WorldCupWinnerMarket.FlaggedOutcome.selector);
        market.resolveFromFlap();

        resolver.setStatus(3, false, false, false);
        vm.expectRevert(WorldCupWinnerMarket.NoClearWinner.selector);
        market.resolveFromFlap();

        resolver.setStatus(4, true, true, false);
        resolver.setStatus(5, true, true, false);
        vm.expectRevert(WorldCupWinnerMarket.NoClearWinner.selector);
        market.resolveFromFlap();
    }

    function test_ResolveFromFlapIgnoresFlaggedNonWinnerButBlocksFlaggedWinner() public {
        vm.prank(admin);
        market.closeBetting();

        resolver.setStatus(2, true, false, true);
        resolver.setStatus(8, true, true, false);
        market.resolveFromFlap();

        assertEq(market.winningOutcomeId(), 8);

        setUp();
        vm.prank(admin);
        market.closeBetting();
        resolver.setStatus(8, true, true, true);
        vm.expectRevert(WorldCupWinnerMarket.FlaggedOutcome.selector);
        market.resolveFromFlap();
    }

    function test_InvalidRefundReturnsRealUsdtAndLockedCredit() public {
        _claimCredit(bob, 100e18);

        vm.prank(alice);
        market.buyWithUsdt(0, 100e18, 0);
        vm.prank(bob);
        market.buyWithCredit(1, 100e18, 0);

        vm.prank(admin);
        market.invalidate("other");

        uint8[] memory aliceOutcomes = new uint8[](1);
        aliceOutcomes[0] = 0;
        uint8[] memory bobOutcomes = new uint8[](1);
        bobOutcomes[0] = 1;

        uint256 aliceBefore = usdt.balanceOf(alice);
        vm.prank(alice);
        market.refund(aliceOutcomes);
        vm.prank(bob);
        market.refund(bobOutcomes);

        assertEq(usdt.balanceOf(alice), aliceBefore + 100e18);
        assertEq(reserve.creditBalance(EVENT_ID, bob), 100e18);
        assertEq(reserve.lockedCreditBalance(EVENT_ID, bob), 0);
        assertEq(usdt.balanceOf(address(market)), 0);
    }

    function test_DoubleClaimRevertsAfterPositionsCleared() public {
        vm.prank(alice);
        market.buyWithUsdt(0, 100e18, 0);
        vm.prank(bob);
        market.buyWithUsdt(1, 100e18, 0);

        _adminResolve(0);

        vm.prank(alice);
        market.claim(new address[](0));

        vm.expectRevert(WorldCupWinnerMarket.NothingToClaim.selector);
        vm.prank(alice);
        market.claim(new address[](0));
    }

    function test_DoubleRefundRevertsAfterPositionsCleared() public {
        vm.prank(alice);
        market.buyWithUsdt(0, 100e18, 0);

        vm.prank(admin);
        market.invalidate("test");

        uint8[] memory outcomes = new uint8[](1);
        outcomes[0] = 0;

        vm.prank(alice);
        market.refund(outcomes);

        vm.expectRevert(WorldCupWinnerMarket.NothingToRefund.selector);
        vm.prank(alice);
        market.refund(outcomes);
    }

    function test_MultipleSequentialRealWinnersUseResolvedSnapshot() public {
        _claimCredit(charlie, 100e18);

        vm.prank(alice);
        market.buyWithUsdt(0, 100e18, 0);
        vm.prank(bob);
        market.buyWithUsdt(0, 100e18, 0);
        vm.prank(charlie);
        market.buyWithCredit(1, 100e18, 0);

        _adminResolve(0);

        address[] memory charlieCreditUsers = new address[](1);
        charlieCreditUsers[0] = charlie;
        uint256 aliceBefore = usdt.balanceOf(alice);
        uint256 bobBefore = usdt.balanceOf(bob);

        vm.prank(alice);
        market.claim(charlieCreditUsers);
        vm.prank(bob);
        market.claim(new address[](0));

        assertEq(usdt.balanceOf(alice), aliceBefore + 150e18);
        assertEq(usdt.balanceOf(bob), bobBefore + 150e18);
        assertEq(reserve.creditBalance(EVENT_ID, charlie), 0);
        assertEq(reserve.lockedCreditBalance(EVENT_ID, charlie), 0);
        assertEq(usdt.balanceOf(address(market)), 0);
    }

    function test_SameUserWinningAndLosingCreditSettlesOnceAndPaysCredit() public {
        _claimCredit(alice, 200e18);

        vm.prank(alice);
        market.buyWithCredit(0, 100e18, 0);
        vm.prank(alice);
        market.buyWithCredit(1, 100e18, 0);
        vm.prank(bob);
        market.buyWithUsdt(1, 100e18, 0);

        _adminResolve(0);

        address[] memory aliceCreditUsers = new address[](1);
        aliceCreditUsers[0] = alice;
        uint256 aliceUsdtBefore = usdt.balanceOf(alice);

        vm.prank(alice);
        market.claim(aliceCreditUsers);

        assertEq(usdt.balanceOf(alice), aliceUsdtBefore);
        assertEq(reserve.creditBalance(EVENT_ID, alice), 300e18);
        assertEq(reserve.lockedCreditBalance(EVENT_ID, alice), 0);
        assertEq(usdt.balanceOf(address(market)), 0);

        vm.expectRevert(WorldCupWinnerMarket.NothingToClaim.selector);
        vm.prank(alice);
        market.claim(new address[](0));

        vm.expectRevert(WorldCupWinnerMarket.AlreadySettled.selector);
        market.settleLosingCredit(aliceCreditUsers);
    }

    function _adminResolve(uint8 outcomeId) internal {
        vm.prank(admin);
        market.closeBetting();
        vm.prank(admin);
        market.adminResolve(outcomeId, "test");
    }

    function _claimCredit(address user, uint256 amount) internal {
        uint64 claimStart = uint64(block.timestamp);
        uint64 claimEnd = uint64(block.timestamp + 1 days);
        bytes32 digest = reserve.getGrantDigest(
            EVENT_ID, user, amount, claimStart, claimEnd, reserve.getAccount(EVENT_ID, user).nonce
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        vm.prank(user);
        reserve.claimCredit(EVENT_ID, amount, claimStart, claimEnd, sig);
    }
}
