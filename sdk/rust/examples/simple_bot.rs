//! Minimal market-making bot for Strike prediction markets.
//!
//! Demonstrates the real bot patterns from the Strike MM:
//! - Nonce manager for rapid transaction sequencing
//! - Startup bootstrap from indexer active markets, then event-driven quoting
//! - Atomic requoting via replaceOrders (zero empty-book time)
//! - Startup order recovery via scan_orders
//! - Graceful shutdown with order cancellation
//! - Basic position tracking
//!
//! This is a skeleton — a real bot would use an external price feed (Binance, Pyth)
//! and proper risk management. This uses the orderbook midpoint as a naive fair value.
//!
//! ```bash
//! PRIVATE_KEY=0x... cargo run --example simple_bot
//! ```

use alloy::primitives::U256;
use std::collections::HashMap;
use strike_sdk::indexer::types::Market;
use strike_sdk::prelude::*;

/// Active quote state for a market
struct QuotedMarket {
    bid_ids: Vec<U256>,
    ask_ids: Vec<U256>,
    position: i64, // net lots: positive = long YES, negative = long NO
}

const SPREAD: u8 = 5; // 5 ticks each side of fair
const LOTS: u64 = 100;

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt::init();

    let private_key = std::env::var("PRIVATE_KEY").expect("PRIVATE_KEY env var required");

    let mut client = StrikeClient::new(StrikeConfig::bsc_testnet())
        .with_private_key(&private_key)
        .build()?;

    let signer = client.signer_address().unwrap();
    println!("bot wallet: {signer}");

    // Initialize nonce manager (essential for bots sending rapid transactions)
    client.init_nonce_sender().await?;

    // Approve USDT (idempotent)
    client.vault().approve_usdt().await?;
    println!("USDT approved");

    // Startup recovery: find any open orders from previous runs
    let from_block = client.block_number().await?.saturating_sub(5000);
    let open_orders = client.scan_orders(from_block, signer).await?;
    if !open_orders.is_empty() {
        println!(
            "found {} markets with open orders from previous run",
            open_orders.len()
        );
        // Cancel stale orders from previous session
        let all_ids: Vec<U256> = open_orders
            .values()
            .flat_map(|(bids, asks)| bids.iter().chain(asks.iter()).cloned())
            .collect();
        if !all_ids.is_empty() {
            client.orders().cancel(&all_ids).await?;
            println!("cancelled {} stale orders", all_ids.len());
        }
    }

    // Track active quotes per market
    let mut markets: HashMap<u64, QuotedMarket> = HashMap::new();
    let mut active_markets: HashMap<u64, Market> = HashMap::new();

    // Bootstrap from current active indexer markets so the bot can quote immediately
    // on startup instead of waiting only for future MarketCreated events.
    for market in client.indexer().get_active_markets().await? {
        let orderbook_market_id = match market.tradable_market_id() {
            Ok(id) => id,
            Err(e) => {
                println!(
                    "skipping active factory market {}: {e}",
                    market.factory_market_id
                );
                continue;
            }
        };

        active_markets.insert(orderbook_market_id, market.clone());

        if let Some(quoted) = quote_market(&client, &market).await {
            markets.insert(orderbook_market_id, quoted);
        }
    }

    // Subscribe to events
    println!("listening for events...\n");
    let mut events = client.events().await?;

    // Graceful shutdown on Ctrl+C
    let (shutdown_tx, mut shutdown_rx) = tokio::sync::oneshot::channel::<()>();
    tokio::spawn(async move {
        tokio::signal::ctrl_c().await.ok();
        let _ = shutdown_tx.send(());
    });

    loop {
        tokio::select! {
            _ = &mut shutdown_rx => {
                println!("\nshutting down — cancelling all orders...");
                let all_ids: Vec<U256> = markets.values()
                    .flat_map(|m| m.bid_ids.iter().chain(m.ask_ids.iter()).cloned())
                    .collect();
                if !all_ids.is_empty() {
                    client.orders().cancel(&all_ids).await?;
                    println!("cancelled {} orders", all_ids.len());
                }
                return Ok(());
            }

            Some(event) = events.next() => {
                match event {
                    StrikeEvent::MarketCreated { market_id, strike_price, expiry_time, .. } => {
                        println!("MarketCreated | id: {market_id} | strike: {strike_price} | expiry: {expiry_time}");

                        if markets.contains_key(&market_id) {
                            println!("  market {market_id} already bootstrapped/quoted; skipping duplicate initial quote");
                            continue;
                        }

                        let market = if let Some(market) = active_markets.get(&market_id) {
                            market.clone()
                        } else {
                            let fetched = client
                                .indexer()
                                .get_active_markets()
                                .await?
                                .into_iter()
                                .find(|market| market.tradable_market_id().ok() == Some(market_id));

                            let Some(market) = fetched else {
                                println!("  market {market_id} not yet available in active indexer markets");
                                continue;
                            };

                            active_markets.insert(market_id, market.clone());
                            market
                        };

                        if let Some(quoted) = quote_market(&client, &market).await {
                            markets.insert(market_id, quoted);
                        }
                    }

                    StrikeEvent::BatchCleared { market_id, clearing_tick, matched_lots, .. } => {
                        if matched_lots > 0 {
                            println!("BatchCleared | market: {market_id} | tick: {clearing_tick} | matched: {matched_lots}");
                        }

                        // Requote using replaceOrders (atomic cancel + place, zero downtime)
                        if let Some(quoted) = markets.get(&market_id) {
                            let cancel_ids: Vec<U256> = quoted.bid_ids.iter()
                                .chain(quoted.ask_ids.iter())
                                .cloned()
                                .collect();

                            if cancel_ids.is_empty() { continue; }

                            let Some(fair) = get_fair_tick(&client, market_id).await else {
                                continue;
                            };
                            let bid_tick = fair.saturating_sub(SPREAD).max(1);
                            let ask_tick = (fair + SPREAD).min(99);

                            let Some(market) = active_markets.get(&market_id) else {
                                println!("  requote skipped: market {market_id} missing from active market cache");
                                continue;
                            };

                            match client.orders().replace_market(
                                &cancel_ids,
                                market,
                                &[OrderParam::bid(bid_tick, LOTS), OrderParam::ask(ask_tick, LOTS)],
                            ).await {
                                Ok(orders) => {
                                    let mut bid_ids = Vec::new();
                                    let mut ask_ids = Vec::new();
                                    for o in &orders {
                                        match o.side {
                                            Side::Bid => bid_ids.push(o.order_id),
                                            Side::Ask => ask_ids.push(o.order_id),
                                            _ => {}
                                        }
                                    }
                                    if let Some(m) = markets.get_mut(&market_id) {
                                        m.bid_ids = bid_ids;
                                        m.ask_ids = ask_ids;
                                    }
                                    println!("  requoted market {market_id} around fair={fair}");
                                }
                                Err(e) => println!("  requote failed: {e}"),
                            }
                        }
                    }

                    StrikeEvent::OrderSettled { order_id, filled_lots, owner, .. } => {
                        if owner != signer || filled_lots == 0 { continue; }

                        // Track position: filled bid = +lots (long YES), filled ask = +lots (long NO)
                        for (mid, quoted) in markets.iter_mut() {
                            if quoted.bid_ids.contains(&order_id) {
                                quoted.position += filled_lots as i64;
                                println!("FILL | market {mid} | bid filled {filled_lots} lots | position: {}", quoted.position);
                            } else if quoted.ask_ids.contains(&order_id) {
                                quoted.position -= filled_lots as i64;
                                println!("FILL | market {mid} | ask filled {filled_lots} lots | position: {}", quoted.position);
                            }
                        }
                    }

                    _ => {}
                }
            }
        }
    }
}

