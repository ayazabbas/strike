# Quick Start

## Prerequisites

- Rust 1.75+ with cargo
- BNB for gas fees
- USDT for collateral

## Read-Only: Fetch Markets

No wallet needed — just connect and read.

```rust
use strike_sdk::prelude::*;

#[tokio::main]
async fn main() -> Result<()> {
    let client = StrikeClient::new(StrikeConfig::bsc_mainnet()).build()?;

    // Fetch markets from the indexer
    let markets = client.indexer().get_markets().await?;
    println!("found {} markets", markets.len());

    // Read on-chain state
    let active = client.markets().active_market_count().await?;
    println!("active markets: {active}");

    // Get orderbook for first active market
    let active_markets: Vec<_> = markets.iter().filter(|m| m.status == "active").collect();
    if let Some(market) = active_markets.first() {
        let ob = client.indexer().get_orderbook(market.id as u64).await?;
        println!("market {} — {} bid levels, {} ask levels", market.id, ob.bids.len(), ob.asks.len());
    }

    Ok(())
}
```

## Trading: Place and Cancel Orders

Requires a private key with BNB and USDT.

```rust
use strike_sdk::prelude::*;

#[tokio::main]
async fn main() -> Result<()> {
    let private_key = std::env::var("PRIVATE_KEY").expect("PRIVATE_KEY required");

    let client = StrikeClient::new(StrikeConfig::bsc_mainnet())
        .with_private_key(&private_key)
        .build()?;

    let signer = client.signer_address().unwrap();
    println!("wallet: {signer}");

    // One-time USDT approval (idempotent)
    client.vault().approve_usdt().await?;

    // Find an active market
    let markets = client.indexer().get_active_markets().await?;
    let market = markets.first().expect("no active markets");

    // Place a bid at tick 40 and an ask at tick 60, 100 lots each
    let orders = client
        .orders()
        .place_market(market, &[OrderParam::bid(40, 100), OrderParam::ask(60, 100)])
        .await?;

    for o in &orders {
        println!("placed order {} | {:?}", o.order_id, o.side);
    }

    // Cancel all
    let ids: Vec<_> = orders.iter().map(|o| o.order_id).collect();
    client.orders().cancel(&ids).await?;
    println!("cancelled {} orders", ids.len());

    Ok(())
}
```

Run it:

```bash
PRIVATE_KEY=0x... cargo run --example place_orders
```

## What's Next

- [Client Configuration](client.md) — customize RPC, WSS, indexer URLs
- [Placing & Managing Orders](orders.md) — order types, sides, and batch operations
- [Real-Time Events](events.md) — stream market and settlement events
