//! Order placement, cancellation, and replacement on the OrderBook contract.

use alloy::primitives::{Address, Bytes, U256};
use alloy::providers::DynProvider;
use alloy::rpc::types::TransactionRequest;
use alloy::sol_types::{SolCall, SolEvent};
use std::sync::Arc;
use tokio::sync::Mutex;
use tracing::info;

use crate::chain::send_tx;
use crate::config::StrikeConfig;
use crate::contracts::OrderBook;
use crate::error::{Result, StrikeError};
use crate::nonce::NonceSender;
use crate::types::{OrderParam, PlacedOrder, Side};

/// Client for order operations on the OrderBook contract.
pub struct OrdersClient<'a> {
    provider: &'a DynProvider,
    signer_addr: Option<Address>,
    config: &'a StrikeConfig,
    nonce_sender: Option<Arc<Mutex<NonceSender>>>,
}

impl<'a> OrdersClient<'a> {
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

    /// Place one or more orders on a market in a single transaction.
    ///
    /// Uses `placeOrders(marketId, OrderParam[])`. Returns placed orders with
    /// their assigned on-chain IDs (parsed from `OrderPlaced` events in the receipt).
    pub async fn place(&self, market_id: u64, params: &[OrderParam]) -> Result<Vec<PlacedOrder>> {
        self.require_wallet()?;

        let contract_params: Vec<OrderBook::OrderParam> =
            params.iter().map(|p| p.to_contract_param()).collect();

        let calldata = OrderBook::placeOrdersCall {
            marketId: U256::from(market_id),
            params: contract_params,
        }
        .abi_encode();

        let order_count = params.len();
        let mut tx = TransactionRequest::default()
            .to(self.config.addresses.order_book)
            .input(Bytes::from(calldata).into());
        tx.gas = Some(350_000 * order_count as u64);

        let pending = send_tx(self.provider, &self.nonce_sender, tx).await?;

        let tx_hash = *pending.tx_hash();
        info!(market_id, order_count, tx = %tx_hash, "placeOrders tx sent");

        let receipt = pending
            .get_receipt()
            .await
            .map_err(|e| StrikeError::Contract(e.to_string()))?;

        if !receipt.status() {
            return Err(StrikeError::Contract(format!(
                "placeOrders reverted (market_id={market_id}, tx={tx_hash}, gas_used={})",
                receipt.gas_used
            )));
        }

        let placed = parse_placed_orders(&receipt, market_id);
        info!(market_id, tx = %tx_hash, gas_used = receipt.gas_used, placed = placed.len(), "placeOrders confirmed");

        Ok(placed)
    }

    /// Atomically cancel existing orders and place new ones via `replaceOrders`.
    ///
    /// Single transaction: cancels happen first, then placements, with net USDT
    /// settlement. Zero empty-book time.
    pub async fn replace(
        &self,
        cancel_ids: &[U256],
        market_id: u64,
        params: &[OrderParam],
    ) -> Result<Vec<PlacedOrder>> {
        self.require_wallet()?;

        let contract_params: Vec<OrderBook::OrderParam> =
            params.iter().map(|p| p.to_contract_param()).collect();

        let calldata = OrderBook::replaceOrdersCall {
            cancelIds: cancel_ids.to_vec(),
            marketId: U256::from(market_id),
            params: contract_params,
        }
        .abi_encode();

        let total_ops = cancel_ids.len() + params.len();
        let mut tx = TransactionRequest::default()
            .to(self.config.addresses.order_book)
            .input(Bytes::from(calldata).into());
        tx.gas = Some(350_000 * total_ops as u64);

        let pending = send_tx(self.provider, &self.nonce_sender, tx).await?;

        let tx_hash = *pending.tx_hash();
        info!(market_id, cancels = cancel_ids.len(), places = params.len(), tx = %tx_hash, "replaceOrders tx sent");

        let receipt = pending
            .get_receipt()
            .await
            .map_err(|e| StrikeError::Contract(e.to_string()))?;

        if !receipt.status() {
            return Err(StrikeError::Contract(format!(
                "replaceOrders reverted (market_id={market_id}, tx={tx_hash}, gas_used={})",
                receipt.gas_used
            )));
        }

        let placed = parse_placed_orders(&receipt, market_id);
        info!(market_id, tx = %tx_hash, gas_used = receipt.gas_used, cancelled = cancel_ids.len(), placed = placed.len(), "replaceOrders confirmed");

        Ok(placed)
    }

    /// Cancel one or more orders in a single transaction via `cancelOrders`.
    ///
    /// Skips already-cancelled orders on-chain (no revert).
    pub async fn cancel(&self, order_ids: &[U256]) -> Result<()> {
        self.require_wallet()?;

        if order_ids.is_empty() {
            return Ok(());
        }

        let calldata = OrderBook::cancelOrdersCall {
            orderIds: order_ids.to_vec(),
        }
        .abi_encode();

        let mut tx = TransactionRequest::default()
            .to(self.config.addresses.order_book)
            .input(Bytes::from(calldata).into());
        tx.gas = Some(100_000 * order_ids.len() as u64);

        let pending = send_tx(self.provider, &self.nonce_sender, tx).await?;

        let tx_hash = *pending.tx_hash();
        info!(count = order_ids.len(), tx = %tx_hash, "cancelOrders tx sent");

        let receipt = pending
            .get_receipt()
            .await
            .map_err(|e| StrikeError::Contract(e.to_string()))?;

        info!(tx = %tx_hash, gas_used = receipt.gas_used, count = order_ids.len(), "cancelOrders confirmed");
        Ok(())
    }

    /// Cancel a single order via `cancelOrder`.
    pub async fn cancel_one(&self, order_id: U256) -> Result<()> {
        self.require_wallet()?;

        let calldata = OrderBook::cancelOrderCall { orderId: order_id }.abi_encode();
        let mut tx = TransactionRequest::default()
            .to(self.config.addresses.order_book)
            .input(Bytes::from(calldata).into());
        tx.gas = Some(200_000);

        let pending = send_tx(self.provider, &self.nonce_sender, tx).await?;

        let tx_hash = *pending.tx_hash();
        let receipt = pending
            .get_receipt()
            .await
            .map_err(|e| StrikeError::Contract(e.to_string()))?;

        info!(order_id = %order_id, tx = %tx_hash, gas_used = receipt.gas_used, "cancelOrder confirmed");
        Ok(())
    }
}

/// Parse `OrderPlaced` events from a transaction receipt.
fn parse_placed_orders(
    receipt: &alloy::rpc::types::TransactionReceipt,
    market_id: u64,
) -> Vec<PlacedOrder> {
    let mut placed = Vec::new();
    for log in receipt.inner.logs() {
        if let Ok(event) = OrderBook::OrderPlaced::decode_log(&log.inner) {
            placed.push(PlacedOrder {
                order_id: event.orderId,
                side: Side::try_from(event.side).unwrap_or(Side::Bid),
                market_id,
            });
        }
    }
    placed
}
