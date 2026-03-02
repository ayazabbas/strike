# BatchAuction.sol

Integrated with OrderBook — handles the clearing algorithm.

## `clearBatch(marketId)`

Permissionless. Callable by anyone (typically keepers).

### Algorithm

1. **Check interval:** `block.timestamp >= lastClearTime + batchInterval`
2. **Read aggregates:** cumulative bid volume (descending from tick 99) and ask volume (ascending from tick 1) via segment trees
3. **Find clearing tick:** highest tick where cumulative bids ≥ cumulative asks (maximizes matched quantity)
4. **Tie-break:** midpoint of tied ticks
5. **Fill fractions:** calculate BPS fill fraction for oversubscribed side at clearing tick
6. **Store result:** write `BatchResult(batchId, clearingTick, bidFillBps, askFillBps, totalVolume)`
7. **Skip if empty:** if no crossing orders, return without writing (save gas)

### BatchResult Struct
```solidity
struct BatchResult {
    uint256 batchId;
    uint8 clearingTick;
    uint16 bidFillFractionBps;
    uint16 askFillFractionBps;
    uint256 totalVolume;
    uint256 timestamp;
}
```

### Gas Efficiency

- Segment tree traversal: O(log N) for 99 ticks (~7 levels)
- Clearing writes: O(1) — only the batch result struct
- No per-order iteration during clearing
- IOC and batch-only orders are marked expired (not iterated — claimed/pruned later)

### Events

```solidity
event BatchCleared(uint256 indexed marketId, uint256 batchId, uint8 clearingTick, uint256 volume);
```
