# 索引器与 API

索引器是一个链下 service，用于索引链上事件并提供实时订单簿数据。它是 **non-authoritative** 的：所有数据都可以从链上独立验证。

## 索引内容

| Event | 提取的数据 |
|-------|---------------|
| `OrderPlaced` | 订单详情、tick、side、amount |
| `OrderResting` | 停放在活跃 tree 之外的订单 |
| `OrderCancelled` | 订单移除 |
| `OrderSettled` | 每个订单的成交结果和数量 |
| `BatchCleared` | 清算价格、成交量、成交比例 |
| `GtcAutoCancelled` | 市场 close 时自动取消的 GTC 订单 |
| `MarketCreated` | 市场参数、expiry |
| `MarketResolved` | 结果、结算价格 |

## REST API

规范化的 versioned API surface 位于 `/v1/`。

### Public OpenAPI Spec

生成的 OpenAPI spec 发布在：

- [https://app.strike.pm/api-docs/](https://app.strike.pm/api-docs/)

请将它作为 routes、params、enums 与 response schemas 的事实来源。

### 主要端点

```
GET /v1/markets                    — List all markets (filterable by status)
GET /v1/markets/:id                — Market details
GET /v1/markets/:id/orderbook      — Current orderbook (bids + asks by tick)
GET /v1/markets/:id/trades         — Trade history
GET /v1/markets/:id/ohlcv          — Candlestick data (from clearing prices)
GET /v1/positions/:address         — Open orders + filled positions for a wallet
GET /v1/stats                      — Aggregate protocol stats
GET /v1/markets/:id/ai-resolution  — AI market resolution details
```

### 市场状态值

索引器当前暴露的市场状态 enum 包括：

- `active`
- `closed`
- `resolving`
- `resolved`
- `cancelled`

## WebSocket

连接后可接收实时更新：

```
ws://indexer:3002/ws
```

### Message Format

所有消息都使用 `{ type, event, data: {...} }` 格式。请始终通过 `msg.data.field` 访问字段。

```json
{"type": "orderbook", "event": "update", "data": {"marketId": "...", "bids": [...], "asks": [...]}}
{"type": "trade", "event": "fill", "data": {"marketId": "...", "price": 65, "volume": "..."}}
{"type": "market_status", "event": "change", "data": {"marketId": "...", "status": "resolved"}}
{"type": "batch_cleared", "event": "cleared", "data": {"marketId": "...", "clearingTick": 65, "volume": "..."}}
```

在 `BatchCleared` 时，WebSocket 会广播完整的订单簿 snapshot，方便 client 对账状态。

订阅指定市场：

```json
{"action": "subscribe", "markets": ["0x..."]}
```

## 基础设施

- **RPC:** 使用 dedicated RPC provider（公开 BSC endpoint 可能禁用 `eth_getLogs`）
- **Database:** PostgreSQL
- **部署:** systemd service，可通过 `.env` 配置
