# How It Works

## The Game Loop

Strike runs on a continuous 5-minute cycle:

```
:00  Market opens → Strike price captured from Pyth
:00 - :02:30  Betting window (first half of duration)
:02:30  Betting closes (anti-frontrun lock)
:05  Market expires → Pyth price fetched → Winners determined
:05  New market opens → Cycle repeats
```

Markets are created at clean 5-minute intervals — on the hour, :05, :10, :15, etc.

## Parimutuel Model

Strike uses a **parimutuel** betting model — the same system used in horse racing and many prediction markets.

### How It Works

1. All bets go into a shared pool
2. The pool is split into two sides: **UP** and **DOWN**
3. When the market resolves, the winning side splits the entire pool
4. Your share = your bet / total winning side bets

### Example

| Player | Side | Bet |
|--------|------|-----|
| Alice | UP | 0.1 BNB |
| Bob | UP | 0.1 BNB |
| Charlie | DOWN | 0.2 BNB |

**Total pool:** 0.4 BNB

If BTC goes **UP**:
- Alice gets: (0.1 / 0.2) × 0.4 = **0.2 BNB** (2x return)
- Bob gets: (0.1 / 0.2) × 0.4 = **0.2 BNB** (2x return)
- Charlie gets: **0 BNB**

If BTC goes **DOWN**:
- Charlie gets: (0.2 / 0.2) × 0.4 = **0.4 BNB** (2x return)
- Alice and Bob get: **0 BNB**

A 3% protocol fee is deducted from the winning pool before distribution.

### Early Bird Bonus

Bets placed earlier in the betting window receive a multiplier on their shares (up to 2x at market open, decreasing linearly to 1x at trading close). This incentivizes early participation and discourages waiting until the last second.

## Edge Cases

- **One-sided market** (everyone bets the same way): All bets are refunded. No one loses.
- **Exact price tie** (resolution price = strike price): All bets are refunded.
- **No resolution within 24h**: Market auto-cancels and all bets are refunded.
- **Empty market** (no bets): Market expires silently, no action needed.

## Oracle Resolution

Markets are resolved using [Pyth Network](https://pyth.network/) price feeds.

1. At market creation, the **strike price** is captured from the current Pyth BTC/USD feed
2. At expiry, the **resolution price** is fetched from Pyth
3. If resolution price > strike price → **UP wins**
4. If resolution price < strike price → **DOWN wins**
5. If resolution price = strike price → **Tie, all refunded**

The Pyth price data is verified on-chain — the contract checks the Pyth signature and price staleness (max 60 seconds old).

## User Flow

```
1. /start → Bot creates your wallet (Privy embedded wallet)
2. Fund wallet → Send tBNB to your wallet address
3. Browse markets → See the current open market with live BTC price
4. Place a bet → Tap UP or DOWN, choose an amount
5. Wait 5 minutes → Market resolves automatically
6. Claim winnings → If you won, collect your share of the pool
```
