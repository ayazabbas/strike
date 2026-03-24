# Real-Time Events

## Event Stream

Subscribe to on-chain events via WebSocket:

```rust
use strike_sdk::prelude::*;

let client = StrikeClient::new(StrikeConfig::bsc_mainnet()).build()?;

let mut events = client.events().await?;

while let Some(event) = events.next().await {
    match event {
        StrikeEvent::MarketCreated { market_id, strike_price, expiry_time, .. } => {
            println!("new market {market_id} | strike: {strike_price} | expiry: {expiry_time}");
        }
        StrikeEvent::BatchCleared { market_id, batch_id, clearing_tick, matched_lots } => {
            println!("batch cleared | market: {market_id} | tick: {clearing_tick} | matched: {matched_lots}");
        }
        StrikeEvent::OrderSettled { order_id, filled_lots, .. } => {
            println!("order settled | {order_id} | filled: {filled_lots}");
        }
        StrikeEvent::GtcAutoCancelled { order_id, .. } => {
            println!("GTC auto-cancelled | {order_id}");
        }
        _ => {}
    }
}
```

No wallet required — event streaming is read-only.

## Event Types

`StrikeEvent` is an enum with the following variants:

### MarketCreated

Emitted when a new market is created via [MarketFactory](../contracts/market-factory.md).

```rust
StrikeEvent::MarketCreated {
    market_id: u64,
    price_id: [u8; 32],   // Pyth price feed ID
    strike_price: i64,
    expiry_time: u64,
}
```

### BatchCleared

Emitted when a [batch auction](../protocol/batch-auctions.md) clears. `clearing_tick` is the uniform price all fills settle at. `matched_lots` is the total volume matched.

```rust
StrikeEvent::BatchCleared {
    market_id: u64,
    batch_id: u64,
    clearing_tick: u64,
    matched_lots: u64,
}
```

### OrderSettled

Emitted per order during batch settlement. Tells you how many lots were filled.

```rust
StrikeEvent::OrderSettled {
    order_id: U256,
    owner: Address,
    filled_lots: u64,
}
```

### GtcAutoCancelled

Emitted when a GTC order is auto-cancelled (e.g., market halted or deactivated).

```rust
StrikeEvent::GtcAutoCancelled {
    order_id: U256,
    owner: Address,
}
```

### OrderPlaced / OrderCancelled

Emitted on order placement and cancellation. Available via historical scanning (see below), not via the live WSS stream.

```rust
StrikeEvent::OrderPlaced {
    order_id: U256,
    market_id: u64,
    side: u8,
    tick: u8,
    lots: u64,
    owner: Address,
}

StrikeEvent::OrderCancelled {
    order_id: U256,
    market_id: u64,
    owner: Address,
}
```

## Auto-Reconnect

`EventStream` handles WSS disconnections automatically. On connection loss, it waits 5 seconds and reconnects. Events emitted during the reconnection gap are missed — use [historical scanning](#historical-scanning) to recover them.

## Historical Scanning

For startup recovery (e.g., a bot restarting and needing to know its open orders), use `scan_orders()`:

```rust
use std::collections::HashMap;
use alloy::primitives::{Address, U256};

let from_block = 48_000_000u64;
let owner: Address = client.signer_address().unwrap();

// Returns: HashMap<market_id, (bid_order_ids, ask_order_ids)>
let open_orders = client.scan_orders(from_block, owner).await?;

for (market_id, (bids, asks)) in &open_orders {
    println!("market {market_id}: {} bids, {} asks", bids.len(), asks.len());
}
```

This scans `OrderPlaced` and `OrderCancelled` events from `from_block` to the latest block, returning only orders that haven't been cancelled.

## Typical Bot Pattern

A common pattern combines the event stream with historical recovery:

```rust
// 1. Recover existing positions on startup
let open_orders = client.scan_orders(from_block, signer).await?;

// 2. Subscribe to live events going forward
let mut events = client.events().await?;

while let Some(event) = events.next().await {
    match event {
        StrikeEvent::MarketCreated { market_id, .. } => {
            // Quote new market
        }
        StrikeEvent::BatchCleared { market_id, clearing_tick, .. } => {
            // Update position tracking, re-quote
        }
        StrikeEvent::OrderSettled { order_id, filled_lots, .. } => {
            // Track fills
        }
        _ => {}
    }
}
```
