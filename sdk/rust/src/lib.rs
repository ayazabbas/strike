//! # Strike SDK
//!
//! Rust SDK for [Strike](https://github.com/ayazabbas/strike) prediction markets
//! on BNB Chain.
//!
//! Strike is a fully on-chain prediction market protocol using Frequent Batch
//! Auctions (FBA) for fair price discovery. Traders buy and sell binary outcome
//! tokens (YES/NO) on whether an asset's price will be above or below a strike
//! price at expiry.
//!
//! ## Quick Start
//!
//! ```rust,no_run
//! use strike_sdk::prelude::*;
//!
//! # async fn example() -> strike_sdk::error::Result<()> {
//! // Read-only client
//! let client = StrikeClient::new(StrikeConfig::bsc_testnet()).build()?;
//! let markets = client.indexer().get_markets().await?;
//!
//! // Trading client (with wallet)
//! let client = StrikeClient::new(StrikeConfig::bsc_testnet())
//!     .with_private_key("0x...")
//!     .build()?;
//!
//! // Approve USDT spending
//! client.vault().approve_usdt().await?;
//!
//! // Place orders
//! let orders = client.orders().place(1, &[
//!     OrderParam::bid(50, 1000),
//!     OrderParam::ask(60, 1000),
//! ]).await?;
//! # Ok(())
//! # }
//! ```
//!
//! ## Key Concepts
//!
//! - **LOT_SIZE** = 1e16 wei ($0.01 per lot)
//! - **Ticks** are 1–99, representing $0.01–$0.99 probability
//! - **4-sided orderbook**: Bid, Ask, SellYes, SellNo
//! - **Batch auctions**: Orders are collected and cleared in batches
//! - All fills pay the clearing tick, not the limit tick
//!
//! ## Features
//!
//! - `nonce-manager` (default) — shared nonce management via [`NonceSender`](nonce::NonceSender)

pub mod chain;
pub mod client;
pub mod config;
#[allow(clippy::too_many_arguments)]
pub mod contracts;
pub mod error;
pub mod events;
pub mod indexer;
pub mod nonce;
pub mod types;

/// Convenient re-exports for common usage.
pub mod prelude {
    pub use crate::client::StrikeClient;
    pub use crate::config::{ContractAddresses, StrikeConfig};
    pub use crate::error::{Result, StrikeError};
    pub use crate::types::*;
}
