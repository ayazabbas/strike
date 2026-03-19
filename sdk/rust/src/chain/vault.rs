//! USDT approval and balance helpers for the Vault contract.

use alloy::primitives::{Address, Bytes, U256};
use alloy::providers::DynProvider;
use alloy::rpc::types::TransactionRequest;
use alloy::sol_types::SolCall;
use std::sync::Arc;
use tokio::sync::Mutex;
use tracing::info;

use crate::chain::send_tx;
use crate::config::StrikeConfig;
use crate::contracts::MockUSDT;
use crate::error::{Result, StrikeError};
use crate::nonce::NonceSender;

/// Client for vault-related operations (USDT approval, balance checks).
pub struct VaultClient<'a> {
    provider: &'a DynProvider,
    signer_addr: Option<Address>,
    config: &'a StrikeConfig,
    nonce_sender: Option<Arc<Mutex<NonceSender>>>,
}

impl<'a> VaultClient<'a> {
    pub(crate) fn new(
        provider: &'a DynProvider,
        signer_addr: Option<Address>,
        config: &'a StrikeConfig,
        nonce_sender: Option<Arc<Mutex<NonceSender>>>,
    ) -> Self {
        Self {
            provider,
            signer_addr,
            config,
            nonce_sender,
        }
    }

    fn require_wallet(&self) -> Result<Address> {
        self.signer_addr.ok_or(StrikeError::NoWallet)
    }

    /// Approve the Vault contract to spend USDT on behalf of the signer.
    ///
    /// Idempotent: skips if already max-approved (allowance >= U256::MAX / 2).
    pub async fn approve_usdt(&self) -> Result<()> {
        let signer = self.require_wallet()?;
        let usdt = MockUSDT::new(self.config.addresses.usdt, self.provider);
        let vault = self.config.addresses.vault;

        if let Ok(current) = usdt.allowance(signer, vault).call().await {
            if current >= (U256::MAX >> 1) {
                info!("vault already approved for USDT — skipping");
                return Ok(());
            }
        }

        info!("approving vault for max USDT spend...");

        let calldata = MockUSDT::approveCall {
            spender: vault,
            value: U256::MAX,
        }
        .abi_encode();

        let mut tx = TransactionRequest::default()
            .to(self.config.addresses.usdt)
            .input(Bytes::from(calldata).into());
        tx.gas = Some(100_000);

        let pending = send_tx(self.provider, &self.nonce_sender, tx).await?;
        let receipt = pending
            .get_receipt()
            .await
            .map_err(|e| StrikeError::Contract(e.to_string()))?;
        info!(tx = %receipt.transaction_hash, "vault approved for USDT");
        Ok(())
    }

    /// Get the USDT balance of an address.
    pub async fn usdt_balance(&self, address: Address) -> Result<U256> {
        let usdt = MockUSDT::new(self.config.addresses.usdt, self.provider);
        usdt.balanceOf(address)
            .call()
            .await
            .map_err(|e| StrikeError::Contract(e.to_string()))
    }

    /// Get the current USDT allowance for the Vault contract.
    pub async fn usdt_allowance(&self, owner: Address) -> Result<U256> {
        let usdt = MockUSDT::new(self.config.addresses.usdt, self.provider);
        usdt.allowance(owner, self.config.addresses.vault)
            .call()
            .await
            .map_err(|e| StrikeError::Contract(e.to_string()))
    }
}
