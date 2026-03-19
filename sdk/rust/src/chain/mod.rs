//! On-chain contract interaction clients.

pub mod markets;
pub mod orders;
pub mod redeem;
pub mod tokens;
pub mod vault;

use alloy::network::Ethereum;
use alloy::providers::{DynProvider, PendingTransactionBuilder, Provider};
use alloy::rpc::types::TransactionRequest;
use std::sync::Arc;
use tokio::sync::Mutex;

use crate::error::{Result, StrikeError};
use crate::nonce::NonceSender;

/// Pending transaction type alias.
pub(crate) type PendingTx = PendingTransactionBuilder<Ethereum>;

/// Send a transaction, routing through NonceSender if available.
///
/// When `nonce_sender` is `Some`, the transaction is stamped with a sequential
/// nonce and sent via the shared NonceSender. Otherwise, it goes through the
/// provider's default send path.
pub(crate) async fn send_tx(
    provider: &DynProvider,
    nonce_sender: &Option<Arc<Mutex<NonceSender>>>,
    tx: TransactionRequest,
) -> Result<PendingTx> {
    if let Some(ns) = nonce_sender {
        ns.lock().await.send(tx).await.map_err(StrikeError::from)
    } else {
        provider
            .send_transaction(tx)
            .await
            .map_err(|e| StrikeError::Contract(e.to_string()))
    }
}
