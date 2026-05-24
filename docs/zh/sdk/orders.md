# 下单与订单管理

## 基本概念

下单前，需要理解几个关键参数：

### Sides

STRIKE 使用 [4-sided 订单簿](../contracts/orderbook.md)。每一侧决定会锁定哪种抵押资产，以及成交后你会收到什么。

| Side | 你的操作 | 锁定的抵押资产 | 成交后收到 |
|------|-------------------|-------------------|-------------------|
| `Bid` | 买入 YES 代币 | `lots × tick/100 × LOT_SIZE` USDT | YES 代币 |
| `Ask` | 买入 NO 代币 | `lots × (100-tick)/100 × LOT_SIZE` USDT | NO 代币 |
| `SellYes` | 卖出 YES 代币 | YES 代币（由订单簿托管） | USDT |
| `SellNo` | 卖出 NO 代币 | NO 代币（由订单簿托管） | USDT |

### Ticks

Tick 范围为 1-99，表示一个 YES 代币以美分计价的价格。以 tick 70 提交 bid，表示你愿意为一个 YES 代币支付 $0.70（隐含价格在到期时高于 STRIKE 的概率为 70%）。

### Lots

每个 lot 等于 `LOT_SIZE = 1e16 wei = $0.01` 的抵押资产。100 lots 以 tick 50 下单会锁定 `100 × 0.50 × $0.01 = $0.50` USDT。

### 订单类型

| Type | 行为 |
|------|----------|
| `GoodTilCancelled` (GTC) | 未成交部分会滚入下一个 [batch](../protocol/batch-auctions.md) |
| `GoodTilBatch` (GTB) | 如果未成交，会在当前 batch 结束时过期 |

### 抗 MEV 价格保护

你的 tick **就是** 你的价格保护。在批量拍卖中，同一个 batch 内的所有成交都会以统一清算价格结算。你的订单永远不会以差于 tick 的价格成交；如果清算价格超过你的 limit，订单就不会成交。

这与 AMM slippage 有本质区别。由于订单会被一起收集并清算，不存在提交和执行之间价格变化带来的风险。请将 tick 设置为你愿意接受的最差价格。

例如，当前 best ask 为 tick 55，而你愿意为一个 YES 代币最多支付 60 cents，则可以以 tick 60 提交 bid。你会支付清算价格（可能是 55、57 或任何不高于 60 的价格），不会支付更高价格。

## OrderParam 构造函数

`OrderParam` 提供默认使用 GTC 的便捷构造函数：

```rust
use strike_sdk::prelude::*;

// GTC orders (default)
let bid = OrderParam::bid(50, 100);          // bid at tick 50, 100 lots
let ask = OrderParam::ask(60, 100);          // ask at tick 60, 100 lots
let sell_yes = OrderParam::sell_yes(55, 50); // sell YES at tick 55, 50 lots
let sell_no = OrderParam::sell_no(45, 50);   // sell NO at tick 45, 50 lots

// For GTB orders, use the full constructor
let gtb_bid = OrderParam::new(Side::Bid, OrderType::GoodTilBatch, 50, 100);
```

## 提交订单

使用 `client.orders().place()` 在一笔交易中提交一个或多个订单：

```rust
let market = client.indexer().get_active_markets().await?
    .into_iter()
    .next()
    .expect("no active markets");

let orders = client
    .orders()
    .place_market(&market, &[OrderParam::bid(40, 100), OrderParam::ask(60, 100)])
    .await?;

for o in &orders {
    println!(
        "order {} | {:?} | orderbook market {}",
        o.order_id, o.side, o.orderbook_market_id
    );
}
```

这会使用市场的 `orderbook_market_id` 调用链上的 `OrderBook.placeOrders()`。返回的 `Vec<PlacedOrder>` 包含从交易回执中 `OrderPlaced` 事件解析得到的订单 ID。

## 取消订单

取消一个或多个订单：

```rust
// Cancel multiple
let ids: Vec<_> = orders.iter().map(|o| o.order_id).collect();
client.orders().cancel(&ids).await?;

// Cancel a single order
client.orders().cancel_one(order_id).await?;
```

`cancel()` 调用 `OrderBook.cancelOrders()`（批量）。`cancel_one()` 调用 `OrderBook.cancelOrder()`（单笔）。两者都会解锁抵押资产或返还由订单簿托管的代币。

## 替换订单（原子化取消 + 下单）

替换订单会在一笔交易中原子化取消现有订单并提交新订单：

```rust
let old_ids = vec![order1.order_id, order2.order_id];
let new_params = vec![OrderParam::bid(45, 100), OrderParam::ask(55, 100)];

let new_orders = client
    .orders()
    .replace_market(&old_ids, &market, &new_params)
    .await?;
```

这会调用 `OrderBook.replaceOrders()`。净抵押资产结算意味着你只需存入或取回差额，适合在不释放并重新锁定抵押资产的情况下调整报价。

## PlacedOrder

`place()` 和 `replace()` 返回的类型：

```rust
pub struct PlacedOrder {
    pub order_id: U256,
    pub side: Side,
    pub market_id: u64,              // legacy alias of orderbook_market_id
    pub orderbook_market_id: u64,
}
```

订单 ID 从交易回执中触发的 `OrderPlaced` 与 `OrderResting` 事件解析得到。

> **休眠订单**：当订单 tick 距离上一次清算价格较远（超过 20 ticks）时，合约会将它加入休眠列表，而不是放入活跃批次。休眠订单会触发 `OrderResting`，而不是 `OrderPlaced`。SDK 会同时跟踪两者，调用方无需处理这个差异。当价格靠近后，休眠订单会自动进入 batch。

## 卖出结果代币

卖出已持有的 YES 或 NO 代币时，使用 `SellYes`/`SellNo` side。提交订单时，订单簿会托管你的代币；如果订单取消或未成交，代币会返还给你。

卖出前，需要授权订单簿转账你的结果代币：

```rust
// Approve OrderBook to transfer your outcome tokens (one-time)
let order_book = client.config().addresses.order_book;
client.tokens().set_approval_for_all(order_book, true).await?;

// Place a sell order
let orders = client
    .orders()
    .place_market(&market, &[OrderParam::sell_yes(55, 50)])
    .await?;
```

更多代币操作请参见[金库与结果代币](vault-and-tokens.md)。
