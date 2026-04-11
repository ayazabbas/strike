//! Response types from the Strike indexer API.

use serde::de::{self, Deserializer};
use serde::Deserialize;
use serde_json::Value;

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

/// A filled position entry from the `/positions/:address` payload.
///
/// The upstream API schema has evolved, so this preserves the raw payload and
/// exposes normalized accessors rather than failing on field drift.
#[derive(Debug, Clone, Deserialize)]
#[serde(transparent)]
pub struct IndexerFilledPosition {
    raw: Value,
}

impl IndexerFilledPosition {
    pub fn raw(&self) -> &Value {
        &self.raw
    }

    pub fn factory_market_id(&self) -> Option<u64> {
        first_u64(
            &self.raw,
            &[
                &["factory_market_id"],
                &["factoryMarketId"],
                &["market", "factory_market_id"],
                &["market", "factoryMarketId"],
                &["market_id"],
                &["marketId"],
                &["market", "market_id"],
                &["market", "marketId"],
                &["market", "id"],
            ],
        )
    }

    pub fn orderbook_market_id(&self) -> Option<u64> {
        first_u64(
            &self.raw,
            &[
                &["orderbook_market_id"],
                &["orderBookMarketId"],
                &["orderbookMarketId"],
                &["market", "orderbook_market_id"],
                &["market", "orderBookMarketId"],
                &["market", "orderbookMarketId"],
            ],
        )
    }

    pub fn status(&self) -> Option<&str> {
        first_str(
            &self.raw,
            &[
                &["market_status"],
                &["marketStatus"],
                &["status"],
                &["market", "status"],
            ],
        )
    }

    pub fn redeemable(&self) -> Option<bool> {
        first_bool(
            &self.raw,
            &[
                &["redeemable"],
                &["claimable"],
                &["can_redeem"],
                &["canRedeem"],
                &["is_redeemable"],
                &["isRedeemable"],
            ],
        )
    }

    pub fn resolved(&self) -> Option<bool> {
        first_bool(
            &self.raw,
            &[
                &["resolved"],
                &["is_resolved"],
                &["isResolved"],
                &["market", "resolved"],
                &["market", "isResolved"],
            ],
        )
        .or_else(|| {
            self.status()
                .map(|status| status.eq_ignore_ascii_case("resolved"))
        })
    }

    pub fn lots_hint(&self) -> Option<u128> {
        let yes = first_u128(
            &self.raw,
            &[
                &["yes_lots"],
                &["yesLots"],
                &["yes_balance"],
                &["yesBalance"],
                &["yes_amount"],
                &["yesAmount"],
            ],
        )
        .unwrap_or(0);
        let no = first_u128(
            &self.raw,
            &[
                &["no_lots"],
                &["noLots"],
                &["no_balance"],
                &["noBalance"],
                &["no_amount"],
                &["noAmount"],
            ],
        )
        .unwrap_or(0);

        let total = yes.saturating_add(no);
        if total > 0 {
            Some(total)
        } else {
            first_u128(
                &self.raw,
                &[
                    &["lots"],
                    &["amount"],
                    &["balance"],
                    &["position_size"],
                    &["positionSize"],
                ],
            )
        }
    }
}

/// A redeemable backlog entry from `/positions/:address/redeemable`.
///
/// The endpoint schema is not stable, so this preserves the raw payload and
/// exposes normalized accessors for redemption flows.
#[derive(Debug, Clone, Deserialize)]
#[serde(transparent)]
pub struct IndexerRedeemablePosition {
    raw: Value,
}

impl IndexerRedeemablePosition {
    pub fn raw(&self) -> &Value {
        &self.raw
    }

    pub fn factory_market_id(&self) -> Option<u64> {
        first_u64(
            &self.raw,
            &[
                &["factory_market_id"],
                &["factoryMarketId"],
                &["market_id"],
                &["marketId"],
                &["market", "factory_market_id"],
                &["market", "factoryMarketId"],
                &["market", "market_id"],
                &["market", "marketId"],
                &["market", "id"],
                &["position", "factory_market_id"],
                &["position", "factoryMarketId"],
                &["position", "market_id"],
                &["position", "marketId"],
            ],
        )
    }

