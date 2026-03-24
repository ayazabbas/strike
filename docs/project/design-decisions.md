# Design Decisions

Key architectural choices and why they were made.

## FBA over Continuous Orderbook

**Decision:** Frequency Batch Auctions, not continuous matching.

**Why:** On EVM, continuous orderbooks create MEV extraction opportunities — bots race for time priority, sandwich trades, and front-run large orders. FBA eliminates intra-batch time priority and gives everyone the same clearing price. The trade-off is 60s latency per batch (configurable), which is acceptable for prediction markets where positions are held for minutes, not milliseconds.

## Atomic Inline Settlement over Claim-Based Settlement

**Decision:** `clearBatch()` settles all orders atomically in a single transaction. No separate claim step.

**Why:** Single-transaction settlement eliminates the UX friction of a separate claim step. Users receive their fills, excess refunds, and minted positions immediately. Gas cost scales linearly with order count, bounded by SETTLE_CHUNK_SIZE = 400 per `clearBatch` call and MAX_ORDERS_PER_BATCH = 1600. Large batches are settled across multiple `clearBatch` calls with precomputed fills ensuring correctness.

## Pyth `price` over `ema_price`

**Decision:** Use spot `price` for settlement, not exponential moving average.

**Why:** Spot price gives clean, direct market semantics. A market asking "Will BTC be above $X at time T?" should resolve on the actual price at T, not a smoothed average. EMA would introduce lag and make resolution prices diverge from what traders observe on exchanges.

## Trading Halt at Final Batch

**Decision:** Stop accepting orders when `timeRemaining < batchInterval`. No midpoint lock.

**Why:** The original PoC used a halfway-point lock (trading stops at 2.5 min in a 5-min market). This was arbitrary and wasted half the market duration. The new rule is simpler and maximizes trading time: the book stays open until the last complete batch can clear, then halts. Deterministic and fair.

## ERC-1155 for Outcome Tokens

**Decision:** Multi-token ERC-1155, not ERC-20 per outcome.

**Why:** Deploying two ERC-20 contracts per market is expensive and creates address management overhead. ERC-1155 uses a single contract with deterministic token IDs (`marketId * 2` for YES, `marketId * 2 + 1` for NO). Cheaper deployment, simpler accounting, and tokens are still freely transferable.

> **Note:** Current 5-minute markets use internal positions (`useInternalPositions = true`) for efficiency. The ERC-1155 token system is retained for future market types that require transferable tokens (e.g., longer-duration markets, secondary market trading).

## Segment Tree for Price Aggregation

**Decision:** Segment tree over naive iteration or Fenwick tree.

**Why:** Clearing requires finding where cumulative bid and ask volumes cross. Naive iteration over 99 ticks costs O(99) storage reads. A segment tree provides O(log 99) ≈ O(7) operations for both updates and prefix sum queries. Clober's LOBSTER research validates this approach for on-chain orderbooks with segmented trees that minimize SSTORE operations.

## Finality Gate on Resolution

**Decision:** Two-step resolution with a 90-second finality period.

**Why:** A single-transaction resolution on BSC could theoretically be reorganized, changing the market outcome. By splitting into `resolveMarket()` (submit data) and `finalizeResolution()` (after the 90-second wait), we ensure the settlement price is economically final. The challenge window during the finality period lets anyone submit a better (earlier) Pyth update, enforcing the deterministic "earliest update wins" rule.

## Open Submission by Default

**Decision:** Orders submitted publicly on-chain; private submission optional.

**Why:** Private transaction channels (BEP-322, NodeReal bundles) introduce infrastructure dependencies and trust assumptions. Open submission is the simplest, most composable baseline. Professional traders who want MEV protection can opt into private channels — the protocol works correctly either way.

## BNB Chain over opBNB

**Decision:** Deploy on BSC mainnet, not opBNB L2.

**Why:** Gas is already cheap on BSC (~$0.008/order at 0.05 gwei). opBNB adds bridge friction (users must bridge from BSC), has a smaller ecosystem, charges nontrivial Pyth fees, and lacks the MEV infrastructure (BEP-322, bundle APIs) documented for BSC. The marginal gas savings don't justify the UX and ecosystem trade-offs.
