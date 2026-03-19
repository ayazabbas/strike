//! Historical event scanning via chunked `getLogs`.
//!
//! BSC RPC nodes limit log queries to ~3000 blocks per request.

use std::collections::{HashMap, HashSet};

use alloy::primitives::{Address, U256};
use alloy::providers::{DynProvider, Provider};
use alloy::rpc::types::Filter;
use alloy::sol_types::SolEvent;
use tracing::{info, warn};

use crate::contracts::OrderBook;
use crate::error::{Result, StrikeError};

/// Maximum block range per log query (BSC RPC limit).
const LOG_SCAN_CHUNK_SIZE: u64 = 3_000;

/// Scan chain events to find orders placed by `owner` that haven't been cancelled.
///
/// Returns a map of `market_id -> (bid_order_ids, ask_order_ids)`.
/// Scans from `from_block` to the latest block in chunks of 3000 blocks.
pub async fn scan_live_orders(
    provider: &DynProvider,
    order_book_addr: Address,
    owner: Address,
    from_block: u64,
) -> Result<HashMap<u64, (Vec<U256>, Vec<U256>)>> {
    let latest_block = provider
        .get_block_number()
        .await
        .map_err(StrikeError::Rpc)?;

    let scan_from = if from_block == 0 {
        latest_block.saturating_sub(LOG_SCAN_CHUNK_SIZE)
    } else {
        from_block
    };

    info!(
        from_block = scan_from,
        to_block = latest_block,
        owner = %owner,
        "scanning chain for live orders (chunk_size={})",
        LOG_SCAN_CHUNK_SIZE
    );

    struct RecoveredOrder {
        order_id: U256,
        market_id: u64,
        side: u8,
    }

    let mut placed_orders: Vec<RecoveredOrder> = Vec::new();
    let mut cancelled_ids: HashSet<U256> = HashSet::new();

    let mut chunk_start = scan_from;
    while chunk_start <= latest_block {
        let chunk_end = (chunk_start + LOG_SCAN_CHUNK_SIZE - 1).min(latest_block);

        // OrderPlaced events filtered by owner (topic3)
        let placed_filter = Filter::new()
            .address(order_book_addr)
            .event_signature(OrderBook::OrderPlaced::SIGNATURE_HASH)
            .topic3(owner)
            .from_block(chunk_start)
            .to_block(chunk_end);

        match provider.get_logs(&placed_filter).await {
            Ok(logs) => {
                for log in &logs {
                    if let Ok(event) = OrderBook::OrderPlaced::decode_log(&log.inner) {
                        placed_orders.push(RecoveredOrder {
                            order_id: event.orderId,
                            market_id: event.marketId.to::<u64>(),
                            side: event.side,
                        });
                    }
                }
            }
            Err(e) => {
                warn!(chunk_start, chunk_end, err = %e, "failed to fetch OrderPlaced logs — skipping chunk");
            }
        }

        // OrderCancelled events filtered by owner (topic3)
        let cancelled_filter = Filter::new()
            .address(order_book_addr)
            .event_signature(OrderBook::OrderCancelled::SIGNATURE_HASH)
            .topic3(owner)
            .from_block(chunk_start)
            .to_block(chunk_end);

        match provider.get_logs(&cancelled_filter).await {
            Ok(logs) => {
                for log in &logs {
                    if let Ok(event) = OrderBook::OrderCancelled::decode_log(&log.inner) {
                        cancelled_ids.insert(event.orderId);
                    }
                }
            }
            Err(e) => {
                warn!(chunk_start, chunk_end, err = %e, "failed to fetch OrderCancelled logs — skipping chunk");
            }
        }

        chunk_start = chunk_end + 1;
    }

    info!(
        placed = placed_orders.len(),
        cancelled = cancelled_ids.len(),
        "event scan complete"
    );

    // Build live orders: placed but not cancelled
    let mut live: HashMap<u64, (Vec<U256>, Vec<U256>)> = HashMap::new();
    for order in placed_orders {
        if cancelled_ids.contains(&order.order_id) {
            continue;
        }
        let entry = live.entry(order.market_id).or_default();
        if order.side == 0 {
            entry.0.push(order.order_id);
        } else {
            entry.1.push(order.order_id);
        }
    }

    let total_live: usize = live.values().map(|(b, a)| b.len() + a.len()).sum();
    info!(
        live_orders = total_live,
        markets = live.len(),
        "scan complete"
    );

    Ok(live)
}
