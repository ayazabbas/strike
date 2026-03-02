# Key Concepts

## Outcome Tokens

Every market has two outcome tokens: **YES** and **NO**. They are ERC-1155 tokens, fully collateralized.

- **Minting:** Deposit 1 unit of collateral → receive 1 YES + 1 NO token. Tokens are always minted as a pair.
- **Merging:** Return 1 YES + 1 NO → get your collateral back. Available anytime before resolution.
- **Redemption:** After resolution, winning tokens redeem 1:1 for collateral. Losing tokens are worthless.

Since YES + NO always equals 1.00 of collateral, prices on the orderbook represent implied probabilities. A YES token trading at 0.65 implies a 65% probability of the outcome occurring.

## Ticks

Prices on the orderbook use a **tick system**: 99 discrete price levels from 0.01 to 0.99, at 1-cent granularity. You can place orders at any tick.

## Batch Intervals

The orderbook doesn't match orders continuously. Instead, orders accumulate and are matched every **batch interval** (~3 seconds by default). This is configurable per market.

## Clearing Price

Each batch that has crossing orders (bids ≥ asks) produces a single **uniform clearing price**. This is the tick that maximizes total matched volume. All fills in that batch happen at this price.

## Pro-Rata Fills

If one side of the book has more volume than the other at the clearing price, the oversubscribed side is filled **pro-rata** — proportional to each order's size. No single order gets priority within a batch.

## Order Types

| Type | Behavior |
|------|----------|
| **Limit** | Rests on the book until filled, cancelled, or expired |
| **Post-Only** | Rejected if it would immediately cross the book (maker protection) |
| **IOC** | Fills in the current batch or is cancelled — never rests |
| **Batch-Only** | Valid for the next batch only, auto-expires after clearing |

## Collateral

All orders are fully collateralized. When you place a bid (buy YES), you lock collateral. When you place an ask (sell YES), you lock YES tokens. There is no leverage or margin.
