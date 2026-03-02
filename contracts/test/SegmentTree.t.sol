// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/SegmentTree.sol";

/// @dev Harness contract so tests can call library functions on storage structs.
contract SegmentTreeHarness {
    using SegmentTree for SegmentTree.Tree;

    SegmentTree.Tree internal bidTree;
    SegmentTree.Tree internal askTree;

    function update(bool isBid, uint256 tick, int256 delta) external {
        if (isBid) {
            bidTree.update(tick, delta);
        } else {
            askTree.update(tick, delta);
        }
    }

    function prefixSum(bool isBid, uint256 tick) external view returns (uint256) {
        return isBid ? bidTree.prefixSum(tick) : askTree.prefixSum(tick);
    }

    function findClearingTick() external view returns (uint256) {
        return SegmentTree.findClearingTick(bidTree, askTree);
    }

    function totalVolume(bool isBid) external view returns (uint256) {
        return isBid ? bidTree.totalVolume() : askTree.totalVolume();
    }

    function volumeAt(bool isBid, uint256 tick) external view returns (uint256) {
        return isBid ? bidTree.volumeAt(tick) : askTree.volumeAt(tick);
    }
}

contract SegmentTreeTest is Test {
    SegmentTreeHarness public h;

    function setUp() public {
        h = new SegmentTreeHarness();
    }

    // -------------------------------------------------------------------------
    // update / volumeAt
    // -------------------------------------------------------------------------

    function test_Update_SingleTick() public {
        h.update(true, 50, 100);
        assertEq(h.volumeAt(true, 50), 100);
        assertEq(h.totalVolume(true), 100);
    }

    function test_Update_MultipleTicks() public {
        h.update(true, 1, 10);
        h.update(true, 50, 50);
        h.update(true, 99, 40);
        assertEq(h.totalVolume(true), 100);
        assertEq(h.volumeAt(true, 1), 10);
        assertEq(h.volumeAt(true, 50), 50);
        assertEq(h.volumeAt(true, 99), 40);
    }

    function test_Update_Accumulate() public {
        h.update(true, 30, 100);
        h.update(true, 30, 50);
        assertEq(h.volumeAt(true, 30), 150);
        assertEq(h.totalVolume(true), 150);
    }

    function test_Update_NegativeDelta() public {
        h.update(true, 30, 100);
        h.update(true, 30, -40);
        assertEq(h.volumeAt(true, 30), 60);
        assertEq(h.totalVolume(true), 60);
    }

    function test_Update_RemoveAll() public {
        h.update(true, 30, 100);
        h.update(true, 30, -100);
        assertEq(h.volumeAt(true, 30), 0);
        assertEq(h.totalVolume(true), 0);
    }

    function test_Update_RevertOnUnderflow() public {
        h.update(true, 30, 50);
        vm.expectRevert("SegmentTree: underflow");
        h.update(true, 30, -51);
    }

    function test_Update_RevertOnTickTooLow() public {
        vm.expectRevert("SegmentTree: tick out of range");
        h.update(true, 0, 100);
    }

    function test_Update_RevertOnTickTooHigh() public {
        vm.expectRevert("SegmentTree: tick out of range");
        h.update(true, 100, 100);
    }

    function test_Update_BoundaryTick1() public {
        h.update(true, 1, 999);
        assertEq(h.volumeAt(true, 1), 999);
    }

    function test_Update_BoundaryTick99() public {
        h.update(true, 99, 777);
        assertEq(h.volumeAt(true, 99), 777);
    }

    // -------------------------------------------------------------------------
    // prefixSum
    // -------------------------------------------------------------------------

    function test_PrefixSum_SingleTick() public {
        h.update(true, 5, 100);
        assertEq(h.prefixSum(true, 5), 100);
        assertEq(h.prefixSum(true, 4), 0);
        assertEq(h.prefixSum(true, 99), 100);
    }

    function test_PrefixSum_MultipleTicks() public {
        h.update(true, 10, 100);
        h.update(true, 20, 200);
        h.update(true, 30, 300);

        assertEq(h.prefixSum(true, 9), 0);
        assertEq(h.prefixSum(true, 10), 100);
        assertEq(h.prefixSum(true, 15), 100);
        assertEq(h.prefixSum(true, 20), 300);
        assertEq(h.prefixSum(true, 25), 300);
        assertEq(h.prefixSum(true, 30), 600);
        assertEq(h.prefixSum(true, 99), 600);
    }

    function test_PrefixSum_EmptyTree() public view {
        assertEq(h.prefixSum(true, 1), 0);
        assertEq(h.prefixSum(true, 99), 0);
    }

    function test_PrefixSum_AllTicks() public {
        // Place 1 unit at every tick
        for (uint256 i = 1; i <= 99; i++) {
            h.update(true, i, 1);
        }
        for (uint256 i = 1; i <= 99; i++) {
            assertEq(h.prefixSum(true, i), i);
        }
        assertEq(h.totalVolume(true), 99);
    }

    function test_PrefixSum_RevertOnZeroTick() public {
        vm.expectRevert("SegmentTree: tick out of range");
        h.prefixSum(true, 0);
    }

    function test_PrefixSum_RevertOnTick100() public {
        vm.expectRevert("SegmentTree: tick out of range");
        h.prefixSum(true, 100);
    }

    // -------------------------------------------------------------------------
    // findClearingTick — no crossing
    // -------------------------------------------------------------------------

    function test_FindClearingTick_EmptyBook() public view {
        assertEq(h.findClearingTick(), 0);
    }

    function test_FindClearingTick_OnlyBids() public {
        h.update(true, 50, 100);
        assertEq(h.findClearingTick(), 0);
    }

    function test_FindClearingTick_OnlyAsks() public {
        h.update(false, 50, 100);
        assertEq(h.findClearingTick(), 0);
    }

    function test_FindClearingTick_NoCross_BidBelowAsk() public {
        // Bid at 30, ask at 70 — no overlap
        h.update(true, 30, 100);
        h.update(false, 70, 100);
        // cumBid(70) = volume at tick >= 70 = 0 (bids only at 30)
        // cumAsk(70) = 100
        // No valid clearing tick exists — bids are at 30 but asks are at 70
        // Actually let's check: at tick 30, cumBid = 100, cumAsk = prefixSum(askTree, 30) = 0 → clearing!
        // Bids at tick 30 mean they are willing to pay 30 cents.
        // Asks at tick 70 mean they are willing to sell at 70 cents.
        // A bid at 30 would NOT cross an ask at 70. Let me reconsider.
        // cumBid(p) = total bids at ticks >= p; cumAsk(p) = total asks at ticks <= p.
        // At p=30: cumBid = 100, cumAsk = 0 → clearing holds but price = 30 < 70 (ask).
        // This means bids at 30 would be "filled" at clearing tick 30, but askers at 70 are not.
        // Actually the FBA logic: if cumBid >= cumAsk at some tick, there IS a crossing.
        // Highest such tick = 30. This seems correct — bids at 30 cross asks at 70 only if
        // someone bids at 70 or higher. With bid at 30 only, clearing at 30 has cumAsk=0
        // (no asks at <= 30), so matched volume = min(100, 0) = 0. That's a degenerate case.
        // The actual "no cross" scenario requires cumBid < cumAsk at ALL ticks.
        // With bid at 30 and ask at 70:
        //   p=1..30: cumBid = 100, cumAsk = 0 → cumBid >= cumAsk, clearing = up to 30
        //   p=31..70: cumBid = 0, cumAsk = 0..100 → depends
        //   p=70: cumBid = 0, cumAsk = 100 → no clearing
        // So clearingTick = 30 (highest p where cumBid >= cumAsk).
        // Matched volume = min(cumBid(30), cumAsk(30)) = min(100, 0) = 0.
        // This is correct — there's a clearing tick but matched volume is 0.
        uint256 ct = h.findClearingTick();
        // At p=69: cumBid=0, cumAsk=0 (no asks <= 69) → 0 >= 0 ✓
        // At p=70: cumBid=0, cumAsk=100 → 0 >= 100 ✗
        // Highest valid tick is 69 (matched volume = 0 since asks are above bids)
        assertEq(ct, 69);
    }

    // -------------------------------------------------------------------------
    // findClearingTick — balanced book
    // -------------------------------------------------------------------------

    function test_FindClearingTick_PerfectMatch_SameTick() public {
        // Bid and ask at same tick 50 — perfect match
        h.update(true, 50, 100);
        h.update(false, 50, 100);

        uint256 ct = h.findClearingTick();
        // At tick 50: cumBid = 100 (bids at >= 50), cumAsk = 100 (asks at <= 50) → crossing
        // At tick 51: cumBid = 0, cumAsk = 100 → no crossing
        assertEq(ct, 50);
    }

    function test_FindClearingTick_BidAboveAsk() public {
        // Bid at 60, ask at 40 — they cross
        h.update(true, 60, 200);
        h.update(false, 40, 200);

        uint256 ct = h.findClearingTick();
        // cumBid(60) = 200, cumAsk(60) = 200 → crossing
        // cumBid(61) = 0, cumAsk(61) = 200 → no crossing
        assertEq(ct, 60);
    }

    function test_FindClearingTick_AsymmetricVolume_BidHeavy() public {
        // 300 bids at 70, 100 asks at 30
        h.update(true, 70, 300);
        h.update(false, 30, 100);

        uint256 ct = h.findClearingTick();
        // p=70: cumBid = 300, cumAsk = 100 → crossing (300 >= 100)
        // p=71..99: cumBid = 0 → no crossing
        // Highest crossing tick = 70
        assertEq(ct, 70);
    }

    function test_FindClearingTick_AsymmetricVolume_AskHeavy() public {
        // 100 bids at 70, 300 asks at 30
        h.update(true, 70, 100);
        h.update(false, 30, 300);

        uint256 ct = h.findClearingTick();
        // p=30: cumBid = 100, cumAsk = 300 → no (100 < 300)
        // p=29: cumBid = 100, cumAsk = 0 → yes (100 >= 0)
        // ...
        // p=70: cumBid = 100, cumAsk = 300 → no
        // p=69: cumBid = 100, cumAsk = 300 → no
        // cumAsk(p) includes all asks at ticks <= p. asks at 30, so cumAsk(29) = 0.
        // Highest p where cumBid >= cumAsk: p=29 (cumBid=100, cumAsk=0) → yes. p=30: 100<300 → no.
        assertEq(ct, 29);
    }

    function test_FindClearingTick_MultiTick() public {
        // Spread out bids and asks
        h.update(true, 50, 100);
        h.update(true, 60, 100);
        h.update(true, 70, 100);
        h.update(false, 40, 100);
        h.update(false, 50, 100);
        h.update(false, 60, 100);

        uint256 ct = h.findClearingTick();
        // cumBid(70) = 100, cumAsk(70) = 300 → no
        // cumBid(60) = 200, cumAsk(60) = 300 → no (200 < 300)
        // cumBid(50) = 300, cumAsk(50) = 200 → yes (300 >= 200)
        // cumBid(51..59) = 200, cumAsk(51..59) = 200 → yes at 51-59
        // Highest: check 60 first (no), then 50 (yes) via binary search
        // Actually binary search: mid=50, check, if yes try higher (55), etc.
        // Let's reason: highest p where cumBid >= cumAsk.
        // p=60: cumBid=200 (ticks 60+70), cumAsk=300 → no
        // p=59: cumBid=200, cumAsk=200 → yes (200 >= 200)
        // p=60: no, p=59: yes → clearing at 59
        assertEq(ct, 59);
    }

    function test_FindClearingTick_SingleTickBook() public {
        h.update(true, 1, 500);
        h.update(false, 1, 500);

        uint256 ct = h.findClearingTick();
        assertEq(ct, 1);
    }

    function test_FindClearingTick_FullBook() public {
        // Place volume at all 99 ticks on both sides
        for (uint256 i = 1; i <= 99; i++) {
            h.update(true, i, 10);
            h.update(false, i, 10);
        }
        // Total bids = 990, total asks = 990
        // cumBid(99) = 10, cumAsk(99) = 990 → no (10 < 990)
        // ... searching down until they balance
        // cumBid(p) = (99 - p + 1) * 10 = (100 - p) * 10
        // cumAsk(p) = p * 10
        // Crossing: (100-p)*10 >= p*10 → 100-p >= p → p <= 50
        // Highest p: 50
        uint256 ct = h.findClearingTick();
        assertEq(ct, 50);
    }

    function test_FindClearingTick_AfterRemoval() public {
        h.update(true, 60, 100);
        h.update(false, 60, 100);
        assertEq(h.findClearingTick(), 60);

        // Remove all bids
        h.update(true, 60, -100);
        assertEq(h.findClearingTick(), 0);
    }

    // -------------------------------------------------------------------------
    // Fuzz
    // -------------------------------------------------------------------------

    function testFuzz_UpdateAndPrefixSum(uint8 tick, uint128 vol) public {
        vm.assume(tick >= 1 && tick <= 99);
        vm.assume(vol > 0);

        h.update(true, tick, int256(uint256(vol)));
        assertEq(h.prefixSum(true, tick), vol);
        assertEq(h.prefixSum(true, 99), vol);
        if (tick > 1) {
            assertEq(h.prefixSum(true, tick - 1), 0);
        }
    }

    function testFuzz_TotalVolume(uint8 tick1, uint8 tick2, uint64 vol1, uint64 vol2) public {
        vm.assume(tick1 >= 1 && tick1 <= 99);
        vm.assume(tick2 >= 1 && tick2 <= 99);
        vm.assume(tick1 != tick2);
        vm.assume(vol1 > 0 && vol2 > 0);

        h.update(true, tick1, int256(uint256(vol1)));
        h.update(true, tick2, int256(uint256(vol2)));
        assertEq(h.totalVolume(true), uint256(vol1) + uint256(vol2));
    }
}
