# strike-sdk

Rust SDK for [Strike](https://github.com/ayazabbas/strike) prediction markets on BNB Chain.

## Installation

```toml
[dependencies]
strike-sdk = "0.2"
```

Or via cargo:

```bash
cargo add strike-sdk
```

## Quick Start

### Read-only (no wallet)

```rust
use strike_sdk::prelude::*;

#[tokio::main]
async fn main() -> Result<()> {
    let client = StrikeClient::new(StrikeConfig::bsc_testnet()).build()?;

    // Fetch markets from indexer
    let markets = client.indexer().get_markets().await?;
    println!("found {} markets", markets.len());

    // Read on-chain state
    let count = client.markets().active_market_count().await?;
    println!("{count} active markets on-chain");

    if let Some(first) = markets.first() {
        let meta = client
            .markets()
            .market_meta(first.factory_market_id as u64)
            .await?;
        println!(
            "factory {} -> orderbook {} | internal positions: {}",
            meta.factory_market_id, meta.orderbook_market_id, meta.use_internal_positions
        );
    }

    Ok(())
}
```

### Trading (with wallet)

```rust
use strike_sdk::prelude::*;

#[tokio::main]
async fn main() -> Result<()> {
    let client = StrikeClient::new(StrikeConfig::bsc_testnet())
        .with_private_key("0x...")
        .build()?;

    // Approve USDT (one-time, idempotent)
    client.vault().approve_usdt().await?;

    // Fetch a market from the indexer and trade using its tradable orderbook ID
    let market = client
        .indexer()
        .get_active_markets()
        .await?
        .into_iter()
        .next()
        .expect("no active markets");

    let orders = client
        .orders()
        .place_market(&market, &[
            OrderParam::bid(50, 1000),
            OrderParam::ask(60, 1000),
        ])
        .await?;

    // Cancel all placed orders
    let ids: Vec<_> = orders.iter().map(|o| o.order_id).collect();
    client.orders().cancel(&ids).await?;

    Ok(())
}
```

### Atomic Replace (cancel + place in one tx)

```rust
let new_orders = client.orders().replace(
    &old_order_ids,
    orderbook_market_id,
    &[OrderParam::bid(52, 1000), OrderParam::ask(58, 1000)],
).await?;
```

### Event Subscriptions

```rust
use futures_util::StreamExt;

let mut events = client.events().await?;
while let Some(event) = events.next().await {
    match event {
        StrikeEvent::MarketCreated { market_id, strike_price, .. } => {
            println!("new market {market_id} at strike {strike_price}");
        }
        StrikeEvent::BatchCleared { market_id, clearing_tick, matched_lots, .. } => {
            println!("batch cleared: market {market_id}, tick {clearing_tick}, {matched_lots} lots");
        }
        _ => {}
    }
}
```

### Track an Order Through Fill / Cancel Lifecycle

For bots, treat a successful `place_market()` as **accepted/live**, not **filled**.
Keep the returned `order_id` locally and classify the final outcome from events:

- `OrderSettled` -> filled (`filled_lots` is authoritative)
- `OrderCancelled` -> explicitly cancelled / cleaned up
- `GtcAutoCancelled` -> auto-cancelled by the batch auction

Minimal example:

```bash
PRIVATE_KEY=0x... cargo run --example track_order_lifecycle
```

Why local tracking matters:

- `OrderSettled` currently includes `order_id`, `owner`, `filled_lots` — but not `market_id` or side
- bots should therefore keep local metadata keyed by returned `order_id`
- the SDK `nonce-manager` feature is enabled by default; use one serialized tx pipeline per wallet

## API Response Format (v0.2+)

As of v0.2, the Strike indexer returns paginated envelopes for list endpoints:

```json
{
  "data": [...],
  "meta": { "total": 441, "limit": 50, "offset": 0 }
}
```

The SDK handles both the new `{ data }` envelope and the legacy `{ markets }` format automatically — no changes needed in your code.

The `get_markets()` call now fetches active markets only by default (equivalent to `?status=active`). To fetch all markets use the underlying indexer client directly with query params.

Market IDs matter:

- `market.id` is retained as a backward-compatible alias of the factory market ID.
- `market.factory_market_id` is the canonical lifecycle/resolution ID.
- `market.orderbook_market_id` is the tradable ID for `OrderBook.placeOrders` and `replaceOrders`.
- `orders().place_market()` and `orders().replace_market()` fail closed if the indexer response does not include `orderbook_market_id`.

## Key Concepts

- **LOT_SIZE** = 1e16 wei ($0.01 per lot)
- **Ticks** are 1–99, representing $0.01–$0.99 probability
- **4-sided orderbook**: Bid, Ask, SellYes, SellNo
- **Order types**: GoodTilBatch (GTB) expires after one batch, GoodTilCancelled (GTC) rolls forward
- **Batch auctions**: orders are collected into batches and cleared atomically
- All fills pay the **clearing tick**, not the limit tick
- **Resting orders**: orders >20 ticks from last clearing tick are placed on a resting list (emit `OrderResting` instead of `OrderPlaced`). The SDK tracks both automatically.
- 1 YES + 1 NO = 1 USDT (always)

## Features

| Feature | Default | Description |
|---------|---------|-------------|
| `nonce-manager` | Yes | Shared nonce management for sequential TX sends |

Disable the nonce manager if you manage nonces yourself:

```toml
strike-sdk = { version = "0.2", default-features = false }
```

## Modules

| Module | Description |
|--------|-------------|
| `client` | `StrikeClient` builder (read-only and trading modes) |
| `chain::orders` | `placeOrders`, `replaceOrders`, `cancelOrders` |
| `chain::vault` | USDT approval, balance queries |
| `chain::redeem` | Outcome token redemption |
| `chain::tokens` | ERC-1155 outcome token helpers |
| `chain::markets` | On-chain market state reads, including `market_meta(factory_market_id)` |
| `events::subscribe` | WSS event stream with auto-reconnect |
| `events::scan` | Historical event scanning (chunked getLogs) |
| `indexer` | REST client: markets, positions, trades, stats (API v1) |
| `nonce` | `NonceSender` for sequential TX sends |

## Wallet Positions

Use the indexer for wallet snapshots and redeem backlog discovery:

```rust
let wallet = "0x...";

let positions = client.indexer().get_positions(wallet).await?;
println!(
    "open orders: {} | filled positions: {}",
    positions.open_orders.len(),
    positions.filled_positions.len()
);

let redeemable = client.indexer().get_redeemable_positions(wallet).await?;
for entry in &redeemable {
    println!(
        "factory {:?} | lots {:?} | redeemable {:?}",
        entry.factory_market_id(),
        entry.lots_hint(),
        entry.redeemable()
    );
}
```

The SDK normalizes evolving `/positions/:address` and `/positions/:address/redeemable` payloads into accessor-based position types, so callers do not need to chase field-name drift across indexer versions.

## AI Markets

Markets with `is_ai_market: true` are resolved by the Flap AI Oracle instead of Pyth price feeds. The `Market` struct includes:

- `is_ai_market` — whether this market uses AI resolution
- `ai_prompt` — the question sent to the LLM
- `ai_status` — resolution status: `pending`, `proposed`, `challenged`, `finalized`, `refunded`

### Checking AI Resolution

```rust
let market = client.indexer().get_market(920).await?;
if market.is_ai_market {
    println!("AI market: {}", market.ai_prompt.as_deref().unwrap_or(""));
    println!("Status: {:?}", market.ai_status);
}
```

### AI Resolution Details

Use the indexer endpoint to fetch full resolution data including the IPFS proof:

```rust
// GET /v1/markets/{id}/ai-resolution
let resolution = client.indexer().get_ai_resolution(920).await?;
println!("Choice: {} ({})", resolution.choice, resolution.choice_label);
println!("IPFS proof: {}", resolution.reasoning_url);
```

## Coming Soon

- Python SDK
- Full API v1 query builder
