# World Cup Markets

Strike’s World Cup section is a campaign-style prediction experience for the 2026 FIFA World Cup. It starts with the **2026 World Cup Winner** market and is designed to support additional World Cup match or tournament markets over time.

The live app is available at [app.strike.pm/world-cup](https://app.strike.pm/world-cup).

For the fixed-multiplier exact-result product used by the first World Cup event series, see [Multiplier Predictions](world-cup-multiplier-predictions.md).

## What you can trade

### 2026 World Cup Winner

The winner market lets users back one of the named national teams supported by the World Cup resolver. Each team is an outcome in one shared pool.

- Pick the team you think will win the 2026 FIFA World Cup.
- Enter how much USDT value you want to place into the pool.
- Your position receives reward shares for that team.
- If your team wins, you claim your eligible payout after resolution.

### Future World Cup markets

Strike may also list individual match or tournament-stage markets during the campaign. These can use the same World Cup campaign credit system while still showing a simple USDT-denominated experience to users.

## Wallet USDT and bonus credit

World Cup markets can accept two funding sources:

- **Wallet USDT** — normal USDT from your connected wallet.
- **Bonus credit** — campaign credit that can be used to enter World Cup markets.

The user interface shows both as **USDT value in the pool** to keep the experience simple. Internally, Strike still accounts for wallet USDT and bonus credit separately so campaign-credit principal cannot be treated as freely withdrawable profit.

When “use bonus credit first” is enabled, the app spends available credit first and tops up the rest of the same position with wallet USDT if needed.

## Early betting incentive

The World Cup winner market rewards earlier correct predictions with more reward shares per USDT.

Each tournament round has a multiplier. Earlier rounds have higher multipliers because less information is available. Later rounds have lower multipliers because teams have already advanced or been eliminated.

Example schedule:

| Stage | Multiplier |
| --- | ---: |
| Pre-tournament | 4.0× |
| Early group stage | 2.5× |
| Late group stage | 1.6× |
| Round of 32 | 1.0× |
| Round of 16 | 0.7× |
| Quarter-final | 0.45× |
| Semi-final | 0.3× |
| Final build-up | 0.2× |

A $10 pre-tournament pick therefore earns many more reward shares than a $10 pick made near the final. Both risk the same principal amount, but the earlier correct pick owns a larger share of the winning side.

## KOL signal icons

Strike can highlight selected traders or creators directly on outcome cards.

If a highlighted wallet backs an outcome, that outcome can show a small stacked avatar signal. These icons are informational only: they show that a highlighted account has taken a position, but they are not trading advice and do not guarantee any outcome.

When a profile link is configured, the icon can link to the KOL’s social profile.

## Resolution and settlement

World Cup markets resolve through the configured resolver for that market type. The winner market uses the World Cup resolver for final team outcome data, with admin fallback available for exceptional cases.

After resolution:

- Winning positions can claim according to the market’s payout rules.
- Invalidated markets refund eligible principal.
- Bonus-credit accounting remains separate behind the scenes, even when the UI shows a simplified USDT value.

## Important notes

- Market prices and pool percentages can change as users trade.
- Bonus credit may have campaign-specific restrictions.
- KOL icons are social/context signals, not endorsements by Strike.
- Always review the selected team, amount, and funding split before confirming a transaction.