    pub fn orderbook_market_id(&self) -> Option<u64> {
        first_u64(
            &self.raw,
            &[
                &["orderbook_market_id"],
                &["orderBookMarketId"],
                &["orderbookMarketId"],
                &["market", "orderbook_market_id"],
                &["market", "orderBookMarketId"],
                &["market", "orderbookMarketId"],
                &["position", "orderbook_market_id"],
                &["position", "orderBookMarketId"],
                &["position", "orderbookMarketId"],
            ],
        )
    }

    pub fn status(&self) -> Option<&str> {
        first_str(
            &self.raw,
            &[
                &["market_status"],
                &["marketStatus"],
                &["status"],
                &["market", "status"],
                &["position", "market_status"],
                &["position", "marketStatus"],
                &["position", "status"],
            ],
        )
    }

    pub fn redeemable(&self) -> Option<bool> {
        first_bool(
            &self.raw,
            &[
                &["redeemable"],
                &["claimable"],
                &["can_redeem"],
                &["canRedeem"],
                &["is_redeemable"],
                &["isRedeemable"],
                &["position", "redeemable"],
                &["position", "claimable"],
                &["position", "can_redeem"],
                &["position", "canRedeem"],
            ],
        )
    }

    pub fn resolved(&self) -> Option<bool> {
        first_bool(
            &self.raw,
            &[
                &["resolved"],
                &["is_resolved"],
                &["isResolved"],
                &["market", "resolved"],
                &["market", "isResolved"],
                &["position", "resolved"],
                &["position", "is_resolved"],
                &["position", "isResolved"],
            ],
        )
        .or_else(|| {
            self.status()
                .map(|status| status.eq_ignore_ascii_case("resolved"))
        })
    }

    pub fn lots_hint(&self) -> Option<u128> {
        let yes = first_u128(
            &self.raw,
            &[
                &["yes_lots"],
                &["yesLots"],
                &["yes_balance"],
                &["yesBalance"],
                &["yes_amount"],
                &["yesAmount"],
                &["position", "yes_lots"],
                &["position", "yesLots"],
                &["position", "yes_balance"],
                &["position", "yesBalance"],
                &["position", "yes_amount"],
                &["position", "yesAmount"],
            ],
        )
        .unwrap_or(0);
        let no = first_u128(
            &self.raw,
            &[
                &["no_lots"],
                &["noLots"],
                &["no_balance"],
                &["noBalance"],
                &["no_amount"],
                &["noAmount"],
                &["position", "no_lots"],
                &["position", "noLots"],
                &["position", "no_balance"],
                &["position", "noBalance"],
                &["position", "no_amount"],
                &["position", "noAmount"],
            ],
        )
        .unwrap_or(0);

        let total = yes.saturating_add(no);
        if total > 0 {
            Some(total)
        } else {
            first_u128(
                &self.raw,
                &[
                    &["lots"],
                    &["amount"],
                    &["balance"],
                    &["position_size"],
                    &["positionSize"],
                    &["position", "lots"],
                    &["position", "amount"],
                    &["position", "balance"],
                    &["position", "position_size"],
                    &["position", "positionSize"],
                ],
            )
        }
    }
}

/// A paginated list wrapper for filled positions.
#[derive(Debug, Deserialize, Default)]
#[serde(untagged)]
pub(crate) enum FilledPositionsOrPaginated {
    Paginated {
        data: Vec<IndexerFilledPosition>,
    },
    Plain(Vec<IndexerFilledPosition>),
    EmptyObject {},
    #[default]
    Null,
}

