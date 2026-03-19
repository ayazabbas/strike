//! Core SDK types: Side, OrderType, OrderParam, and event types.

use alloy::primitives::U256;
use serde::{Deserialize, Serialize};

use crate::contracts::OrderBook;

/// LOT_SIZE = 1e16 wei = $0.01 per lot.
pub const LOT_SIZE: u64 = 10_000_000_000_000_000;

/// Order side on the 4-sided orderbook.
///
/// - `Bid` / `Ask` — standard buy/sell with USDT collateral
/// - `SellYes` / `SellNo` — sell existing outcome tokens back into the book
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[repr(u8)]
pub enum Side {
    Bid = 0,
    Ask = 1,
    SellYes = 2,
    SellNo = 3,
}

impl From<Side> for u8 {
    fn from(s: Side) -> u8 {
        s as u8
    }
}

impl TryFrom<u8> for Side {
    type Error = &'static str;
    fn try_from(v: u8) -> Result<Self, Self::Error> {
        match v {
            0 => Ok(Self::Bid),
            1 => Ok(Self::Ask),
            2 => Ok(Self::SellYes),
            3 => Ok(Self::SellNo),
            _ => Err("invalid side value (must be 0-3)"),
        }
    }
}

/// Order type: Good-Til-Batch or Good-Til-Cancelled.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[repr(u8)]
pub enum OrderType {
    /// Expires at end of current batch if unfilled.
    GoodTilBatch = 0,
    /// Rolls unfilled remainder to the next batch.
    GoodTilCancelled = 1,
}

impl From<OrderType> for u8 {
    fn from(o: OrderType) -> u8 {
        o as u8
    }
}

/// Parameters for placing a single order.
///
/// Use the convenience constructors [`OrderParam::bid`], [`OrderParam::ask`],
/// [`OrderParam::sell_yes`], [`OrderParam::sell_no`] for common cases.
#[derive(Debug, Clone, Copy)]
pub struct OrderParam {
    /// Order side (Bid, Ask, SellYes, SellNo).
    pub side: Side,
    /// Order type (GoodTilBatch or GoodTilCancelled).
    pub order_type: OrderType,
    /// Price tick (1–99), representing $0.01 to $0.99 probability.
    pub tick: u8,
    /// Number of lots. Each lot = $0.01 (LOT_SIZE = 1e16 wei).
    pub lots: u64,
}

impl OrderParam {
    /// Create a new order parameter.
    pub fn new(side: Side, order_type: OrderType, tick: u8, lots: u64) -> Self {
        Self {
            side,
            order_type,
            tick,
            lots,
        }
    }

    /// GTC bid at `tick` for `lots`.
    pub fn bid(tick: u8, lots: u64) -> Self {
        Self::new(Side::Bid, OrderType::GoodTilCancelled, tick, lots)
    }

    /// GTC ask at `tick` for `lots`.
    pub fn ask(tick: u8, lots: u64) -> Self {
        Self::new(Side::Ask, OrderType::GoodTilCancelled, tick, lots)
    }

    /// GTC sell-yes at `tick` for `lots`.
    pub fn sell_yes(tick: u8, lots: u64) -> Self {
        Self::new(Side::SellYes, OrderType::GoodTilCancelled, tick, lots)
    }

    /// GTC sell-no at `tick` for `lots`.
    pub fn sell_no(tick: u8, lots: u64) -> Self {
        Self::new(Side::SellNo, OrderType::GoodTilCancelled, tick, lots)
    }

    /// Convert to the on-chain `OrderBook::OrderParam` struct.
    pub(crate) fn to_contract_param(self) -> OrderBook::OrderParam {
        OrderBook::OrderParam {
            side: self.side as u8,
            orderType: self.order_type as u8,
            tick: self.tick,
            lots: self.lots,
        }
    }
}

/// An order that was placed on-chain, with its assigned ID.
#[derive(Debug, Clone)]
pub struct PlacedOrder {
    /// On-chain order ID (from OrderPlaced event).
    pub order_id: U256,
    /// The side this order was placed on.
    pub side: Side,
    /// Market ID.
    pub market_id: u64,
}

/// On-chain event types emitted by Strike contracts.
#[derive(Debug, Clone)]
pub enum StrikeEvent {
    /// A new market was created.
    MarketCreated {
        market_id: u64,
        price_id: [u8; 32],
        strike_price: i64,
        expiry_time: u64,
    },
    /// A batch was cleared (auction resolved).
    BatchCleared {
        market_id: u64,
        batch_id: u64,
        clearing_tick: u64,
        matched_lots: u64,
    },
    /// An order was settled after batch clearing.
    OrderSettled {
        order_id: U256,
        owner: alloy::primitives::Address,
        filled_lots: u64,
    },
    /// A GTC order was auto-cancelled.
    GtcAutoCancelled {
        order_id: U256,
        owner: alloy::primitives::Address,
    },
    /// An order was placed.
    OrderPlaced {
        order_id: U256,
        market_id: u64,
        side: u8,
        tick: u8,
        lots: u64,
        owner: alloy::primitives::Address,
    },
    /// An order was cancelled.
    OrderCancelled {
        order_id: U256,
        market_id: u64,
        owner: alloy::primitives::Address,
    },
}
