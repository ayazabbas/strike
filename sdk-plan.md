# Strike SDK Plan

## Overview

Public SDK for building trading bots and integrations on Strike prediction markets. Rust first, TS and Python later. Lives in `strike/sdk/` as a monorepo subdirectory.

## Structure

```
strike/
  sdk/
    rust/        # Rust crate (strike-sdk on crates.io)
    ts/          # TypeScript package (@strike-pm/sdk on npm) — later
    py/          # Python package (strike-sdk on PyPI) — later
```

## Rust SDK (`sdk/rust/`)

### Crate Name
`strike-sdk` on crates.io. Published from `sdk/rust/`.

### Features
```toml
[features]
default = ["nonce-manager"]
nonce-manager = []    # Shared nonce management for sequential TX sends
```

### Design Decision: On-Chain First

All market data, orderbook state, and event subscriptions go directly to the chain via RPC/WSS — no indexer dependency in the hot path. This matches the MM architecture: fastest possible reads, no middleware latency. The indexer client is an optional convenience for things like historical fills or market discovery, but the core trading loop is pure on-chain.

### Module Layout

```
src/
  lib.rs              # Re-exports, StrikeClient builder
  contracts.rs        # Alloy contract bindings (sol! macros) — OrderBook, Vault, BatchAuction, etc.
  types.rs            # SDK types: Side, OrderType, OrderParam, Market, Order, BatchResult
  client.rs           # StrikeClient — high-level entry point
  chain/
    mod.rs
    orders.rs         # placeOrder, placeOrders, replaceOrders, cancelOrder, cancelOrders
    markets.rs        # On-chain market reads: active markets, market state, expiry
    vault.rs          # deposit, withdraw, approve, balanceOf, allowance
    redeem.rs         # Redemption of outcome tokens after resolution
    tokens.rs         # OutcomeToken balance/approval helpers
  events/
    mod.rs
    subscribe.rs      # WSS subscriptions: MarketCreated, BatchCleared, OrderSettled, GtcAutoCancelled
    scan.rs           # Historical event scanning (chunked getLogs for startup recovery)
  indexer/
    mod.rs
    client.rs         # REST client for indexer API (market snapshots, orderbook, open orders)
    types.rs          # Response types
  nonce.rs            # NonceSender (optional feature)
  config.rs           # Chain config, contract addresses, RPC URLs
  error.rs            # SDK error types
```

### StrikeClient API

```rust
use strike_sdk::prelude::*;

// Read-only (no wallet needed)
let client = StrikeClient::new(StrikeConfig::bsc_testnet())
    .with_rpc("https://bsc-testnet-rpc.publicnode.com")
    .build()?;

let markets = client.indexer().get_markets().await?;
let orderbook = client.indexer().get_orderbook(market_id).await?;

// With wallet (for trading)
let client = StrikeClient::new(StrikeConfig::bsc_testnet())
    .with_rpc("https://bsc-testnet-rpc.publicnode.com")
    .with_private_key("0x...")
    .build()?;

// Approve USDT (one-time)
client.vault().approve_usdt().await?;

// Place orders
let order_ids = client.orders().place(
    market_id,
    &[
        OrderParam::bid(50, 1000),   // bid at tick 50, 1000 lots
        OrderParam::ask(60, 1000),   // ask at tick 60, 1000 lots
    ],
).await?;

// Replace orders (atomic cancel + place)
let new_ids = client.orders().replace(
    &order_ids,
    market_id,
    &[
        OrderParam::bid(52, 1000),
        OrderParam::ask(58, 1000),
    ],
).await?;

// Cancel
client.orders().cancel(&order_ids).await?;

// Redeem winnings
client.redeem().redeem_yes(market_id, amount).await?;

// Subscribe to on-chain events via WSS
let mut events = client.events().subscribe().await?;
while let Some(event) = events.next().await {
    match event {
        StrikeEvent::MarketCreated { market_id, strike, expiry } => { /* ... */ }
        StrikeEvent::BatchCleared { market_id, clearing_tick, matched_lots } => { /* ... */ }
        StrikeEvent::OrderSettled { order_id, filled_lots } => { /* ... */ }
        _ => {}
    }
}

// Scan historical events (startup recovery)
let orders = client.events().scan_orders(from_block, owner).await?;
```

### What to Extract from strike-mm

