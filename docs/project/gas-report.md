# Gas Report

Measured on local devnet (Anvil, chain 31337). All values are actual `gasUsed` from executed transactions.

**Assumptions:** 1 gwei gas price (BNB Chain typical), BNB @ $600

## Results

| Function | Gas | USD @ 1 gwei |
|----------|----:|------:|
| **Vault.deposit** | 27,853 | $0.017 |
| **Vault.withdraw** | 39,943 | $0.024 |
| **MarketFactory.createMarket** | 257,716 | $0.155 |
| **placeOrder (BID GTC, first)** | 276,265 | $0.166 |
| **placeOrder (BID GTC, second)** | 207,865 | $0.125 |
| **placeOrder (BID GTB)** | 190,753 | $0.114 |
| **placeOrder (ASK GTC, crossing)** | 276,328 | $0.166 |
| **placeOrder (ASK GTC, non-crossing)** | 259,228 | $0.156 |
| **cancelOrder** | 74,376 | $0.045 |
| **clearBatch** (4 orders, 2 crossing) | 307,567 | $0.185 |
| **claimFills** (full fill, BID→YES) | 183,539 | $0.110 |
| **claimFills** (full fill, ASK→NO) | 148,688 | $0.089 |
| **claimFills** (no fill) | 60,354 | $0.036 |
| **pruneExpiredOrder** | 114,490 | $0.069 |
| **closeMarket** | 101,097 | $0.061 |

## Key Observations

### User Costs
- **Place + claim flow:** ~$0.28 per trade (placeOrder + claimFills)
- **Deposit + place:** ~$0.18 first time, ~$0.14 subsequently
- Very cheap on BNB Chain — even at 5 gwei, a full trade is ~$1.40

### Keeper Costs (Current Design — Separate Claims)
Per batch with N filled orders:
- **clearBatch:** ~$0.19
- **claimFills × N:** ~$0.10-0.11 per order
- **Example:** 10 filled orders = $0.19 + 10×$0.10 = **$1.19 per batch**
- **Example:** 50 filled orders = $0.19 + 50×$0.10 = **$5.19 per batch**

### Keeper Costs (Inline Settlement — Proposed)
With settlement folded into `clearBatch`:
- Estimated: clearBatch + N×(settlement overhead) ≈ **307k + N×130k gas**
- Saves ~50k gas per order (no separate tx overhead, no redundant SLOADs)
- **Example:** 10 orders ≈ 1.6M gas = **$0.96** (saved $0.23)
- **Example:** 50 orders ≈ 6.8M gas = **$4.08** (saved $1.11)
- **Block gas limit (BNB):** 140M — can settle ~1,000 orders per batch before hitting limits

### Monthly Keeper Costs (Estimates)
Assuming 1 market, 60-second batches, avg 5 filled orders per batch:

| Scenario | Batches/day | Orders/day | Monthly Cost |
|----------|------------|------------|-------------|
| Low activity | 100 | 500 | ~$80 |
| Medium | 500 | 2,500 | ~$400 |
| High | 1,440 | 7,200 | ~$1,100 |

With inline settlement, keeper costs drop ~20% and users save the claim tx entirely.

---

*Generated: 2026-03-10 | Script: `contracts/script/gas-report.sh`*
