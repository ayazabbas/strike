# Example Bots

The SDK ships with four runnable examples in `sdk/rust/examples/`. Clone the repo and run them directly.

## read_markets — Read-Only Market Discovery

Connects to the indexer and chain, fetches all markets, and displays the orderbook for the first active market. No wallet required.

```bash
cargo run --example read_markets
```

```rust
use strike_sdk::prelude::*;

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt::init();

    let client = StrikeClient::new(StrikeConfig::bsc_mainnet()).build()?;

    // Fetch markets from indexer
    let markets = client.indexer().get_markets().await?;
    println!("found {} markets", markets.len());

    for market in &markets {
        println!(
            "  market {} | status: {} | expiry: {} | batch_interval: {}s",
            market.id, market.status, market.expiry_time, market.batch_interval,
        );
    }

    // Read on-chain state
    let active_count = client.markets().active_market_count().await?;
    println!("active markets: {active_count}");

    // Get orderbook for first active market
    let active_markets: Vec<_> = markets.iter().filter(|m| m.status == "active").collect();
    if let Some(market) = active_markets.first() {
        let ob = client.indexer().get_orderbook(market.id as u64).await?;
        println!("\norderbook for market {}:", market.id);
        for level in &ob.bids {
            println!("  bid: tick {} | {} lots", level.tick, level.lots);
        }
        for level in &ob.asks {
            println!("  ask: tick {} | {} lots", level.tick, level.lots);
        }
    }

    Ok(())
}
```

**What it demonstrates:** [Client setup](client.md) in read-only mode, [indexer queries](indexer.md), on-chain market reads.

## place_orders — Full Trading Lifecycle

Connects with a wallet, approves USDT, finds an active market, places a bid and ask, then cancels both.

```bash
PRIVATE_KEY=0x... cargo run --example place_orders
```

```rust
use strike_sdk::prelude::*;

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt::init();

    let private_key = std::env::var("PRIVATE_KEY").expect("PRIVATE_KEY required");

    let client = StrikeClient::new(StrikeConfig::bsc_mainnet())
        .with_private_key(&private_key)
        .build()?;

    let signer = client.signer_address().unwrap();
    println!("wallet: {signer}");

    // Check balance and approve
    let balance = client.vault().usdt_balance(signer).await?;
    println!("USDT balance: {balance}");
    client.vault().approve_usdt().await?;

    // Find active market
    let markets = client.indexer().get_active_markets().await?;
    let market = markets.first().expect("no active markets");
    let market_id = market.id as u64;

    // Place bid at 40, ask at 60
    let orders = client
        .orders()
        .place(market_id, &[OrderParam::bid(40, 100), OrderParam::ask(60, 100)])
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

**What it demonstrates:** [Wallet setup](client.md), [USDT approval](vault-and-tokens.md), [order placement and cancellation](orders.md).

## stream_events — Event-Driven Architecture

Subscribes to WSS events and prints market creations, batch clearings, and settlements.

```bash
cargo run --example stream_events
```

```rust
use strike_sdk::prelude::*;

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt::init();

    let client = StrikeClient::new(StrikeConfig::bsc_mainnet()).build()?;

    let mut events = client.events().await?;
    println!("listening for events...\n");

    while let Some(event) = events.next().await {
        match event {
            StrikeEvent::MarketCreated { market_id, strike_price, expiry_time, .. } => {
                println!("MarketCreated | id: {market_id} | strike: {strike_price} | expiry: {expiry_time}");
            }
            StrikeEvent::BatchCleared { market_id, batch_id, clearing_tick, matched_lots } => {
                println!("BatchCleared  | market: {market_id} | batch: {batch_id} | tick: {clearing_tick} | matched: {matched_lots}");
            }
            StrikeEvent::OrderSettled { order_id, filled_lots, .. } => {
                println!("OrderSettled  | order: {order_id} | filled: {filled_lots}");
            }
            StrikeEvent::GtcAutoCancelled { order_id, .. } => {
                println!("GtcCancelled  | order: {order_id}");
            }
            _ => {}
        }
    }

    Ok(())
}
```

**What it demonstrates:** [Event streaming](events.md), pattern matching on `StrikeEvent`, read-only WSS subscription.

## simple_bot — Minimal Market Maker Skeleton

Listens for new markets and quotes a fixed 10-tick spread around mid (tick 50). This is a skeleton — a real bot would compute fair value from a price feed.

```bash
PRIVATE_KEY=0x... cargo run --example simple_bot
```

```rust
use strike_sdk::prelude::*;

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt::init();

    let private_key = std::env::var("PRIVATE_KEY").expect("PRIVATE_KEY required");

    let client = StrikeClient::new(StrikeConfig::bsc_mainnet())
        .with_private_key(&private_key)
        .build()?;

    client.vault().approve_usdt().await?;

    let mut events = client.events().await?;
    println!("listening for new markets...\n");

    while let Some(event) = events.next().await {
        match event {
            StrikeEvent::MarketCreated { market_id, strike_price, expiry_time, .. } => {
                println!("new market {market_id} | strike: {strike_price} | expiry: {expiry_time}");

                let mid = 50u8;
                let spread = 5u8;
                let lots = 100u64;

                match client
                    .orders()
                    .place(market_id, &[
                        OrderParam::bid(mid - spread, lots),
                        OrderParam::ask(mid + spread, lots),
                    ])
                    .await
                {
                    Ok(orders) => {
                        println!("  placed {} orders on market {market_id}", orders.len());
                    }
                    Err(e) => println!("  failed to place orders: {e}"),
                }
            }
            StrikeEvent::BatchCleared { market_id, clearing_tick, matched_lots, .. } => {
                if matched_lots > 0 {
                    println!("batch cleared: market {market_id} | tick {clearing_tick} | {matched_lots} lots");
                }
            }
            _ => {}
        }
    }

    Ok(())
}
```

**What it demonstrates:** Combining [events](events.md) with [order placement](orders.md), event-driven bot architecture, error handling per-market.

## Tips for Building a Real Bot

- **Pricing:** Use a Pyth price feed to compute fair value instead of a fixed mid. The strike price and expiry are in `MarketCreated`.
- **Position tracking:** Use [`scan_orders()`](events.md#historical-scanning) on startup to recover open orders, then track fills via `OrderSettled` events.
- **Risk management:** Track net position per market. Consider maximum exposure limits and position sizing.
- **Requoting:** Use [`replace()`](orders.md#replacing-orders-atomic-cancel--place) to atomically cancel stale quotes and place new ones, avoiding temporary unhedged exposure.
- **Nonce management:** Enable [`init_nonce_sender()`](client.md#nonce-manager) for rapid transaction sending without nonce collisions.
- **Reconnection:** `EventStream` auto-reconnects on WSS failures, but you may miss events during the gap. Periodically reconcile state via the [indexer](indexer.md) or `scan_orders()`.
