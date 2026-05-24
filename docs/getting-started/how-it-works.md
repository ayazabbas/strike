# How It Works

## Ways to Trade

Strike has three live market surfaces:

- **FBA orderbook markets** — binary markets with limit orders, batch-auction matching, active trading, and the ability to sell positions before expiry.
- **Parimutuel pool markets** — 2–8 outcome pool markets where users buy into an outcome directly and winners split the losing pools after resolution.
- **Flap Token Pools** — creator-launched token pools using BEP20 collateral and FLAP AI resolution from an on-chain prompt.

Use orderbook markets when you want price discovery and active trading. Use standard parimutuel markets for simple multi-outcome pools. Use Flap Token Pools when a creator wants to launch an AI-resolved token-data market backed by a BEP20 token.

## The Orderbook Trading Loop

Strike runs continuous short-duration prediction markets (default: 5 minutes). Each market asks a simple question:

> **Will BTC/USD be above $X at time T?**

Where `$X` is the strike price (captured from Pyth at market creation) and `T` is the expiry timestamp.

Markets can also resolve through the **Flap AI Oracle** where configured. Public Flap Token Pools are currently optimized for token-data prompts resolvable from Ave-supported data such as price, liquidity, volume, FDV, or market cap.

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


## The Flap Token Pool Loop

Flap Token Pools are creator-launched pool markets backed by a chosen BEP20 token.

1. **Creator defines the market** — collateral token, outcomes, timing, and prompt.
2. **Official metadata is uploaded** — Strike hosts hash-checked metadata before the on-chain create transaction.
3. **Users trade** — traders buy outcome exposure using the selected token.
4. **FLAP AI resolves** — the resolver uses the on-chain prompt after the resolution time.
5. **Challenge window** — AI proposals have a 30 minute challenge window.
6. **Claim or refund** — finalized winners claim; invalid/cancelled markets refund.

Read the full [Flap Token Pools](flap-token-pools.md) guide for prompt, collateral, and lifecycle details.
