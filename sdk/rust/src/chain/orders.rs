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
use crate::indexer::types::Market as IndexerMarket;
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
    /// Uses `placeOrders(orderbookMarketId, OrderParam[])`. Returns placed orders with
    /// their assigned on-chain IDs (parsed from `OrderPlaced` events in the receipt).
    pub async fn place(
        &self,
        orderbook_market_id: u64,
        params: &[OrderParam],
    ) -> Result<Vec<PlacedOrder>> {
        self.require_wallet()?;

        let contract_params: Vec<OrderBook::OrderParam> =
            params.iter().map(|p| p.to_contract_param()).collect();

        let calldata = OrderBook::placeOrdersCall {
            marketId: U256::from(orderbook_market_id),
            params: contract_params,
        }
        .abi_encode();

        let order_count = params.len();
        let gas_limit = gas_limit_place_orders(order_count);
        let mut tx = TransactionRequest::default()
            .to(self.config.addresses.order_book)
            .input(Bytes::from(calldata).into());
        tx.gas = Some(gas_limit);

        let pending = send_tx(self.provider, &self.nonce_sender, tx).await?;

        let tx_hash = *pending.tx_hash();
        info!(orderbook_market_id, order_count, gas_limit, tx = %tx_hash, "placeOrders tx sent");

        let receipt = pending
            .get_receipt()
            .await
            .map_err(|e| StrikeError::Contract(e.to_string()))?;

        if !receipt.status() {
            return Err(StrikeError::Contract(format!(
                "placeOrders reverted (orderbook_market_id={orderbook_market_id}, tx={tx_hash}, gas_used={})",
                receipt.gas_used
            )));
        }

        let placed = parse_placed_orders(&receipt, orderbook_market_id);
        info!(
            orderbook_market_id,
            tx = %tx_hash,
            gas_limit,
            gas_used = receipt.gas_used,
            gas_utilization_pct = %format_gas_utilization_pct(receipt.gas_used, gas_limit),
            placed = placed.len(),
            "placeOrders confirmed"
        );

        Ok(placed)
    }

    /// Place one or more orders using an indexer market object.
    ///
    /// This resolves the tradable `orderbook_market_id` and fails closed if the
    /// indexer response only exposed the legacy factory ID.
    pub async fn place_market(
        &self,
        market: &IndexerMarket,
        params: &[OrderParam],
    ) -> Result<Vec<PlacedOrder>> {
        self.place(market.tradable_market_id()?, params).await
    }

    /// Atomically cancel existing orders and place new ones via `replaceOrders`.
    ///
    /// Single transaction: cancels happen first, then placements, with net USDT
    /// settlement. Zero empty-book time.
    pub async fn replace(
        &self,
        cancel_ids: &[U256],
        orderbook_market_id: u64,
        params: &[OrderParam],
    ) -> Result<Vec<PlacedOrder>> {
        self.require_wallet()?;

        let contract_params: Vec<OrderBook::OrderParam> =
            params.iter().map(|p| p.to_contract_param()).collect();

        let calldata = OrderBook::replaceOrdersCall {
            cancelIds: cancel_ids.to_vec(),
            marketId: U256::from(orderbook_market_id),
            params: contract_params,
        }
        .abi_encode();

        let gas_limit = gas_limit_replace_orders(cancel_ids.len(), params.len());
        let mut tx = TransactionRequest::default()
            .to(self.config.addresses.order_book)
            .input(Bytes::from(calldata).into());
        tx.gas = Some(gas_limit);

        let pending = send_tx(self.provider, &self.nonce_sender, tx).await?;

        let tx_hash = *pending.tx_hash();
        info!(
            orderbook_market_id,
            cancels = cancel_ids.len(),
            places = params.len(),
            gas_limit,
            tx = %tx_hash,
            "replaceOrders tx sent"
        );

        let receipt = pending
            .get_receipt()
            .await
            .map_err(|e| StrikeError::Contract(e.to_string()))?;

        if !receipt.status() {
            return Err(StrikeError::Contract(format!(
                "replaceOrders reverted (orderbook_market_id={orderbook_market_id}, tx={tx_hash}, gas_used={})",
                receipt.gas_used
            )));
        }

        let placed = parse_placed_orders(&receipt, orderbook_market_id);
        info!(
            orderbook_market_id,
            tx = %tx_hash,
            gas_limit,
            gas_used = receipt.gas_used,
            gas_utilization_pct = %format_gas_utilization_pct(receipt.gas_used, gas_limit),
            cancelled = cancel_ids.len(),
            placed = placed.len(),
            "replaceOrders confirmed"
        );

        Ok(placed)
    }

    /// Replace one or more orders using an indexer market object.
    ///
    /// This resolves the tradable `orderbook_market_id` and fails closed if the
    /// indexer response only exposed the legacy factory ID.
    pub async fn replace_market(
        &self,
        cancel_ids: &[U256],
        market: &IndexerMarket,
        params: &[OrderParam],
    ) -> Result<Vec<PlacedOrder>> {
        self.replace(cancel_ids, market.tradable_market_id()?, params)
            .await
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

        let gas_limit = gas_limit_cancel_orders(order_ids.len());
        let mut tx = TransactionRequest::default()
            .to(self.config.addresses.order_book)
            .input(Bytes::from(calldata).into());
        tx.gas = Some(gas_limit);

        let pending = send_tx(self.provider, &self.nonce_sender, tx).await?;

        let tx_hash = *pending.tx_hash();
        info!(count = order_ids.len(), gas_limit, tx = %tx_hash, "cancelOrders tx sent");

        let receipt = pending
            .get_receipt()
            .await
            .map_err(|e| StrikeError::Contract(e.to_string()))?;

        info!(
            tx = %tx_hash,
            gas_limit,
            gas_used = receipt.gas_used,
            gas_utilization_pct = %format_gas_utilization_pct(receipt.gas_used, gas_limit),
            count = order_ids.len(),
            "cancelOrders confirmed"
        );
        Ok(())
    }

    /// Cancel a single order via `cancelOrder`.
    pub async fn cancel_one(&self, order_id: U256) -> Result<()> {
        self.require_wallet()?;

        let calldata = OrderBook::cancelOrderCall { orderId: order_id }.abi_encode();
        let gas_limit = gas_limit_cancel_order();
        let mut tx = TransactionRequest::default()
            .to(self.config.addresses.order_book)
            .input(Bytes::from(calldata).into());
        tx.gas = Some(gas_limit);

        let pending = send_tx(self.provider, &self.nonce_sender, tx).await?;

        let tx_hash = *pending.tx_hash();
        info!(order_id = %order_id, gas_limit, tx = %tx_hash, "cancelOrder tx sent");
        let receipt = pending
            .get_receipt()
            .await
            .map_err(|e| StrikeError::Contract(e.to_string()))?;

        info!(
            order_id = %order_id,
            tx = %tx_hash,
            gas_limit,
            gas_used = receipt.gas_used,
            gas_utilization_pct = %format_gas_utilization_pct(receipt.gas_used, gas_limit),
            "cancelOrder confirmed"
        );
        Ok(())
    }
}

