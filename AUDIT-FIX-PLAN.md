# Strike V2 Audit — Fix Plan

**Date:** 2026-03-12
**Based on:** AUDIT-REPORT.md (commit `5350a15`)

## Scope

Addressing findings that represent real bugs or attack vectors. Excluding:
- **C-02 (Admin resolve)** — Intentional. Need manual resolution fallback if Pyth has issues.
- **H-02 (Short finality)** — Accepted risk for now.
- **M-04 (Challenge delay)** — Low practical impact. Bounded by Pyth publish window.
- **L-01 (int64 min overflow)** — Theoretical only, asset prices are always positive.

---

## Fix 1: Pool Insolvency (C-01) — CRITICAL

**Problem:** Fees deducted from collateral before it enters the pool. Redemption pays full LOT_SIZE. Pool is always short by total fees. Last redeemers can't withdraw.

**Fix:** Charge fees from the excess refund, not from the pool contribution.

Currently the flow is:
```
filledCollateral = lots * tick_price
fee = filledCollateral * 20bps
toPool = filledCollateral - fee          ← pool underfunded
refund = lockedCollateral - filledCollateral
```

New flow:
```
filledCollateral = lots * tick_price
toPool = filledCollateral                ← pool gets full amount
fee = min(refund, filledCollateral * 20bps)
refund = lockedCollateral - filledCollateral - fee
```

