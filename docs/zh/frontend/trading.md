# 交易界面

交易页面（`/market/:id`）是用户执行主要操作的地方。

## Layout

```
┌─────────────────────────────────────────────────────────┐
│  Market Info Bar: BTC/USD | Expiry 4:32 | Batch in 2s   │
├──────────────┬──────────────────────┬───────────────────┤
│              │                      │                   │
│  Order Entry │     Orderbook        │   Trade History   │
│              │   (depth chart +     │   (recent fills)  │
│  Side: UP/DOWN    price ladder)     │                   │
│  Price: 0.65 │                      │                   │
│  Amount: 10  │                      │                   │
│  Type: Limit │                      │                   │
│  [Place Order]│                     │                   │
│              │                      │                   │
├──────────────┴──────────────────────┴───────────────────┤
│  Open Orders: tick | side | amount | remaining | [cancel]│
│  (Settlement is automatic — no claim step needed)          │
└─────────────────────────────────────────────────────────┘
```

## 订单簿可视化

- **Price ladder:** 垂直 tick 列表，左侧显示 bid volume，右侧显示 ask volume，并用颜色编码 depth bars
- **Depth chart:** 累计 bid/ask volume 曲线，交叉点代表 indicative clearing price
- **Spread indicator:** 以美分显示 best bid、best ask 与 spread

## 下单区

- **Side toggle:** Buy UP（绿色）/ Buy DOWN（红色）
- **Price input:** tick slider（1-99）或 numeric input；价格显示为 $0.01-$0.99，并展示隐含概率
- **Amount:** USDT input，并显示可用余额
- **订单类型:** 切换 GoodTilCancel (GTC) / GoodTilBatch (GTB)
- **Submit:** 通过 Privy server wallet 发送单笔交易，状态 toast 会跟踪确认过程

### 市价单与抗 MEV 价格保护

在 **market mode** 中，前端会根据最佳可用价格加上 slippage tolerance（默认 5%，可在下单表单中配置）推导 tick，并以该 tick 提交 limit order。这可以保证你的订单以不差于 worst acceptable price 的价格成交。

在 **limit mode** 中，你的 tick 就是精确的价格保护。只有当清算价格等于或优于你的 tick 时，订单才会成交。不需要额外的 slippage setting。

两种情况下，所有成交都会以 batch clearing price 结算，且不会以差于 tick 的价格成交。详情请参见[批量拍卖](../protocol/batch-auctions.md#anti-mev-price-protection)。

## Batch Info Bar

- 到下一次批量清算的 countdown
- 当前 batch ID
- Indicative clearing price（由客户端根据当前 book 状态计算）
- 上一次清算价格与 volume
