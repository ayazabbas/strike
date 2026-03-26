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
/// Supports both v1 format { data: [...] } and legacy { markets: [...] }.
#[derive(Debug, Deserialize)]
pub(crate) struct MarketsResponse {
    #[serde(alias = "markets")]
    pub data: Vec<Market>,
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

/// A paginated list wrapper: `{ data: [...], total: N }` or a plain array.
#[derive(Debug, Deserialize)]
#[serde(untagged)]
pub(crate) enum OrdersOrPaginated {
    Paginated { data: Vec<IndexerOrder> },
    Plain(Vec<IndexerOrder>),
}

impl OrdersOrPaginated {
    pub fn into_vec(self) -> Vec<IndexerOrder> {
        match self {
            Self::Paginated { data } => data,
            Self::Plain(v) => v,
        }
    }
}

/// Wrapper for the `/positions/:address` response.
/// Supports both v1 `{ open_orders: { data: [...], total }, ... }` and legacy `{ open_orders: [...], ... }`.
#[derive(Debug, Deserialize)]
pub(crate) struct PositionsResponse {
    pub open_orders: OrdersOrPaginated,
    #[allow(dead_code)]
    pub filled_positions: serde_json::Value,
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