impl FilledPositionsOrPaginated {
    pub fn into_vec(self) -> Vec<IndexerFilledPosition> {
        match self {
            Self::Paginated { data } => data,
            Self::Plain(v) => v,
            Self::EmptyObject {} | Self::Null => Vec::new(),
        }
    }
}

/// Wallet positions from the indexer.
#[derive(Debug, Clone)]
pub struct IndexerPositions {
    pub open_orders: Vec<IndexerOrder>,
    pub filled_positions: Vec<IndexerFilledPosition>,
}

/// A paginated list wrapper for redeemable positions.
#[derive(Debug, Deserialize, Default)]
#[serde(untagged)]
pub(crate) enum RedeemablePositionsOrPaginated {
    Paginated {
        data: Vec<IndexerRedeemablePosition>,
    },
    Plain(Vec<IndexerRedeemablePosition>),
    EmptyObject {},
    #[default]
    Null,
}

impl RedeemablePositionsOrPaginated {
    pub fn into_vec(self) -> Vec<IndexerRedeemablePosition> {
        match self {
            Self::Paginated { data } => data,
            Self::Plain(v) => v,
            Self::EmptyObject {} | Self::Null => Vec::new(),
        }
    }
}

/// Wrapper for the `/positions/:address` response.
/// Supports both v1 `{ open_orders: { data: [...], total }, ... }` and legacy `{ open_orders: [...], ... }`.
#[derive(Debug, Deserialize)]
pub(crate) struct PositionsResponse {
    pub open_orders: OrdersOrPaginated,
    #[serde(default)]
    pub filled_positions: FilledPositionsOrPaginated,
}

impl PositionsResponse {
    pub fn into_positions(self) -> IndexerPositions {
        IndexerPositions {
            open_orders: self.open_orders.into_vec(),
            filled_positions: self.filled_positions.into_vec(),
        }
    }
}

/// Wrapper for the `/positions/:address/redeemable` response.
/// Supports both paginated `{ data: [...] }` and plain array payloads.
#[derive(Debug, Deserialize)]
#[serde(untagged)]
pub(crate) enum RedeemablePositionsResponse {
    Positions(RedeemablePositionsOrPaginated),
}

impl RedeemablePositionsResponse {
    pub fn into_positions(self) -> Vec<IndexerRedeemablePosition> {
        match self {
            Self::Positions(positions) => positions.into_vec(),
        }
    }
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

fn first_u64(value: &Value, paths: &[&[&str]]) -> Option<u64> {
    paths
        .iter()
        .find_map(|path| get_path(value, path).and_then(value_as_u64))
}

fn first_u128(value: &Value, paths: &[&[&str]]) -> Option<u128> {
    paths
        .iter()
        .find_map(|path| get_path(value, path).and_then(value_as_u128))
}

fn first_bool(value: &Value, paths: &[&[&str]]) -> Option<bool> {
    paths
        .iter()
        .find_map(|path| get_path(value, path).and_then(value_as_bool))
}

fn first_str<'a>(value: &'a Value, paths: &[&[&str]]) -> Option<&'a str> {
    paths
        .iter()
        .find_map(|path| get_path(value, path).and_then(Value::as_str))
}

fn get_path<'a>(value: &'a Value, path: &[&str]) -> Option<&'a Value> {
    let mut current = value;
    for segment in path {
        current = get_field(current, segment)?;
    }
    Some(current)
}

fn get_field<'a>(value: &'a Value, key: &str) -> Option<&'a Value> {
    if let Some(exact) = value.get(key) {
        return Some(exact);
    }

    let Value::Object(map) = value else {
        return None;
    };

    let normalized_key = normalize_key(key);
    map.iter().find_map(|(candidate, value)| {
        (normalize_key(candidate) == normalized_key).then_some(value)
    })
}

fn normalize_key(key: &str) -> String {
    key.chars()
        .filter(|c| c.is_ascii_alphanumeric())
        .map(|c| c.to_ascii_lowercase())
        .collect()
}

