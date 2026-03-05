# Strike CLOB Conversion Plan

> Convert Strike from parimutuel pools to a Frequency Batch Auction (FBA) CLOB with a web frontend.

## Current State
- **Contracts:** `Market.sol` (parimutuel UP/DOWN pools) + `MarketFactory.sol` (EIP-1167 clones)
- **Bot:** grammY Telegram bot with Privy wallets, keeper for market creation/resolution
- **Oracle:** Pyth pull oracle with `parsePriceFeedUpdates` for resolution
- **Chain:** BNB Chain (BSC)

## Target State
- On-chain FBA CLOB with limit orders, batch clearing every ~3s (multi-block), pro-rata fills
- Claim-based lazy settlement (no per-order loops in clearing)
- Segment tree for efficient price-level aggregation
- ERC-1155 outcome tokens (YES/NO per market)
- Web frontend (React/Next.js) with real-time orderbook display
- Keeper system for batch clearing + market resolution
- Pyth resolution via `parsePriceFeedUpdatesUnique` with deterministic settlement windows

## Design Decisions
- **Settlement price:** Use Pyth `price` field (not `ema_price`) — spot price for clean market semantics
- **Trading halt:** No midpoint lock. Trading halts when `timeRemaining < batchInterval` — the final batch clears normally, then no more orders are accepted. Simple and deterministic.
- **Batch cadence:** Multi-block FBA (~3s default, configurable)
- **Order submission:** Open on-chain by default; optional private path (BEP-322 / bundle APIs) deferred to Phase 4
- **Outcome tokens:** ERC-1155 multi-token (one token ID per outcome per market)
- **Fee model:** Maker/taker split with maker rebates; resolver/pruner bounties funded from taker fees + market creation bonds
- **Finality:** Resolution not finalized until economic finality (block n+2 under BEP-126 fast finality)
- **Confidence interval:** Reject resolution if Pyth `conf > X% of price` (configurable threshold, e.g. 1%)

---

## Phase 1A: Core Primitives

Foundation contracts — outcome tokens, segment tree, collateral vault, fee model.

### Tasks

1. **Design and implement outcome token model (`OutcomeToken.sol`)**
   - ERC-1155 multi-token: each market gets two token IDs (YES and NO)
   - Minting: user deposits collateral → receives 1 YES + 1 NO token (always minted as a pair, fully collateralized)
   - Burning: user returns 1 YES + 1 NO → receives collateral back (merge/redeem pair)
   - Post-resolution redemption: winning token redeems 1:1 for collateral; losing token is worthless
   - Only the protocol contracts can mint/burn (access control)
   - Token IDs: `marketId * 2` for YES, `marketId * 2 + 1` for NO (deterministic, no registry needed)

2. **Implement segment tree library (`SegmentTree.sol`)**
   - Fixed-size segment tree over 99 ticks (binary outcome prices 0.01–0.99, 1-cent granularity)
   - Operations: `update(tick, delta)`, `prefixSum(tick)`, `findClearingTick(targetVolume)`
   - Optimized for minimal SSTORE: use segmented segment tree pattern (Clober/LOBSTER research) to batch node updates
   - Pure library — no storage ownership, caller passes storage slot
   - Gas target: O(log N) updates and queries (~7 levels for 99 ticks → 128 leaves)

