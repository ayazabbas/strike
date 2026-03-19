//! Trading example: approve USDT, place orders, and cancel them.
//!
//! Requires PRIVATE_KEY env var.
//!
//! ```bash
//! PRIVATE_KEY=0x... cargo run --example place_orders
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
    println!("wallet: {signer}");

    // Check USDT balance
    let balance = client.vault().usdt_balance(signer).await?;
    println!("USDT balance: {balance}");

    // Approve vault (idempotent)
    client.vault().approve_usdt().await?;
    println!("vault approved");

    // Find an active market
    let markets = client.indexer().get_active_markets().await?;
    let market = match markets.first() {
        Some(m) => m,
        None => {
            println!("no active markets found");
            return Ok(());
        }
    };
    println!(
        "using market {} (expiry: {})",
        market.id, market.expiry_time
    );

    let market_id = market.id as u64;

    // Place orders: bid at tick 40, ask at tick 60
    let orders = client
        .orders()
        .place(
            market_id,
            &[OrderParam::bid(40, 100), OrderParam::ask(60, 100)],
        )
        .await?;

    println!("placed {} orders:", orders.len());
    for o in &orders {
        println!("  order {} | side: {:?}", o.order_id, o.side);
    }

    // Cancel all orders
    let ids: Vec<_> = orders.iter().map(|o| o.order_id).collect();
    client.orders().cancel(&ids).await?;
    println!("cancelled {} orders", ids.len());

    Ok(())
}
