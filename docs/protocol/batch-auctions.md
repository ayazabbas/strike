# Batch Auctions

Strike uses **Frequency Batch Auctions (FBA)** instead of continuous order matching. This is the core mechanism that determines how trades execute.

## How a Batch Clears

1. **Accumulate orders** — during the batch interval (~3s), traders place and cancel orders. Orders are recorded on-chain but not matched yet.

2. **Trigger clearing** — anyone (typically a keeper) calls `clearBatch()`. This is permissionless.

3. **Find clearing price** — the contract traverses the segment tree to find the tick that maximizes matched volume:
   - Cumulative bid volume is computed descending from tick 99
   - Cumulative ask volume is computed ascending from tick 1
   - The clearing tick is where these curves cross
   - Tie-break: midpoint of tied ticks

4. **Calculate fill fractions** — at the clearing tick, one side may be oversubscribed. The fill fraction (in BPS) is stored for that side.

5. **Store result** — a `BatchResult` is written: clearing tick, fill fractions, total volume, batch ID. No per-order writes happen here — this is what keeps clearing gas-efficient.

6. **Traders claim** — after clearing, traders call `claimFills()` to receive their outcome tokens or collateral based on the batch result.

## Fill Logic

| Order Position | Result |
|---------------|--------|
| Bid above clearing tick | Fully filled |
| Ask below clearing tick | Fully filled |
| At clearing tick (non-oversubscribed side) | Fully filled |
| At clearing tick (oversubscribed side) | Partially filled (pro-rata) |
| Bid below clearing tick | Not filled (remains resting) |
| Ask above clearing tick | Not filled (remains resting) |

## Why Batches?

### vs. Continuous Matching
- **No speed advantage** — all orders in a batch are equal, eliminating latency races
- **Uniform price** — everyone gets the same price, not a sequence of price-moving fills
- **Maker-friendly** — makers have the full batch interval to cancel stale quotes

### vs. Parimutuel Pools
- **Real price discovery** — prices are set by supply and demand, not pool ratios
- **Capital efficient** — traders can express precise views at specific prices
- **Secondary market** — outcome tokens are tradeable on the book, not locked until resolution

## Batch Cadence

| Setting | Duration | Best For |
|---------|----------|----------|
| Multi-block (default) | ~3s | Standard markets — balances fairness and UX |
| Long interval | 10–30s | Low-volume markets, mobile-first UX |

The batch interval is configurable per market at creation time.

## Segment Tree

Clearing requires knowing cumulative volume at each tick. A naive approach iterates all 99 ticks — expensive on-chain. Strike uses a **segment tree** (inspired by Clober's LOBSTER research) to compute prefix sums and find the clearing tick in O(log N) operations with minimal storage writes.
