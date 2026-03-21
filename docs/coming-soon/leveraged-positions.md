# Leveraged Positions

> **Status: Coming Soon** — This feature is in the design phase.

## Overview

Strike will support **leveraged binary positions** on short-duration markets (e.g. 5-minute BTC/USD), allowing traders to amplify their exposure without needing more capital upfront.

Leverage is backed by a **protocol liquidity vault** — similar to how HLP powers Hyperliquid or JLP powers Jupiter. Vault depositors provide the additional collateral for leveraged trades and earn yield from trading fees and trader losses.

## How It Works

### Without Leverage (Current)

A trader buys YES at tick 50 ($0.50):
- Pays **$0.50** per lot
- Wins **$1.00** if YES (2x return on capital)
- Loses **$0.50** if NO

### With 3x Leverage

A trader buys YES at tick 50 with 3x:
- Pays **$0.50** per lot (same as before)
- Vault locks an additional **$1.00** per lot as backing
- Wins **$1.50** if YES (the vault contributes the extra $0.50)
- Loses **$0.50** if NO (vault keeps its locked capital + collects a premium)

The trader's risk/reward is amplified, but max loss is still capped at their collateral — no liquidations.

### Why Binary Markets Make This Simple

Unlike perpetual futures where leverage can lead to cascading liquidations:

- **Bounded outcomes** — binary markets resolve to 0 or 1. The vault's maximum liability per lot is known at order time
- **Short duration** — capital is locked for minutes, not indefinitely. Vault utilization turns over rapidly
- **No funding rates** — positions expire naturally, no need for continuous balancing

## The Strike Liquidity Vault (SLV)

### For Depositors

- Deposit USDT into the SLV, receive SLV LP tokens
- Earn yield from:
  - **Leverage premiums** — fees charged on leveraged positions
  - **Trader losses** — when leveraged traders lose, the vault keeps their collateral plus the unlocked backing
  - **Trading fees** — share of protocol fees
- Withdraw anytime (subject to utilization — if vault capital is locked in active markets, withdrawals may be partially delayed until markets resolve)

### For Traders

- Select leverage multiplier (2x, 3x, 5x, 10x) when placing an order
- Pay a **leverage premium** on top of the standard trading fee — scales with multiplier and vault utilization
- Max loss is always your collateral — no liquidation risk
- Payouts are automatically calculated and settled at market resolution

## Vault Risk Management

The vault has built-in safeguards:

| Parameter | Purpose |
|---|---|
| **Max leverage** | Per-market cap (e.g. 10x) based on market type and duration |
| **Max vault exposure per market** | Limits how much of the vault can be locked in a single market |
| **Utilization-based pricing** | Leverage premium increases as vault utilization rises — naturally throttles demand when capital is scarce |
| **Diversification** | Vault exposure is spread across many concurrent 5-minute markets — individual market outcomes average out |

### Why The Vault Wins Long-Term

Short-duration binary markets have a statistical edge for the house:
- Retail traders tend to lose more than they win on rapid directional bets
- The leverage premium provides guaranteed income regardless of outcomes
- High turnover (5-minute cycles) means the law of large numbers kicks in fast
- Vault is diversified across many concurrent markets — variance is smoothed

This is the same dynamic that makes HLP consistently profitable on Hyperliquid.

## Premium Pricing

The leverage premium can be structured in different ways:

**Option A — Fixed fee per multiplier:**

| Leverage | Premium |
|---|---|
| 2x | 1% of position |
| 3x | 2% |
| 5x | 4% |
| 10x | 8% |

Simple, predictable for traders.

**Option B — Dynamic (utilization-based):**

Premium scales with vault utilization — cheap when the vault is idle, expensive when heavily utilized. Similar to Aave/Compound interest rate curves.

```
premium = baseFee × leverage × utilizationMultiplier
```

More capital-efficient, but less predictable for traders.

## Example Scenario

**Market:** BTC above $84,500 in 5 minutes? (tick 50 = $0.50)

| Trader | Action | Leverage | Pays | Vault Locks | If YES Wins | If NO Wins |
|---|---|---|---|---|---|---|
| Alice | Buy YES | 1x | $50 | $0 | +$50 | -$50 |
| Bob | Buy YES | 3x | $50 | $100 | +$100 | -$50 |
| Carol | Buy NO | 5x | $50 | $200 | -$50 | +$200 |

- Bob pays a 2% premium ($1) for 3x leverage
- If YES wins: Bob gets $150 ($50 collateral + $100 from vault). Vault is down $100 on Bob but keeps Carol's $50 + $200 locked backing
- Net vault P&L depends on aggregate outcomes across all traders and markets

## Comparison

| | Strike Leveraged | Perp DEX (Hyperliquid) | Binary Options (traditional) |
|---|---|---|---|
| Max loss | Collateral only | Collateral (liquidation) | Collateral only |
| Liquidation risk | None | Yes | None |
| Duration | Fixed (5 min) | Indefinite | Fixed |
| Funding rates | None | Continuous | None |
| Vault model | SLV (like HLP) | HLP | House/bookmaker |
| Settlement | On-chain, deterministic | Mark price | Often off-chain |

## Roadmap

- [ ] SLV vault contract (deposit/withdraw/LP tokens)
- [ ] Leverage parameter in order placement
- [ ] Premium pricing model (fixed or dynamic)
- [ ] Vault risk management (exposure caps, utilization curve)
- [ ] Frontend: leverage selector + P&L preview
- [ ] Backtesting: vault P&L simulation on historical 5-min data
- [ ] BSC testnet deployment
