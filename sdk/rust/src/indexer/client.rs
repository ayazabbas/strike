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

    /// Fetch all markets from the indexer (defaults to active only).
    pub async fn get_markets(&self) -> Result<Vec<Market>> {
        self.get_markets_by_status(None).await
    }

    /// Fetch only active markets (status == "active").
    pub async fn get_active_markets(&self) -> Result<Vec<Market>> {
        self.get_markets_by_status(Some("active")).await
    }

    /// Fetch resolved markets, paginating through all results.
    pub async fn get_resolved_markets(&self) -> Result<Vec<Market>> {
        self.get_markets_by_status(Some("resolved")).await
    }

    /// Fetch markets with an optional status filter, handling pagination.
    async fn get_markets_by_status(&self, status: Option<&str>) -> Result<Vec<Market>> {
        let mut all_markets = Vec::new();
        let limit = 500;
        let mut offset = 0;

        loop {
            let mut url = format!(
                "{}/markets?limit={}&offset={}",
                self.base_url, limit, offset
            );
            if let Some(s) = status {
                url.push_str(&format!("&status={}", s));
            }

            let resp: MarketsResponse = self
                .http
                .get(&url)
                .send()
                .await?
                .json()
                .await
                .map_err(|e| StrikeError::Indexer(e.to_string()))?;

            let count = resp.data.len();
            all_markets.extend(resp.data);

            // If we got fewer than limit, we've reached the end
            if count < limit {
                break;
            }
            offset += limit;
        }

        Ok(all_markets)
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
        Ok(resp.open_orders.into_vec())
    }
}
