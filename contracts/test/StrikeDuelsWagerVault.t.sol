// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/MockStrikeToken.sol";
import "../src/StrikeDuelsWagerVault.sol";

contract StrikeDuelsWagerVaultTest is Test {
    StrikeDuelsWagerVault vault;
    MockStrikeToken strike;

    address admin = address(0xA11CE);
    address treasury = address(0x7E35);
    address settler = address(0x5E77E7);
    address playerA = address(0xA11CE01);
    address playerB = address(0xB0B01);
    address attacker = address(0xBAD01);

    uint256 constant AI_STAKE = 20_000 ether;
    uint256 constant AI_REWARD = 20_000 ether;
    uint256 constant SMALL_BNB = 0.001 ether;
    uint256 constant LARGE_BNB = 0.01 ether;

    bytes32 constant MATCH_HASH = keccak256("match-summary");
    bytes32 constant AI_CONFIG = keccak256("hard-ai-v1");

    function setUp() public {
        strike = new MockStrikeToken();
        vault = new StrikeDuelsWagerVault(
            address(strike), admin, treasury, settler, AI_STAKE, AI_REWARD, 500, LARGE_BNB, 500_000 ether
        );

        vm.startPrank(admin);
        vault.setPvpBracket(SMALL_BNB, true);
        vault.setPvpBracket(LARGE_BNB, true);
        vm.stopPrank();

        vm.deal(playerA, 10 ether);
        vm.deal(playerB, 10 ether);
        strike.mint(playerA, 1_000_000 ether);
        strike.mint(treasury, 1_000_000 ether);

        vm.prank(treasury);
        strike.transfer(address(vault), 500_000 ether);

        vm.prank(playerA);
        strike.approve(address(vault), type(uint256).max);
    }

    function testPvpPlayerAWinsReceivesPoolMinusFee() public {
        bytes32 wagerId = keccak256("pvp-a-wins");

        vm.prank(playerA);
        vault.createPvpWager{value: SMALL_BNB}(wagerId, playerB);
        vm.prank(playerB);
        vault.joinPvpWager{value: SMALL_BNB}(wagerId);

        uint256 beforeWinner = playerA.balance;
        uint256 beforeTreasury = treasury.balance;

        vm.prank(settler);
        vault.finalizeWager(wagerId, StrikeDuelsWagerVault.Result.PlayerAWins, MATCH_HASH);

        uint256 fee = (SMALL_BNB * 2 * 500) / 10_000;
        assertEq(playerA.balance - beforeWinner, SMALL_BNB * 2 - fee);
        assertEq(treasury.balance - beforeTreasury, fee);
        assertEq(address(vault).balance, 0);
    }

    function testPvpPlayerBWinsReceivesPoolMinusFee() public {
        bytes32 wagerId = keccak256("pvp-b-wins");

        vm.prank(playerA);
        vault.createPvpWager{value: LARGE_BNB}(wagerId, playerB);
        vm.prank(playerB);
        vault.joinPvpWager{value: LARGE_BNB}(wagerId);

        uint256 beforeWinner = playerB.balance;
        uint256 beforeTreasury = treasury.balance;

        vm.prank(settler);
        vault.finalizeWager(wagerId, StrikeDuelsWagerVault.Result.PlayerBWins, MATCH_HASH);

        uint256 fee = (LARGE_BNB * 2 * 500) / 10_000;
        assertEq(playerB.balance - beforeWinner, LARGE_BNB * 2 - fee);
        assertEq(treasury.balance - beforeTreasury, fee);
    }

    function testPvpDrawNoContestRefundsBothPlayers() public {
        bytes32 wagerId = keccak256("pvp-refund");

        vm.prank(playerA);
        vault.createPvpWager{value: SMALL_BNB}(wagerId, playerB);
        vm.prank(playerB);
        vault.joinPvpWager{value: SMALL_BNB}(wagerId);

        uint256 beforeA = playerA.balance;
        uint256 beforeB = playerB.balance;

        vm.prank(settler);
        vault.finalizeWager(wagerId, StrikeDuelsWagerVault.Result.DrawNoContest, MATCH_HASH);

        assertEq(playerA.balance - beforeA, SMALL_BNB);
        assertEq(playerB.balance - beforeB, SMALL_BNB);
        assertEq(address(vault).balance, 0);
    }

    function testCannotFinalizeTwice() public {
        bytes32 wagerId = keccak256("double-finalize");

        vm.prank(playerA);
        vault.createPvpWager{value: SMALL_BNB}(wagerId, playerB);
        vm.prank(playerB);
        vault.joinPvpWager{value: SMALL_BNB}(wagerId);

        vm.prank(settler);
        vault.finalizeWager(wagerId, StrikeDuelsWagerVault.Result.PlayerAWins, MATCH_HASH);

        vm.expectRevert(StrikeDuelsWagerVault.InvalidWagerStatus.selector);
        vm.prank(settler);
        vault.finalizeWager(wagerId, StrikeDuelsWagerVault.Result.PlayerAWins, MATCH_HASH);
    }

    function testAiPlayerWinReceivesStakeAndClaimableFixedReward() public {
        bytes32 wagerId = keccak256("ai-player-win");

        vm.prank(playerA);
        vault.createAiWager(wagerId, AI_CONFIG);
        uint256 before = strike.balanceOf(playerA);

        vm.prank(settler);
        vault.finalizeWager(wagerId, StrikeDuelsWagerVault.Result.PlayerAWins, MATCH_HASH);

        assertEq(strike.balanceOf(playerA) - before, AI_STAKE);
        assertEq(vault.pendingAiRewards(playerA), AI_REWARD);
        assertEq(vault.aiClaimableRewards(), AI_REWARD);
        assertEq(vault.aiRewardExposure(), 0);

        vm.prank(playerA);
        vault.claimAiReward();

        assertEq(strike.balanceOf(playerA) - before, AI_STAKE + AI_REWARD);
        assertEq(vault.pendingAiRewards(playerA), 0);
        assertEq(vault.aiClaimableRewards(), 0);
    }

    function testAiRewardCannotBeClaimedTwice() public {
        bytes32 wagerId = keccak256("ai-duplicate-claim");

        vm.prank(playerA);
        vault.createAiWager(wagerId, AI_CONFIG);

        vm.prank(settler);
        vault.finalizeWager(wagerId, StrikeDuelsWagerVault.Result.PlayerAWins, MATCH_HASH);

        vm.prank(playerA);
        vault.claimAiReward();

        vm.expectRevert(StrikeDuelsWagerVault.NoAiRewardClaimable.selector);
        vm.prank(playerA);
        vault.claimAiReward();
    }

    function testAiWinKeepsPlayerStakeInPool() public {
        bytes32 wagerId = keccak256("ai-wins");
        uint256 beforeVault = strike.balanceOf(address(vault));

        vm.prank(playerA);
        vault.createAiWager(wagerId, AI_CONFIG);

        vm.prank(settler);
        vault.finalizeWager(wagerId, StrikeDuelsWagerVault.Result.PlayerBWins, MATCH_HASH);

        assertEq(strike.balanceOf(address(vault)), beforeVault + AI_STAKE);
        assertEq(vault.aiRewardExposure(), 0);
    }

    function testAiDrawRefundsPlayerStake() public {
        bytes32 wagerId = keccak256("ai-draw");

        vm.prank(playerA);
        vault.createAiWager(wagerId, AI_CONFIG);
        uint256 before = strike.balanceOf(playerA);

        vm.prank(settler);
        vault.finalizeWager(wagerId, StrikeDuelsWagerVault.Result.DrawNoContest, MATCH_HASH);

        assertEq(strike.balanceOf(playerA) - before, AI_STAKE);
        assertEq(vault.aiRewardExposure(), 0);
    }

    function testAiCannotCreateIfRewardLiquidityIsInsufficient() public {
        StrikeDuelsWagerVault emptyVault = new StrikeDuelsWagerVault(
            address(strike), admin, treasury, settler, AI_STAKE, AI_REWARD, 500, LARGE_BNB, 500_000 ether
        );
        vm.prank(playerA);
        strike.approve(address(emptyVault), type(uint256).max);

        vm.expectRevert(StrikeDuelsWagerVault.InsufficientAiRewardLiquidity.selector);
        vm.prank(playerA);
        emptyVault.createAiWager(keccak256("no-liquidity"), AI_CONFIG);
    }

    function testPvpStakeAboveCapReverts() public {
        vm.startPrank(admin);
        vault.setPvpBracket(0.02 ether, true);
        vault.setCaps(LARGE_BNB, 500_000 ether);
        vm.stopPrank();

        vm.expectRevert(StrikeDuelsWagerVault.PvpStakeExceedsCap.selector);
        vm.prank(playerA);
        vault.createPvpWager{value: 0.02 ether}(keccak256("too-large"), playerB);
    }

    function testNonSettlerCannotFinalize() public {
        bytes32 wagerId = keccak256("non-settler");

        vm.prank(playerA);
        vault.createPvpWager{value: SMALL_BNB}(wagerId, playerB);
        vm.prank(playerB);
        vault.joinPvpWager{value: SMALL_BNB}(wagerId);

        vm.expectRevert();
        vm.prank(attacker);
        vault.finalizeWager(wagerId, StrikeDuelsWagerVault.Result.PlayerAWins, MATCH_HASH);
    }

    function testPauseBlocksCreateJoinFinalizeAndRefund() public {
        bytes32 wagerId = keccak256("paused");

        vm.prank(playerA);
        vault.createPvpWager{value: SMALL_BNB}(wagerId, playerB);

        vm.prank(admin);
        vault.pause();

        vm.expectRevert();
        vm.prank(playerB);
        vault.joinPvpWager{value: SMALL_BNB}(wagerId);

        vm.expectRevert();
        vm.prank(settler);
        vault.finalizeWager(wagerId, StrikeDuelsWagerVault.Result.PlayerAWins, MATCH_HASH);

        vm.expectRevert();
        vm.prank(settler);
        vault.refundWager(wagerId, bytes32("paused"));
    }

    function testRefundOpenPvpWagerReturnsCreatorStake() public {
        bytes32 wagerId = keccak256("manual-refund");

        vm.prank(playerA);
        vault.createPvpWager{value: SMALL_BNB}(wagerId, playerB);
        uint256 before = playerA.balance;

        vm.prank(settler);
        vault.refundWager(wagerId, bytes32("cancelled"));

        assertEq(playerA.balance - before, SMALL_BNB);
        assertEq(address(vault).balance, 0);
    }

    function testPvpPayoutCannotReenterSettlement() public {
        bytes32 wagerId = keccak256("reentrant-winner");
        ReenteringPvpWinner winner = new ReenteringPvpWinner(vault, wagerId, MATCH_HASH);
        vm.deal(address(winner), 1 ether);

        winner.create{value: SMALL_BNB}(playerB);
        vm.prank(playerB);
        vault.joinPvpWager{value: SMALL_BNB}(wagerId);

        vm.prank(settler);
        vault.finalizeWager(wagerId, StrikeDuelsWagerVault.Result.PlayerAWins, MATCH_HASH);

        uint256 fee = (SMALL_BNB * 2 * 500) / 10_000;
        assertEq(address(winner).balance, 1 ether + (SMALL_BNB * 2 - fee));
        assertTrue(winner.reentryBlocked());
    }

    function testTreasuryCanRecoverSurplusNativeWithoutTouchingOpenPvpEscrow() public {
        bytes32 wagerId = keccak256("native-surplus-open-pvp");

        vm.prank(playerA);
        vault.createPvpWager{value: SMALL_BNB}(wagerId, playerB);
        vm.deal(address(vault), address(vault).balance + 0.5 ether);

        uint256 beforeTreasury = treasury.balance;

        vm.prank(treasury);
        vault.recoverNativeSurplus(treasury, 0.5 ether);

        assertEq(treasury.balance - beforeTreasury, 0.5 ether);
        assertEq(address(vault).balance, SMALL_BNB);
    }

    function testTreasuryCannotRecoverNativeReservedForOpenPvpWager() public {
        bytes32 wagerId = keccak256("native-reserved-open-pvp");

        vm.prank(playerA);
        vault.createPvpWager{value: SMALL_BNB}(wagerId, playerB);

        vm.expectRevert();
        vm.prank(treasury);
        vault.recoverNativeSurplus(treasury, SMALL_BNB);
    }

    function testTreasuryCanRecoverSurplusStrikeButNotReservedAiExposureOrStake() public {
        bytes32 wagerId = keccak256("strike-surplus-open-ai");

        vm.prank(playerA);
        vault.createAiWager(wagerId, AI_CONFIG);

        uint256 beforeTreasury = strike.balanceOf(treasury);

        vm.prank(treasury);
        vault.recoverERC20(address(strike), treasury, 480_000 ether);

        assertEq(strike.balanceOf(treasury) - beforeTreasury, 480_000 ether);
        assertEq(strike.balanceOf(address(vault)), AI_STAKE + AI_REWARD);

        vm.expectRevert();
        vm.prank(treasury);
        vault.recoverERC20(address(strike), treasury, 1);
    }

    function testTreasuryCannotRecoverClaimableAiReward() public {
        bytes32 wagerId = keccak256("claimable-ai-reserved");

        vm.prank(playerA);
        vault.createAiWager(wagerId, AI_CONFIG);

        vm.prank(settler);
        vault.finalizeWager(wagerId, StrikeDuelsWagerVault.Result.PlayerAWins, MATCH_HASH);

        uint256 beforeTreasury = strike.balanceOf(treasury);

        vm.prank(treasury);
        vault.recoverERC20(address(strike), treasury, 480_000 ether);

        assertEq(strike.balanceOf(treasury) - beforeTreasury, 480_000 ether);
        assertEq(strike.balanceOf(address(vault)), AI_REWARD);

        vm.expectRevert();
        vm.prank(treasury);
        vault.recoverERC20(address(strike), treasury, 1);

        vm.prank(playerA);
        vault.claimAiReward();

        assertEq(strike.balanceOf(address(vault)), 0);
    }

    function testTreasuryCanRescueUnrelatedERC20() public {
        MockStrikeToken unrelated = new MockStrikeToken();
        unrelated.mint(address(vault), 123 ether);

        vm.prank(treasury);
        vault.recoverERC20(address(unrelated), treasury, 123 ether);

        assertEq(unrelated.balanceOf(treasury), 123 ether);
        assertEq(unrelated.balanceOf(address(vault)), 0);
    }

    function testNonTreasuryCannotRecoverAssets() public {
        vm.deal(address(vault), 1 ether);

        vm.expectRevert();
        vm.prank(attacker);
        vault.recoverNativeSurplus(attacker, 1 ether);

        vm.expectRevert();
        vm.prank(attacker);
        vault.recoverERC20(address(strike), attacker, 1 ether);
    }

    function testRejectedNativePayoutCreatesClaimableBalanceAndDoesNotTrapSurplus() public {
        bytes32 wagerId = keccak256("failed-native-payout");
        RejectingNativeReceiver winner = new RejectingNativeReceiver(vault, wagerId);
        vm.deal(address(winner), 1 ether);

        winner.create{value: SMALL_BNB}(playerB);
        vm.prank(playerB);
        vault.joinPvpWager{value: SMALL_BNB}(wagerId);
        vm.deal(address(vault), address(vault).balance + 0.25 ether);

        uint256 fee = (SMALL_BNB * 2 * 500) / 10_000;
        uint256 payout = SMALL_BNB * 2 - fee;
        uint256 beforeTreasury = treasury.balance;

        vm.prank(settler);
        vault.finalizeWager(wagerId, StrikeDuelsWagerVault.Result.PlayerAWins, MATCH_HASH);

        assertEq(vault.pendingNativeWithdrawals(address(winner)), payout);

        vm.prank(treasury);
        vault.recoverNativeSurplus(treasury, 0.25 ether);

        assertEq(treasury.balance - beforeTreasury, fee + 0.25 ether);
        assertEq(address(vault).balance, payout);

        winner.setRejectNative(false);
        winner.claimNativePayout();

        assertEq(vault.pendingNativeWithdrawals(address(winner)), 0);
        assertEq(address(winner).balance, 1 ether + payout);
        assertEq(address(vault).balance, 0);
    }

    function testRejectingRecipientCanClaimNativePayoutToAlternateAddress() public {
        bytes32 wagerId = keccak256("failed-native-payout-to");
        RejectingNativeReceiver winner = new RejectingNativeReceiver(vault, wagerId);
        address payable alternate = payable(address(0xA17E));
        vm.deal(address(winner), 1 ether);

        winner.create{value: SMALL_BNB}(playerB);
        vm.prank(playerB);
        vault.joinPvpWager{value: SMALL_BNB}(wagerId);

        uint256 fee = (SMALL_BNB * 2 * 500) / 10_000;
        uint256 payout = SMALL_BNB * 2 - fee;
        uint256 beforeAlternate = alternate.balance;

        vm.prank(settler);
        vault.finalizeWager(wagerId, StrikeDuelsWagerVault.Result.PlayerAWins, MATCH_HASH);

        assertEq(vault.pendingNativeWithdrawals(address(winner)), payout);

        winner.claimNativePayoutTo(alternate);

        assertEq(vault.pendingNativeWithdrawals(address(winner)), 0);
        assertEq(alternate.balance - beforeAlternate, payout);
        assertEq(address(vault).balance, 0);
    }
}

