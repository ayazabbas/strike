# Indexer Client

The Strike indexer provides REST endpoints for querying aggregated market state. Use it for startup snapshots — fetching all markets, orderbook levels, and open positions. For live data, use [event streaming](events.md).

## API v1

All indexer endpoints are available under the `/v1/` prefix. The legacy unprefixed routes remain for backward compatibility but new integrations should use `/v1/`.

Responses use a standard envelope: `{ data: [...], meta: { total, limit, offset } }`. The SDK handles this transparently — callers receive plain `Vec<Market>`, `Vec<IndexerOrder>`, etc. with no change to existing code.

For wallet position endpoints, the SDK also normalizes known schema drift across legacy and v1 payloads. Filled and redeemable entries preserve the raw JSON but expose stable accessors like `factory_market_id()`, `orderbook_market_id()`, `redeemable()`, `resolved()`, and `lots_hint()`.

## Canonical OpenAPI Reference

The generated OpenAPI spec is the source of truth for the public indexer API:

- [https://app.strike.pm/api-docs/](https://app.strike.pm/api-docs/)

If this page and the OpenAPI spec ever disagree, trust the generated spec.

## Get Markets

`get_markets()` fetches all markets from the indexer:

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

`get_active_markets()` filters for active markets client-side:

```rust
let active = client.indexer().get_active_markets().await?;
```

### Pagination (direct HTTP)

If you query the indexer directly (without the SDK), the `/v1/markets` endpoint supports pagination:

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `status` | string | — | Filter by status (`active`, `closed`, `resolving`, `resolved`, `cancelled`) |
| `limit` | int | 50 | Max results per page |
| `offset` | int | 0 | Number of results to skip |
| `since` | int | — | Unix timestamp; return markets created after this time |

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

### Market Type

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

Use `factory_market_id` for lifecycle/resolution flows and `orderbook_market_id` for trading. The legacy `id` field is kept for backward compatibility and still maps to the factory market ID.

## Get Orderbook

Fetch aggregated bid/ask levels for a market:

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

### OrderbookSnapshot Type

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

## Get Open Orders

Fetch open orders for a wallet address:

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

The v1 response from `/v1/positions/:address` is paginated:

```json
{
  "open_orders": { "data": [...], "total": 15 },
  "filled_positions": { "data": [...], "total": 8 }
}
```

The SDK handles both the v1 paginated and legacy flat-array formats automatically — `get_open_orders` always returns `Vec<IndexerOrder>`.

## Get Wallet Positions

Fetch the full wallet snapshot from `/positions/:address`:

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

`get_positions()` returns:

```rust
pub struct IndexerPositions {
    pub open_orders: Vec<IndexerOrder>,
    pub filled_positions: Vec<IndexerFilledPosition>,
}
```

Use the accessor methods on `IndexerFilledPosition` instead of relying on a specific upstream JSON shape.

## Get Redeemable Positions

Fetch the wallet's redeem backlog from `/positions/:address/redeemable`:

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

This is the right discovery path before calling on-chain redemption. The SDK normalizes both paginated and legacy redeemable payloads, including nested and casing-drifted field names.

### IndexerOrder Type

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

The `/v1/markets/:id/trades` endpoint returns cleared batches for a market, filtering out empty batches by default. This endpoint is available via direct HTTP — the SDK does not wrap it yet.

```
GET /v1/markets/1/trades?limit=50&offset=0
```

## Stats

The `/v1/stats` endpoint returns aggregate protocol statistics (total volume, active markets, etc.). This endpoint is available via direct HTTP — the SDK does not wrap it yet.

```
GET /v1/stats
```

## Configuration

The indexer URL is set in `StrikeConfig` with a default for each network. Override it with the builder:

```rust
let client = StrikeClient::new(StrikeConfig::bsc_mainnet())
    .with_indexer("https://your-indexer.com")
    .build()?;
```

Indexer errors return `StrikeError::Indexer`.
