# Trading Guide

Everything you need to know about trading on Strike.

## Understanding Prices

Every market on Strike has two outcomes: **UP** and **DOWN**. Tokens for each outcome trade between **$0.01** and **$0.99**.

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

One side always wins. When a market resolves, the winning token pays out **$1.00** and the losing token pays **$0.00**.

## Placing Orders

All orders on Strike are **limit orders**. You choose:

1. **Side** -- UP or DOWN
2. **Price** -- the most you're willing to pay (e.g., $0.35)
3. **Amount** -- how many lots you want

Your order sits on the orderbook until it's matched in the next batch.

## How Batches Work

Strike uses **Frequent Batch Auctions** for fair price discovery. Here's how it works:

1. Orders are collected over a short window (a few seconds).
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

If you held the winning token, you receive **$1.00 per token**. Your profit is $1.00 minus what you paid.

## Fees

Strike charges a flat **0.20% fee** (20 basis points) on every trade. The fee is split evenly -- 0.10% from the buyer and 0.10% from the seller. That's it. No hidden costs, no variable rates.
