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
/// BSC mainnet minimum gas price (5 Gwei = 5_000_000_000 wei).
const BSC_MIN_GAS_PRICE: u128 = 5_000_000_000;

pub struct NonceSender {
    provider: DynProvider,
    signer_addr: Address,
    nonce: u64,
    min_gas_price: Option<u128>,
}

impl NonceSender {
    /// Create a new NonceSender, fetching the current nonce from chain.
    pub async fn new(provider: DynProvider, signer_addr: Address) -> Result<Self> {
        let nonce = provider
            .get_transaction_count(signer_addr)
            .await
            .wrap_err("failed to get initial nonce")?;
        info!(nonce, "NonceSender initialized");
        Ok(Self {
            provider,
            signer_addr,
            nonce,
            min_gas_price: None,
        })
    }

    /// Set a minimum gas price floor (e.g. for BSC mainnet).
    pub fn with_min_gas_price(mut self, min: u128) -> Self {
        self.min_gas_price = Some(min);
        self
    }

    /// Set BSC mainnet gas price floor (5 Gwei).
    pub fn with_bsc_gas_price(self) -> Self {
        self.with_min_gas_price(BSC_MIN_GAS_PRICE)
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

    /// Send a transaction, stamping it with the next nonce.
    ///
    /// On nonce-related errors: syncs from chain and retries once.
    /// The returned [`PendingTx`] can be `.await`ed for the receipt
    /// **after** releasing the Mutex lock.
    /// Apply gas price floor to a transaction request.
    fn apply_gas_price(&self, tx: TransactionRequest) -> TransactionRequest {
        if let Some(min) = self.min_gas_price {
            tx.gas_price(min)
        } else {
            tx
        }
    }

    pub async fn send(&mut self, tx: TransactionRequest) -> Result<PendingTx> {
        let attempt = self.apply_gas_price(tx.clone().nonce(self.nonce));
        match self.provider.send_transaction(attempt).await {
            Ok(pending) => {
                self.nonce += 1;
                Ok(pending)
            }
            Err(e) => {
                let err_str = e.to_string();
                if err_str.contains("nonce")
                    || err_str.contains("replacement")
                    || err_str.contains("already known")
                {
                    warn!(nonce = self.nonce, err = %e, "nonce error — syncing and retrying");
                    self.sync().await?;
                    let retry = self.apply_gas_price(tx.nonce(self.nonce));
                    let pending = self
                        .provider
                        .send_transaction(retry)
                        .await
                        .wrap_err("retry after nonce sync failed")?;
                    self.nonce += 1;
                    Ok(pending)
                } else {
                    Err(e.into())
                }
            }
        }
    }
}
