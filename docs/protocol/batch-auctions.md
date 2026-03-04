# Batch Auctions

Strike uses **Frequency Batch Auctions (FBA)** instead of continuous order matching. This is the core mechanism that determines how trades execute.

## How a Batch Clears

1. **Accumulate orders** — during the batch interval, traders place and cancel orders. Orders are recorded on-chain but not matched yet.

2. **Trigger clearing** — anyone calls `clearBatch()`. This is permissionless. A minimum time (`batchInterval`) must pass between consecutive clears.

3. **Find clearing price** — the contract uses a segment tree binary search to find the clearing tick:
   - Binary search for the highest tick where cumulative bids >= cumulative asks
   - Post-search correction: check tick+1 to ensure maximum matched volume min(cumBid, cumAsk)
   - This handles cases where asks exceed bids at the crossing tick

4. **Calculate pro-rata fills** — at the clearing tick, one side may be oversubscribed. Each order on the oversubscribed side gets `filledLots = (orderLots * matchedLots) / totalSideLots`.

5. **Store result** — a `BatchResult` is written: clearing tick, matched lots, total bid/ask lots, timestamp. No per-order writes happen during clearing — this keeps gas efficient.

6. **Traders claim** — after clearing, traders call `claimFills()` for settlement:
   - Filled collateral moves to the market pool (for later redemption)
   - Taker fee deducted, sent to protocol fee collector
   - Outcome tokens minted (bidder gets YES, asker gets NO)
   - Unfilled collateral returned to owner

## Collateral Model (Option A: BNB-only)

Both sides lock BNB. Asks do NOT require pre-existing outcome tokens.

- **Bid** at tick 50 for 10 lots: locks `10 * 0.001 * 50/100 = 0.005 BNB`
- **Ask** at tick 50 for 10 lots: locks `10 * 0.001 * 50/100 = 0.005 BNB`
- Total per matched lot = LOT_SIZE (0.001 BNB), fully collateralized

This is simpler than requiring askers to hold outcome tokens, and provides symmetric UX for both sides.

## Fill Logic

| Order Position | Result |
|---------------|--------|
| Bid at or above clearing tick (non-oversubscribed side) | Fully filled |
| Ask at or below clearing tick (non-oversubscribed side) | Fully filled |
| At clearing tick (oversubscribed side) | Partially filled (pro-rata) |
| Bid below clearing tick | Not filled |
| Ask above clearing tick | Not filled |

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

The batch interval is configurable per market at creation time (default: 60 seconds).

## Segment Tree

Clearing requires knowing cumulative volume at each tick. A naive approach iterates all 99 ticks — expensive on-chain. Strike uses a **segment tree** to compute prefix sums and find the clearing tick in O(log N) operations with minimal storage writes.
