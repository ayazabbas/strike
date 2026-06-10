# Trading Guide

Everything you need to know about trading on Strike's orderbook markets and parimutuel pool markets.

## Market Formats

Strike has two trading experiences:

- **Orderbook markets** — active binary markets with limit orders, FBA matching, and sell-before-expiry support.
- **Parimutuel pool markets** — simple 2–8 outcome markets where you buy into an outcome pool and claim after resolution.

The sections below cover orderbook trading first, then pool markets.

## Understanding Orderbook Prices

Every orderbook market on Strike has two outcomes: **UP** and **DOWN**. Positions trade between **$0.01** and **$0.99** per lot.

The price reflects the market's implied probability:

| Price | Implied Probability |
|-------|-------------------|
| $0.10 | 10% chance        |
| $0.25 | 25% chance        |
| $0.50 | 50% chance        |
| $0.75 | 75% chance        |
| $0.99 | 99% chance        |

An UP token at $0.30 means the market thinks there's roughly a 30% chance the asset finishes above the strike price. If you disagree and think it's more likely, that's your trading opportunity.

## UP vs DOWN

- **UP** -- you're betting the asset's price will be **above** the strike price at expiry.
- **DOWN** -- you're betting the asset's price will be **below** the strike price at expiry.

One side wins at resolution. Winning orderbook positions pay their full settlement value; losing positions pay nothing.

## Placing Orders

All orders on Strike are **limit orders**. You choose:

1. **Side** -- UP or DOWN
2. **Price** -- the most you're willing to pay (e.g., $0.35)
3. **Amount** -- how many lots you want

Your order sits on the orderbook until it's matched in the next batch.

## How Batches Work

Strike uses **Frequent Batch Auctions** for fair price discovery. Here's how it works:

1. Orders are collected into short keeper-cleared batches. The exact cadence can vary by market and network conditions.
2. At the end of the window, all orders in the batch are matched simultaneously.
3. A single **clearing price** is calculated -- every fill in that batch trades at the same price.

This means no one gets an unfair advantage from speed. Everyone in the same batch gets the same price.

## Reading the Orderbook

The orderbook shows resting buy and sell orders at each price level:

- **UP side** -- buy orders (bids) on the left, sell orders (asks) on the right.
- **DOWN side** -- the mirror image.

The spread between the best bid and best ask tells you how tight the market is. A narrow spread means lots of liquidity around the current price.

## Order Types

### GTC (Good Till Cancelled)

Your order stays on the book until it fills or you cancel it. If only part of your order fills in a batch, the remaining portion rolls over to the next batch automatically.

### GTB (Good Till Batch)

Your order is only valid for the current batch. If it doesn't fill, it expires automatically -- no need to cancel. Useful when you want to take a shot at the current price without leaving a resting order.

## Resting Orders

Orders placed far from the current market price won't fill immediately. They sit on the book as **resting orders**, waiting for the market to move toward them. These orders are still valid and will participate in any batch where the clearing price reaches their level.

Think of resting orders as standing offers: "I'll buy UP at $0.15 if the price ever gets there."

## Selling Your Position

You don't have to wait for a market to resolve. If you hold UP or DOWN tokens, you can sell them back into the orderbook at any time before expiry.

This lets you:

- **Lock in profit** if the price has moved in your favor
- **Cut losses** if you've changed your mind
- **Trade actively** around price movements

## Managing Positions in Portfolio

Your **Portfolio** page shows:

- **Open orders** -- orders waiting to fill
- **Active positions** -- tokens you hold in live markets
- **Resolved markets** -- markets that have settled, with winnings ready to claim

## Claiming Winnings

When a market resolves:

1. Go to **Portfolio**
2. Find the resolved market
3. Click **Claim** to receive your USDT payout

If your side wins, your profit is the winning payout minus your entry cost and fees.

## Fees

Strike charges a flat **0.20% fee** (20 basis points) on every trade. The fee is split evenly -- 0.10% from the buyer and 0.10% from the seller. That's it. No hidden costs, no variable rates.


## Trading Parimutuel Pool Markets

Parimutuel markets are simpler than orderbook markets:

1. Open a pool market.
2. Pick the outcome you think will win.
3. Enter the USDT amount you want to buy.
4. Review the projected payout and implied probability.
5. Submit the buy.

There are no limit prices, resting orders, GTB/GTC choices, or sell orders. You hold the pool position until the market resolves.

## Reading Pool Markets

Each outcome shows:

- **Pool size** — total USDT currently backing that outcome.
- **Implied probability** — the market's current estimate based on pool balances and curve settings.
- **Projected payout** — an estimate of what your buy would receive if that outcome wins.

Projected payouts change as other users buy into any outcome.

## Pool Market Timing

Parimutuel markets show both:

- **Trading closes** — last moment to buy into a pool.
- **Resolution time** — when the outcome is evaluated.

These can be different. For example, trading can close before a match starts, while resolution happens after the match ends.

## Claiming Pool Winnings

When a pool market resolves:

1. Go to the market or Portfolio.
2. If your outcome won, click **Claim** to receive your payout.
3. If the market was marked invalid, click **Refund** to recover principal.

Losing outcomes do not receive a payout.
