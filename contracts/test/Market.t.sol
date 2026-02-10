// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {Market} from "../src/Market.sol";
import {MarketFactory} from "../src/MarketFactory.sol";
import {MockPyth} from "@pythnetwork/pyth-sdk-solidity/MockPyth.sol";

contract MarketTest is Test {
    MockPyth public mockPyth;
    MarketFactory public factory;
    Market public market;

    address public owner = address(this);
    address public feeCollector = makeAddr("feeCollector");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");
    address public resolver = makeAddr("resolver");

    bytes32 public constant BTC_PRICE_ID = bytes32(uint256(1));
    int64 public constant STRIKE = 100_000 * 1e8; // $100,000 with 8 decimals
    int32 public constant EXPO = -8;
    uint64 public constant CONF = 50 * 1e8; // confidence
    uint256 public constant DURATION = 1 hours;

    function setUp() public {
        // Deploy MockPyth with 60s valid period and 1 wei update fee
        mockPyth = new MockPyth(60, 1);
        factory = new MarketFactory(address(mockPyth), feeCollector);

        // Create a market with strike price at $100,000
        bytes[] memory updateData = _createPriceUpdate(STRIKE, uint64(block.timestamp));
        uint256 fee = mockPyth.getUpdateFee(updateData);

        address marketAddr = factory.createMarket{value: fee}(
            BTC_PRICE_ID,
            DURATION,
            updateData
        );
        market = Market(payable(marketAddr));

        // Fund test users
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(charlie, 100 ether);
        vm.deal(resolver, 10 ether);
    }

    // ─── Helpers ─────────────────────────────────────────────────────────

    function _createPriceUpdate(int64 price, uint64 publishTime) internal view returns (bytes[] memory) {
        bytes[] memory updateData = new bytes[](1);
        updateData[0] = mockPyth.createPriceFeedUpdateData(
            BTC_PRICE_ID,
            price,
            CONF,
            EXPO,
            price,   // emaPrice
            CONF,    // emaConf
            publishTime,
            publishTime - 1
        );
        return updateData;
    }

    function _placeBet(address user, Market.Side side, uint256 amount) internal {
        vm.prank(user);
        market.bet{value: amount}(side);
    }

    function _resolveMarket(int64 resolutionPrice) internal {
        // Warp past expiry
        vm.warp(market.expiryTime() + 1);

        bytes[] memory updateData = _createPriceUpdate(resolutionPrice, uint64(block.timestamp));
        uint256 fee = mockPyth.getUpdateFee(updateData);

        vm.prank(resolver);
        market.resolve{value: fee}(updateData);
    }

    // ─── Initialization Tests ────────────────────────────────────────────

    function test_initialization() public view {
        assertEq(market.strikePrice(), STRIKE);
        assertEq(market.strikePriceExpo(), EXPO);
        assertEq(uint256(market.state()), uint256(Market.State.Open));
        assertEq(market.expiryTime(), market.startTime() + DURATION);
        assertEq(market.totalPool(), 0);
    }

    function test_cannotReinitialize() public {
        bytes[] memory updateData = _createPriceUpdate(STRIKE, uint64(block.timestamp));
        uint256 fee = mockPyth.getUpdateFee(updateData);

        vm.expectRevert("Already initialized");
        market.initialize{value: fee}(
            address(mockPyth), BTC_PRICE_ID, DURATION, feeCollector, updateData
        );
    }

    // ─── Betting Tests ───────────────────────────────────────────────────

    function test_betUp() public {
        _placeBet(alice, Market.Side.Up, 1 ether);

        (uint256 upBet, uint256 downBet) = market.getUserBets(alice);
        assertEq(upBet, 1 ether);
        assertEq(downBet, 0);
        assertEq(market.totalBets(Market.Side.Up), 1 ether);
        assertEq(market.totalPool(), 1 ether);
    }

    function test_betDown() public {
        _placeBet(bob, Market.Side.Down, 2 ether);

        (uint256 upBet, uint256 downBet) = market.getUserBets(bob);
        assertEq(upBet, 0);
        assertEq(downBet, 2 ether);
        assertEq(market.totalBets(Market.Side.Down), 2 ether);
    }

    function test_multipleBets() public {
        _placeBet(alice, Market.Side.Up, 1 ether);
        _placeBet(alice, Market.Side.Up, 0.5 ether);

        (uint256 upBet, ) = market.getUserBets(alice);
        assertEq(upBet, 1.5 ether);
    }

    function test_betBothSides() public {
        _placeBet(alice, Market.Side.Up, 1 ether);
        _placeBet(alice, Market.Side.Down, 0.5 ether);

        (uint256 upBet, uint256 downBet) = market.getUserBets(alice);
        assertEq(upBet, 1 ether);
        assertEq(downBet, 0.5 ether);
        assertEq(market.totalPool(), 1.5 ether);
    }

    function test_revertBelowMinBet() public {
        vm.prank(alice);
        vm.expectRevert("Below minimum bet");
        market.bet{value: 0.0005 ether}(Market.Side.Up);
    }

    function test_revertBetAfterLockPeriod() public {
        // Warp to lock period (60s before expiry)
        vm.warp(market.expiryTime() - 60);

        vm.prank(alice);
        vm.expectRevert("Invalid state");
        market.bet{value: 1 ether}(Market.Side.Up);
    }

    function test_betEmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit Market.BetPlaced(alice, Market.Side.Up, 1 ether);

        _placeBet(alice, Market.Side.Up, 1 ether);
    }

    // ─── Resolution Tests ────────────────────────────────────────────────

    function test_resolveUpWins() public {
        _placeBet(alice, Market.Side.Up, 3 ether);
        _placeBet(bob, Market.Side.Down, 1 ether);

        int64 higherPrice = STRIKE + 1000 * 1e8; // $101,000
        _resolveMarket(higherPrice);

        assertEq(uint256(market.state()), uint256(Market.State.Resolved));
        assertEq(uint256(market.winningSide()), uint256(Market.Side.Up));
        assertEq(market.resolutionPrice(), higherPrice);
    }

    function test_resolveDownWins() public {
        _placeBet(alice, Market.Side.Up, 1 ether);
        _placeBet(bob, Market.Side.Down, 3 ether);

        int64 lowerPrice = STRIKE - 1000 * 1e8; // $99,000
        _resolveMarket(lowerPrice);

        assertEq(uint256(market.state()), uint256(Market.State.Resolved));
        assertEq(uint256(market.winningSide()), uint256(Market.Side.Down));
    }

    function test_resolveExactTieCancels() public {
        _placeBet(alice, Market.Side.Up, 1 ether);
        _placeBet(bob, Market.Side.Down, 1 ether);

        _resolveMarket(STRIKE); // Exact same price

        assertEq(uint256(market.state()), uint256(Market.State.Cancelled));
    }

    function test_resolveOneSidedCancels() public {
        // Only UP bets, no DOWN
        _placeBet(alice, Market.Side.Up, 1 ether);
        _placeBet(bob, Market.Side.Up, 2 ether);

        int64 higherPrice = STRIKE + 1000 * 1e8;
        _resolveMarket(higherPrice);

        assertEq(uint256(market.state()), uint256(Market.State.Cancelled));
    }

    function test_resolveOneSidedDownOnlyCancels() public {
        _placeBet(alice, Market.Side.Down, 1 ether);

        int64 lowerPrice = STRIKE - 1000 * 1e8;
        _resolveMarket(lowerPrice);

        assertEq(uint256(market.state()), uint256(Market.State.Cancelled));
    }

    function test_revertResolveBeforeExpiry() public {
        _placeBet(alice, Market.Side.Up, 1 ether);
        _placeBet(bob, Market.Side.Down, 1 ether);

        // Warp to closed state but not past expiry
        vm.warp(market.expiryTime() - 30);

        bytes[] memory updateData = _createPriceUpdate(STRIKE + 1e8, uint64(block.timestamp));
        uint256 fee = mockPyth.getUpdateFee(updateData);

        vm.prank(resolver);
        vm.expectRevert("Market not yet expired");
        market.resolve{value: fee}(updateData);
    }

    function test_resolvePermissionless() public {
        _placeBet(alice, Market.Side.Up, 1 ether);
        _placeBet(bob, Market.Side.Down, 1 ether);

        // Random address can resolve
        address randomResolver = makeAddr("random");
        vm.deal(randomResolver, 1 ether);
        vm.warp(market.expiryTime() + 1);

        bytes[] memory updateData = _createPriceUpdate(STRIKE + 1e8, uint64(block.timestamp));
        uint256 fee = mockPyth.getUpdateFee(updateData);

        vm.prank(randomResolver);
        market.resolve{value: fee}(updateData);

        assertEq(uint256(market.state()), uint256(Market.State.Resolved));
    }

    // ─── Payout Tests ────────────────────────────────────────────────────

    function test_claimPayout() public {
        _placeBet(alice, Market.Side.Up, 3 ether);
        _placeBet(bob, Market.Side.Down, 1 ether);

        _resolveMarket(STRIKE + 1000 * 1e8); // UP wins

        uint256 balanceBefore = alice.balance;

        vm.prank(alice);
        market.claim();

        uint256 balanceAfter = alice.balance;
        uint256 payout = balanceAfter - balanceBefore;

        // Total pool = 4 ether, fee = 4 * 300 / 10000 = 0.12 ether
        // Net pool = 3.88 ether
        // Alice payout = (3 / 3) * 3.88 = 3.88 ether
        assertEq(payout, 3.88 ether);
    }

    function test_claimProportionalPayouts() public {
        _placeBet(alice, Market.Side.Up, 3 ether);
        _placeBet(bob, Market.Side.Up, 1 ether);
        _placeBet(charlie, Market.Side.Down, 4 ether);

        _resolveMarket(STRIKE + 1000 * 1e8); // UP wins

        // Total pool = 8 ether, fee = 0.24 ether, net = 7.76 ether
        // Alice: (3/4) * 7.76 = 5.82 ether
        // Bob: (1/4) * 7.76 = 1.94 ether

        uint256 aliceBefore = alice.balance;
        vm.prank(alice);
        market.claim();
        assertEq(alice.balance - aliceBefore, 5.82 ether);

        uint256 bobBefore = bob.balance;
        vm.prank(bob);
        market.claim();
        assertEq(bob.balance - bobBefore, 1.94 ether);
    }

    function test_revertDoubleClaim() public {
        _placeBet(alice, Market.Side.Up, 1 ether);
        _placeBet(bob, Market.Side.Down, 1 ether);

        _resolveMarket(STRIKE + 1000 * 1e8);

        vm.prank(alice);
        market.claim();

        vm.prank(alice);
        vm.expectRevert("No winning bet");
        market.claim();
    }

    function test_revertLoserClaim() public {
        _placeBet(alice, Market.Side.Up, 1 ether);
        _placeBet(bob, Market.Side.Down, 1 ether);

        _resolveMarket(STRIKE + 1000 * 1e8); // UP wins

        vm.prank(bob);
        vm.expectRevert("No winning bet");
        market.claim();
    }

    // ─── Refund Tests ────────────────────────────────────────────────────

    function test_refundOnCancel() public {
        _placeBet(alice, Market.Side.Up, 2 ether);
        _placeBet(bob, Market.Side.Down, 3 ether);

        // Warp past resolution deadline to auto-cancel
        vm.warp(market.expiryTime() + 24 hours + 1);

        uint256 aliceBefore = alice.balance;
        vm.prank(alice);
        market.refund();
        assertEq(alice.balance - aliceBefore, 2 ether);

        uint256 bobBefore = bob.balance;
        vm.prank(bob);
        market.refund();
        assertEq(bob.balance - bobBefore, 3 ether);
    }

    function test_refundOnExactTie() public {
        _placeBet(alice, Market.Side.Up, 1 ether);
        _placeBet(bob, Market.Side.Down, 1 ether);

        _resolveMarket(STRIKE); // Tie -> cancelled

        uint256 aliceBefore = alice.balance;
        vm.prank(alice);
        market.refund();
        assertEq(alice.balance - aliceBefore, 1 ether);
    }

    function test_refundOneSidedMarket() public {
        _placeBet(alice, Market.Side.Up, 2 ether);
        _placeBet(bob, Market.Side.Up, 1 ether);

        _resolveMarket(STRIKE + 1e8); // One-sided -> cancelled

        uint256 aliceBefore = alice.balance;
        vm.prank(alice);
        market.refund();
        assertEq(alice.balance - aliceBefore, 2 ether);
    }

    function test_refundBothSides() public {
        // User bet on both sides
        _placeBet(alice, Market.Side.Up, 1 ether);
        _placeBet(alice, Market.Side.Down, 0.5 ether);

        _resolveMarket(STRIKE); // Tie -> cancelled

        uint256 before = alice.balance;
        vm.prank(alice);
        market.refund();
        assertEq(alice.balance - before, 1.5 ether);
    }

    function test_revertDoubleRefund() public {
        _placeBet(alice, Market.Side.Up, 1 ether);

        _resolveMarket(STRIKE);

        vm.prank(alice);
        market.refund();

        vm.prank(alice);
        vm.expectRevert("No bets to refund");
        market.refund();
    }

    // ─── Protocol Fee Tests ──────────────────────────────────────────────

    function test_collectFees() public {
        _placeBet(alice, Market.Side.Up, 5 ether);
        _placeBet(bob, Market.Side.Down, 5 ether);

        _resolveMarket(STRIKE + 1e8);

        uint256 expectedFee = (10 ether * 300) / 10_000; // 0.3 ether
        assertEq(market.protocolFeeAmount(), expectedFee);

        uint256 collectorBefore = feeCollector.balance;
        market.collectFees();
        assertEq(feeCollector.balance - collectorBefore, expectedFee);
    }

    function test_revertDoubleCollectFees() public {
        _placeBet(alice, Market.Side.Up, 1 ether);
        _placeBet(bob, Market.Side.Down, 1 ether);

        _resolveMarket(STRIKE + 1e8);

        market.collectFees();

        vm.expectRevert("Fees already claimed");
        market.collectFees();
    }

    // ─── State Transition Tests ──────────────────────────────────────────

    function test_autoTransitionToClosedAtLockPeriod() public {
        _placeBet(alice, Market.Side.Up, 1 ether);

        // Before lock period: betting works
        vm.warp(market.expiryTime() - 61);
        _placeBet(bob, Market.Side.Up, 0.5 ether);

        // At lock period: betting fails
        vm.warp(market.expiryTime() - 60);
        vm.prank(charlie);
        vm.expectRevert("Invalid state");
        market.bet{value: 1 ether}(Market.Side.Down);
    }

    function test_autoTransitionToCancelledAfterDeadline() public {
        _placeBet(alice, Market.Side.Up, 1 ether);

        vm.warp(market.expiryTime() + 24 hours + 1);

        // getCurrentState should report Cancelled
        assertEq(uint256(market.getCurrentState()), uint256(Market.State.Cancelled));
    }

    // ─── Emergency Tests ─────────────────────────────────────────────────

    function test_emergencyPause() public {
        factory.pauseMarket(address(market));

        vm.prank(alice);
        vm.expectRevert();
        market.bet{value: 1 ether}(Market.Side.Up);
    }

    function test_emergencyUnpause() public {
        factory.pauseMarket(address(market));
        factory.unpauseMarket(address(market));

        _placeBet(alice, Market.Side.Up, 1 ether);
        assertEq(market.totalPool(), 1 ether);
    }

    function test_emergencyCancel() public {
        _placeBet(alice, Market.Side.Up, 1 ether);

        factory.cancelMarket(address(market));
        assertEq(uint256(market.state()), uint256(Market.State.Cancelled));

        // Alice can refund
        uint256 before = alice.balance;
        vm.prank(alice);
        market.refund();
        assertEq(alice.balance - before, 1 ether);
    }

    function test_revertEmergencyCancelAfterResolved() public {
        _placeBet(alice, Market.Side.Up, 1 ether);
        _placeBet(bob, Market.Side.Down, 1 ether);
        _resolveMarket(STRIKE + 1e8);

        vm.expectRevert("Already resolved");
        factory.cancelMarket(address(market));
    }

    // ─── View Function Tests ─────────────────────────────────────────────

    function test_estimatePayout() public {
        _placeBet(alice, Market.Side.Up, 3 ether);
        _placeBet(bob, Market.Side.Down, 1 ether);

        // If charlie bets 1 ether on Down:
        // newDownTotal = 2, newTotal = 5, fee = 0.15, net = 4.85
        // payout = (1 * 4.85) / 2 = 2.425 ether
        uint256 estimated = market.estimatePayout(Market.Side.Down, 1 ether);
        assertEq(estimated, 2.425 ether);
    }

    function test_getMarketInfo() public {
        _placeBet(alice, Market.Side.Up, 2 ether);
        _placeBet(bob, Market.Side.Down, 1 ether);

        (
            Market.State currentState,
            bytes32 _priceId,
            int64 _strikePrice,
            ,
            ,
            ,
            uint256 upPool,
            uint256 downPool,
            uint256 _totalPool
        ) = market.getMarketInfo();

        assertEq(uint256(currentState), uint256(Market.State.Open));
        assertEq(_priceId, BTC_PRICE_ID);
        assertEq(_strikePrice, STRIKE);
        assertEq(upPool, 2 ether);
        assertEq(downPool, 1 ether);
        assertEq(_totalPool, 3 ether);
    }

    // ─── Fuzz Tests ──────────────────────────────────────────────────────

    function testFuzz_betAndClaim(uint96 aliceAmount, uint96 bobAmount) public {
        // Bound to reasonable values
        uint256 aliceBet = bound(uint256(aliceAmount), 0.001 ether, 50 ether);
        uint256 bobBet = bound(uint256(bobAmount), 0.001 ether, 50 ether);

        _placeBet(alice, Market.Side.Up, aliceBet);
        _placeBet(bob, Market.Side.Down, bobBet);

        _resolveMarket(STRIKE + 1e8); // UP wins

        uint256 totalPool = aliceBet + bobBet;
        uint256 expectedFee = (totalPool * 300) / 10_000;
        uint256 netPool = totalPool - expectedFee;

        uint256 aliceBefore = alice.balance;
        vm.prank(alice);
        market.claim();

        // Alice is sole UP bettor, gets entire net pool
        assertEq(alice.balance - aliceBefore, netPool);
    }

    function testFuzz_refundOnTie(uint96 aliceAmount, uint96 bobAmount) public {
        uint256 aliceBet = bound(uint256(aliceAmount), 0.001 ether, 50 ether);
        uint256 bobBet = bound(uint256(bobAmount), 0.001 ether, 50 ether);

        _placeBet(alice, Market.Side.Up, aliceBet);
        _placeBet(bob, Market.Side.Down, bobBet);

        _resolveMarket(STRIKE); // Tie -> cancelled

        uint256 aliceBefore = alice.balance;
        vm.prank(alice);
        market.refund();
        assertEq(alice.balance - aliceBefore, aliceBet);

        uint256 bobBefore = bob.balance;
        vm.prank(bob);
        market.refund();
        assertEq(bob.balance - bobBefore, bobBet);
    }
}
