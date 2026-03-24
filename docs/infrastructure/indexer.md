# Indexer & API

The indexer is an off-chain service that indexes on-chain events and serves real-time orderbook data. It is **non-authoritative** — all data can be independently verified from the chain.

## What It Indexes

| Event | Data Extracted |
|-------|---------------|
| `OrderPlaced` | Order details, tick, side, amount |
| `OrderResting` | Order parked outside active tree |
| `OrderCancelled` | Order removal |
| `OrderSettled` | Per-order fill result, amounts |
| `BatchCleared` | Clearing price, volume, fill fractions |
| `GtcAutoCancelled` | GTC order auto-cancelled on market close |
| `MarketCreated` | Market parameters, expiry |
| `MarketResolved` | Outcome, settlement price |

## REST API

### Markets
```
GET /markets                    — List all markets (filterable by status)
GET /markets/:id                — Market details
GET /markets/:id/orderbook      — Current orderbook (bids + asks by tick)
GET /markets/:id/trades         — Trade history
GET /markets/:id/ohlcv          — Candlestick data (from clearing prices)
```

### Users
```
GET /users/:address/orders      — Open + historical orders
GET /users/:address/positions   — Outcome token balances
GET /users/:address/fills       — Pending + claimed fills
```

## WebSocket

Connect to receive real-time updates:

```
ws://indexer:3002/ws
```

### Message Format

All messages use the format `{ type, event, data: {...} }`. Always access fields via `msg.data.field`.

```json
{"type": "orderbook", "event": "update", "data": {"marketId": "...", "bids": [...], "asks": [...]}}
{"type": "trade", "event": "fill", "data": {"marketId": "...", "price": 65, "volume": "..."}}
{"type": "market_status", "event": "change", "data": {"marketId": "...", "status": "resolved"}}
{"type": "batch_cleared", "event": "cleared", "data": {"marketId": "...", "clearingTick": 65, "volume": "..."}}
```

On `BatchCleared`, the WebSocket broadcasts a full orderbook snapshot so clients can reconcile state.

Subscribe to specific markets:
```json
{"action": "subscribe", "markets": ["0x..."]}
```

## Infrastructure

- **RPC:** uses a dedicated RPC provider (public BSC endpoints may disable `eth_getLogs`)
- **Database:** PostgreSQL
- **Deployment:** systemd service, configurable via `.env`
