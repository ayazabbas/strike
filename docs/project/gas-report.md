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

## Key Observations

### User Costs
- **Place order:** ~$0.13-0.17 per order
- Very cheap on BNB Chain — even at 5 gwei, a trade is under $1

### Keeper Costs (Inline Settlement)
Settlement is folded into `clearBatch` — all orders are settled atomically. No separate claim step.

Per batch with N filled orders:
- Estimated: clearBatch + N×(settlement overhead) ≈ **307k + N×130k gas**
- **Example:** 10 orders ≈ 1.6M gas = **$0.96**
- **Example:** 50 orders ≈ 6.8M gas = **$4.08**
- **Block gas limit (BNB):** 140M — can settle ~1,000 orders per batch before hitting limits

### Monthly Keeper Costs (Estimates)
Assuming 1 market, 60-second batches, avg 5 filled orders per batch:

| Scenario | Batches/day | Orders/day | Monthly Cost |
|----------|------------|------------|-------------|
| Low activity | 100 | 500 | ~$65 |
| Medium | 500 | 2,500 | ~$325 |
| High | 1,440 | 7,200 | ~$900 |

---

*Generated: 2026-03-18 | Script: `contracts/script/gas-report.sh`*
