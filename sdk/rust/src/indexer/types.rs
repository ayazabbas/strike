//! Response types from the Strike indexer API.

use serde::Deserialize;

/// A market as returned by the indexer.
#[derive(Debug, Clone, Deserialize)]
pub struct Market {
    pub id: i64,
    pub expiry_time: i64,
    pub status: String,
    pub pyth_feed_id: Option<String>,
    pub strike_price: Option<i64>,
    pub batch_interval: i64,
}

/// Wrapper for the `/markets` response.
#[derive(Debug, Deserialize)]
pub(crate) struct MarketsResponse {
    pub markets: Vec<Market>,
}

/// An open order from the indexer.
#[derive(Debug, Clone, Deserialize)]
pub struct IndexerOrder {
    pub id: i64,
    pub market_id: i64,
    pub side: String,
    pub tick: u64,
    pub lots: u64,
    pub status: String,
}

/// Wrapper for the `/positions/:address` response.
#[derive(Debug, Deserialize)]
pub(crate) struct PositionsResponse {
    pub open_orders: Vec<IndexerOrder>,
    #[allow(dead_code)]
    pub filled_positions: Vec<serde_json::Value>,
}

/// An orderbook level.
#[derive(Debug, Clone, Deserialize)]
pub struct OrderbookLevel {
    pub tick: u64,
    pub lots: u64,
}

/// Orderbook snapshot from the indexer.
#[derive(Debug, Clone, Deserialize)]
pub struct OrderbookSnapshot {
    pub bids: Vec<OrderbookLevel>,
    pub asks: Vec<OrderbookLevel>,
}
