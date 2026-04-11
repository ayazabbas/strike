//! On-chain market state reads.

use alloy::primitives::U256;
use alloy::providers::DynProvider;

use crate::config::StrikeConfig;
use crate::contracts::MarketFactory;
use crate::error::{Result, StrikeError};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct MarketMeta {
    pub factory_market_id: u64,
    pub orderbook_market_id: u64,
    pub state: u8,
    pub outcome_yes: bool,
    pub use_internal_positions: bool,
}

/// Client for reading on-chain market state.
pub struct MarketsClient<'a> {
    provider: &'a DynProvider,
    config: &'a StrikeConfig,
}

impl<'a> MarketsClient<'a> {
    pub(crate) fn new(provider: &'a DynProvider, config: &'a StrikeConfig) -> Self {
        Self { provider, config }
    }

    fn factory(&self) -> MarketFactory::MarketFactoryInstance<&DynProvider> {
        MarketFactory::new(self.config.addresses.market_factory, self.provider)
    }

    /// Get the number of active markets.
    pub async fn active_market_count(&self) -> Result<u64> {
        let count = self
            .factory()
            .getActiveMarketCount()
            .call()
            .await
            .map_err(|e| StrikeError::Contract(e.to_string()))?;
        Ok(count.to::<u64>())
    }

    /// Get the next factory market ID (total markets created).
    pub async fn next_market_id(&self) -> Result<u64> {
        let id = self
            .factory()
            .nextFactoryMarketId()
            .call()
            .await
            .map_err(|e| StrikeError::Contract(e.to_string()))?;
        Ok(id.to::<u64>())
    }

    /// Get the next order ID from the OrderBook.
    pub async fn next_order_id(&self) -> Result<u64> {
        let ob = crate::contracts::OrderBook::new(self.config.addresses.order_book, self.provider);
        let id = ob
            .nextOrderId()
            .call()
            .await
            .map_err(|e| StrikeError::Contract(e.to_string()))?;
        Ok(id)
    }

    /// Get on-chain metadata for a factory market ID.
    pub async fn market_meta(&self, factory_market_id: u64) -> Result<MarketMeta> {
        let meta = self
            .factory()
            .marketMeta(U256::from(factory_market_id))
            .call()
            .await
            .map_err(|e| StrikeError::Contract(e.to_string()))?;

        Ok(MarketMeta {
            factory_market_id,
            orderbook_market_id: meta.orderBookMarketId.to::<u64>(),
            state: meta.state,
            outcome_yes: meta.outcomeYes,
            use_internal_positions: meta.useInternalPositions,
        })
    }
}
