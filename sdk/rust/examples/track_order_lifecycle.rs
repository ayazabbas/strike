//! Minimal bot-flow example: place one order, keep the returned order id locally,
//! and classify what happens next from on-chain events.
//!
//! This demonstrates the core rule:
//! accepted/live != filled
//!
//! Outcome mapping:
//! - `place_market(...).await?` succeeds        => accepted/live (not necessarily filled)
//! - `StrikeEvent::OrderSettled`               => filled (check `filled_lots`)
//! - `StrikeEvent::OrderCancelled`             => explicitly cancelled
//! - `StrikeEvent::GtcAutoCancelled`           => auto-cancelled by batch auction
//!
//! Notes:
//! - `OrderSettled` currently does not include `market_id` or side, so bots should
//!   keep local metadata keyed by returned `order_id`.
//! - The SDK nonce manager is enabled by default; keep one client / tx pipeline per wallet
//!   and avoid concurrent place/cancel/replace sends from the same wallet.
//! - The live WSS stream carries `OrderSettled` and `GtcAutoCancelled`; for durable recovery
//!   after disconnects/restarts, reconcile via historical scans / indexer state.
//!
//! ```bash
//! PRIVATE_KEY=0x... cargo run --example track_order_lifecycle
//! ```

use std::collections::HashMap;
use std::env;
use std::time::Duration;

use strike_sdk::prelude::*;

#[allow(dead_code)]
#[derive(Debug, Clone, PartialEq, Eq)]
enum LifecycleState {
    AcceptedLive,
    PartiallyFilled,
    FullyFilled,
    Cancelled,
    AutoCancelled,
    TimedOutNeedsReconciliation,
}

#[derive(Debug, Clone)]
struct LocalOrderMeta {
    market_id: u64,
    side: &'static str,
    tick: u8,
    lots: u64,
    state: LifecycleState,
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt::init();

    let private_key = env::var("PRIVATE_KEY").expect("set PRIVATE_KEY=0x...");

    let client = StrikeClient::new(StrikeConfig::bsc_testnet())
        .with_private_key(&private_key)
        .build()?;

    let signer = client.signer_address().expect("wallet configured");
    println!("wallet: {signer}");
    println!("nonce-manager: enabled by default; send txs sequentially per wallet\n");

    client.vault().approve_usdt().await?;

    let market = client
        .indexer()
        .get_active_markets()
        .await?
        .into_iter()
        .next()
        .expect("no active markets");

    let market_id = market.tradable_market_id()?;
    let tick = 50;
    let lots = 100;

    let mut events = client.events().await?;

    let placed = client
        .orders()
        .place_market(&market, &[OrderParam::bid(tick, lots)])
        .await?;

    if placed.is_empty() {
        println!("tx confirmed but no order ids were parsed from receipt");
        return Ok(());
    }

    let mut tracked: HashMap<alloy::primitives::U256, LocalOrderMeta> = HashMap::new();
    for p in placed {
        tracked.insert(
            p.order_id,
            LocalOrderMeta {
                market_id,
                side: "bid",
                tick,
                lots,
                state: LifecycleState::AcceptedLive,
            },
        );
        println!(
            "accepted/live | order_id={} | market={} | side=bid | tick={} | lots={}",
            p.order_id, market_id, tick, lots
        );
    }

    println!("\nwaiting for OrderSettled / OrderCancelled / GtcAutoCancelled...\n");

    let timeout = Duration::from_secs(120);
    let deadline = tokio::time::Instant::now() + timeout;

    loop {
        tokio::select! {
            maybe_event = events.next() => {
                let Some(event) = maybe_event else {
                    println!("event stream ended; reconcile via scan_orders()/indexer on restart");
                    break;
                };

                match event {
                    StrikeEvent::OrderSettled { order_id, owner, filled_lots } => {
                        if owner != signer {
                            continue;
                        }
                        if let Some(meta) = tracked.get_mut(&order_id) {
                            println!(
                                "filled | order_id={} | market={} | side={} | filled_lots={} | requested_lots={} | tick={}",
                                order_id, meta.market_id, meta.side, filled_lots, meta.lots, meta.tick
                            );

                            if filled_lots >= meta.lots {
                                meta.state = LifecycleState::FullyFilled;
                                println!("terminal status: fully filled");
                                tracked.remove(&order_id);
                            } else if filled_lots > 0 {
                                meta.state = LifecycleState::PartiallyFilled;
                                println!("state update: partially filled (order may still remain open if GTC)");
                            } else {
                                println!("OrderSettled with 0 lots (no fill)");
                            }
                        }
                    }
                    StrikeEvent::OrderCancelled { order_id, market_id, owner } => {
                        if owner != signer {
                            continue;
                        }
                        if tracked.remove(&order_id).is_some() {
                            println!(
                                "cancelled | order_id={} | market={} | reason=explicit cancel / cleanup",
                                order_id, market_id
                            );
                        }
                    }
                    StrikeEvent::GtcAutoCancelled { order_id, owner } => {
                        if owner != signer {
                            continue;
                        }
                        if let Some(meta) = tracked.remove(&order_id) {
                            println!(
                                "auto-cancelled | order_id={} | market={} | side={} | reason=GtcAutoCancelled",
                                order_id, meta.market_id, meta.side
                            );
                        }
                    }
                    _ => {}
                }

                if tracked.is_empty() {
                    println!("\nall tracked orders reached a terminal outcome");
                    break;
                }
            }
            _ = tokio::time::sleep_until(deadline) => {
                for meta in tracked.values_mut() {
                    meta.state = LifecycleState::TimedOutNeedsReconciliation;
                }
                println!("timeout waiting for terminal lifecycle event; reconcile via scan_orders()/positions/indexer");
                break;
            }
        }
    }

    Ok(())
}
