//! OutcomeToken (ERC-1155) balance and approval helpers.

use alloy::primitives::{Address, U256};
use alloy::providers::DynProvider;

use crate::config::StrikeConfig;
use crate::contracts::OutcomeToken;
use crate::error::{Result, StrikeError};

/// Client for outcome token operations.
pub struct TokensClient<'a> {
    provider: &'a DynProvider,
    signer_addr: Option<Address>,
    config: &'a StrikeConfig,
}

impl<'a> TokensClient<'a> {
    pub(crate) fn new(
        provider: &'a DynProvider,
        signer_addr: Option<Address>,
        config: &'a StrikeConfig,
    ) -> Self {
        Self {
            provider,
            signer_addr,
            config,
        }
    }

    fn ot(&self) -> OutcomeToken::OutcomeTokenInstance<&DynProvider> {
        OutcomeToken::new(self.config.addresses.outcome_token, self.provider)
    }

    /// Get the YES token ID for a market.
    pub async fn yes_token_id(&self, market_id: u64) -> Result<U256> {
        self.ot()
            .yesTokenId(U256::from(market_id))
            .call()
            .await
            .map_err(|e| StrikeError::Contract(e.to_string()))
    }

    /// Get the NO token ID for a market.
    pub async fn no_token_id(&self, market_id: u64) -> Result<U256> {
        self.ot()
            .noTokenId(U256::from(market_id))
            .call()
            .await
            .map_err(|e| StrikeError::Contract(e.to_string()))
    }

    /// Get the ERC-1155 balance of `owner` for a specific token ID.
    pub async fn balance_of(&self, owner: Address, token_id: U256) -> Result<U256> {
        self.ot()
            .balanceOf(owner, token_id)
            .call()
            .await
            .map_err(|e| StrikeError::Contract(e.to_string()))
    }

    /// Check if `operator` is approved for all tokens owned by `owner`.
    pub async fn is_approved_for_all(&self, owner: Address, operator: Address) -> Result<bool> {
        self.ot()
            .isApprovedForAll(owner, operator)
            .call()
            .await
            .map_err(|e| StrikeError::Contract(e.to_string()))
    }

    /// Set approval for all tokens to an operator (e.g., the OrderBook for SellYes/SellNo).
    pub async fn set_approval_for_all(&self, operator: Address, approved: bool) -> Result<()> {
        self.signer_addr.ok_or(StrikeError::NoWallet)?;

        let pending = self
            .ot()
            .setApprovalForAll(operator, approved)
            .send()
            .await
            .map_err(|e| StrikeError::Contract(e.to_string()))?;
        pending
            .get_receipt()
            .await
            .map_err(|e| StrikeError::Contract(e.to_string()))?;
        Ok(())
    }
}
