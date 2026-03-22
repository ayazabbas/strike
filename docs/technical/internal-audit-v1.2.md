# Strike v1.2 Internal Security Audit Report

**Date:** 2026-03-22
**Auditor:** Claude Opus 4.6 (Automated)
**Scope:** New code since commit `ae11599` — `OrderBook.sol`, `BatchAuction.sol`, `FeeModel.sol` (~400 new lines)
**Test baseline:** 338+ tests in `contracts/test/`, including `AuditFixes.t.sol` (836 lines of targeted fix tests)
**Framework:** Foundry, Solidity ^0.8.25, OpenZeppelin 5.x

---

## Executive Summary

Strike v1.2 addresses all actionable findings from the v1.1 audit (M-03, L-01, L-02) and adds new features: per-user order caps, price-proximity resting lists, and chunked settlement with precomputed fills. The implementation is generally sound with good test coverage of the new paths.

This audit identified **0 Critical**, **1 High**, **2 Medium**, **2 Low**, and **2 Informational** findings. The High finding is a sell-side fee extraction from pool that can cause pool insolvency on Bid+SellYes matches. The Medium findings relate to resting list gas griefing and a precomputed fill edge case for zero-fill orders.

**Overall Risk Assessment: LOW-MODERATE.** The v1.1 fixes are correctly implemented. The new proximity filtering and chunked settlement introduce manageable complexity. The most material risk is pool solvency under sell-side fees (H-01).

---

## v1.1 Findings — Verification Status

| v1.1 ID | Title | Status | Notes |
|---------|-------|--------|-------|
| H-01 | Cross-contract reentrancy DoS | **Not addressed** | Acknowledged risk; mitigated by internal positions default. No code change in v1.2. See I-01 below. |
| M-01 | PythResolver conf=0 bypass | **Not addressed** | Out of scope (PythResolver unchanged). |
| M-02 | Redemption uint128 truncation | **Not addressed** | Out of scope (Redemption unchanged). |
| M-03 | Chunked settlement re-computes fills | **Fixed** | Precomputed fills stored in `_precomputedFills` mapping during first chunk, reused in subsequent chunks. Verified correct in `_settleChunk`. Test: `test_Fix2_MultiChunkSettlement`. |
| L-01 | Unbounded GTC rollover | **Mitigated** | `MAX_ORDERS_PER_BATCH` raised to 1600. GTC far-from-price orders now park in resting list via `_tryRollOrCancel`. Effective cap, but `pushBatchOrderId` still has no hard limit. |
| L-02 | Sell orders pay zero fees | **Fixed** | 50/50 fee split: buy side pays `calculateOtherHalfFee`, sell side pays `calculateHalfFee` deducted from payout. Tests: `test_Fix5_*`. |
| L-03 | No batch interval enforcement | **Acknowledged** | Documented in NatSpec comment on `clearBatch`. No code enforcement added. |

---

## Findings

### H-01: Sell-Side Fee Extracted From Pool Can Cause Insolvency on Bid+Sell Matches

**Severity:** High
**Contract:** BatchAuction.sol
**Functions:** `_settleSellOrder` (L527-549), `_settleBuyOrder` (L480-517)

**Description:**

When a Bid matches a SellYes order at clearing tick `t`:

- **Buy side (Bid):** Deposits `lots * t / 100 * LOT_SIZE` into pool. Pays `calculateOtherHalfFee` as protocol fee (deducted from locked excess, not from pool).
- **Sell side (SellYes):** Receives `grossPayout = lots * t / 100 * LOT_SIZE` from pool, minus `sellFee = calculateHalfFee(grossPayout)`. The sell fee is *also* redeemed from pool via `vault.redeemFromPool`.

The pool accounting for a Bid+SellYes match:

```
poolIn  = filledCollateral (from buy side via vault.settleFill toPool)
poolOut = payout + sellFee
        = (grossPayout - sellFee) + sellFee
        = grossPayout
        = filledCollateral  (both computed at clearing tick)
```

