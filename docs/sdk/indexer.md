# Indexer Client

The [Strike indexer](../infrastructure/indexer.md) provides REST endpoints for querying aggregated market state. Use it for startup snapshots — fetching all markets, orderbook levels, and open positions. For live data, use [event streaming](events.md) or direct RPC reads.

## When to Use

| Use case | Indexer | RPC/WSS |
|----------|---------|---------|
| Fetch all markets on startup | Yes | No (no batch query on-chain) |
| Get orderbook snapshot | Yes | Possible but expensive |
| Get open orders for a wallet | Yes | Use `scan_orders()` |
| Live event stream | No | Yes |
| Place/cancel orders | No | Yes |

## Get Markets

```rust
let client = StrikeClient::new(StrikeConfig::bsc_testnet()).build()?;

// All markets
let markets = client.indexer().get_markets().await?;

// Only active markets
let active = client.indexer().get_active_markets().await?;

for market in &active {
    println!(
        "market {} | expiry: {} | interval: {}s",
        market.id, market.expiry_time, market.batch_interval,
    );
}
```

### Market Type

```rust
pub struct Market {
    pub id: i64,
    pub expiry_time: i64,
    pub status: String,            // "active", "halted", "resolved", etc.
    pub pyth_feed_id: Option<String>,
    pub strike_price: Option<i64>,
    pub batch_interval: i64,
}
```

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

## Configuration

The indexer URL is set in `StrikeConfig` and defaults to `https://strike-indexer.fly.dev` for testnet. Override it with the builder:

```rust
let client = StrikeClient::new(StrikeConfig::bsc_testnet())
    .with_indexer("https://your-indexer.com")
    .build()?;
```

Indexer errors return `StrikeError::Indexer`.
