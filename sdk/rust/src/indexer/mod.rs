//! REST client for the Strike indexer API.
//!
//! Used for startup snapshots — live data comes from on-chain WSS subscriptions.

pub mod client;
pub mod types;

pub use client::IndexerClient;