3. **Implement collateral vault (`Vault.sol`)**
   - Deposit/withdraw BNB (native) — wrapping handled internally if needed
   - Lock collateral on order placement, release on cancel/fill/redeem
   - Accounting: per-user balance, per-user locked balance, protocol fee pool
   - Emergency withdrawal with timelock (admin can't steal, users can always exit after delay)
   - Integration point for outcome token minting (deposit → mint pair) and redemption

4. **Design and implement fee model (`FeeModel.sol`)**
   - Maker/taker fee schedule: configurable BPS (e.g. maker 0bps / taker 30bps)
   - Maker rebates funded from taker fees (net positive for makers)
   - Resolver bounty: fixed amount per market from market creation bond (e.g. 0.005 BNB)
   - Pruner bounty: small reward per pruned order from order bonds
   - Protocol fee collector address (admin-settable)
   - Fee distribution: deducted at claim time (not during clearBatch, to keep clearing cheap)

5. **Unit tests for Phase 1A**
   - Outcome token: mint pair, burn pair, redemption, access control, token ID scheme
   - Segment tree: update, prefixSum, findClearingTick with various distributions, edge cases (empty, full, single tick)
   - Vault: deposit, withdraw, lock, unlock, emergency withdrawal, reentrancy protection
   - Fee model: fee calculation accuracy, rebate distribution, bounty accounting
   - Target: 40+ tests

6. **Update README.md and claude.md**
   - Document outcome token model, segment tree design, vault mechanics, fee schedule
   - Add architecture diagram showing contract relationships

---

## Phase 1B: Orderbook & Batch Auction

Core trading engine — order management, batch clearing, claim-based settlement.

### Tasks

1. **Implement order types and validation**
   - **GoodTilCancel (GTC):** resting order at a specific tick, valid until filled or cancelled
   
   - **GoodTilBatch (GTB):** valid for the next batch only; auto-expires after clearing if unfilled
   
   - All orders require: side (bid/ask), tick (1-99), amount, expiry timestamp
   - Validation: tick in range, amount ≥ minimum lot size, expiry ≤ market close, order bond deposited

2. **Implement `OrderBook.sol`**
   - `placeOrder(marketId, side, tick, amount, orderType, expiry)` — lock collateral/outcome tokens in vault, record order, update segment tree aggregates
   - `cancelOrder(orderId)` — remove order, unlock collateral, update aggregates, refund order bond
   - Order storage: mapping from `orderId` → `Order` struct (owner, side, tick, amount, remaining, batchId, expiry, orderType)
   - Per-tick aggregate volumes maintained via segment tree (one tree per side per market)
   - Anti-spam: minimum lot size (configurable), refundable order bond per order
   - Per-side order caps per tick to bound worst-case clearing cost
   - **Trading halt rule:** reject new orders when `block.timestamp + batchInterval >= market.expiryTime`

3. **Implement `BatchAuction.sol`**
   - `clearBatch(marketId)` — permissionless, callable by anyone (keepers)
   - Algorithm:
     1. Read cumulative bid volume (descending from tick 99) and ask volume (ascending from tick 1) via segment trees
     2. Find clearing tick: highest tick where cumulative bid volume ≥ cumulative ask volume (maximizes matched quantity)
     3. Tie-break: if multiple ticks tie, use midpoint
     4. Calculate fill fraction for oversubscribed side at clearing tick (BPS precision)
     5. Store batch result: `BatchResult(batchId, clearingTick, bidFillFractionBps, askFillFractionBps, totalVolume)`
   - Bounded iteration: segment tree traversal is O(log N), clearing is O(1) additional writes
   - Minimum batch interval enforcement: `block.timestamp >= lastClearTime + batchInterval`
   - Emit `BatchCleared(marketId, batchId, clearingTick, volume)` event
   - Skip clearing if no crossing orders (save gas)

4. **Implement claim-based settlement**
   - `claimFills(orderId[])` — batch claim for gas efficiency
   - Per-order logic:
     - Order at tick better than clearing tick → fully filled
     - Order at clearing tick on oversubscribed side → partial fill by stored fraction
     - Order at tick worse than clearing tick → unfilled (remains resting or expired)
   - On fill: transfer outcome tokens (bidder gets YES, seller gets collateral) via vault
   - Fee deduction at claim time (taker fee taken, maker rebate given)
   - Mark order as claimed for that batch; partially filled orders remain active with reduced size

5. **Implement order expiry and pruning**
   - Hard expiry: orders auto-expire at their expiry timestamp or market close (whichever is earlier)
   - `pruneExpiredOrders(orderId[])` — permissionless, anyone can call
   - Returns collateral to order owner, reclaims order bond, pays pruner bounty
   - Updates segment tree aggregates
   - Bounded: caller specifies which orders to prune (no unbounded iteration)

6. **Integration tests for Phase 1B**
   - Place/cancel/modify order flows
   - Batch clearing with: balanced book, one-sided, sparse, single order, empty batch
   - Pro-rata fill accuracy at clearing tick (verify BPS math)
   - Order type behavior: GTC resting, GTB auto-expiry after clearing
   - Trading halt enforcement near market close
   - Pruning: expired orders, bounty distribution, aggregate updates
   - Multi-batch sequences (place → clear → claim → place again)
   - Target: 50+ tests

7. **Update README.md and claude.md**
   - Document order types, clearing algorithm, claim flow
   - Add batch auction sequence diagram
   - Gas benchmarks for place/cancel/clear/claim

---

## Phase 1C: Market Lifecycle & Resolution

Market factory, Pyth integration, state machine, and full protocol tests.

### Tasks

1. **Implement `MarketFactory.sol` v2**
   - `createMarket(priceId, duration, batchInterval, tickGranularity)` — deploy new market via EIP-1167 minimal proxy
   - Market creation bond required (funds resolver bounty)
   - Configurable parameters: duration, batch interval, min lot size, max orders per tick
   - Market registry: list active/closed/resolved markets
   - Admin controls: pause factory, update default parameters, set fee collector
   - Access control: initially admin-only market creation, with path to permissionless

2. **Implement Pyth resolution module (`PythResolver.sol`)**
   - `resolveMarket(marketId, bytes[] updateData)` — permissionless
   - Use `parsePriceFeedUpdatesUnique(updateData, priceId, T, T+Δ)` where Δ = 60s (configurable)
   - Settlement rule: use Pyth `price` field (NOT `ema_price`)
   - **Confidence interval check:** reject resolution if `conf > confThresholdBps * |price| / 10000` (e.g. 1% = 100 bps)
   - Fallback windows: if no update in `[T, T+Δ]`, allow resolution with `[T, T+2Δ]`, then `[T, T+3Δ]`, up to max `K*Δ`
   - **Finality gate:** resolution transaction sets `pendingResolution`; finalization only after economic finality (n+2 blocks, enforced by requiring a second `finalizeResolution()` call at least 3 blocks later)
   - Procedural challenge: during finality window, anyone can submit alternative updateData; contract picks earliest valid `publishTime` deterministically
   - Resolver bounty: paid from market creation bond to `msg.sender` of successful resolution
   - Market state transitions: `Open → Closed → Resolving → Resolved` (or `Cancelled`)

3. **Implement market state machine**
   - `Open`: orders accepted, batches cleared
   - `Closed`: triggered automatically when `block.timestamp + batchInterval >= expiryTime`; final batch clears, no new orders, cancels allowed
   - `Resolving`: resolution submitted, waiting for finality + challenge window
   - `Resolved`: outcome determined, users can redeem winning outcome tokens
   - `Cancelled`: no valid resolution within max window → all users refunded (burn outcome tokens, return collateral)
   - 24h auto-cancel deadline (same as current Market.sol)

4. **Implement outcome token redemption**
   - `redeem(marketId, amount)` — burn winning outcome tokens, receive collateral from vault
   - Only callable in `Resolved` state
   - 1:1 redemption (1 winning token = 1 unit collateral)
   - Losing tokens: no value, can be burned by anyone (or left as-is)
   - Pair merge still available pre-resolution: return 1 YES + 1 NO → get collateral back

5. **Full protocol integration tests**
   - Complete lifecycle: create market → mint tokens → place orders → clear batches → close market → resolve → redeem
   - Multi-user scenarios: 5+ users with different positions, verify everyone gets correct payouts
   - Resolution edge cases: stale Pyth data, missing updates, confidence interval rejection, fallback windows
   - Challenge scenario: two resolvers submit different updates, earliest wins
   - Cancellation flow: no resolution within deadline → refunds
   - Gas benchmarks for all operations, compared to report estimates:
     - Place order: target <250k gas
     - Cancel order: target <100k gas
     - Clear batch: target <1.5M gas
     - Claim fill: target <150k gas
     - Pyth verify: target <300k gas
   - Target: 40+ tests (total across all phases: 130+)

6. **Update README.md and claude.md**
   - Complete contract architecture documentation
   - Market lifecycle state diagram
   - Pyth resolution rule specification
   - Gas benchmark results table
   - Full project structure update

---

## Phase 2: Keeper & Indexer Infrastructure ✅ COMPLETE

> **Built in [`strike-infra`](https://github.com/ayazabbas/strike-infra) (private repo) — all server code written in Rust**

Off-chain support services for batch clearing, resolution, and real-time data. Includes batch clearing keeper, market resolution keeper, order pruning keeper, and event indexer with REST/WebSocket API. All services are written in **Rust**.

> **Oracle:** Pyth Core — standard `IPyth.parsePriceFeedUpdates()` from `@pythnetwork/pyth-sdk-solidity`. Uses `bytes32` price feed IDs.

See the strike-infra repo for implementation details.

---

## Phase 3: Integration, Hardening & Deployment ✅ COMPLETE

> **Moved before frontend** — validate everything end-to-end on testnet, find and fix bugs in contracts + infra, before building the frontend on top of a working backend.
> Contract hardening and gas optimization in the main `strike` repo. Keeper + indexer deployment in `strike-infra`. Frontend deployment deferred to Phase 4.

### Summary

- **Struct packing:** Order 7→2 slots, BatchResult 7→2 slots, Market 6→1 slot
- **Gas optimisation:** `settleFill` consolidation (single cross-contract call), `mintSingle` (mint only the outcome token the user needs), removed `bidOrderIds`/`askOrderIds` arrays (keepers don't need per-tick on-chain enumeration)
- **Security:** Reentrancy guards on `placeOrder`, `cancelOrder`, `cancelMarket`, `finalizeResolution`; CEI pattern fix in `claimFills`; overflow checks on batch result packing
- **Docker-compose devnet stack** with full e2e integration tests (batch clearing, order placement, claim fills, outcome token verification, partial fill pro-rata path)
- **297 tests passing** across all contract test suites
- **Gas optimisation deferred** to future phase (`placeOrder` at 288k vs 250k target — acceptable for launch)

### Tasks

1. **End-to-end integration tests** ✅
   - Full user flow: deposit → place orders → batch clears → claim fills → verify outcome tokens
   - Multi-user trading with bid/ask at same tick
   - Partial fill pro-rata path (bid volume ≠ ask volume)
   - Keeper automation: batch-keeper clears batches automatically
   - Docker-compose devnet with anvil + all keepers + indexer

2. **Gas optimization pass** ✅ (partial — deferred remaining)
   - Struct packing: Order (2 slots), BatchResult (2 slots), Market (1 slot)
   - `settleFill` consolidation saves cross-contract overhead
   - `mintSingle` vs `mintPair` + `redeem` — only mint needed token
   - Removed `bidOrderIds`/`askOrderIds` on-chain arrays
   - Remaining: `placeOrder` at 288k (target 250k) — deferred to future phase

3. **Security hardening** ✅
   - Reentrancy guards on all external-facing state-changing functions
   - CEI fix in `claimFills` (state changes before external calls)
   - Overflow checks on uint64/uint40/uint32/uint8 downcasts in batch result packing
   - `_orderParticipates` validation in `pruneExpiredOrder` (prevents settlement bypass)

4. **Private submission support** — deferred
5. **BSC testnet deployment** — deferred to after frontend
6. **Telegram bot update** — deferred to after frontend
7. **Documentation + demo** — deferred
8. **Update README.md and claude.md** — deferred

---

## Phase 4: Web Frontend

> **Built in [`strike-frontend`](https://github.com/ayazabbas/strike-frontend) (private repo)**
> Built after Phase 3 testnet validation — the backend is proven to work before we build UI on top of it.

React/Next.js trading interface with real-time orderbook, order management, portfolio tracking, and mobile optimization. Connects to the live indexer API and contracts deployed in Phase 3.

### Tasks

1. **Trading UI** — real-time orderbook display (bids/asks by tick), order placement form, portfolio view
2. **Wallet integration** — wagmi/viem + MetaMask/WalletConnect, BNB deposit/withdraw flows
3. **WebSocket live updates** — subscribe to indexer WS, update orderbook + fills in real time
4. **Market browser** — list active/closed/resolved markets, market detail page with chart
5. **Position management** — open orders, fill history, outcome token balances, redeem winning tokens
6. **Mobile optimization** — responsive layout, touch-friendly order entry
7. **Telegram bot update** — place limit orders via inline buttons, orderbook summary, link to frontend
8. **Deploy** — Vercel or self-hosted, connect to testnet then mainnet
