# USDT Parimutuel V3 Notes

This pass adds an isolated USDT Parimutuel V3 contract layer for World Cup game markets. It is intentionally separate from live V2 contracts.

Implemented:

- Admin-created 2-8 outcome markets with trading close, resolution time, metadata, fee bps, credit event ID, and credit enabled flag.
- Real USDT buys with vault custody and separate real positions.
- USDT-credit buys through `USDTCreditReserve.lockCredit`, with separate credit positions.
- Admin resolution, invalidation, and cancellation.
- Refunds that return real principal as USDT and return credit principal with `returnLockedCredit`.
- Resolved claims that use combined parimutuel economics while splitting settlement by source:
  - real winners receive USDT from the V3 vault;
  - credit winners receive reserve ledger credit via `settleCreditPayout`;
  - credit loser backing for real winners is withdrawn through `settleCreditPayoutAndWithdraw`;
  - real loser backing for credit winners is transferred from the vault to the reserve and recorded with `fundFromMarketSettlement`.
- Source-specific reserve/vault movements use a per-market snapshot of the resolved winning pool's real-vs-credit reward-share mix. This avoids changing backing allocation when winners claim in different orders.
- After resolution, `marketTotalPrincipal` is treated as the remaining settlement pot, not as a strict sum of outcome pool position aggregates. `consumeClaim` debits it by the real plus credit payout exactly once, while also removing every real/credit position deleted for the claimant from the corresponding outcome pool. This keeps sequential payout math stable and prevents stale mixed-position pool shares after a claimant held both winning and losing outcomes.

Deferred:

- AI/Pyth resolver adapters and admin fallback complexity from V2.
- Batch buys and piecewise/log pricing curves.
- Production deployment wiring, frontend/backend integration, and market-creation automation.
- Fee recipient treatment for credit-funded fee bps. Real-USDT fees accrue in the manager and are withdrawable to `feeRecipient`. Credit-funded fees are consumed from locked credit and remain as reserve surplus in this pass; paying credit fees out as USDT requires a product decision because it converts promotional backing into protocol revenue.

Credit losing accounts are settled with an explicit user list through the redemption path. This keeps settlement bounded and reviewable for this first pass instead of adding an unbounded participant loop.
Real winners whose payout depends on losing credit backing must settle the relevant credit losers in the same claim transaction, or earlier, so the vault has the reserve-funded USDT needed for payout.
