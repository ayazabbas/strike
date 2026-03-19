//! HTTP client for the Strike indexer REST API.

use crate::error::{Result, StrikeError};
use crate::indexer::types::*;

/// Client for the Strike indexer REST API.
///
/// Used for bootstrap/snapshot reads. Live data comes from on-chain WSS.
pub struct IndexerClient {
    base_url: String,
    http: reqwest::Client,
}

impl IndexerClient {
    pub(crate) fn new(base_url: &str) -> Self {
        Self {
            base_url: base_url.trim_end_matches('/').to_string(),
            http: reqwest::Client::new(),
        }
    }

    /// Fetch all markets from the indexer.
    pub async fn get_markets(&self) -> Result<Vec<Market>> {
        let url = format!("{}/markets", self.base_url);
        let resp: MarketsResponse = self
            .http
            .get(&url)
            .send()
            .await?
            .json()
            .await
            .map_err(|e| StrikeError::Indexer(e.to_string()))?;
        Ok(resp.markets)
    }

    /// Fetch only active markets (status == "active").
    pub async fn get_active_markets(&self) -> Result<Vec<Market>> {
        let markets = self.get_markets().await?;
        Ok(markets
            .into_iter()
            .filter(|m| m.status == "active")
            .collect())
    }

    /// Fetch the orderbook snapshot for a market.
    pub async fn get_orderbook(&self, market_id: u64) -> Result<OrderbookSnapshot> {
        let url = format!("{}/markets/{}/orderbook", self.base_url, market_id);
        let resp: OrderbookSnapshot = self
            .http
            .get(&url)
            .send()
            .await?
            .json()
            .await
            .map_err(|e| StrikeError::Indexer(e.to_string()))?;
        Ok(resp)
    }

    /// Fetch open orders for a given address.
    pub async fn get_open_orders(&self, address: &str) -> Result<Vec<IndexerOrder>> {
        let url = format!("{}/positions/{}", self.base_url, address);
        let resp: PositionsResponse = self
            .http
            .get(&url)
            .send()
            .await?
            .json()
            .await
            .map_err(|e| StrikeError::Indexer(e.to_string()))?;
        Ok(resp.open_orders)
    }
}
