# Key Concepts

## Market Types

Strike supports three live market surfaces:

- **FBA orderbook markets** — binary UP/DOWN or YES/NO markets with limit orders, batch clearing, and active position management.
- **Standard parimutuel pool markets** — 2–8 outcome markets where users buy into outcome pools and winners split losing pools.
- **Flap Token Pools** — creator-launched BEP20-collateral pools with FLAP AI resolution from an on-chain prompt.

## Orderbook Positions

Every orderbook market has two sides: **UP** and **DOWN**. Current 5-minute markets use **internal positions** tracked on-chain, fully collateralized. (The contracts also include an ERC-1155 token system for future market types, but it is not used for 5-minute markets.)

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


## Parimutuel Pools

Parimutuel markets have 2–8 outcomes. Instead of placing limit orders, you choose an outcome and buy into its pool. Your position is an internal claim on that outcome's pool.

If your outcome wins, you receive your winning principal back plus a proportional share of the losing outcome pools. If the market is invalid or cancelled, you can refund your principal.

## Trading Close vs. Resolution Time

Parimutuel V2 markets have two distinct timestamps:

- **Trading close time** — when buying into pools stops.
- **Resolution time** — the event/reference timestamp used by admin, AI, or Pyth resolution.

This lets Strike support markets where betting should stop before the outcome is known, such as sports events, elections, or price-range markets.


## Flap Token Pools

Flap Token Pools are creator-launched parimutuel markets backed by a selected BEP20 token. Creators define outcomes, timing, and a resolution prompt; Strike uses a fixed FLAP AI resolver and official hash-checked metadata before the pool is shown in the app.

The current public flow is optimized for token-data prompts resolvable from Ave-supported data, such as price, liquidity, volume, FDV, or market cap.
