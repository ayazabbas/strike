# Batch Auctions

Strike uses **Frequency Batch Auctions (FBA)** instead of continuous order matching. This is the core mechanism that determines how trades execute.

## How a Batch Clears

1. **Accumulate orders** — during the batch interval, traders place and cancel orders. Orders are recorded on-chain but not matched yet.

2. **Trigger clearing** — anyone calls `clearBatch(marketId)`. This is permissionless. There is no on-chain batch interval enforcement — the keeper decides clearing cadence.

3. **Find clearing price** — the contract uses a segment tree binary search to find the clearing tick:
   - Binary search for the highest tick where cumulative bids >= cumulative asks
   - Post-search correction: check tick+1 to ensure maximum matched volume min(cumBid, cumAsk)
   - This handles cases where asks exceed bids at the crossing tick

4. **Calculate pro-rata fills** — at the clearing tick, one side may be oversubscribed. Each order on the oversubscribed side gets `filledLots = (orderLots * matchedLots) / totalSideLots`.

5. **Store result + advance batch** — a `BatchResult` is written: clearing tick, matched lots, total bid/ask lots, timestamp. The batch counter advances so new orders go to the next batch.

6. **Atomic settlement** — all orders in the batch are settled inline in the same transaction:
   - Filled collateral (at clearing price, not order tick) moves to the market pool
   - Excess refund = (locked at order tick) - (cost at clearing tick) returned to owner
   - Uniform fee (20 bps) deducted, sent to protocol fee collector
   - Positions credited (bidder gets UP, asker gets DOWN) — for internal position markets; ERC-1155 tokens minted for token-based markets
   - Unfilled collateral returned to owner
   - GTC orders with remaining lots roll to the next batch

## Collateral Model (USDT)

Both sides lock USDT (ERC-20). Users must approve the Vault before placing orders. Asks do NOT require pre-existing positions.

- **Bid** at tick 50 for 10 lots: locks `10 × $0.01 × 50/100 = $0.05`
- **Ask** at tick 50 for 10 lots: locks `10 × $0.01 × 50/100 = $0.05`
- Total per matched lot = LOT_SIZE (1e16 = $0.01), fully collateralized

This is simpler than requiring askers to hold positions, and provides symmetric UX for both sides.

## Clearing Price Settlement

All fills settle at the **clearing tick**, not each order's limit tick. A bid placed at tick 70 that clears at tick 55 pays only 55% per lot — the excess 15% is refunded. This ensures all participants in a batch trade at the same fair price.

## Anti-MEV Price Protection

Limit orders provide built-in price protection. Your order will never fill at a price worse than your tick — if the clearing price exceeds your limit, your order simply doesn't fill and your collateral is returned (or rolls to the next batch for GTC orders).

This is fundamentally different from AMM-style slippage. In continuous AMMs, price can move between when you submit a trade and when it executes. In a batch auction, all orders are collected first and cleared together at a single uniform price. There is no "front-running window" — everyone in the batch gets the same deal.

To express willingness to pay more for guaranteed fills, place your order at a tick further from the expected clearing price. The difference between your tick and the actual clearing price is refunded automatically.

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
- **Secondary market** — positions are tradeable on the book via sell orders

## Resting Orders (Price-Proximity Filtering)

Orders placed far from the last clearing tick (more than **PROXIMITY_THRESHOLD = 20 ticks** away) are parked in a **resting list** instead of being inserted into the segment tree. This prevents phantom volume from distant orders distorting the clearing price.

- Resting orders lock collateral/tokens normally — they are real orders, just parked outside the tree
- An `OrderResting` event is emitted (distinct from `OrderPlaced`)
- At the start of each `clearBatch`, `pullRestingOrders` runs automatically, pulling in-range resting orders back into the segment tree (paginated: max **MAX_RESTING_PULL = 200** pulled, max **MAX_RESTING_SCAN = 400** scanned per call)
- GTC orders that move far from price after a batch clear are rolled to the resting list via `_tryRollOrCancel`
- Users can cancel resting orders normally

## Chunked Settlement

Large batches settle across multiple `clearBatch` calls:

- **MAX_ORDERS_PER_BATCH = 1600** — up from 400 in v1.1
- **SETTLE_CHUNK_SIZE = 400** — each `clearBatch` call settles up to 400 orders
- Batches with more than 400 orders require multiple `clearBatch` calls to fully settle
- Precomputed fills (clearing tick, matched lots) are stored on the first call and reused by subsequent chunks, ensuring correctness across calls

## Batch Overflow

Each batch can hold up to **MAX_ORDERS_PER_BATCH (1600)** orders. When a batch is full, new orders automatically spill into the next batch. This bounds the gas cost of `clearBatch()` while keeping order placement seamless.

## Batch Cadence

The batch interval is configurable per market at creation time. There is no on-chain enforcement of the interval — the keeper decides when to call `clearBatch()`.

## Segment Tree

Clearing requires knowing cumulative volume at each tick. A naive approach iterates all 99 ticks — expensive on-chain. Strike uses a **segment tree** to compute prefix sums and find the clearing tick in O(log N) operations with minimal storage writes.