contract ReenteringPvpWinner {
    StrikeDuelsWagerVault public immutable vault;
    bytes32 public immutable wagerId;
    bytes32 public immutable matchHash;
    bool public reentryBlocked;

    constructor(StrikeDuelsWagerVault vault_, bytes32 wagerId_, bytes32 matchHash_) {
        vault = vault_;
        wagerId = wagerId_;
        matchHash = matchHash_;
    }

    function create(address opponent) external payable {
        vault.createPvpWager{value: msg.value}(wagerId, opponent);
    }

    receive() external payable {
        try vault.finalizeWager(wagerId, StrikeDuelsWagerVault.Result.PlayerAWins, matchHash) {
            reentryBlocked = false;
        } catch {
            reentryBlocked = true;
        }
    }
}

contract RejectingNativeReceiver {
    StrikeDuelsWagerVault public immutable vault;
    bytes32 public immutable wagerId;
    bool public rejectNative = true;

    constructor(StrikeDuelsWagerVault vault_, bytes32 wagerId_) {
        vault = vault_;
        wagerId = wagerId_;
    }

    function create(address opponent) external payable {
        vault.createPvpWager{value: msg.value}(wagerId, opponent);
    }

    function setRejectNative(bool rejectNative_) external {
        rejectNative = rejectNative_;
    }

    function claimNativePayout() external {
        vault.claimNativePayout();
    }

    function claimNativePayoutTo(address payable to) external {
        vault.claimNativePayoutTo(to);
    }

    receive() external payable {
        if (rejectNative) revert("reject native");
    }
}
