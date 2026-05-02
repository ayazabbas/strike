# How It Works

## Two Ways to Trade

Strike has two first-class market formats:

- **FBA orderbook markets** — binary markets with limit orders, batch-auction matching, active trading, and the ability to sell positions before expiry.
- **Parimutuel pool markets** — 2–8 outcome pool markets where users buy into an outcome directly and winners split the losing pools after resolution.

Use orderbook markets when you want price discovery and active trading. Use parimutuel markets when the question has several possible outcomes or when you want a simpler buy-and-hold pool experience.

## The Orderbook Trading Loop

Strike runs continuous short-duration prediction markets (default: 5 minutes). Each market asks a simple question:

> **Will BTC/USD be above $X at time T?**

Where `$X` is the strike price (captured from Pyth at market creation) and `T` is the expiry timestamp.

Markets can also be resolved by **AI oracle** instead of price feeds. AI markets ask open-ended questions — "Will the Fed cut rates in May?" or "Will GTA VI release before June 2026?" — and are resolved by the [Flap AI Oracle](../protocol/ai-markets.md). Orderbook trading mechanics are identical for price and AI binary markets.

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


## The Parimutuel Pool Loop

Parimutuel markets do not use an orderbook. Each market has 2–8 named outcomes and a pool for each outcome.

1. **Market opens** — outcomes, resolver mode, trading close time, resolution time, fee, and curve are configured.
2. **Choose an outcome** — traders select the outcome they think will win and buy into that pool with USDT.
3. **Pool odds update** — displayed probabilities and projected payouts update as liquidity moves between outcome pools.
4. **Trading closes** — buys stop at `tradingCloseTime`. This can be earlier than the event's final `resolutionTime`.
5. **Market resolves** — admin, AI, or Pyth resolution selects the winning outcome, or the market is marked invalid.
6. **Claim or refund** — winners claim principal plus their pro-rata share of losing pools. Invalid markets refund principal.

Read the full [Parimutuel Pool Markets](../protocol/parimutuel-markets.md) guide for timing, payout, and resolver details.
