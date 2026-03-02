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
   - **Limit:** resting order at a specific tick, valid until expiry or cancel
   - **Post-only:** rejected if it would cross the book (maker protection)
   - **IOC (Immediate-or-Cancel):** fills in current batch or cancelled; never rests
   - **Batch-only:** valid for next batch only, auto-expires after clearing
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
   - Order type behavior: post-only rejection, IOC expiry, batch-only lifecycle
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

## Phase 2: Keeper & Indexer Infrastructure

Off-chain support services for batch clearing, resolution, and real-time data.

### Tasks

1. **Build batch clearing keeper**
   - TypeScript service that calls `clearBatch()` on active markets at configured intervals
   - Monitor pending order volume — skip clearing if no crossing orders (read segment tree aggregates)
   - Gas estimation + retry logic with exponential backoff
   - Multi-market scheduling (round-robin or priority-based by volume)
   - Configurable: RPC endpoint, wallet, gas limits, batch interval override

2. **Build market resolution keeper**
   - Watch for markets entering `Closed` state
   - Fetch signed Pyth update data from Hermes historical API: `GET /v2/updates/price/{publishTime}?ids[]={priceId}`
   - Submit `resolveMarket()` transaction with fetched updateData
   - Handle fallback: if no update in initial window, retry with extended Δ
   - After finality window, call `finalizeResolution()`
   - Claim resolver bounty

3. **Build order pruning keeper**
   - Periodic scan for expired orders (query contract or index events)
   - Call `pruneExpiredOrders()` in batches
   - Claim pruning bounties
   - Run less frequently than clearing keeper (e.g. every 30s)

4. **Build event indexer + API**
   - Index events: `OrderPlaced`, `OrderCancelled`, `BatchCleared`, `FillClaimed`, `MarketCreated`, `MarketResolved`
   - Maintain real-time orderbook state (aggregated by tick level per market)
   - Store trade history with timestamps, users, amounts
   - **WebSocket server** for live updates: orderbook snapshots, trade feed, market status changes
   - **REST API endpoints:**
     - `GET /markets` — list markets with status, volume, spread
     - `GET /markets/:id/orderbook` — current book (bids + asks by tick)
     - `GET /markets/:id/trades` — trade history
     - `GET /markets/:id/ohlcv` — candlestick data (derived from clearing prices)
     - `GET /users/:address/orders` — open + historical orders
     - `GET /users/:address/positions` — outcome token balances
   - Use dedicated RPC provider (not public BSC endpoints — `eth_getLogs` disabled on some)
   - SQLite or PostgreSQL for indexed data

5. **Integrate keepers with existing bot**
   - Replace old keeper logic (parimutuel market creation + resolution) with CLOB keepers
   - Retain Telegram bot for user notifications: market resolved, fills available, positions won/lost
   - Keeper health monitoring: log errors, alert on missed clears/resolutions
   - systemd services for all keeper processes

6. **Update README.md and claude.md**
   - Document keeper architecture and configuration
   - Indexer API reference (endpoints, WebSocket events)
   - Deployment guide for keeper services
   - Operational runbook (monitoring, troubleshooting)

---

## Phase 3: Web Frontend

React/Next.js trading interface with real-time orderbook.

### Tasks

1. **Project scaffolding**
   - Next.js 15 + TypeScript + Tailwind CSS + shadcn/ui
   - Dark trading terminal aesthetic (inspired by Bloomberg / Polymarket)
   - Wallet connection: RainbowKit (MetaMask, WalletConnect, Coinbase Wallet)
   - Directory: `frontend/`
   - Contract ABIs auto-generated from Foundry artifacts
   - wagmi v2 + viem for contract interactions

2. **Market discovery page**
   - List active markets with: asset, expiry countdown, current spread, 24h volume, last clearing price
   - Filter by: asset, status (open/closed/resolved), time remaining
   - Sort by: volume, expiry, spread
   - Auto-refresh via WebSocket subscription to indexer
   - Quick-trade buttons (jump to trading page)

3. **Trading page (core)**
   - **Orderbook visualization:** bid/ask depth chart + price ladder (tick-by-tick, color-coded)
   - **Order entry panel:** side toggle (Buy YES / Buy NO), price input (tick slider or numeric), amount, order type dropdown (limit/post-only/IOC)
   - **Position summary:** open orders, filled positions, unrealized P&L
   - **Batch info bar:** countdown to next clearing, indicative clearing price (computed client-side from current book), batch ID
   - **Trade history feed:** recent fills from indexer WebSocket
   - **Market info sidebar:** asset, expiry, resolution rule, Pyth feed link, contract address

4. **Order management panel**
   - Open orders table: tick, side, amount, remaining, status, cancel button
   - Pending claims: fills ready to claim after batch clearing, "Claim All" button
   - Order history: filled, cancelled, expired — filterable
   - Bulk cancel functionality

