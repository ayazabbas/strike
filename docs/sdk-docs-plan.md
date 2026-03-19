# SDK Documentation Plan

## Location

New section in `~/dev/strike/docs/` under an `sdk/` directory, added to `SUMMARY.md`.

## Pages

### 1. `sdk/overview.md` — SDK Overview
- What the SDK is (Rust crate for programmatic trading on Strike)
- On-chain first design philosophy — live data from RPC/WSS, indexer for snapshots only
- Feature flags (nonce-manager)
- Installation: `cargo add strike-sdk` / git path dep
- Link to crates.io and docs.rs
- Coming soon: TypeScript SDK, Python SDK

### 2. `sdk/quickstart.md` — Quick Start
- Prerequisites (Rust, BSC testnet tBNB, testnet USDT from faucet)
- Minimal read-only example (connect, fetch markets)
- Minimal trading example (connect with wallet, approve USDT, place orders, cancel)
- Link to faucet page for testnet USDT

### 3. `sdk/client.md` — Client Configuration
- `StrikeConfig::bsc_testnet()` / `bsc_mainnet()` / `custom()`
- Builder pattern: `with_rpc()`, `with_wss()`, `with_indexer()`, `with_private_key()`
- NonceSender: `init_nonce_sender()`, when to use it (bots with rapid TX sends)
- Read-only vs trading mode
- Provider access for advanced usage

### 4. `sdk/orders.md` — Placing & Managing Orders
- Order concepts: Side (Bid/Ask/SellYes/SellNo), OrderType (GTB/GTC), ticks (1-99), lots
- LOT_SIZE = 1e16 ($0.01/lot)
- `OrderParam` convenience constructors: `bid()`, `ask()`, `sell_yes()`, `sell_no()`
- `client.orders().place(market_id, &params)` — single TX batch placement
- `client.orders().replace(cancel_ids, market_id, &params)` — atomic cancel+place
- `client.orders().cancel(&ids)` / `cancel_one(id)` — batch and single cancel
- Parsing `PlacedOrder` results (order IDs from receipt)
- Gas estimation notes

### 5. `sdk/events.md` — Real-Time Events
- `client.events()` → `EventStream` with auto-reconnect
- `StrikeEvent` variants: MarketCreated, BatchCleared, OrderSettled, GtcAutoCancelled, OrderPlaced, OrderCancelled
- Pattern matching examples
- Historical scanning: `client.scan_orders(from_block, owner)` — chunked getLogs for startup recovery
- Reconnection behavior (5s backoff)

### 6. `sdk/vault-and-tokens.md` — Vault & Outcome Tokens
- USDT approval: `client.vault().approve_usdt()` (idempotent, checks allowance first)
- Balance queries: `usdt_balance()`, `usdt_allowance()`
- Outcome tokens: `yes_token_id()`, `no_token_id()`, `balance_of()`
- Token approval for selling: `set_approval_for_all()`
- Redemption: `client.redeem().redeem(market_id, amount)` / `balances()`

### 7. `sdk/indexer.md` — Indexer Client
- When to use (startup snapshots, not live data)
- `client.indexer().get_markets()` / `get_active_markets(feed_id)`
- `client.indexer().get_orderbook(market_id)`
- `client.indexer().get_open_orders(owner)`
- Response types: `Market`, `IndexerOrder`, `OrderbookSnapshot`

### 8. `sdk/examples.md` — Example Bots
- Walk through each example in `sdk/rust/examples/`:
  - `read_markets.rs` — read-only market discovery
  - `place_orders.rs` — full trading lifecycle
  - `stream_events.rs` — event-driven architecture
  - `simple_bot.rs` — minimal market maker skeleton
- Tips for building a real bot (risk management, position tracking, price feeds)

## SUMMARY.md Addition

Add after the "Guides" section, before "Technical":

```markdown
## SDK

* [Overview](sdk/overview.md)
* [Quick Start](sdk/quickstart.md)
* [Client Configuration](sdk/client.md)
* [Placing & Managing Orders](sdk/orders.md)
* [Real-Time Events](sdk/events.md)
* [Vault & Outcome Tokens](sdk/vault-and-tokens.md)
* [Indexer Client](sdk/indexer.md)
* [Example Bots](sdk/examples.md)
```

## Style

- Match existing docs tone (technical, concise, code-heavy)
- Every page has runnable code snippets
- Use `rust` code blocks with `no_run` annotation comments where wallet/RPC needed
- Reference contract concepts by linking to existing protocol docs (e.g., link "batch auction" to `protocol/batch-auctions.md`)
- Keep each page focused — one concept per page, cross-link liberally

## Implementation

Single coding agent task — write all 8 markdown files + update SUMMARY.md. Reference the SDK source at `~/dev/strike/sdk/rust/src/` for accurate API signatures. Reference existing docs in `~/dev/strike/docs/` for consistent style and cross-linking.
