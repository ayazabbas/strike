# SegmentTree.sol

Pure Solidity library implementing a fixed-size segment tree over 99 price ticks (1--99). Used internally by `OrderBook` to track bid/ask volume at each tick and compute the optimal clearing price for Frequent Batch Auctions.

## Layout

The tree is backed by a `uint256[256]` array (`Tree.nodes`), 1-indexed:

```
               nodes[1] = root (total volume)
              /                              \
        nodes[2]                          nodes[3]
       /        \                        /        \
    nodes[4]  nodes[5]  ...          ...       nodes[7]
     ...                                          ...
  nodes[128] nodes[129] ... nodes[226]  nodes[227] ... nodes[255]
    tick 1     tick 2        tick 99     (unused padding)
```

- **Leaves:** indices 128--226 (tick `i` maps to leaf index `127 + i`)
- **Internal nodes:** indices 1--127
- **Root:** `nodes[1]` stores the total volume across all ticks
- **Unused:** leaf indices 227--255 are padding (next power of 2 >= 99 is 128)

Each node stores the total volume in its subtree.

## Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `LEAVES` | 128 | Next power-of-2 >= 99 |
| `SIZE` | 256 | Array length (2 * LEAVES, 1-indexed) |
| `MAX_TICK` | 99 | Maximum valid tick |

## Storage Struct

```solidity
struct Tree {
    uint256[256] nodes;
}
```

## Functions

All operations are **O(log 128) = O(7)** storage reads/writes.

### update

```solidity
function update(Tree storage tree, uint256 tick, int256 delta) internal
```

Add or remove volume at a specific tick. `delta` is signed: positive values add volume, negative values remove it. Walks from the leaf up to the root, updating each ancestor node.

- Reverts if `tick` is outside [1, 99].
- Reverts on underflow (removing more volume than exists at a node).

### prefixSum

```solidity
function prefixSum(Tree storage tree, uint256 tick) internal view returns (uint256 sum)
```

Returns the cumulative volume at ticks [1, tick] (inclusive). Uses a standard recursive range query on the segment tree.

- Reverts if `tick` is outside [1, 99].

### findClearingTick

```solidity
function findClearingTick(
    Tree storage bidTree,
    Tree storage askTree
) internal view returns (uint256 clearingTick)
```

Binary search for the optimal clearing tick in a Frequency Batch Auction. The algorithm:

1. **Cumulative bids at tick p:** total bid volume at ticks >= p (bids willing to pay at least p). Computed as `totalBidVolume - prefixSum(bidTree, p-1)`.
2. **Cumulative asks at tick p:** total ask volume at ticks <= p (asks willing to sell at most p). Computed as `prefixSum(askTree, p)`.
3. **Clearing tick:** the highest `p` in [1, 99] where `cumBid(p) >= cumAsk(p)`.
4. **Tie-break correction:** after finding the candidate, checks `p+1` and picks whichever tick maximises matched volume (`min(cumBid, cumAsk)`).

Returns 0 if no crossing exists (no valid clearing tick).

### totalVolume

```solidity
function totalVolume(Tree storage tree) internal view returns (uint256)
```

Returns the root node value -- the total volume stored across all ticks. This is an O(1) read.

### volumeAt

```solidity
function volumeAt(Tree storage tree, uint256 tick) internal view returns (uint256)
```

Returns the volume at a specific tick (leaf value). O(1) read.

- Reverts if `tick` is outside [1, 99].

## Usage in OrderBook

`OrderBook` maintains two segment trees per market:

- `bidTrees[marketId]` -- tracks bid volume at each tick
- `askTrees[marketId]` -- tracks ask volume at each tick

When an order is placed at tick `t` for `n` lots, `update(tree, t, int256(n))` is called. On cancel, `update(tree, t, -int256(n))`. Clearing calls `findClearingTick(bidTrees[id], askTrees[id])`.