fn value_as_u64(value: &Value) -> Option<u64> {
    match value {
        Value::Number(n) => n.as_u64(),
        Value::String(s) => s.parse().ok(),
        _ => None,
    }
}

fn value_as_u128(value: &Value) -> Option<u128> {
    match value {
        Value::Number(n) => n.as_u64().map(u128::from),
        Value::String(s) => s.parse().ok(),
        _ => None,
    }
}

fn value_as_bool(value: &Value) -> Option<bool> {
    match value {
        Value::Bool(v) => Some(*v),
        Value::String(s) => match s.to_ascii_lowercase().as_str() {
            "true" => Some(true),
            "false" => Some(false),
            _ => None,
        },
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::{
        IndexerFilledPosition, IndexerRedeemablePosition, PositionsResponse,
        RedeemablePositionsResponse,
    };

    #[test]
    fn parses_filled_positions_with_nested_market_ids() {
        let json = r#"
        {
          "open_orders": [],
          "filled_positions": [
            {
              "redeemable": true,
              "market": {
                "id": 101,
                "factoryMarketId": 101,
                "orderBookMarketId": 202,
                "status": "resolved"
              },
              "yesLots": "15",
              "noLots": "0"
            }
          ]
        }
        "#;

        let response: PositionsResponse = serde_json::from_str(json).unwrap();
        let positions = response.into_positions();
        let position: &IndexerFilledPosition = &positions.filled_positions[0];

        assert_eq!(position.factory_market_id(), Some(101));
        assert_eq!(position.orderbook_market_id(), Some(202));
        assert_eq!(position.redeemable(), Some(true));
        assert_eq!(position.resolved(), Some(true));
        assert_eq!(position.lots_hint(), Some(15));
    }

    #[test]
    fn parses_legacy_filled_positions_with_flat_market_fields() {
        let json = r#"
        {
          "open_orders": { "data": [] },
          "filled_positions": {
            "data": [
              {
                "market_id": "303",
                "market_status": "resolved",
                "claimable": "true",
                "lots": "9"
              }
            ]
          }
        }
        "#;

        let response: PositionsResponse = serde_json::from_str(json).unwrap();
        let positions = response.into_positions();
        let position = &positions.filled_positions[0];

        assert_eq!(position.factory_market_id(), Some(303));
        assert_eq!(position.redeemable(), Some(true));
        assert_eq!(position.resolved(), Some(true));
        assert_eq!(position.lots_hint(), Some(9));
    }

    #[test]
    fn parses_redeemable_positions_from_plain_array_with_casing_drift() {
        let json = r#"
        [
          {
            "Redeemable": "true",
            "Position": {
              "FactoryMarketID": "404",
              "OrderBookMarketId": 505,
              "MarketStatus": "resolved",
              "YesBalance": "7",
              "NoBalance": "2"
            }
          }
        ]
        "#;

        let response: RedeemablePositionsResponse = serde_json::from_str(json).unwrap();
        let positions = response.into_positions();
        let position: &IndexerRedeemablePosition = &positions[0];

        assert_eq!(position.factory_market_id(), Some(404));
        assert_eq!(position.orderbook_market_id(), Some(505));
        assert_eq!(position.redeemable(), Some(true));
        assert_eq!(position.resolved(), Some(true));
        assert_eq!(position.lots_hint(), Some(9));
    }

    #[test]
    fn parses_redeemable_positions_from_paginated_payload() {
        let json = r#"
        {
          "data": [
            {
              "market": {
                "id": 606,
                "status": "resolved"
              },
              "claimable": true,
              "lots": "11"
            }
          ]
        }
        "#;

        let response: RedeemablePositionsResponse = serde_json::from_str(json).unwrap();
        let positions = response.into_positions();
        let position = &positions[0];

        assert_eq!(position.factory_market_id(), Some(606));
        assert_eq!(position.redeemable(), Some(true));
        assert_eq!(position.resolved(), Some(true));
        assert_eq!(position.lots_hint(), Some(11));
    }
}
