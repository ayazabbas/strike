//! Shared nonce manager for sequential transaction sends.
//!
//! Enabled by the `nonce-manager` feature (on by default). All transaction sends
//! go through [`NonceSender`] to avoid nonce collisions when multiple operations
//! are in flight.

use alloy::network::Ethereum;
use alloy::primitives::Address;
use alloy::providers::{DynProvider, PendingTransactionBuilder, Provider};
use alloy::rpc::types::TransactionRequest;
use eyre::{Result, WrapErr};
use tracing::{info, warn};

use crate::config::TxConfig;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum SendErrorKind {
    NonceDrift,
    PendingConflict,
    Other,
}

fn classify_send_error(err: &str) -> SendErrorKind {
    let err = err.to_ascii_lowercase();

    if err.contains("replacement transaction underpriced") || err.contains("already known") {
        return SendErrorKind::PendingConflict;
    }

    if err.contains("nonce") {
        return SendErrorKind::NonceDrift;
    }

    SendErrorKind::Other
}

/// BSC RPC providers enforce a minimum gas price of 0.05 gwei.
const BSC_MIN_GAS_PRICE: u128 = 50_000_000; // 0.05 gwei in wei

/// Concrete pending tx type.
pub type PendingTx = PendingTransactionBuilder<Ethereum>;

/// Shared nonce manager — all tx sends go through this to avoid nonce collisions.
///
/// Wraps a type-erased provider ([`DynProvider`]) so it's a plain concrete type.
/// Callers should wrap this in `Arc<Mutex<NonceSender>>` and lock before each send.
///
/// # Auto-recovery
///
/// On nonce-related errors, the sender automatically syncs the nonce from chain
/// and retries once before returning an error.
pub struct NonceSender {
    provider: DynProvider,
    signer_addr: Address,
    nonce: u64,
    tx_config: TxConfig,
}

impl NonceSender {
    /// Create a new NonceSender, fetching the current nonce from chain.
    pub async fn new(
        provider: DynProvider,
        signer_addr: Address,
        tx_config: TxConfig,
    ) -> Result<Self> {
        let nonce = provider
            .get_transaction_count(signer_addr)
            .await
            .wrap_err("failed to get initial nonce")?;
        info!(
            nonce,
            receipt_poll_interval_ms = tx_config.receipt_poll_interval_ms,
            gas_price_multiplier_bps = tx_config.gas_price_multiplier_bps,
            max_gas_price_wei = ?tx_config.max_gas_price_wei,
            "NonceSender initialized"
        );
        Ok(Self {
            provider,
            signer_addr,
            nonce,
            tx_config,
        })
    }

    /// Re-fetch nonce from chain (use after errors).
    pub async fn sync(&mut self) -> Result<()> {
        let n = self
            .provider
            .get_transaction_count(self.signer_addr)
            .await
            .wrap_err("failed to sync nonce")?;
        info!(
            old_nonce = self.nonce,
            new_nonce = n,
            "nonce synced from chain"
        );
        self.nonce = n;
        Ok(())
    }

    /// Current local nonce value.
    pub fn current_nonce(&self) -> u64 {
        self.nonce
    }

    /// Choose a competitive legacy gas price while preserving a hard floor.
    async fn resolve_gas_price(&self, explicit_gas_price: Option<u128>) -> Result<u128> {
        let configured_multiplier_bps = self.tx_config.gas_price_multiplier_bps.max(10_000);
        let live_gas_price = self
            .provider
            .get_gas_price()
            .await
            .wrap_err("failed to fetch live gas price")?;

        let bumped_live_gas_price = live_gas_price
            .saturating_mul(configured_multiplier_bps as u128)
            .saturating_add(9_999)
            / 10_000;

        let mut chosen_gas_price = explicit_gas_price
            .unwrap_or(bumped_live_gas_price)
            .max(BSC_MIN_GAS_PRICE);

        if let Some(max_gas_price_wei) = self.tx_config.max_gas_price_wei {
            if chosen_gas_price > max_gas_price_wei {
                warn!(
                    live_gas_price,
                    bumped_live_gas_price,
                    chosen_gas_price,
                    max_gas_price_wei,
                    "capping legacy gas price at configured maximum"
                );
                chosen_gas_price = max_gas_price_wei.max(BSC_MIN_GAS_PRICE);
            }
        }

        Ok(chosen_gas_price)
    }

    /// Enforce BSC legacy gas pricing on a transaction request.
    async fn prepare_transaction(&self, tx: TransactionRequest) -> Result<TransactionRequest> {
        let mut tx = tx;
        let gas_price = self.resolve_gas_price(tx.gas_price).await?;
        tx.gas_price = Some(gas_price);
        tx.max_fee_per_gas = None;
        tx.max_priority_fee_per_gas = None;
        Ok(tx)
    }

    /// Send a transaction, stamping it with the next nonce.
    ///
    /// Nonce drift errors are retried once after syncing from chain. Pending
    /// mempool conflicts (for example replacement underpriced / already known)
    /// are treated conservatively: refresh local nonce state, but do not blindly
    /// resend into the same nonce lane.
    ///
    /// The returned [`PendingTx`] can be `.await`ed for the receipt
    /// **after** releasing the Mutex lock.
    pub async fn send(&mut self, tx: TransactionRequest) -> Result<PendingTx> {
        let tx = self.prepare_transaction(tx).await?;
        let attempt = tx.clone().nonce(self.nonce);
        match self.provider.send_transaction(attempt).await {
            Ok(pending) => {
                self.nonce += 1;
                Ok(pending)
            }
            Err(e) => match classify_send_error(&e.to_string()) {
                SendErrorKind::NonceDrift => {
                    warn!(nonce = self.nonce, err = %e, "nonce drift detected — syncing and retrying");
                    self.sync().await?;
                    let retry = tx.nonce(self.nonce);
                    let pending = self
                        .provider
                        .send_transaction(retry)
                        .await
                        .wrap_err("retry after nonce sync failed")?;
                    self.nonce += 1;
                    Ok(pending)
                }
                SendErrorKind::PendingConflict => {
                    warn!(nonce = self.nonce, err = %e, "pending nonce conflict detected — syncing without blind retry");
                    self.sync().await?;
                    Err(e.into())
                }
                SendErrorKind::Other => Err(e.into()),
            },
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{classify_send_error, SendErrorKind};

    #[test]
    fn classifies_nonce_drift_errors() {
        assert_eq!(
            classify_send_error("nonce too low: next nonce 12, tx nonce 11"),
            SendErrorKind::NonceDrift
        );
        assert_eq!(
            classify_send_error("invalid transaction nonce"),
            SendErrorKind::NonceDrift
        );
    }

    #[test]
    fn classifies_pending_conflicts() {
        assert_eq!(
            classify_send_error("replacement transaction underpriced"),
            SendErrorKind::PendingConflict
        );
        assert_eq!(
            classify_send_error("already known"),
            SendErrorKind::PendingConflict
        );
    }

    #[test]
    fn leaves_unrelated_errors_alone() {
        assert_eq!(
            classify_send_error("execution reverted: not enough balance"),
            SendErrorKind::Other
        );
    }
}
