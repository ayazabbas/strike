//! Minimal bot: subscribe to MarketCreated events and quote a fixed spread.
//!
//! This is a skeleton — a real bot would have pricing, risk management, and
//! position tracking. This just demonstrates the SDK flow.
//!
//! ```bash
//! PRIVATE_KEY=0x... cargo run --example simple_bot
//! ```

use strike_sdk::prelude::*;

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt::init();

    let private_key = std::env::var("PRIVATE_KEY").expect("PRIVATE_KEY env var required");

    let client = StrikeClient::new(StrikeConfig::bsc_testnet())
        .with_private_key(&private_key)
        .build()?;

    let signer = client.signer_address().unwrap();
    println!("bot wallet: {signer}");

    // Approve USDT (idempotent)
    client.vault().approve_usdt().await?;

    // Subscribe to events
    println!("listening for new markets...\n");
    let mut events = client.events().await?;

    while let Some(event) = events.next().await {
        match event {
            StrikeEvent::MarketCreated {
                market_id,
                strike_price,
                expiry_time,
                ..
            } => {
                println!("new market {market_id} | strike: {strike_price} | expiry: {expiry_time}");

                // Quote a fixed 10-tick spread around mid (tick 50)
                // A real bot would compute fair value from an oracle
                let mid = 50u8;
                let spread = 5u8;
                let lots = 100u64;

                match client
                    .orders()
                    .place(
                        market_id,
                        &[
                            OrderParam::bid(mid - spread, lots),
                            OrderParam::ask(mid + spread, lots),
                        ],
                    )
                    .await
                {
                    Ok(orders) => {
                        println!("  placed {} orders on market {market_id}", orders.len());
                        for o in &orders {
                            println!("    {} | {:?}", o.order_id, o.side);
                        }
                    }
                    Err(e) => {
                        println!("  failed to place orders: {e}");
                    }
                }
            }
            StrikeEvent::BatchCleared {
                market_id,
                clearing_tick,
                matched_lots,
                ..
            } => {
                if matched_lots > 0 {
                    println!("batch cleared: market {market_id} | tick {clearing_tick} | {matched_lots} lots matched");
                }
            }
            _ => {}
        }
    }

    Ok(())
}
