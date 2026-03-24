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

    /// Enforce BSC minimum gas price on a transaction request.
    ///
    /// BSC uses legacy (non-EIP-1559) transactions. When no gas fields are set,
    /// alloy auto-fills at the provider level — which can result in values below
    /// the RPC's minimum. We force legacy `gas_price` to at least 0.05 gwei and
    /// clear EIP-1559 fields to prevent alloy from choosing type-2 transactions.
    fn apply_gas_floor(tx: TransactionRequest) -> TransactionRequest {
        let mut tx = tx;
        // Force legacy gas price — BSC doesn't use EIP-1559
        let gp = tx.gas_price.unwrap_or(BSC_MIN_GAS_PRICE);
        tx.gas_price = Some(if gp < BSC_MIN_GAS_PRICE { BSC_MIN_GAS_PRICE } else { gp });
        // Clear EIP-1559 fields so alloy sends a type-0 (legacy) tx
        tx.max_fee_per_gas = None;
        tx.max_priority_fee_per_gas = None;
        tx
    }

    /// Send a transaction, stamping it with the next nonce.
    ///
    /// On nonce-related errors: syncs from chain and retries once.
    /// The returned [`PendingTx`] can be `.await`ed for the receipt
    /// **after** releasing the Mutex lock.
    pub async fn send(&mut self, tx: TransactionRequest) -> Result<PendingTx> {
        let tx = Self::apply_gas_floor(tx);
        let attempt = tx.clone().nonce(self.nonce);
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
                    let retry = tx.nonce(self.nonce);
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
