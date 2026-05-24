# 实时事件

## Event Stream

通过 WebSocket 订阅链上事件：

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

无需钱包，事件流是只读功能。

## Event Types

`StrikeEvent` 是包含以下 variant 的 enum：

### MarketCreated

通过 [MarketFactory](../contracts/market-factory.md) 创建新市场时触发。

```rust
StrikeEvent::MarketCreated {
    market_id: u64,
    price_id: [u8; 32],   // Pyth price feed ID
    strike_price: i64,
    expiry_time: u64,
}
```

### BatchCleared

[批量拍卖](../protocol/batch-auctions.md)清算时触发。`clearing_tick` 是所有成交结算所用的统一价格。`matched_lots` 是匹配到的总成交量。

```rust
StrikeEvent::BatchCleared {
    market_id: u64,
    batch_id: u64,
    clearing_tick: u64,
    matched_lots: u64,
}
```

### OrderSettled

每个订单在批次结算时触发。它会告诉你成交了多少 lots。

```rust
StrikeEvent::OrderSettled {
    order_id: U256,
    owner: Address,
    filled_lots: u64,
}
```

### GtcAutoCancelled

GTC 订单被自动取消时触发，例如市场 halted 或 deactivated。

```rust
StrikeEvent::GtcAutoCancelled {
    order_id: U256,
    owner: Address,
}
```

### OrderPlaced / OrderCancelled

下单和取消时触发。可通过历史扫描获取（见下文），但不会通过实时 WSS stream 推送。

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

## 自动重连

`EventStream` 会自动处理 WSS 断连。连接断开后，它会等待 5 秒并重新连接。重连空档期间触发的事件会丢失；请使用[历史扫描](#historical-scanning)恢复这些事件。

## Historical Scanning

启动恢复时，例如 bot 重启后需要了解自己的 open orders，可以使用 `scan_orders()`：

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

这会从 `from_block` 扫描到最新区块中的 `OrderPlaced` 和 `OrderCancelled` 事件，并只返回尚未取消的订单。

## 典型 Bot 模式

常见模式是将事件流与历史恢复结合：

```rust
// 1. Recover existing positions on startup
let open_orders = client.scan_orders(from_block, signer).await?;

// 2. Subscribe to real-time events going forward
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