Both sides of a matched lot contribute their clearing-price collateral to the pool in full. Fees come from the excess (the difference between what was locked at the order's limit tick and what was needed at clearing). If the order fills exactly at its limit tick (no excess), the fee is 0 for that side — this is fine since the other side will have excess unless clearing is at 50/50.

**Edge case — clearing at limit tick:** If a bid at tick 60 fills at clearing tick 60, there's zero excess. Fee would be 0. Total fee per lot would only come from the ask side. This means fees scale with the spread between order tick and clearing tick, which is actually a natural incentive: tighter orders pay less, wider orders pay more. If we don't like this, alternative is to lock `collateral + fee` upfront at order placement (requires changing `placeOrder`).

**Decision needed:** Option A (fees from excess, simpler, variable fee revenue) vs Option B (lock collateral + fee upfront, consistent fee revenue but changes order flow).

**Recommendation:** Option B — lock `collateral + maxFee` at placement. Fee is always `filledCollateral * feeBps / 10000`, deducted from the locked amount separately. Pool always gets `filledCollateral` in full. User's locked amount = `collateral + fee` where fee is based on their limit price. Refund = `locked - filledCollateral - actualFee`.

**Files:** `BatchAuction.sol` (_settleAmounts), `OrderBook.sol` (placeOrder collateral calc), `Vault.sol` (lock amounts)

**Tests:** Add a test that creates a market, fills orders, resolves, and redeems ALL tokens — assert Vault pool balance == 0 after all redemptions (currently fails).

---

## Fix 2: GTC Rollover Cap (H-01) — HIGH

**Problem:** `pushBatchOrderId` has no max check. GTC rollovers bypass the 400-order cap. Batches can grow unbounded → clearBatch exceeds block gas limit → stuck funds.

**Fix:** Enforce the cap in `pushBatchOrderId`. If next batch is full, auto-cancel the GTC order and refund the user.

```solidity
function pushBatchOrderId(uint256 marketId, uint256 batchId, uint256 orderId)
    external onlyRole(OPERATOR_ROLE)
{
    require(
        batchOrderIds[marketId][batchId].length < MAX_ORDERS_PER_BATCH,
        "OrderBook: batch full"
    );
    batchOrderIds[marketId][batchId].push(orderId);
}
```

In `BatchAuction._settleOrder` where GTC rollover happens: if `pushBatchOrderId` reverts (batch full), catch and auto-cancel the order, unlocking collateral.

Alternative: don't revert, just cancel inline. Add a return bool to `pushBatchOrderId` and handle gracefully.

**Files:** `OrderBook.sol` (pushBatchOrderId), `BatchAuction.sol` (_settleOrder GTC rollover logic)

**Tests:** Place 400 GTC orders, clear (none fill), place 400 more new orders in next batch. Verify the GTC rollovers are handled (capped or cancelled) and clearBatch succeeds.

---

## Fix 3: Reentrancy Guard on clearBatch (M-02) — MEDIUM

**Problem:** `clearBatch` makes external calls in a loop (Vault, OrderBook, OutcomeToken ERC-1155 with receiver hooks) but has no `nonReentrant`.

**Fix:** Add `nonReentrant` modifier to `clearBatch`. Simple, no downside.

**Files:** `BatchAuction.sol`

---

## Fix 4: Emergency Pool Recovery (M-01) — MEDIUM

**Problem:** In emergency mode, `emergencyWithdraw` only returns user `balance`. Funds in `marketPool[marketId]` are stuck forever if Redemption contract is broken or market never resolves.

**Fix:** Add `emergencyDrainPool(uint256 marketId)` callable only by admin when emergency mode is active. Distributes pool funds pro-rata to outcome token holders, or sends to a recovery address.

Simpler approach: in emergency mode, allow admin to call `emergencyDrainPool(marketId, recipient)` with a timelock or multi-sig requirement. This is a last resort.

**Files:** `Vault.sol`

---

## Fix 5: confThreshold Minimum (M-03) — MEDIUM

**Problem:** `confThresholdBps = 0` blocks all oracle resolutions since every Pyth price has non-zero confidence.

**Fix:** Add `require(newBps >= 10)` in `setConfThreshold`. One line.

**Files:** `PythResolver.sol`

---

## Fix 6: Pro-Rata Rounding (H-03) — HIGH (but bounded)

**Problem:** Integer division in `_calcFilledLots` rounds down. Sum of individual fills < matchedLots. Creates phantom volume in segment tree.

**Assessment:** This is a real issue but the impact is bounded — the phantom volume per batch is at most `n-1` lots (where n = number of orders on the larger side). For 400 orders that's 399 lots maximum phantom volume. Over many batches this accumulates but the clearing price impact is marginal since the segment tree has 128 ticks of resolution.

**Fix:** After iterating all orders in a batch, compute `actualFilled = sum(individual fills)`. If `actualFilled < matchedLots`, assign the remainder (`matchedLots - actualFilled`) to the last order. This ensures total fills == matchedLots exactly.

**Files:** `BatchAuction.sol` (clearBatch settlement loop)

---

## Fix 7: Stale Cancelled Orders in Batch (L-02) — LOW

**Problem:** Cancelled orders stay in `batchOrderIds`, wasting gas during `clearBatch`.

**Fix:** Accept as-is. The early return for 0-lot orders is cheap (~2k gas per skip). Fixing requires array surgery (swap + pop) which adds complexity. Not worth it unless cancellation rates are very high.

**Status:** Won't fix.

---

## Fix 8: Minimum Market Duration (L-03) — LOW

**Problem:** Markets can be created with duration barely > interval (e.g., 61 seconds).

**Fix:** Add `require(duration >= 600)` in `createMarket`. Easy, one line.

**Files:** `MarketFactory.sol`

---

## Implementation Order

1. **C-01 (Pool insolvency)** — Most critical, affects every market. Do first.
2. **H-01 (GTC rollover cap)** — Attack vector for stuck funds. Do second.
3. **M-02 (Reentrancy guard)** — One-line fix, do alongside above.
4. **H-03 (Rounding remainder)** — Fix during the clearBatch work for H-01.
5. **M-01 (Emergency pool drain)** — Safety net.
6. **M-03 (confThreshold min)** — One-line fix.
7. **L-03 (Min duration)** — One-line fix.

Estimated scope: ~200-300 lines of contract changes + ~400 lines of new tests.
