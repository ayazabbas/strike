//! StrikeClient — the main entry point for the SDK.
//!
//! Supports both read-only mode (no wallet) and trading mode (with wallet).
//!
//! # Examples
//!
//! ```no_run
//! use strike_sdk::prelude::*;
//!
//! # async fn example() -> strike_sdk::error::Result<()> {
//! // Read-only
//! let client = StrikeClient::new(StrikeConfig::bsc_testnet()).build()?;
//!
//! // With wallet
//! let client = StrikeClient::new(StrikeConfig::bsc_testnet())
//!     .with_private_key("0x...")
//!     .build()?;
//! # Ok(())
//! # }
//! ```

use alloy::primitives::Address;
use alloy::providers::{DynProvider, Provider, ProviderBuilder};
use alloy::signers::local::PrivateKeySigner;
use std::sync::Arc;
use tokio::sync::Mutex;

use crate::chain::markets::MarketsClient;
use crate::chain::orders::OrdersClient;
use crate::chain::redeem::RedeemClient;
use crate::chain::tokens::TokensClient;
use crate::chain::vault::VaultClient;
use crate::config::StrikeConfig;
use crate::error::{Result, StrikeError};
use crate::events::subscribe::EventStream;
use crate::indexer::client::IndexerClient;
use crate::nonce::NonceSender;

/// Shared nonce sender reference type.
pub type NonceSenderRef = Option<Arc<Mutex<NonceSender>>>;

/// Builder for constructing a [`StrikeClient`].
pub struct StrikeClientBuilder {
    config: StrikeConfig,
    rpc_url: Option<String>,
    wss_url: Option<String>,
    indexer_url: Option<String>,
    private_key: Option<String>,
}

impl StrikeClientBuilder {
    /// Override the RPC URL from the config.
    pub fn with_rpc(mut self, url: &str) -> Self {
        self.rpc_url = Some(url.to_string());
        self
    }

    /// Override the WSS URL from the config.
    pub fn with_wss(mut self, url: &str) -> Self {
        self.wss_url = Some(url.to_string());
        self
    }

    /// Override the indexer URL from the config.
    pub fn with_indexer(mut self, url: &str) -> Self {
        self.indexer_url = Some(url.to_string());
        self
    }

    /// Set a private key for signing transactions.
    ///
    /// Without this, the client operates in read-only mode — event subscriptions
    /// and queries work, but order placement/cancellation will fail.
    pub fn with_private_key(mut self, key: &str) -> Self {
        self.private_key = Some(key.to_string());
        self
    }

    /// Build the client.
    ///
    /// Connects to the RPC endpoint and optionally configures a signing wallet.
    pub fn build(self) -> Result<StrikeClient> {
        let rpc_url = self.rpc_url.unwrap_or(self.config.rpc_url.clone());
        let wss_url = self.wss_url.unwrap_or(self.config.wss_url.clone());
        let indexer_url = self.indexer_url.unwrap_or(self.config.indexer_url.clone());

        if rpc_url.is_empty() {
            return Err(StrikeError::Config("RPC URL is required".into()));
        }

        let rpc_parsed: reqwest::Url = rpc_url
            .parse()
            .map_err(|e| StrikeError::Config(format!("invalid RPC URL: {e}")))?;

        let (provider, signer_addr) = if let Some(key) = &self.private_key {
            let signer: PrivateKeySigner = key
                .parse()
                .map_err(|e| StrikeError::Config(format!("invalid private key: {e}")))?;
            let addr = signer.address();
            let wallet = alloy::network::EthereumWallet::from(signer);
            let p = ProviderBuilder::new()
                .wallet(wallet)
                .connect_http(rpc_parsed);
            (DynProvider::new(p), Some(addr))
        } else {
            let p = ProviderBuilder::new().connect_http(rpc_parsed);
            (DynProvider::new(p), None)
        };

        Ok(StrikeClient {
            provider,
            config: self.config,
            signer_addr,
            wss_url,
            indexer_url,
            nonce_sender: None,
        })
    }
}

/// The main Strike SDK client.
///
/// Provides access to all protocol operations through typed sub-clients:
/// - [`orders()`](Self::orders) — place, cancel, replace orders
/// - [`vault()`](Self::vault) — USDT approval and balance
/// - [`redeem()`](Self::redeem) — redeem outcome tokens
/// - [`tokens()`](Self::tokens) — outcome token queries
/// - [`markets()`](Self::markets) — on-chain market reads
/// - [`events()`](Self::events) — WSS event subscriptions
/// - [`indexer()`](Self::indexer) — REST indexer client
pub struct StrikeClient {
    provider: DynProvider,
    config: StrikeConfig,
    signer_addr: Option<Address>,
    wss_url: String,
    indexer_url: String,
    nonce_sender: NonceSenderRef,
}

