//! Redemption of outcome tokens for USDT after market resolution.

use alloy::primitives::{Address, Bytes, U256};
use alloy::providers::DynProvider;
use alloy::rpc::types::TransactionRequest;
use alloy::sol_types::SolCall;
use std::sync::Arc;
use tokio::sync::Mutex;
use tracing::info;

use crate::chain::send_tx;
use crate::config::StrikeConfig;
use crate::contracts::{OutcomeToken, RedemptionContract};
use crate::error::{Result, StrikeError};
use crate::nonce::NonceSender;

/// Client for redeeming resolved market positions.
pub struct RedeemClient<'a> {
    provider: &'a DynProvider,
    signer_addr: Option<Address>,
    config: &'a StrikeConfig,
    nonce_sender: Option<Arc<Mutex<NonceSender>>>,
}

impl<'a> RedeemClient<'a> {
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

    /// Redeem outcome tokens for a resolved market.
    ///
    /// Calls `Redemption.redeem(factoryMarketId, amount)`. The contract determines
    /// the winning side and burns the tokens, returning USDT.
    pub async fn redeem(&self, market_id: u64, amount: U256) -> Result<()> {
        self.require_wallet()?;

        info!(market_id, amount = %amount, "redeeming outcome tokens");

        let calldata = RedemptionContract::redeemCall {
            factoryMarketId: U256::from(market_id),
            amount,
        }
        .abi_encode();

        let mut tx = TransactionRequest::default()
            .to(self.config.addresses.redemption)
            .input(Bytes::from(calldata).into());
        tx.gas = Some(300_000);

        let pending = send_tx(self.provider, &self.nonce_sender, tx).await?;
        let receipt = pending
            .get_receipt()
            .await
            .map_err(|e| StrikeError::Contract(e.to_string()))?;

        info!(market_id, tx = %receipt.transaction_hash, gas_used = receipt.gas_used, "redemption confirmed");
        Ok(())
    }

    /// Check balances of YES and NO tokens for a market. Returns `(yes_balance, no_balance)`.
    pub async fn balances(&self, market_id: u64, owner: Address) -> Result<(U256, U256)> {
        let ot = OutcomeToken::new(self.config.addresses.outcome_token, self.provider);
        let mid = U256::from(market_id);

        let yes_id = ot
            .yesTokenId(mid)
            .call()
            .await
            .map_err(|e| StrikeError::Contract(e.to_string()))?;
        let no_id = ot
            .noTokenId(mid)
            .call()
            .await
            .map_err(|e| StrikeError::Contract(e.to_string()))?;

        let yes_bal = ot
            .balanceOf(owner, yes_id)
            .call()
            .await
            .map_err(|e| StrikeError::Contract(e.to_string()))?;
        let no_bal = ot
            .balanceOf(owner, no_id)
            .call()
            .await
            .map_err(|e| StrikeError::Contract(e.to_string()))?;

        Ok((yes_bal, no_bal))
    }
}
