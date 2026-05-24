# 示例机器人

SDK 提供可运行示例和适用于 bot 与集成场景的常见模式。

## read_markets — 只读市场发现

连接索引器和链，获取所有市场，并展示第一个活跃市场的订单簿。无需钱包。

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

**演示内容：** [客户端配置](client.md)的只读模式、[索引器查询](indexer.md)、链上市场读取。

## redeem_backlog_check — 赎回前查找可赎回仓位

这是供赎回 bot 使用的简洁发现流程：

1. 使用 `get_redeemable_positions(address)` 查询索引器 backlog
2. 从每个归一化 entry 中读取 factory 市场 ID
3. 将该 factory 市场 ID 传入链上 redemption 调用

```rust
use strike_sdk::prelude::*;

let address = "0x...";
let redeemable = client.indexer().get_redeemable_positions(address).await?;

for pos in redeemable {
    let Some(factory_market_id) = pos.factory_market_id() else {
        continue;
    };

    println!(
        "redeem backlog | factory {} | lots {:?} | redeemable {:?}",
        factory_market_id,
        pos.lots_hint(),
        pos.redeemable()
    );

    // Example on-chain call path once you choose an amount:
    // client.redeem().redeem(factory_market_id, amount).await?;
}
```

这里 SDK 会归一化旧版与 v1 redeemable payload 变体，因此 `factory_market_id()` 及相关 accessor 会保持稳定。

## place_orders — 完整交易生命周期

使用钱包连接，授权 USDT，找到一个活跃市场，提交一笔 bid 和一笔 ask，然后取消两笔订单。

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

**演示内容：** [钱包配置](client.md)、[USDT 授权](vault-and-tokens.md)、[下单和取消](orders.md)。

## active_market_quote — 查找活跃市场并报价

该示例展示一个清晰的双边报价流程：

1. 从索引器获取活跃市场
2. 选择一个市场
3. 读取当前订单簿
4. 根据订单簿推导 bid/ask quote tick
5. 如有需要，授权 USDT
6. 在一笔交易中同时提交两侧订单

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
    let market_id = market.tradable_market_id()?;
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

**演示内容：** 活跃市场发现、基于订单簿选择报价、成对下单。

## atomic_requote — 在一笔交易中替换现有报价

该示例展示如何使用 `replace()` 原子化取消过时报价并提交新报价。

当你已经在某个市场有 resting quotes，并希望在不产生取消/下单空档的情况下移动它们时，可以使用这个模式。

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

**演示内容：** 原子化取消并下单、无空档刷新报价，以及 `replace()` 的实际用法。

## track_order_lifecycle — Accepted/Live 与 Filled

这是一个最小 bot 流程示例，用于说明最重要的执行状态区别：

- successful `place_market()` = **accepted/live**
- later `OrderSettled` = **成交**
- `OrderCancelled` = **显式取消或清理**
- `GtcAutoCancelled` = **由批量拍卖自动取消**

该示例使用返回的 `order_id` 作为 key 保存本地 metadata，这也是真实做市方常用的核心模式。本地跟踪很重要，因为当前 `OrderSettled` 包含 `order_id`、`owner` 和 `filled_lots`，但不包含 `market_id` 或 side。

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

**演示内容：** 正确处理 bot 执行状态、一个很小的本地生命周期 enum、本地 `order_id` 跟踪，以及为什么 accepted/live 必须与成交分开处理。

**运维说明：**
- SDK 的 `nonce-manager` feature 默认启用。对 bot 来说，每个钱包应保持一个串行 tx pipeline，并避免同一钱包并发发送下单、取消或替换交易。
- 如果超时前没有收到终态事件，将订单标记为需要对账，并回退到 `scan_orders()` 或索引器 positions，不要猜测状态。
- `OrderCancelled` 也适合作为恢复和对账的一部分处理；实时 WSS stream 侧重结算与 batch 事件，因此 bot 在重连空档后应始终有恢复路径。

## stream_events — 事件驱动架构

订阅 WSS 事件，并打印市场创建、批量清算和结算事件。

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

**演示内容：** [事件流](events.md)、`StrikeEvent` pattern matching、只读 WSS subscription。

## simple_bot — 最小做市 Bot 骨架

这是一个事件驱动的市场做市方示例，展示 STRIKE MM 中的真实 bot 模式。启动时，它会从索引器的活跃市场 bootstrap，因此可以立即报价；之后继续响应实时事件。报价围绕订单簿 midpoint、使用固定 spread 提交，通过 `replaceOrders` 原子化重新报价，跟踪成交，并在关闭时取消所有订单。

```bash
PRIVATE_KEY=0x... cargo run --example simple_bot
```

演示的关键模式：

| Pattern | 重要性 |
|---------|---------------|
| `init_nonce_sender()` | 防止快速发送交易时出现 nonce-too-low 错误 |
| `scan_orders()` startup recovery | 取消上一轮运行遗留的 stale orders |
| `get_active_markets()` bootstrap | 启动时立即为当前活跃市场报价 |
| `replace()` 用于 requoting | 原子化取消 + 下单，避免订单簿出现空档 |
| `tokio::select!` 事件 loop | 响应事件并处理 graceful shutdown |
| 通过 `OrderSettled` 跟踪仓位 | 了解每个市场的 net exposure |

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

**演示内容：** [Nonce management](client.md#nonce-manager)、[事件流](events.md)、[下单](orders.md)、[原子化 requoting](orders.md#替换订单原子化取消--下单)、[startup recovery](events.md#historical-scanning)、graceful shutdown。

## 构建真实 Bot 的建议

- **Pricing:** 使用 Pyth price feed 计算 fair value，而不是固定 mid。STRIKE price 与 expiry 位于 `MarketCreated`。
- **Position tracking:** 启动时使用 [`scan_orders()`](events.md#historical-scanning) 恢复 open orders，然后通过 `OrderSettled` 事件跟踪成交。
- **Risk management:** 跟踪每个市场的 net position。考虑设置 maximum exposure limits 与 position sizing。
- **重新报价：** 使用 [`replace()`](orders.md#replace-orders-atomic-cancel--place) 原子化取消过时报价并提交新报价，避免临时未对冲敞口。
- **Nonce management:** 使用 [`init_nonce_sender()`](client.md#nonce-manager) 支持快速发送交易，避免 nonce collisions。
- **Reconnection:** `EventStream` 发生 WSS 连接故障时会自动重连，但你可能会丢失空档期间的事件。请定期通过[索引器](indexer.md)或 `scan_orders()` 对账状态。
