# 快速开始

## 前置条件

- Rust 1.75+ 与 cargo
- 用于支付 Gas 费用的 BNB
- 用作抵押资产的 USDT

## 只读：获取市场

无需钱包，只需连接并读取数据。

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

    // Get orderbook for first active market using the tradable OrderBook ID
    let active_markets: Vec<_> = markets.iter().filter(|m| m.status == "active").collect();
    if let Some(market) = active_markets.first() {
        let market_id = market.tradable_market_id()?;
        let ob = client.indexer().get_orderbook(market_id).await?;
        println!("market {} (ob {}) — {} bid levels, {} ask levels", market.factory_market_id, market_id, ob.bids.len(), ob.asks.len());
    }

    Ok(())
}
```

## 交易：下单与撤单

需要一个拥有 BNB 与 USDT 的私钥。

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

    // Place a bid at tick 40 and an ask at tick 60, each for 100 lots
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

运行：

```bash
PRIVATE_KEY=0x... cargo run --example place_orders
```

## 后续阅读

- [客户端配置](client.md) — 自定义 RPC、WSS 和索引器 URL
- [下单与订单管理](orders.md) — 订单类型、方向和批量操作
- [实时事件](events.md) — 流式订阅市场和结算事件
