# Key Concepts

## Positions

Every market has two sides: **UP** and **DOWN**. Current 5-minute markets use **internal positions** tracked on-chain, fully collateralized. (The contracts also include an ERC-1155 token system for future market types, but it is not used for 5-minute markets.)

- **Filling:** When your order fills, your position is credited internally. Positions are tracked per user, per market, per side.
- **Settlement:** After resolution, winning positions pay out automatically at $0.01 per lot. Losing positions are worthless.

Since UP + DOWN always equals $0.01 of collateral per lot, prices on the orderbook represent implied probabilities. An UP position trading at $0.65 implies a 65% probability of the outcome occurring.

## Ticks

Prices on the orderbook use a **tick system**: 99 discrete price levels from $0.01 to $0.99, at 1-cent granularity. You can place orders at any tick.

## Batch Intervals

The orderbook doesn't match orders continuously. Instead, orders accumulate and are matched in periodic batches. The clearing cadence is determined by the keeper — there is no on-chain interval enforcement.

## Clearing Price

Each batch that has crossing orders (bids >= asks) produces a single **uniform clearing price**. This is the tick that maximizes total matched volume. All fills in that batch settle at this clearing price — not at each order's limit tick. Any excess collateral (difference between order tick and clearing tick) is refunded automatically.

## Pro-Rata Fills

If one side of the book has more volume than the other at the clearing price, the oversubscribed side is filled **pro-rata** — proportional to each order's size. No single order gets priority within a batch.

## Order Types

| Type | Behavior |
|------|----------|
| **GoodTilCancel (GTC)** | Rests on the book until filled or cancelled by the owner |
| **GoodTilBatch (GTB)** | Valid for the next batch only — auto-expires after clearing if unfilled |

## Collateral

All orders are fully collateralized with **USDT** (ERC-20). Users must approve the Vault contract before placing orders. When you place a bid (buy UP), you lock USDT proportional to the tick price. When you place an ask (buy DOWN), you also lock USDT proportional to `(100 - tick)`. Both sides lock USDT — asks do NOT require pre-existing positions. Each lot represents $0.01 of collateral (LOT_SIZE = 1e16). There is no leverage or margin.
