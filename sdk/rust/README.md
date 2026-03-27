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

    // Place orders: bid at tick 50, ask at tick 60, 1000 lots each
    let orders = client.orders().place(1, &[
        OrderParam::bid(50, 1000),
        OrderParam::ask(60, 1000),
    ]).await?;

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
    market_id,
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

## Key Concepts

- **LOT_SIZE** = 1e16 wei ($0.01 per lot)
- **Ticks** are 1–99, representing $0.01–$0.99 probability
- **4-sided orderbook**: Bid, Ask, SellYes, SellNo
- **Order types**: GoodTilBatch (GTB) expires after one batch, GoodTilCancelled (GTC) rolls forward
- **Batch auctions**: orders are collected into batches and cleared atomically
- All fills pay the **clearing tick**, not the limit tick
- 1 YES + 1 NO = 1 USDT (always)

## Features

| Feature | Default | Description |
|---------|---------|-------------|
| `nonce-manager` | Yes | Shared nonce management for sequential TX sends |

Disable the nonce manager if you manage nonces yourself:

```toml
strike-sdk = { version = "0.1", default-features = false }
```

## Modules

| Module | Description |
|--------|-------------|
| `client` | `StrikeClient` builder (read-only and trading modes) |
| `chain::orders` | `placeOrders`, `replaceOrders`, `cancelOrders` |
| `chain::vault` | USDT approval, balance queries |
| `chain::redeem` | Outcome token redemption |
| `chain::tokens` | ERC-1155 outcome token helpers |
| `chain::markets` | On-chain market state reads |
| `events::subscribe` | WSS event stream with auto-reconnect |
| `events::scan` | Historical event scanning (chunked getLogs) |
| `indexer` | REST client: markets, positions, trades, stats (API v1) |
| `nonce` | `NonceSender` for sequential TX sends |

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
