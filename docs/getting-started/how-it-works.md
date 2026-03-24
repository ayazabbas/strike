# How It Works

## The Trading Loop

Strike runs continuous short-duration prediction markets (default: 5 minutes). Each market asks a simple question:

> **Will BTC/USD be above $X at time T?**

Where `$X` is the strike price (captured from Pyth at market creation) and `T` is the expiry timestamp.

Traders express their view by placing orders on the orderbook:
- **Buy UP** if you think the price will be above the strike at expiry
- **Buy DOWN** if you think the price will be below the strike at expiry

## Step by Step

1. **Market opens** — A new market is created with a strike price and expiry. The orderbook begins accepting orders.

2. **Deposit USDT** — Deposit USDT to your Strike wallet. Approvals and gas are handled automatically.

3. **Place orders** — Traders submit limit orders at their desired price ($0.01–$0.99). An UP position priced at $0.70 means "70% chance price is above strike." USDT collateral is locked automatically when you place an order.

4. **Batches clear** — Periodically, all pending orders are matched at a single uniform clearing price. If bids and asks cross, a clearing price is found that maximizes matched volume. The oversubscribed side gets pro-rata partial fills. Settlement happens atomically in the same transaction — your position is recorded and any excess collateral refund is applied automatically.

5. **Trading halts** — When less than one batch interval remains before expiry, the book stops accepting new orders. The final batch clears normally.

6. **Market resolves** — After expiry, anyone can submit a signed Pyth price update to resolve the market. The contract verifies the update cryptographically and determines the outcome.

7. **Redeem winnings** — Winning positions pay out their full value. Losing positions pay nothing.

## What Makes FBA Different?

In a continuous orderbook, the first order to arrive gets priority — this creates speed races and MEV extraction. In a **Frequent Batch Auction**:

- All orders within a batch window are treated equally (no time priority within a batch)
- Everyone gets the same clearing price (uniform price)
- Oversubscribed sides are filled pro-rata (fair partial fills)
- Makers have time to cancel stale quotes before the next batch

This is the same mechanism used by traditional stock exchanges for opening/closing auctions, adapted for on-chain prediction markets.
