// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/// @title SegmentTree
/// @notice Pure library for a fixed-size segment tree over 99 price ticks (1-99).
///
/// Layout
/// ------
/// The tree is backed by `Tree.nodes`, a uint256 array of length 256 (1-indexed).
/// Leaves occupy indices 128-255; internal nodes occupy 1-127.
/// Tick i (1-99) maps to leaf index (128 + i - 1) = 127 + i.
/// Leaves 100-128 (indices 226-255) are unused padding.
///
/// Node values store the TOTAL volume in the subtree rooted at that node.
///
/// Operations are O(log 128) = O(7) SSTOREs/SLOADs.
library SegmentTree {
    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    uint256 internal constant LEAVES = 128; // next power-of-2 >= 99
    uint256 internal constant MAX_TICK = 99;

    // -------------------------------------------------------------------------
    // Storage struct
    // -------------------------------------------------------------------------

    struct Tree {
        // nodes[0] unused; nodes[1] = root; nodes[127+i] = leaf for tick i
        uint256[256] nodes;
    }

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

    /// @dev Leaf index for tick i (1-indexed ticks, 1-99).
    function _leafIndex(uint256 tick) private pure returns (uint256) {
        return LEAVES + tick - 1; // tick 1 → 128, tick 99 → 226
    }

    // -------------------------------------------------------------------------
    // Core operations
    // -------------------------------------------------------------------------

    /// @notice Add `delta` volume to tick `tick`.
    ///         `delta` may be positive (add volume) or negative (remove volume).
    ///         Caller must ensure resulting leaf value stays non-negative.
    /// @param tree  Storage reference to the Tree struct.
    /// @param tick  Price tick in [1, 99].
    /// @param delta Volume change (signed).
    function update(Tree storage tree, uint256 tick, int256 delta) internal {
        require(tick >= 1 && tick <= MAX_TICK, "SegmentTree: tick out of range");

        uint256 idx = _leafIndex(tick);

        if (delta >= 0) {
            uint256 absDelta = uint256(delta);
            while (idx >= 1) {
                unchecked { tree.nodes[idx] += absDelta; }
                if (idx == 1) break;
                idx >>= 1;
            }
        } else {
            uint256 absDelta = uint256(-delta);
            // Leaf check guarantees all ancestors are >= absDelta (sum tree invariant:
            // parent nodes are always >= any child), so unchecked subtraction is safe.
            require(tree.nodes[idx] >= absDelta, "SegmentTree: underflow");
            while (idx >= 1) {
                unchecked { tree.nodes[idx] -= absDelta; }
                if (idx == 1) break;
                idx >>= 1;
            }
        }
    }

    /// @notice Returns the sum of volumes at ticks [1, tick] (inclusive).
    /// @param tree Storage reference to the Tree struct.
    /// @param tick Upper bound tick (1-99).
    function prefixSum(Tree storage tree, uint256 tick) internal view returns (uint256 sum) {
        require(tick >= 1 && tick <= MAX_TICK, "SegmentTree: tick out of range");

        // Query range [1, tick] by traversing the segment tree.
        // Map to 0-indexed leaf range: [0, tick-1] → tree indices [LEAVES, LEAVES+tick-1].
        uint256 lo = LEAVES; // leaf for tick 1
        uint256 hi = LEAVES + tick - 1; // leaf for `tick`

        // Accumulate using standard range query on 1-indexed segment tree.
        sum = _rangeQuery(tree, lo, hi, 1, LEAVES, LEAVES * 2 - 1);
    }

    /// @dev Recursive range query on segment tree.
    ///      node covers leaves [nodeL, nodeR].
    ///      Query range [lo, hi].
    function _rangeQuery(Tree storage tree, uint256 lo, uint256 hi, uint256 node, uint256 nodeL, uint256 nodeR)
        private
        view
        returns (uint256)
    {
        if (lo > nodeR || hi < nodeL) return 0;
        if (lo <= nodeL && nodeR <= hi) return tree.nodes[node];

        uint256 mid = (nodeL + nodeR) / 2;
        uint256 left = _rangeQuery(tree, lo, hi, node * 2, nodeL, mid);
        uint256 right = _rangeQuery(tree, lo, hi, node * 2 + 1, mid + 1, nodeR);
        return left + right;
    }

    /// @notice Find the clearing tick for a Frequency Batch Auction.
    ///
    ///         Algorithm:
    ///         - Cumulative bids at tick p  = total bid volume at ticks >= p (bids willing to pay >= p)
    ///           implemented as: totalBidVolume - prefixSum(bidTree, p-1)
    ///         - Cumulative asks at tick p  = total ask volume at ticks <= p (asks willing to sell <= p)
    ///           implemented as: prefixSum(askTree, p)
    ///         - Clearing tick = highest p in [1, 99] where cumBid(p) >= cumAsk(p)
    ///           (maximizes matched volume = min(cumBid(p), cumAsk(p)))
    ///         - Returns 0 if no crossing exists (no valid clearing tick).
    ///
    /// @param bidTree  Storage reference to the bid-side Tree.
    /// @param askTree  Storage reference to the ask-side Tree.
    /// @return clearingTick  The optimal clearing tick, or 0 if no cross.
    function findClearingTick(Tree storage bidTree, Tree storage askTree)
        internal
        view
        returns (uint256 clearingTick)
    {
        uint256 totalBids = bidTree.nodes[1]; // root = total bid volume
        if (totalBids == 0) return 0;

        uint256 totalAsks = askTree.nodes[1];
        if (totalAsks == 0) return 0;

        // Binary search for the highest tick p where cumBid(p) >= cumAsk(p).
        // cumBid(p) = totalBids - prefixSum(bidTree, p-1)
        // cumAsk(p) = prefixSum(askTree, p)
        //
        // At p=1:  cumBid = totalBids, cumAsk = volume at tick 1.
        //          Always cumBid >= cumAsk if there are any bids (since totalBids >= 0).
        // At p=99: cumBid = volume at tick 99, cumAsk = totalAsks.
        //
        // We want the HIGHEST p where crossing holds.

        uint256 lo = 1;
        uint256 hi = MAX_TICK;
        clearingTick = 0;

        while (lo <= hi) {
            uint256 mid = (lo + hi) / 2;

            uint256 bidPrefix = mid > 1 ? prefixSum(bidTree, mid - 1) : 0;
            uint256 cumBid = totalBids >= bidPrefix ? totalBids - bidPrefix : 0;
            uint256 cumAsk = prefixSum(askTree, mid);

            if (cumBid >= cumAsk) {
                clearingTick = mid;
                lo = mid + 1;
            } else {
                hi = mid - 1;
            }
        }

        // The binary search finds the highest tick where cumBid >= cumAsk.
        // But max matched volume min(cumBid, cumAsk) may be at clearingTick+1
        // where cumAsk > cumBid. Check both and pick the tick with more matches.
        if (clearingTick < MAX_TICK) {
            uint256 nextTick = clearingTick + 1;

            uint256 matchCur;
            if (clearingTick > 0) {
                uint256 bp = clearingTick > 1 ? prefixSum(bidTree, clearingTick - 1) : 0;
                uint256 cb = totalBids - bp;
                uint256 ca = prefixSum(askTree, clearingTick);
                matchCur = cb < ca ? cb : ca;
            }

            uint256 bpN = nextTick > 1 ? prefixSum(bidTree, nextTick - 1) : 0;
            uint256 cbN = totalBids >= bpN ? totalBids - bpN : 0;
            uint256 caN = prefixSum(askTree, nextTick);
            uint256 matchNext = cbN < caN ? cbN : caN;

            if (matchNext > matchCur) {
                clearingTick = nextTick;
            }
        }
    }

    /// @notice Total volume stored in the tree (root node value).
    function totalVolume(Tree storage tree) internal view returns (uint256) {
        return tree.nodes[1];
    }

    /// @notice Volume at a specific tick (leaf value).
    function volumeAt(Tree storage tree, uint256 tick) internal view returns (uint256) {
        require(tick >= 1 && tick <= MAX_TICK, "SegmentTree: tick out of range");
        return tree.nodes[_leafIndex(tick)];
    }
}
