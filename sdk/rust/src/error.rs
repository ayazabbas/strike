//! Error types for the Strike SDK.

use std::fmt;

/// Errors returned by the Strike SDK.
#[derive(Debug)]
pub enum StrikeError {
    /// RPC transport error.
    Rpc(alloy::transports::TransportError),
    /// Contract call reverted with a reason.
    Contract(String),
    /// Nonce mismatch (nonce-manager feature).
    NonceMismatch { expected: u64, got: u64 },
    /// Market is not in an active state.
    MarketNotActive(u64),
    /// Insufficient USDT balance for the operation.
    InsufficientBalance,
    /// Configuration error.
    Config(String),
    /// No wallet configured (tried to send a transaction in read-only mode).
    NoWallet,
    /// WebSocket connection error.
    WebSocket(String),
    /// Indexer API error.
    Indexer(String),
    /// Generic error wrapper.
    Other(eyre::Report),
}

impl fmt::Display for StrikeError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Rpc(e) => write!(f, "RPC error: {e}"),
            Self::Contract(reason) => write!(f, "contract reverted: {reason}"),
            Self::NonceMismatch { expected, got } => {
                write!(f, "nonce mismatch: expected {expected}, got {got}")
            }
            Self::MarketNotActive(id) => write!(f, "market {id} is not active"),
            Self::InsufficientBalance => write!(f, "insufficient USDT balance"),
            Self::Config(msg) => write!(f, "config error: {msg}"),
            Self::NoWallet => write!(f, "no wallet configured — cannot send transactions"),
            Self::WebSocket(msg) => write!(f, "WebSocket error: {msg}"),
            Self::Indexer(msg) => write!(f, "indexer error: {msg}"),
            Self::Other(e) => write!(f, "{e}"),
        }
    }
}

impl std::error::Error for StrikeError {}

impl From<alloy::transports::TransportError> for StrikeError {
    fn from(e: alloy::transports::TransportError) -> Self {
        Self::Rpc(e)
    }
}

impl From<eyre::Report> for StrikeError {
    fn from(e: eyre::Report) -> Self {
        Self::Other(e)
    }
}

impl From<reqwest::Error> for StrikeError {
    fn from(e: reqwest::Error) -> Self {
        Self::Indexer(e.to_string())
    }
}

/// Result type alias for Strike SDK operations.
pub type Result<T> = std::result::Result<T, StrikeError>;
