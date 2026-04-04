//! Read-only example: fetch markets from the indexer and read on-chain state.
//!
//! ```bash
//! cargo run --example read_markets
//! ```

use strike_sdk::prelude::*;

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt::init();

    let client = StrikeClient::new(StrikeConfig::bsc_testnet()).build()?;

    // Fetch markets from indexer
    println!("fetching markets from indexer...");
    let markets = client.indexer().get_markets().await?;
    println!("found {} markets\n", markets.len());

    for market in &markets {
        println!(
            "  factory {} | orderbook {:?} | status: {} | expiry: {} | batch_interval: {}s",
            market.factory_market_id,
            market.orderbook_market_id,
            market.status,
            market.expiry_time,
            market.batch_interval,
        );
    }

    // Read on-chain state
    println!("\non-chain state:");
    let active_count = client.markets().active_market_count().await?;
    println!("  active markets: {active_count}");

    let next_id = client.markets().next_market_id().await?;
    println!("  next market id: {next_id}");

    // Get orderbook snapshot for first active market
    let active_markets: Vec<_> = markets.iter().filter(|m| m.status == "active").collect();
    if let Some(market) = active_markets.first() {
        let tradable_market_id = market.tradable_market_id()?;
        println!(
            "\norderbook for tradable market {} (factory {}):",
            tradable_market_id, market.factory_market_id
        );
        match client.indexer().get_orderbook(tradable_market_id).await {
            Ok(ob) => {
                println!("  bids: {} levels", ob.bids.len());
                for level in &ob.bids {
                    println!("    tick {} | {} lots", level.tick, level.lots);
                }
                println!("  asks: {} levels", ob.asks.len());
                for level in &ob.asks {
                    println!("    tick {} | {} lots", level.tick, level.lots);
                }
            }
            Err(e) => println!("  failed to fetch orderbook: {e}"),
        }
    }

    Ok(())
}
