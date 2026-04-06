# Example Bots

The SDK ships with runnable examples and patterns for bots and integrations.

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
            "  factory {} | orderbook {:?} | status: {} | expiry: {} | batch_interval: {}s",
            market.factory_market_id,
            market.orderbook_market_id,
            market.status,
            market.expiry_time,
            market.batch_interval,
        );
    }

    // Read on-chain state
    let active_count = client.markets().active_market_count().await?;
    println!("active markets: {active_count}");

    // Get orderbook for first active market using the tradable OrderBook ID
    let active_markets: Vec<_> = markets.iter().filter(|m| m.status == "active").collect();
    if let Some(market) = active_markets.first() {
        let market_id = market.tradable_market_id()?;
        let ob = client.indexer().get_orderbook(market_id).await?;
        println!("\norderbook for factory market {} (ob {}):", market.factory_market_id, market_id);
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

    // Place bid at 40, ask at 60
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

**What it demonstrates:** [Wallet setup](client.md), [USDT approval](vault-and-tokens.md), [order placement and cancellation](orders.md).

## active_market_quote — Find the Active Market and Quote It

This example shows a clean two-sided quoting flow:

1. fetch active markets from the indexer
2. pick a market
3. read the current orderbook
4. derive bid/ask quote ticks from the book
5. approve USDT if needed
6. place both sides in one transaction

```bash
PRIVATE_KEY=0x... cargo run --example active_market_quote
```

```rust
use anyhow::{anyhow, Result};
use strike_sdk::prelude::*;

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt::init();

    let private_key = std::env::var("PRIVATE_KEY").expect("PRIVATE_KEY required");

    let client = StrikeClient::new(StrikeConfig::bsc_mainnet())
        .with_private_key(&private_key)
        .build()?;

    let signer = client.signer_address().expect("wallet required");
    println!("wallet: {signer}");

    // One-time approval; safe to call repeatedly.
    client.vault().approve_usdt().await?;

    // 1) Fetch active markets.
    let markets = client.indexer().get_active_markets().await?;
    let market = markets
        .into_iter()
        .min_by_key(|m| m.expiry_time)
        .ok_or_else(|| anyhow!("no active markets found"))?;

    println!(
        "selected factory market {} | orderbook {:?} | expiry {} | batch interval {}s",
        market.factory_market_id, market.orderbook_market_id, market.expiry_time, market.batch_interval
    );

    // 2) Read orderbook snapshot.
    let ob = client.indexer().get_orderbook(market_id).await?;

    let best_bid = ob.bids.iter().map(|l| l.tick).max();
    let best_ask = ob.asks.iter().map(|l| l.tick).min();

    println!("best bid: {:?} | best ask: {:?}", best_bid, best_ask);

    // 3) Derive a simple two-sided quote.
    let (bid_tick, ask_tick) = match (best_bid, best_ask) {
        (Some(bid), Some(ask)) if bid < ask => {
            let next_bid = (bid + 1).min(98);
            let next_ask = ask.saturating_sub(1).max(2);

            if next_bid < next_ask {
                (next_bid, next_ask)
            } else {
                (bid, ask)
            }
        }
        (Some(bid), None) => (bid.min(98), (bid + 10).min(99)),
        (None, Some(ask)) => (ask.saturating_sub(10).max(1), ask.max(2)),
        (None, None) => (45, 55),
        _ => return Err(anyhow!("crossed or invalid orderbook; refusing to quote")),
    };

    let quote_lots = 100u64;

    println!(
        "placing quote on market {} | bid {} | ask {} | lots {}",
        market.tradable_market_id()?, bid_tick, ask_tick, quote_lots
    );

    // 4) Place both sides atomically.
    let placed = client
        .orders()
        .place_market(
            &market,
            &[
                OrderParam::bid(bid_tick, quote_lots),
                OrderParam::ask(ask_tick, quote_lots),
            ],
        )
        .await?;

    for order in &placed {
        println!(
            "placed order {} | side {:?} | orderbook market {}",
            order.order_id, order.side, order.orderbook_market_id
        );
    }

    Ok(())
}
```

**What it demonstrates:** active market discovery, orderbook-based quote selection, paired order placement.

## atomic_requote — Replace Existing Quotes in One Transaction

This example shows how to cancel stale quotes and place fresh ones atomically using `replace()`.

Use this when you already have resting quotes on a market and want to move them without creating a cancel/place gap.

```bash
PRIVATE_KEY=0x... cargo run --example atomic_requote
```

```rust
use anyhow::{anyhow, Result};
use strike_sdk::prelude::*;

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt::init();

    let private_key = std::env::var("PRIVATE_KEY").expect("PRIVATE_KEY required");

    let client = StrikeClient::new(StrikeConfig::bsc_mainnet())
        .with_private_key(&private_key)
        .build()?;

    let signer = client.signer_address().expect("wallet required");
    let market = client
        .indexer()
        .get_active_markets()
        .await?
        .into_iter()
        .min_by_key(|m| m.expiry_time)
        .ok_or_else(|| anyhow!("no active markets found"))?;

    // Start with an initial two-sided quote.
    let initial = client
        .orders()
        .place_market(
            &market,
            &[
                OrderParam::bid(45, 100),
                OrderParam::ask(55, 100),
            ],
        )
        .await?;

    let old_ids: Vec<_> = initial.iter().map(|o| o.order_id).collect();

    println!("wallet: {signer}");
    println!("initial order ids: {:?}", old_ids);

    // Move both sides tighter using one atomic replace.
    let updated = client
        .orders()
        .replace_market(
            &old_ids,
            &market,
            &[
                OrderParam::bid(46, 100),
                OrderParam::ask(54, 100),
            ],
        )
        .await?;

    for order in &updated {
        println!(
            "replacement order {} | side {:?} | orderbook market {}",
            order.order_id, order.side, order.orderbook_market_id
        );
    }

    Ok(())
}
```

**What it demonstrates:** atomic cancel-and-place, quote refresh without a gap, and practical use of `replace()`.

## track_order_lifecycle — Accepted/Live vs Filled

Minimal bot-flow example for the most important execution-state distinction:

- successful `place_market()` = **accepted/live**
- later `OrderSettled` = **filled**
- `OrderCancelled` = **explicitly cancelled / cleaned up**
- `GtcAutoCancelled` = **auto-cancelled by batch auction**

This example keeps local metadata keyed by returned `order_id`, which is the same core pattern used in the real market maker. That local tracking matters because `OrderSettled` currently includes `order_id`, `owner`, and `filled_lots`, but not `market_id` or side.

```bash
PRIVATE_KEY=0x... cargo run --example track_order_lifecycle
```

```rust
use std::collections::HashMap;
use std::env;

use futures_util::StreamExt;
use strike_sdk::prelude::*;

#[derive(Debug, Clone)]
struct LocalOrderMeta {
    market_id: u64,
    side: &'static str,
    tick: u8,
    lots: u64,
}

#[tokio::main]
async fn main() -> Result<()> {
    let private_key = env::var("PRIVATE_KEY").expect("set PRIVATE_KEY=0x...");

    let client = StrikeClient::new(StrikeConfig::bsc_testnet())
        .with_private_key(&private_key)
        .build()?;

    let signer = client.address().expect("wallet configured");
    let market = client
        .indexer()
        .get_active_markets()
        .await?
        .into_iter()
        .next()
        .expect("no active markets");

    let market_id = market.tradable_market_id()?;
    let mut events = client.events().await?;

    let placed = client
        .orders()
        .place_market(&market, &[OrderParam::bid(50, 100)])
        .await?;

    let mut tracked: HashMap<alloy::primitives::U256, LocalOrderMeta> = HashMap::new();
    for p in placed {
        tracked.insert(
            p.order_id,
            LocalOrderMeta {
                market_id,
                side: "bid",
                tick: 50,
                lots: 100,
            },
        );
        println!("accepted/live | order_id={}", p.order_id);
    }

    while let Some(event) = events.next().await {
        match event {
            StrikeEvent::OrderSettled { order_id, owner, filled_lots } if owner == signer => {
                if let Some(meta) = tracked.get(&order_id) {
                    println!(
                        "filled | order_id={} | market={} | side={} | filled_lots={} | requested_lots={}",
                        order_id, meta.market_id, meta.side, filled_lots, meta.lots
                    );
                    if filled_lots >= meta.lots {
                        tracked.remove(&order_id);
                    }
                }
            }
            StrikeEvent::OrderCancelled { order_id, owner, .. } if owner == signer => {
                if tracked.remove(&order_id).is_some() {
                    println!("cancelled | order_id={}", order_id);
                }
            }
            StrikeEvent::GtcAutoCancelled { order_id, owner } if owner == signer => {
                if tracked.remove(&order_id).is_some() {
                    println!("auto-cancelled | order_id={}", order_id);
                }
            }
            _ => {}
        }

        if tracked.is_empty() {
            break;
        }
    }

    Ok(())
}
```

**What it demonstrates:** correct bot execution-state handling, a tiny local lifecycle enum, local `order_id` tracking, and why accepted/live must be treated separately from filled.

**Operational notes:**
- the SDK `nonce-manager` feature is enabled by default. For bots, keep one serialized tx pipeline per wallet and avoid concurrent place/cancel/replace sends from the same wallet.
- if no terminal event arrives before your timeout, mark the order as needing reconciliation and fall back to `scan_orders()` / indexer positions instead of guessing.
- `OrderCancelled` is best treated as part of recovery/reconciliation as well; the live WSS stream is centered on settlement/batch events, so bots should always have a recovery path after reconnect gaps.

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

Event-driven market maker that demonstrates real bot patterns from the Strike MM. On startup it bootstraps from the indexer's active markets so it can quote immediately, then continues reacting to live events. Quotes are placed around the orderbook midpoint with a fixed spread, requotes atomically via `replaceOrders`, tracks fills, and cancels all orders on shutdown.

```bash
PRIVATE_KEY=0x... cargo run --example simple_bot
```

Key patterns demonstrated:

| Pattern | Why it matters |
|---------|---------------|
| `init_nonce_sender()` | Prevents nonce-too-low errors under rapid sends |
| `scan_orders()` startup recovery | Cancels stale orders from previous runs |
| `get_active_markets()` bootstrap | Quotes current active markets immediately on startup |
| `replace()` for requoting | Atomic cancel + place — zero empty-book time |
| `tokio::select!` event loop | React to events, handle graceful shutdown |
| Position tracking via `OrderSettled` | Know your net exposure per market |

```rust
// Core loop structure (see full source in sdk/rust/examples/simple_bot.rs):
loop {
    tokio::select! {
        _ = &mut shutdown_rx => {
            // Cancel all orders on Ctrl+C
            client.orders().cancel(&all_ids).await?;
            return Ok(());
        }
        Some(event) = events.next() => {
            match event {
                // Bootstrap uses indexer markets + place_market() so the bot
                // trades with orderbook_market_id instead of the legacy ID.
                StrikeEvent::MarketCreated { market_id, .. } => {
                    // New market: resolve active market metadata → place_market()
                }
                StrikeEvent::BatchCleared { market_id, .. } => {
                    // Requote: replace_market() = atomic cancel + place
                }
                StrikeEvent::OrderSettled { filled_lots, .. } => {
                    // Track position: bid fill = +lots, ask fill = -lots
                }
                _ => {}
            }
        }
    }
}
```

**What it demonstrates:** [Nonce management](client.md#nonce-manager), [event streaming](events.md), [order placement](orders.md), [atomic requoting](orders.md#replacing-orders-atomic-cancel--place), [startup recovery](events.md#historical-scanning), graceful shutdown.

## Tips for Building a Real Bot

- **Pricing:** Use a Pyth price feed to compute fair value instead of a fixed mid. The strike price and expiry are in `MarketCreated`.
- **Position tracking:** Use [`scan_orders()`](events.md#historical-scanning) on startup to recover open orders, then track fills via `OrderSettled` events.
- **Risk management:** Track net position per market. Consider maximum exposure limits and position sizing.
- **Requoting:** Use [`replace()`](orders.md#replacing-orders-atomic-cancel--place) to atomically cancel stale quotes and place new ones, avoiding temporary unhedged exposure.
- **Nonce management:** Enable [`init_nonce_sender()`](client.md#nonce-manager) for rapid transaction sending without nonce collisions.
- **Reconnection:** `EventStream` auto-reconnects on WSS failures, but you may miss events during the gap. Periodically reconcile state via the [indexer](indexer.md) or `scan_orders()`.
