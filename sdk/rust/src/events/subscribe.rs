//! Live WSS event subscriptions with auto-reconnect.

use alloy::primitives::Address;
use alloy::providers::{Provider, ProviderBuilder, WsConnect};
use alloy::rpc::types::Filter;
use alloy::sol_types::SolEvent;
use futures_util::stream::{Stream, StreamExt};
use std::pin::Pin;
use std::task::{Context, Poll};
use tokio::sync::mpsc;
use tracing::{info, warn};

use crate::contracts::{BatchAuction, MarketFactory};
use crate::error::Result;
use crate::types::StrikeEvent;

/// A stream of on-chain Strike events.
///
/// Internally manages a WebSocket connection with auto-reconnect on drop
/// (5-second backoff between attempts).
pub struct EventStream {
    rx: mpsc::UnboundedReceiver<StrikeEvent>,
    // Hold the task handle so it doesn't get dropped
    _handle: tokio::task::JoinHandle<()>,
}

impl EventStream {
    /// Connect to the WSS endpoint and start streaming events.
    pub(crate) async fn connect(
        wss_url: &str,
        market_factory_addr: Address,
        batch_auction_addr: Address,
    ) -> Result<Self> {
        let (tx, rx) = mpsc::unbounded_channel();
        let wss_url = wss_url.to_string();

        let handle = tokio::spawn(async move {
            loop {
                match run_subscriptions(&wss_url, market_factory_addr, batch_auction_addr, &tx)
                    .await
                {
                    Ok(()) => {
                        info!("WS subscriber exited cleanly");
                        break;
                    }
                    Err(e) => {
                        warn!(err = %e, "WS subscription dropped — reconnecting in 5s");
                        tokio::time::sleep(tokio::time::Duration::from_secs(5)).await;
                    }
                }
            }
        });

        Ok(Self {
            rx,
            _handle: handle,
        })
    }

    /// Receive the next event. Returns `None` if the stream has ended.
    pub async fn next(&mut self) -> Option<StrikeEvent> {
        self.rx.recv().await
    }
}

impl Stream for EventStream {
    type Item = StrikeEvent;

    fn poll_next(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Option<Self::Item>> {
        self.rx.poll_recv(cx)
    }
}

async fn run_subscriptions(
    wss_url: &str,
    market_factory_addr: Address,
    batch_auction_addr: Address,
    tx: &mpsc::UnboundedSender<StrikeEvent>,
) -> std::result::Result<(), eyre::Report> {
    let ws = WsConnect::new(wss_url);
    let provider = ProviderBuilder::new()
        .connect_ws(ws)
        .await
        .map_err(|e| eyre::eyre!("WS connect failed: {e}"))?;

    // MarketCreated
    let mc_filter = Filter::new()
        .address(market_factory_addr)
        .event_signature(MarketFactory::MarketCreated::SIGNATURE_HASH);
    let mc_sub = provider.subscribe_logs(&mc_filter).await?;
    info!("subscribed to MarketCreated events");

    // BatchCleared
    let batch_filter = Filter::new()
        .address(batch_auction_addr)
        .event_signature(BatchAuction::BatchCleared::SIGNATURE_HASH);
    let batch_sub = provider.subscribe_logs(&batch_filter).await?;
    info!("subscribed to BatchCleared events");

    // OrderSettled (all — no owner filter in the SDK)
    let settled_filter = Filter::new()
        .address(batch_auction_addr)
        .event_signature(BatchAuction::OrderSettled::SIGNATURE_HASH);
    let settled_sub = provider.subscribe_logs(&settled_filter).await?;
    info!("subscribed to OrderSettled events");

    // GtcAutoCancelled
    let gtc_filter = Filter::new()
        .address(batch_auction_addr)
        .event_signature(BatchAuction::GtcAutoCancelled::SIGNATURE_HASH);
    let gtc_sub = provider.subscribe_logs(&gtc_filter).await?;
    info!("subscribed to GtcAutoCancelled events");

    let mut mc_stream = mc_sub.into_stream();
    let mut batch_stream = batch_sub.into_stream();
    let mut settled_stream = settled_sub.into_stream();
    let mut gtc_stream = gtc_sub.into_stream();

    loop {
        tokio::select! {
            Some(log) = mc_stream.next() => {
                if let Ok(event) = MarketFactory::MarketCreated::decode_log(&log.inner) {
                    let mut price_id = [0u8; 32];
                    price_id.copy_from_slice(&event.priceId[..]);
                    let _ = tx.send(StrikeEvent::MarketCreated {
                        market_id: event.orderBookMarketId.to::<u64>(),
                        price_id,
                        strike_price: event.strikePrice,
                        expiry_time: event.expiryTime.to::<u64>(),
                    });
                }
            }
            Some(log) = batch_stream.next() => {
                if let Ok(event) = BatchAuction::BatchCleared::decode_log(&log.inner) {
                    let _ = tx.send(StrikeEvent::BatchCleared {
                        market_id: event.marketId.to::<u64>(),
                        batch_id: event.batchId.to::<u64>(),
                        clearing_tick: event.clearingTick.to::<u64>(),
                        matched_lots: event.matchedLots.to::<u64>(),
                    });
                }
            }
            Some(log) = settled_stream.next() => {
                if let Ok(event) = BatchAuction::OrderSettled::decode_log(&log.inner) {
                    let _ = tx.send(StrikeEvent::OrderSettled {
                        order_id: event.orderId,
                        owner: event.owner,
                        filled_lots: event.filledLots.to::<u64>(),
                    });
                }
            }
            Some(log) = gtc_stream.next() => {
                if let Ok(event) = BatchAuction::GtcAutoCancelled::decode_log(&log.inner) {
                    let _ = tx.send(StrikeEvent::GtcAutoCancelled {
                        order_id: event.orderId,
                        owner: event.owner,
                    });
                }
            }
            else => {
                eyre::bail!("all event streams ended");
            }
        }
    }
}
