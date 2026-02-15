# Gas & Fees

## Gas Costs

Measured on BSC testnet:

| Operation | Gas | Approx. Cost (BSC) |
|-----------|-----|-------------------|
| `createMarket()` | ~440,000 | ~$0.03 |
| `bet()` | ~98,000 | ~$0.01 |
| `resolve()` | ~96,000 | ~$0.01 |
| `claim()` | ~29,000 | < $0.01 |
| `refund()` | ~29,000 | < $0.01 |

BSC gas costs are extremely low — a full market lifecycle (create → bet → resolve → claim) costs under $0.06.

## Protocol Fee

- **Rate:** 3% (300 basis points)
- **Charged on:** Winning pool only (not total pool)
- **When:** At resolution time
- **Collected by:** Fee collector address set in MarketFactory

### Fee Calculation Example

| | Amount |
|---|---|
| Total pool | 1.0 BNB |
| Winning side pool | 0.4 BNB |
| Losing side pool | 0.6 BNB |
| Protocol fee (3% of 1.0 BNB) | 0.03 BNB |
| Distributed to winners | 0.97 BNB |

Winners receive their proportional share of 0.97 BNB based on their share count.

## Minimum Bet

- **Amount:** 0.001 BNB (~$0.30 at current prices)
- **Why:** Prevents dust bets that would cost more in gas than they're worth

## Pyth Oracle Fees

- Pyth charges a small fee for price updates (1 wei on BSC testnet)
- This fee is included in the `createMarket()` and `resolve()` transactions
- The MarketFactory contract includes a `receive()` function to handle Pyth fee refunds

## Cost Summary for Users

| Action | Cost |
|--------|------|
| Place a bet | Bet amount + ~$0.01 gas |
| Claim winnings | ~$0.01 gas |
| Get a refund | ~$0.01 gas |

There are no hidden fees. The 3% protocol fee is only charged on winnings — if you lose, you lose exactly what you bet and nothing more.