5. **Portfolio page**
   - Outcome token balances across all markets
   - Active positions with current mark-to-market (using last clearing price)
   - Historical P&L chart
   - "Claim All Fills" and "Redeem All Winners" bulk actions
   - Collateral balance (deposited, locked, available)

6. **Market detail / resolved market page**
   - Full orderbook + trade history for active markets
   - Resolved markets: outcome, settlement price, Pyth proof link
   - Price chart (from indexed OHLCV / clearing price history)
   - Market lifecycle status indicator with state transitions

7. **Mobile optimization**
   - Responsive breakpoints: desktop (full layout), tablet (stacked), mobile (simplified)
   - Mobile orderbook: compact depth view, swipe between book/trades/orders
   - Touch-friendly order entry with large tap targets
   - PWA manifest for home screen installation

8. **Transaction UX**
   - Transaction status toasts (pending → confirmed → success/error)
   - Wallet balance display + "insufficient funds" guards
   - Gas estimation display before confirmation
   - Batch-aware messaging: "Your order will be included in the next batch clearing (~3s)"

9. **Update README.md and claude.md**
   - Document frontend setup, environment variables, build/deploy commands
   - Architecture: frontend ↔ indexer ↔ contracts data flow
   - Screenshots or wireframe descriptions
   - Updated project structure with `frontend/` directory

---

## Phase 4: Integration, Hardening & Deployment

End-to-end testing, security, testnet deployment, and production readiness.

### Tasks

1. **End-to-end integration tests**
   - Full user flow: connect wallet → deposit → mint tokens → place orders → batch clears → claim fills → market resolves → redeem winnings
   - Multi-user concurrency: 5+ wallets trading simultaneously
   - Keeper automation: verify auto-clear, auto-resolve, auto-prune work hands-off
   - Frontend ↔ indexer ↔ contract integration smoke tests
   - Failure scenarios: keeper downtime, RPC errors, stale oracle

2. **Gas optimization pass**
   - Benchmark all contract operations on BSC testnet with real Pyth data
   - Optimize storage layout: pack structs, minimize cold storage reads
   - Evaluate segment tree vs Fenwick tree gas costs (swap if Fenwick wins)
   - Verify against report estimates:
     - Place order: <250k gas (report typical: 250k)
     - Clear batch: <1.5M gas (report typical: 1.5M)
     - Claim fill: <150k gas (report typical: 150k)
   - Profile hot paths with `forge test --gas-report`

3. **Security hardening**
   - Reentrancy guards on all external-facing state-changing functions
   - Access control audit: factory admin, keeper roles, fee collector
   - Oracle safety: confidence interval enforcement, fallback window bounds, resolution replay protection
   - Anti-spam verification: lot sizes, order bonds, per-tick caps all enforced
   - Circuit breaker: admin can pause trading on a per-market or protocol-wide basis
   - Static analysis: Slither + Mythril scan, fix all high/medium findings
   - Consider: Aderyn or 4naly3er for additional coverage

4. **Private submission support (optional, MEV mitigation)**
   - Document how to use BEP-322 builder API for private order submission
   - Test with NodeReal bundle API: verify atomic inclusion + privacy
   - Frontend toggle: "Submit privately" option that routes through MEV-protected RPC
   - Graceful degradation: works identically if submitted via public mempool

5. **BSC testnet deployment**
   - Deploy all contracts, configure factory with test parameters
   - Deploy keepers + indexer as systemd services
   - Deploy frontend (Vercel or self-hosted)
   - Seed markets: create BTC/USD and ETH/USD 5-minute markets
   - Run 24h soak test with automated trading bots (randomized orders)
   - Validate gas costs against estimates, log any outliers

6. **Telegram bot update**
   - Update bot to work with CLOB: place limit orders via inline buttons
   - Show orderbook summary (top 3 bids/asks) in Telegram messages
   - Link to web frontend for advanced trading ("Open full trading view →")
   - Keep Privy wallet management + fund/withdraw flows
   - Notifications: batch fills, market resolved, positions won/lost

7. **Documentation + demo**
   - User-facing docs: how to trade, market mechanics, fee structure, glossary
   - Developer docs: contract API reference, indexer API, keeper deployment
   - Demo video or walkthrough (for hackathon/pitch purposes)
   - Architecture decision record: why FBA, why not continuous, why claim-based

8. **Update README.md and claude.md**
   - Final architecture diagram: contracts + keepers + indexer + frontend + bot
   - Deployed contract addresses (testnet)
   - Live URLs (frontend, API)
   - Final gas benchmark table
   - Complete project structure with all directories
   - Updated roadmap reflecting CLOB completion
