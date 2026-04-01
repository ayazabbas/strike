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

The canonical versioned API surface lives under `/v1/`.

### Public OpenAPI Spec

The generated OpenAPI spec is published at:

- [https://app.strike.pm/openapi.json](https://app.strike.pm/openapi.json)
- [https://app.strike.pm/v1/openapi.json](https://app.strike.pm/v1/openapi.json)

Use this as the source of truth for routes, params, enums, and response schemas.

### Key Endpoints

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

### Market Status Values

The current market status enum exposed by the indexer is:

- `active`
- `closed`
- `resolving`
- `resolved`
- `cancelled`

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
