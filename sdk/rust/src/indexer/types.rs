//! Response types from the Strike indexer API.

use serde::de::{self, Deserializer};
use serde::Deserialize;

use crate::error::{Result, StrikeError};

/// A market as returned by the indexer.
#[derive(Debug, Clone)]
pub struct Market {
    /// Legacy API field. This remains the factory market ID for backward compatibility.
    pub id: i64,
    /// Canonical market ID in `MarketFactory`.
    pub factory_market_id: i64,
    /// Tradable market ID in `OrderBook`, used for order placement.
    pub orderbook_market_id: Option<i64>,
    pub expiry_time: i64,
    pub status: String,
    pub pyth_feed_id: Option<String>,
    pub strike_price: Option<i64>,
    pub batch_interval: i64,
}

#[derive(Debug, Deserialize)]
struct MarketWire {
    #[serde(default)]
    id: Option<i64>,
    #[serde(default, alias = "factoryMarketId")]
    factory_market_id: Option<i64>,
    #[serde(default, alias = "orderBookMarketId", alias = "orderbookMarketId")]
    orderbook_market_id: Option<i64>,
    expiry_time: i64,
    status: String,
    pyth_feed_id: Option<String>,
    strike_price: Option<i64>,
    batch_interval: i64,
}

impl<'de> Deserialize<'de> for Market {
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        let wire = MarketWire::deserialize(deserializer)?;
        let factory_market_id = wire
            .factory_market_id
            .or(wire.id)
            .ok_or_else(|| de::Error::missing_field("id"))?;

        Ok(Self {
            id: wire.id.unwrap_or(factory_market_id),
            factory_market_id,
            orderbook_market_id: wire.orderbook_market_id,
            expiry_time: wire.expiry_time,
            status: wire.status,
            pyth_feed_id: wire.pyth_feed_id,
            strike_price: wire.strike_price,
            batch_interval: wire.batch_interval,
        })
    }
}

impl Market {
    /// Return the tradable OrderBook market ID, failing closed if the indexer
    /// response did not expose it yet.
    pub fn tradable_market_id(&self) -> Result<u64> {
        let orderbook_market_id = self.orderbook_market_id.ok_or_else(|| {
            StrikeError::Config(format!(
                "market {} is missing orderbook_market_id; upgrade the indexer/API before using this market for trading",
                self.factory_market_id
            ))
        })?;

        u64::try_from(orderbook_market_id).map_err(|_| {
            StrikeError::Config(format!(
                "market {} has invalid orderbook_market_id {}",
                self.factory_market_id, orderbook_market_id
            ))
        })
    }
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
    #[serde(alias = "total_lots")]
    pub lots: u64,
}

/// Orderbook snapshot from the indexer.
#[derive(Debug, Clone, Deserialize)]
pub struct OrderbookSnapshot {
    pub bids: Vec<OrderbookLevel>,
    pub asks: Vec<OrderbookLevel>,
}
