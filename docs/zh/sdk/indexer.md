# 索引器客户端

STRIKE 索引器提供 REST endpoint，用于查询聚合后的市场状态。它适合用来获取启动快照，例如全部市场、订单簿档位以及 open positions。实时数据请使用[事件流](events.md)。

## API v1

所有索引器 endpoint 都位于 `/v1/` 前缀下。旧版无前缀 route 仍保留用于向后兼容，但新的集成应使用 `/v1/`。

响应使用标准封装：`{ data: [...], meta: { total, limit, offset } }`。SDK 会透明处理这些内容，调用方收到的仍是普通 `Vec<Market>`、`Vec<IndexerOrder>` 等类型，无需修改现有代码。

对于钱包 position endpoint，SDK 还会归一化旧版与 v1 payload 中已知的 schema 漂移。Filled 与 redeemable entry 会保留原始 JSON，同时暴露稳定的 accessor，例如 `factory_market_id()`、`orderbook_market_id()`、`redeemable()`、`resolved()` 与 `lots_hint()`。

## Canonical OpenAPI Reference

生成的 OpenAPI spec 是公开索引器 API 的事实来源：

- [https://app.strike.pm/api-docs/](https://app.strike.pm/api-docs/)

如果本页与 OpenAPI spec 不一致，请以生成的 spec 为准。

## 获取市场

`get_markets()` 会从索引器获取所有市场：

```rust
let client = StrikeClient::new(StrikeConfig::bsc_mainnet()).build()?;

let markets = client.indexer().get_markets().await?;

for market in &markets {
    println!(
        "factory {} | orderbook {:?} | expiry: {} | interval: {}s | status: {}",
        market.factory_market_id,
        market.orderbook_market_id,
        market.expiry_time,
        market.batch_interval,
        market.status,
    );
}
```

`get_active_markets()` 会在客户端侧过滤活跃市场：

```rust
let active = client.indexer().get_active_markets().await?;
```

### Pagination（直接 HTTP）

如果直接查询索引器而不使用 SDK，`/v1/markets` endpoint 支持 pagination：

| Parameter | Type | 默认 | 说明 |
|-----------|------|---------|-------------|
| `status` | string | — | 按状态过滤（`active`、`closed`、`resolving`、`resolved`、`cancelled`） |
| `limit` | int | 50 | 每页最大结果数 |
| `offset` | int | 0 | 跳过的结果数量 |
| `since` | int | — | Unix 时间戳；返回此时间之后创建的市场 |

```
GET /v1/markets?status=active&limit=20&offset=0
```

Response:

```json
{
  "data": [ { "id": 1, "status": "active", ... } ],
  "meta": { "total": 42, "limit": 20, "offset": 0 }
}
```

### Market 类型

```rust
pub struct Market {
    pub id: i64,                      // legacy alias of factory_market_id
    pub factory_market_id: i64,
    pub orderbook_market_id: Option<i64>,
    pub expiry_time: i64,
    pub status: String,            // "active", "closed", "resolving", "resolved", "cancelled"
    pub pyth_feed_id: Option<String>,
    pub strike_price: Option<i64>,
    pub batch_interval: i64,
}
```

生命周期与结算流程使用 `factory_market_id`，交易使用 `orderbook_market_id`。旧版 `id` 字段保留用于向后兼容，并且仍映射为 factory 市场 ID。

## 获取订单簿

获取某个市场聚合后的 bid/ask 档位：

```rust
let ob = client.indexer().get_orderbook(market_id).await?;

println!("bids:");
for level in &ob.bids {
    println!("  tick {} | {} lots", level.tick, level.lots);
}

println!("asks:");
for level in &ob.asks {
    println!("  tick {} | {} lots", level.tick, level.lots);
}
```

### OrderbookSnapshot 类型

```rust
pub struct OrderbookSnapshot {
    pub bids: Vec<OrderbookLevel>,
    pub asks: Vec<OrderbookLevel>,
}

pub struct OrderbookLevel {
    pub tick: u64,
    pub lots: u64,
}
```

## 获取 Open Orders

获取某个钱包地址的 open orders：

```rust
let address = "0x...";
let orders = client.indexer().get_open_orders(address).await?;

for order in &orders {
    println!(
        "order {} | market {} | {} @ tick {} | {} lots",
        order.id, order.market_id, order.side, order.tick, order.lots,
    );
}
```

来自 `/v1/positions/:address` 的 v1 response 是分页格式：

```json
{
  "open_orders": { "data": [...], "total": 15 },
  "filled_positions": { "data": [...], "total": 8 }
}
```

SDK 会自动处理 v1 分页格式和旧版 flat-array 格式，`get_open_orders` 始终返回 `Vec<IndexerOrder>`。

## 获取钱包仓位

从 `/positions/:address` 获取完整的钱包快照：

```rust
let address = "0x...";
let positions = client.indexer().get_positions(address).await?;

println!("open orders: {}", positions.open_orders.len());
println!("filled positions: {}", positions.filled_positions.len());

for pos in &positions.filled_positions {
    println!(
        "factory {:?} | orderbook {:?} | lots {:?} | redeemable {:?}",
        pos.factory_market_id(),
        pos.orderbook_market_id(),
        pos.lots_hint(),
        pos.redeemable()
    );
}
```

`get_positions()` 返回：

```rust
pub struct IndexerPositions {
    pub open_orders: Vec<IndexerOrder>,
    pub filled_positions: Vec<IndexerFilledPosition>,
}
```

请使用 `IndexerFilledPosition` 的 accessor methods，不要依赖某一种特定的上游 JSON 形状。

## 获取可赎回仓位

从 `/positions/:address/redeemable` 获取钱包的赎回 backlog：

```rust
let address = "0x...";
let redeemable = client.indexer().get_redeemable_positions(address).await?;

for pos in &redeemable {
    if let Some(factory_market_id) = pos.factory_market_id() {
        println!(
            "redeem backlog | factory {} | lots {:?}",
            factory_market_id,
            pos.lots_hint()
        );
    }
}
```

这是调用链上 redemption 前发现可赎回仓位的正确路径。SDK 会归一化分页和旧版 redeemable payload，包括嵌套字段和大小写漂移的字段名。

### IndexerOrder 类型

```rust
pub struct IndexerOrder {
    pub id: i64,
    pub market_id: i64,
    pub side: String,       // "bid", "ask", "sell_yes", "sell_no"
    pub tick: u64,
    pub lots: u64,
    pub status: String,
}
```

## Trades

`/v1/markets/:id/trades` endpoint 返回某个市场的清算 batch，默认会过滤掉空 batch。该 endpoint 可通过直接 HTTP 使用，SDK 目前尚未封装。

```
GET /v1/markets/1/trades?limit=50&offset=0
```

## Stats

`/v1/stats` endpoint 返回聚合后的协议统计数据，例如总成交量、活跃市场等。该 endpoint 可通过直接 HTTP 使用，SDK 目前尚未封装。

```
GET /v1/stats
```

## 配置

`StrikeConfig` 会为每个 network 设置默认索引器 URL。可以使用 builder 覆盖：

```rust
let client = StrikeClient::new(StrikeConfig::bsc_mainnet())
    .with_indexer("https://your-indexer.com")
    .build()?;
```

索引器错误会返回 `StrikeError::Indexer`。
