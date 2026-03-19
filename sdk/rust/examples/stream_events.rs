//! Event streaming example: subscribe to on-chain events via WSS.
//!
//! ```bash
//! cargo run --example stream_events
//! ```

use strike_sdk::prelude::*;

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt::init();

    let client = StrikeClient::new(StrikeConfig::bsc_testnet()).build()?;

    println!("subscribing to Strike events via WSS...");
    let mut events = client.events().await?;

    println!("listening for events (ctrl+c to stop):\n");
    while let Some(event) = events.next().await {
        match event {
            StrikeEvent::MarketCreated {
                market_id,
                strike_price,
                expiry_time,
                ..
            } => {
                println!(
                    "MarketCreated | id: {market_id} | strike: {strike_price} | expiry: {expiry_time}"
                );
            }
            StrikeEvent::BatchCleared {
                market_id,
                batch_id,
                clearing_tick,
                matched_lots,
            } => {
                println!(
                    "BatchCleared  | market: {market_id} | batch: {batch_id} | tick: {clearing_tick} | matched: {matched_lots}"
                );
            }
            StrikeEvent::OrderSettled {
                order_id,
                filled_lots,
                ..
            } => {
                println!("OrderSettled  | order: {order_id} | filled: {filled_lots}");
            }
            StrikeEvent::GtcAutoCancelled { order_id, .. } => {
                println!("GtcCancelled  | order: {order_id}");
            }
            _ => {}
        }
    }

    Ok(())
}