| MM Module | SDK Destination | Notes |
|-----------|----------------|-------|
| `quoter.rs` → `placeOrders`/`replaceOrders`/`cancelOrders` call logic | `chain/orders.rs` | Strip MM-specific logic (risk, requoting), keep pure TX construction + send |
| `quoter.rs` → `approve_vault` | `chain/vault.rs` | Direct copy |
| `quoter.rs` → `parse_placed_orders` | `chain/orders.rs` | Receipt parsing for order IDs |
| `nonce_sender.rs` | `nonce.rs` | Direct copy, behind feature flag |
| `redeemer.rs` → redeem calls | `chain/redeem.rs` | Strip scheduling, keep the call logic |
| `contracts.rs` → sol! bindings | `contracts.rs` | Direct copy |
| `main.rs` → WSS event subscriptions | `events/subscribe.rs` | MarketCreated, BatchCleared, OrderSettled, GtcAutoCancelled |
| `quoter.rs` → startup chain scan | `events/scan.rs` | Chunked getLogs for OrderPlaced/OrderCancelled recovery |
| ABI JSON files | `abi/` | Direct copy from contracts build |

### What NOT to include from strike-mm

- Black-Scholes pricing / fair value calculation
- Risk management / position tracking
- Binance price feed
- Market manager / event loop
- Requoting logic

These are trading strategy, not SDK primitives.

### Indexer Client

Included for bootstrap/snapshot reads — same pattern as the MM:
- `GET /markets` — list active markets on startup
- `GET /markets/:id/orderbook` — orderbook snapshot
- `GET /orders?owner=0x...` — open orders for recovery

No API key gating. No WebSocket — live data comes from on-chain WSS subscriptions.

### Coming Soon (future versions)

Document in README under a "Coming Soon" section:
- **Historical queries** — fills, trade history, resolved markets
- **TypeScript SDK** (`sdk/ts/`)
- **Python SDK** (`sdk/py/`)

### Chain Configs

Pre-built configs for known deployments:

```rust
impl StrikeConfig {
    pub fn bsc_testnet() -> Self { /* current testnet addresses */ }
    pub fn bsc_mainnet() -> Self { /* mainnet addresses when ready */ }
    pub fn custom(addresses: ContractAddresses, chain_id: u64) -> Self { /* custom */ }
}
```

### Error Handling

```rust
pub enum StrikeError {
    Rpc(alloy::transports::TransportError),
    Contract(String),          // revert reason decoded
    NonceMismatch { expected: u64, got: u64 },
    MarketNotActive(u64),
    InsufficientBalance,
    Config(String),
}
```

### Dependencies

```toml
[dependencies]
alloy = { version = "0.12", features = ["full"] }
tokio = { version = "1", features = ["full"] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
eyre = "0.6"
tracing = "0.1"
futures-util = "0.3"
reqwest = { version = "0.12", features = ["json"] }
```

## Dogfooding

After the SDK is built, refactor `strike-mm` to depend on `strike-sdk`:

```toml
# strike-mm/Cargo.toml
[dependencies]
strike-sdk = { path = "../sdk/rs", features = ["nonce-manager"] }
```

Remove duplicated code from the MM — it should only contain trading strategy logic, not chain interaction primitives.

## Documentation

- `sdk/rust/README.md` — getting started, quick examples
- `sdk/rust/examples/` — runnable examples:
  - `read_markets.rs` — list markets, read orderbook (no wallet)
  - `place_orders.rs` — approve + place + cancel flow
  - `stream_orderbook.rs` — WebSocket orderbook stream
  - `simple_bot.rs` — minimal bot that quotes a spread around mid
- Doc comments on all public types and functions
- Published to docs.rs via crates.io

## Documentation

Two READMEs:
- `sdk/README.md` — top-level overview, links to language SDKs, coming soon section
- `sdk/rust/README.md` — Rust-specific: installation, quick start, API reference, examples

## Implementation Order

1. **Scaffold** — crate structure, Cargo.toml, feature flags, ABIs
2. **contracts.rs + types.rs** — alloy bindings and SDK types
3. **config.rs** — chain configs with hardcoded addresses
4. **chain/orders.rs** — placeOrder, placeOrders, replaceOrders, cancel
5. **chain/vault.rs** — approve, deposit helpers
6. **chain/redeem.rs** — redemption
7. **chain/tokens.rs** — outcome token balance/approval
8. **events/** — WSS subscriptions + historical event scanning
9. **indexer/** — REST client for market snapshots + orderbook + open orders
10. **nonce.rs** — NonceSender behind feature flag
11. **client.rs** — StrikeClient builder tying it all together
12. **READMEs** — sdk/README.md + sdk/rust/README.md (with Coming Soon section)
13. **examples/** — runnable examples
14. **Dogfood** — refactor strike-mm to use the SDK
15. **Publish** to crates.io