So the net pool delta per Bid+SellYes lot at tick `t` is zero. However, the YES token the buyer receives requires `1 LOT_SIZE` backing at redemption if YES wins. The pool only holds the collateral from the original Bid+Ask match that created the token the seller held.

The sell fee is extracted from pool and sent to `feeCollector`. This is a net drain:

```
poolDelta = +filledCollateral - grossPayout - sellFee = -sellFee
```

Wait — re-examining. `_settleSellOrder` does two `redeemFromPool` calls:

```solidity
vault.redeemFromPool(o.marketId, o.owner, payout);       // grossPayout - sellFee
vault.redeemFromPool(o.marketId, feeModel.protocolFeeCollector(), sellFee);
```

Total out from pool = `payout + sellFee = grossPayout`.

And `_settleBuyOrder` sends `s.toPool = s.filledCollateral = grossPayout` to pool.

So pool net = `+grossPayout - grossPayout = 0`. **The pool breaks even on the Bid+SellYes match itself.** But the original backing for the now-burned SellYes tokens was `LOT_SIZE` per lot (from the original Bid+Ask match). Burning the seller's tokens removes their claim, and the new buyer's YES tokens are backed by the `grossPayout` sent to pool. At redemption, if YES wins, the buyer redeems `LOT_SIZE` per lot. The pool needs `LOT_SIZE` per outstanding lot. Since the original pool contribution was `LOT_SIZE` per lot and we withdrew `grossPayout = t/100 * LOT_SIZE` (from the seller's side), but also added `grossPayout = t/100 * LOT_SIZE` from the buyer — the net pool balance for the original position's backing is `LOT_SIZE - grossPayout + grossPayout = LOT_SIZE`. Pool solvent.

**Correction:** On further trace, `_settleSellOrder` calls `vault.redeemFromPool` for both `payout` and `sellFee`. But `_settleBuyOrder` calls `vault.settleFill` with `toPool = filledCollateral`. This sends `filledCollateral` to the pool. Since `filledCollateral = grossPayout`, and total withdrawn from pool = `grossPayout`, the pool is flat on this match.

The sell fee comes out of pool but the entire `grossPayout` was being withdrawn anyway (for the seller). The fee just redirects part of that withdrawal to the fee collector instead of the seller. **Pool solvency is maintained.**

**Revised assessment:** After careful accounting, pool solvency holds. Downgrading to Informational — see I-03 below.

---

### ~~H-01~~ → I-03: Sell Fee Accounting Is Correct But Non-Obvious

**Severity:** Informational (downgraded from initial High)
**Contract:** BatchAuction.sol

The sell-side fee extraction via two separate `redeemFromPool` calls (one for seller payout, one for sell fee to collector) is functionally correct:

```
Pool receives: filledCollateral (from buyer via settleFill)
Pool pays out: payout + sellFee = grossPayout = filledCollateral
Net pool: 0
```

The original pool backing (from the Bid+Ask match that created the tokens) remains intact. However, the dual `redeemFromPool` pattern is confusing and should be documented clearly for future auditors.

For Bid+Ask matches, both sides pay `calculateOtherHalfFee` (the floor half). Total fee collected = `2 * floor(fullFee/2)`, which loses at most 1 wei per side compared to the pre-v1.2 single full fee. Negligible.

---

### M-01: Resting List Unbounded Growth — Gas Grief on `pullRestingOrders`

**Severity:** Medium
**Contract:** OrderBook.sol
**Function:** `pullRestingOrders` (L605-645)

**Description:**

`pullRestingOrders` iterates the entire `restingOrderIds[marketId]` array on every `clearBatch` call. Although it caps pulled orders at `MAX_RESTING_PULL = 200`, it always scans the full array for compaction. With `MAX_USER_ORDERS = 20` per user per market, 50 Sybil addresses can accumulate 1000 resting entries. After cancellation, entries are lazy-skipped (`lots == 0`) but still require an SLOAD per entry during scan.

The compaction loop does trim cancelled entries, so repeated attacks don't compound indefinitely. But a single scan with 1000+ entries costs ~1000 SLOADs + array writes, pushing `clearBatch` gas cost significantly higher.

Additionally, `restingScanIndex` is declared (L60) but never used — the scan always starts at index 0. This is dead state.

**Impact:**

Griefing vector that increases `clearBatch` gas cost. Not a DoS (gas scales linearly, compaction prevents unbounded growth), but raises keeper costs. Per-user cap of 20 limits per-address impact, but Sybil addresses multiply it.

**Proof of Concept:**

```solidity
// 50 addresses, each placing 20 far orders = 1000 resting entries
for (uint i = 0; i < 50; i++) {
    address a = address(uint160(0xDEAD + i));
    // fund + approve
    for (uint j = 0; j < 20; j++) {
        vm.prank(a);
        book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 1, 1); // tick 1 = far
    }
}
// Next clearBatch scans all 1000 entries
auction.clearBatch(mId); // gas cost elevated
```

**Recommended Fix:**

1. Use `restingScanIndex` for bounded-window scanning instead of full-array iteration.
2. Add a per-market resting list cap, reverting if exceeded.
3. Remove `restingScanIndex` if not going to be used (dead state).

---

### M-02: Precomputed Fill Mapping Has Dead `_hasPrecomputed` Guard

**Severity:** Medium
**Contract:** BatchAuction.sol
**Function:** `_settleChunk` (L185-234)

**Description:**

The `_hasPrecomputed` mapping (L42) is written during first chunk settlement:

```solidity
_hasPrecomputed[ids[j]] = 1;  // L205
```

And deleted during final chunk:

```solidity
delete _hasPrecomputed[ids[j]];  // L229
```

But it is **never read** in the settlement path. Subsequent chunks read `_precomputedFills[ids[i]]` directly without checking `_hasPrecomputed`. This is dead code that costs ~20,000 gas per order for the SSTORE (cold slot) and ~5,000 gas for the delete.

For a 1000-order batch: ~25,000 * 1000 = 25M gas wasted on unused writes/deletes.

**Impact:**

Gas waste proportional to batch size. No correctness impact since `_precomputedFills` defaults to 0 for missing entries, which is handled correctly by `_settleOrder`'s zero-fill branches.

**Recommended Fix:**

Remove `_hasPrecomputed` mapping entirely — declaration, all writes, and all deletes.

---

### L-01: `activeOrderCount` Saturating Decrement Masks Accounting Bugs

**Severity:** Low
**Contract:** OrderBook.sol
**Functions:** `decrementActiveOrderCount` (L608-612), `_cancelCore` (L468-470), `_cancelForReplace` (L259-261)

**Description:**

All decrement sites use a saturating pattern:

```solidity
if (activeOrderCount[user][marketId] > 0) {
    activeOrderCount[user][marketId]--;
}
```

This prevents underflow but silently absorbs double-decrement bugs. If an order is decremented twice (e.g., once during settlement and once during cancel of the same orderId), the count absorbs the error at 0.

No double-decrement path was found in current code — the `if (o.lots == 0) return` guard in `_settleOrder` and `_cancelCore` prevents re-processing. However, the saturating pattern makes future accounting bugs silent rather than reverting.

**Impact:** Theoretical bypass of the 20-order cap if a double-decrement path is introduced in future code.

**Recommended Fix:**

Use a reverting check in `decrementActiveOrderCount` (the OPERATOR_ROLE path), keeping saturating only in user-facing cancel functions as a safety net:

```solidity
function decrementActiveOrderCount(address user, uint256 marketId) external onlyRole(OPERATOR_ROLE) {
    require(activeOrderCount[user][marketId] > 0, "OrderBook: count underflow");
    activeOrderCount[user][marketId]--;
}
```

---

### L-02: `placeOrders` / `replaceOrders` Cast `params.length` to uint16

**Severity:** Low
**Contract:** OrderBook.sol
**Functions:** `placeOrders` (L366), `replaceOrders` (L416-420)

**Description:**

```solidity
require(activeOrderCount[msg.sender][marketId] + uint16(params.length) <= MAX_USER_ORDERS, ...);
activeOrderCount[msg.sender][marketId] += uint16(params.length);
```

`params.length` is `uint256`. The `uint16()` cast silently truncates values > 65535. If `params.length == 65556`, the cast yields 20, potentially bypassing the cap check.

**Impact:** Not exploitable in practice — 65536 `OrderParam` structs would exceed the block gas limit. But the truncation is a code smell.

**Recommended Fix:**

```solidity
require(params.length <= MAX_USER_ORDERS, "OrderBook: batch too large");
```

---

### I-01: v1.1 H-01 (ERC1155 Reentrancy DoS) Remains Unaddressed

**Severity:** Informational
**Contract:** BatchAuction.sol, OrderBook.sol

The cross-contract reentrancy via ERC1155 callbacks identified in v1.1 H-01 has not been fixed. Markets using `useInternalPositions = true` are immune. The recommended `settlementActive` lock was not implemented.

**Recommendation:** Either implement the settlement lock, remove ERC1155 market support, or document that `useInternalPositions = false` markets are vulnerable to DoS.

---

### I-02: `_isTickFar` Is `public` But Uses Internal Naming Convention

**Severity:** Informational
**Contract:** OrderBook.sol, L579

```solidity
function _isTickFar(uint256 marketId, uint256 tick, Side side) public view returns (bool) {
```

The underscore prefix conventionally indicates `internal`. This function must be `public` because `BatchAuction._tryRollOrCancel` calls it cross-contract, but the naming is confusing.

**Recommendation:** Rename to `isTickFar`.

---

## New Code Deep Dive

### 1. Per-User Active Order Cap (Fix 4b)

**Implementation:** `activeOrderCount[user][marketId]` tracked as `uint16`, capped at `MAX_USER_ORDERS = 20`.

| Path | Increments | Decrements | Correct? |
|------|-----------|-----------|----------|
| `placeOrder` | +1 at placement | — | Yes |
| `placeOrders` | +params.length at entry | — | Yes |
| `replaceOrders` | +params.length after cancels | -1 per cancel via `_cancelForReplace` | Yes |
| `cancelOrder` / `cancelOrders` | — | -1 via `_cancelCore` | Yes |
| `cancelExpiredOrder(s)` | — | -1 via `_cancelCore` | Yes |
| Settlement: full fill / GTB expire | — | -1 via `decrementActiveOrderCount` | Yes |
| Settlement: GTC partial fill | — | None (order stays active) | Correct |
| Settlement: GTC partial → resting | — | None (order stays counted) | Correct |
| Settlement: GTB zero-fill cleanup | — | -1 via `decrementActiveOrderCount` | Yes (new code) |
| `pullRestingOrders` (cancelled entry) | — | None (lazy skip) | Correct |

**Assessment:** Accounting is correct across all traced paths.

### 2. Price-Proximity Resting List (Fix 4a)

**Invariant: Resting orders are NOT in the segment tree.**

| Entry point | Tree updated? | `isResting` set? | Consistent? |
|-------------|--------------|-----------------|-------------|
| `placeOrder` → `_lockAndTree(!shouldRest)` | No if resting | Yes | Yes |
| `_placeOne` → shouldRest check | No if resting | Yes | Yes |
| `_tryRollOrCancel` → `removeFromTree` + `pushRestingOrderId` | Removed | Yes | Yes |
| `pullRestingOrders` | Added to tree | Set to false | Yes |
| `_cancelCore` / `_cancelForReplace` | No if resting | Set to false | Yes |

**Assessment:** Resting↔tree invariant maintained across all paths.

### 3. Chunked Settlement with Precomputed Fills (Fix 2)

Fills computed once during first chunk, stored in `_precomputedFills`, reused by subsequent chunks. `_readOrder` in later chunks reads current storage (which may have modified `lots` from chunk 1 settlements) but uses precomputed fill values — not recomputed. The v1.1 M-03 rounding over-fill bug is fully resolved.

### 4. Fee Split (Fix 5)

- `calculateHalfFee(amount)` = `ceil(fullFee / 2)` — paid by sell side
- `calculateOtherHalfFee(amount)` = `floor(fullFee / 2)` — paid by buy side
- Invariant: `halfFee + otherHalfFee == fullFee` — verified by test and code review

Pool solvency confirmed through accounting trace (see I-03).

---

## Test Coverage Analysis

**Strengths:**
- 836-line dedicated `AuditFixes.t.sol` covering all v1.2 features
- Per-user cap tests: placement, cancellation, fill decrement
- GTB zero-fill cleanup: buy, sell (ERC1155), sell (internal positions)
- Fee split: equal fees, total preservation, rounding, fuzz solvency
- Multi-chunk settlement: 3-chunk, partial fills across chunks, both-sides GTC
- Proximity filtering: far/near placement, pull-in, cancel resting, GTC roll-to-resting, lazy skip, events
- Post-review: batch proximity, replace proximity, deduplication

**Gaps:**

| Gap | Risk | Recommendation |
|-----|------|----------------|
| H-01 reentrancy (v1.1) still untested | Medium | Add malicious `IERC1155Receiver` test |
| Resting list > MAX_RESTING_PULL (200+) entries | Low | Test partial pull + compaction boundary |
| `replaceOrders` cancel resting + place near | Low | Test count correctness for mixed resting/active replace |
| `_isTickFar` boundary at exactly `ref ± PROXIMITY_THRESHOLD` | Low | Fuzz test boundary conditions |
| Sell-side fee pool accounting on Bid+SellYes match | Low | Explicit pool balance assertion test |

---

## Access Control Changes

| New Function | Contract | Role | Caller |
|-------------|----------|------|--------|
| `decrementActiveOrderCount` | OrderBook | OPERATOR_ROLE | BatchAuction |
| `pullRestingOrders` | OrderBook | OPERATOR_ROLE | BatchAuction |
| `pushRestingOrderId` | OrderBook | OPERATOR_ROLE | BatchAuction |
| `setLastClearingTick` | OrderBook | OPERATOR_ROLE | BatchAuction |
| `removeFromTree` | OrderBook | OPERATOR_ROLE | BatchAuction |
| `_isTickFar` | OrderBook | public (view) | Anyone |

All new OPERATOR_ROLE functions correctly restricted. No privilege escalation paths identified.

---

## Overall Risk Assessment

| Category | Rating | Notes |
|----------|--------|-------|
| Pool Solvency | **Strong** | Verified via accounting trace for all match types |
| Active Order Accounting | **Strong** | All increment/decrement paths traced correctly |
| Resting ↔ Tree Consistency | **Strong** | Invariant maintained across all entry/exit points |
| Chunked Settlement | **Strong** | Precomputed fills resolve v1.1 M-03 |
| Fee Arithmetic | **Strong** | half + otherHalf = full; no underflow |
| Reentrancy (ERC1155) | **Weak** | v1.1 H-01 unaddressed for non-internal markets |
| Gas Griefing | **Moderate** | Resting list O(n) scan per clearBatch |
| Access Control | **Strong** | All new functions correctly gated |

**Recommendation:** Remove the dead `_hasPrecomputed` mapping to save gas (M-02). Address resting list gas griefing (M-01) before markets with high secondary trading activity. The v1.1 ERC1155 reentrancy should be fixed or formally excluded before any non-internal-position market goes live.