impl Clone for StrikeClient {
    fn clone(&self) -> Self {
        Self {
            provider: self.provider.clone(),
            config: self.config.clone(),
            signer_addr: self.signer_addr,
            wss_url: self.wss_url.clone(),
            indexer_url: self.indexer_url.clone(),
            nonce_sender: self.nonce_sender.clone(),
        }
    }
}

impl StrikeClient {
    /// Create a new client builder with the given config.
    #[allow(clippy::new_ret_no_self)]
    pub fn new(config: StrikeConfig) -> StrikeClientBuilder {
        StrikeClientBuilder {
            config,
            rpc_url: None,
            wss_url: None,
            indexer_url: None,
            private_key: None,
        }
    }

    /// Initialize the shared nonce manager.
    ///
    /// Call this once at startup before sending any transactions. All subsequent
    /// transaction sends (orders, vault approval, redemptions) will route through
    /// the NonceSender to avoid nonce collisions.
    ///
    /// The nonce manager is shared across clones of this client via `Arc`.
    pub async fn init_nonce_sender(&mut self) -> Result<()> {
        let signer = self.signer_addr.ok_or(StrikeError::NoWallet)?;
        let ns = NonceSender::new(self.provider.clone(), signer)
            .await
            .map_err(StrikeError::from)?;
        self.nonce_sender = Some(Arc::new(Mutex::new(ns)));
        Ok(())
    }

    /// Get a reference to the shared nonce sender, if initialized.
    pub fn nonce_sender(&self) -> NonceSenderRef {
        self.nonce_sender.clone()
    }

    /// Order placement, cancellation, and replacement.
    pub fn orders(&self) -> OrdersClient<'_> {
        OrdersClient::new(
            &self.provider,
            self.signer_addr,
            &self.config,
            self.nonce_sender.clone(),
        )
    }

    /// USDT vault approval and balance queries.
    pub fn vault(&self) -> VaultClient<'_> {
        VaultClient::new(
            &self.provider,
            self.signer_addr,
            &self.config,
            self.nonce_sender.clone(),
        )
    }

    /// Outcome token redemption.
    pub fn redeem(&self) -> RedeemClient<'_> {
        RedeemClient::new(
            &self.provider,
            self.signer_addr,
            &self.config,
            self.nonce_sender.clone(),
        )
    }

    /// Outcome token balance and approval queries.
    pub fn tokens(&self) -> TokensClient<'_> {
        TokensClient::new(&self.provider, self.signer_addr, &self.config)
    }

    /// On-chain market metadata reads.
    pub fn markets(&self) -> MarketsClient<'_> {
        MarketsClient::new(&self.provider, &self.config)
    }

    /// Subscribe to on-chain events via WSS with auto-reconnect.
    ///
    /// Returns an [`EventStream`] that yields [`StrikeEvent`](crate::types::StrikeEvent) items.
    pub async fn events(&self) -> Result<EventStream> {
        EventStream::connect(
            &self.wss_url,
            self.config.addresses.market_factory,
            self.config.addresses.batch_auction,
        )
        .await
    }

    /// Scan historical events from chain logs.
    ///
    /// Finds orders placed by `owner` that haven't been cancelled.
    pub async fn scan_orders(
        &self,
        from_block: u64,
        owner: Address,
    ) -> Result<
        std::collections::HashMap<
            u64,
            (Vec<alloy::primitives::U256>, Vec<alloy::primitives::U256>),
        >,
    > {
        crate::events::scan::scan_live_orders(
            &self.provider,
            self.config.addresses.order_book,
            owner,
            from_block,
        )
        .await
    }

    /// REST indexer client for startup snapshots.
    pub fn indexer(&self) -> IndexerClient {
        IndexerClient::new(&self.indexer_url)
    }

    /// Get the current block number.
    pub async fn block_number(&self) -> Result<u64> {
        self.provider
            .get_block_number()
            .await
            .map_err(StrikeError::Rpc)
    }

    /// The signer address, if a wallet is configured.
    pub fn signer_address(&self) -> Option<Address> {
        self.signer_addr
    }

    /// The active config.
    pub fn config(&self) -> &StrikeConfig {
        &self.config
    }

    /// The underlying provider (for advanced usage).
    pub fn provider(&self) -> &DynProvider {
        &self.provider
    }
}
