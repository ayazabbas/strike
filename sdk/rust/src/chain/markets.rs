//! On-chain market state reads.

use alloy::providers::DynProvider;

use crate::config::StrikeConfig;
use crate::contracts::MarketFactory;
use crate::error::{Result, StrikeError};

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
}
