# Indexer & API

The indexer is an off-chain service that indexes on-chain events and serves real-time orderbook data. It is **non-authoritative** — all data can be independently verified from the chain.

## What It Indexes

| Event | Data Extracted |
|-------|---------------|
| `OrderPlaced` | Order details, tick, side, amount |
| `OrderCancelled` | Order removal |
| `BatchCleared` | Clearing price, volume, fill fractions |
| `FillClaimed` | User fills, amounts |
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

### Events
```json
{"type": "orderbook", "marketId": "...", "data": {...}}
{"type": "trade", "marketId": "...", "data": {...}}
{"type": "market_status", "marketId": "...", "status": "resolved"}
{"type": "batch_cleared", "marketId": "...", "clearingTick": 65, "volume": "..."}
```

Subscribe to specific markets:
```json
{"action": "subscribe", "markets": ["0x..."]}
```

## Infrastructure

- **RPC:** uses a dedicated RPC provider (public BSC endpoints may disable `eth_getLogs`)
- **Database:** SQLite (dev) or PostgreSQL (production)
- **Deployment:** systemd service, configurable via `.env`