fn gas_limit_place_orders(order_count: usize) -> u64 {
    550_000 + 175_000 * (order_count.saturating_sub(1) as u64)
}

fn gas_limit_replace_orders(cancel_count: usize, place_count: usize) -> u64 {
    300_000 + 120_000 * cancel_count as u64 + 180_000 * place_count as u64
}

fn gas_limit_cancel_orders(order_count: usize) -> u64 {
    120_000 + 70_000 * order_count as u64
}

fn gas_limit_cancel_order() -> u64 {
    250_000
}

fn format_gas_utilization_pct(gas_used: u64, gas_limit: u64) -> String {
    if gas_limit == 0 {
        return "0.0".to_string();
    }

    format!("{:.1}", gas_used as f64 / gas_limit as f64 * 100.0)
}

/// Parse `OrderPlaced` and `OrderResting` events from a transaction receipt.
/// Resting orders are placed far from the clearing price and emit `OrderResting`
/// instead of `OrderPlaced`, but they're still live orders that need tracking.
fn parse_placed_orders(
    receipt: &alloy::rpc::types::TransactionReceipt,
    orderbook_market_id: u64,
) -> Vec<PlacedOrder> {
    let mut placed = Vec::new();
    for log in receipt.inner.logs() {
        if let Ok(event) = OrderBook::OrderPlaced::decode_log(&log.inner) {
            placed.push(PlacedOrder {
                order_id: event.orderId,
                side: Side::try_from(event.side).unwrap_or(Side::Bid),
                market_id: orderbook_market_id,
                orderbook_market_id,
            });
        } else if let Ok(event) = OrderBook::OrderResting::decode_log(&log.inner) {
            // OrderResting doesn't include side — read from on-chain order storage.
            // Use Bid as fallback; the quoter cancels all tracked IDs regardless of side.
            placed.push(PlacedOrder {
                order_id: event.orderId,
                side: Side::Bid,
                market_id: orderbook_market_id,
                orderbook_market_id,
            });
        }
    }
    placed
}

#[cfg(test)]
mod tests {
    use super::{
        gas_limit_cancel_order, gas_limit_cancel_orders, gas_limit_place_orders,
        gas_limit_replace_orders,
    };

    #[test]
    fn gas_limit_place_orders_formula() {
        assert_eq!(gas_limit_place_orders(0), 550_000);
        assert_eq!(gas_limit_place_orders(1), 550_000);
        assert_eq!(gas_limit_place_orders(2), 725_000);
        assert_eq!(gas_limit_place_orders(3), 900_000);
    }

    #[test]
    fn gas_limit_replace_orders_formula() {
        assert_eq!(gas_limit_replace_orders(0, 0), 300_000);
        assert_eq!(gas_limit_replace_orders(1, 0), 420_000);
        assert_eq!(gas_limit_replace_orders(0, 1), 480_000);
        assert_eq!(gas_limit_replace_orders(2, 3), 1_080_000);
    }

    #[test]
    fn gas_limit_cancel_orders_formula() {
        assert_eq!(gas_limit_cancel_orders(0), 120_000);
        assert_eq!(gas_limit_cancel_orders(1), 190_000);
        assert_eq!(gas_limit_cancel_orders(3), 330_000);
    }

    #[test]
    fn gas_limit_cancel_order_formula() {
        assert_eq!(gas_limit_cancel_order(), 250_000);
    }
}