/// Get fair value tick from orderbook midpoint. Returns None if no liquidity.
async fn get_fair_tick(client: &StrikeClient, market_id: u64) -> Option<u8> {
    let ob = client.indexer().get_orderbook(market_id).await.ok()?;
    let best_bid = ob.bids.first()?.tick as u8;
    let best_ask = ob.asks.first()?.tick as u8;
    Some((best_bid + best_ask) / 2)
}

async fn quote_market(client: &StrikeClient, market: &Market) -> Option<QuotedMarket> {
    let market_id = market.tradable_market_id().ok()?;

    // Get fair value from orderbook midpoint (naive — real bots use a price feed).
    let fair = get_fair_tick(client, market_id).await.unwrap_or(50);

    // Quote around fair value.
    let bid_tick = fair.saturating_sub(SPREAD).max(1);
    let ask_tick = (fair + SPREAD).min(99);

    match client
        .orders()
        .place_market(
            market,
            &[
                OrderParam::bid(bid_tick, LOTS),
                OrderParam::ask(ask_tick, LOTS),
            ],
        )
        .await
    {
        Ok(orders) => {
            let mut bid_ids = Vec::new();
            let mut ask_ids = Vec::new();
            for o in &orders {
                match o.side {
                    Side::Bid => bid_ids.push(o.order_id),
                    Side::Ask => ask_ids.push(o.order_id),
                    _ => {}
                }
                println!("  placed {:?} @ market {market_id}", o.side);
            }

            Some(QuotedMarket {
                bid_ids,
                ask_ids,
                position: 0,
            })
        }
        Err(e) => {
            println!("  place failed for market {market_id}: {e}");
            None
        }
    }
}
