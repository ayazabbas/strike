# Internal Security Audit — v1.2

**Date:** 2026-03-22
**Auditor:** Internal Security Review
**Scope:** All Solidity contracts in `contracts/src/` (~2,777 lines, 10 files)
**Framework:** Solidity ^0.8.25, Foundry
**Chain:** BNB Chain (BSC)
**Test Suite:** 347 tests, all passing

---

## Executive Summary

This audit covers the complete Strike v1.2 prediction market protocol — all 10 Solidity contracts comprising the on-chain CLOB with Frequent Batch Auctions. The review focused on correctness, access control, pool solvency, gas efficiency, and reentrancy safety.

Strike v1.2 incorporates fixes for all findings from the v1.1 audit (chunked settlement, fee splits, order caps, proximity filtering) and the v1.2 re-audit (paginated resting scan, stale lots fix, dead code removal, naming conventions). The protocol is well-structured with clear trust boundaries, comprehensive test coverage, and sound arithmetic.

**Overall Risk Assessment: LOW.** No critical or high severity issues remain. Two medium-severity design risks are documented (ERC1155 reentrancy for non-internal markets, MEV exposure on `clearBatch` timing). All previous audit findings have been addressed.

---

## Scope

| Contract | Lines | Role |
|----------|-------|------|
| `OrderBook.sol` | 760 | Order placement, cancellation, segment trees, resting list, proximity filtering |
| `BatchAuction.sol` | 599 | Atomic `clearBatch` — clearing price discovery + chunked settlement |
| `Vault.sol` | 255 | USDT (ERC-20) collateral escrow, position tracking, pool accounting |
| `MarketFactory.sol` | 308 | Market lifecycle, permissioned creation (MARKET_CREATOR_ROLE) |
| `FeeModel.sol` | 85 | Uniform 20 bps fee calculation with 50/50 buy/sell split |
| `OutcomeToken.sol` | 139 | ERC-1155 YES/NO tokens, mint/burn/escrow roles |
| `PythResolver.sol` | 269 | Pyth Core oracle resolution with challenge mechanism |
| `Redemption.sol` | 82 | Post-resolution token redemption for USDT |
| `SegmentTree.sol` | 199 | Library for O(log N) clearing tick computation |
| `ITypes.sol` | 81 | Shared types, enums, constants |
| **Total** | **2,777** | |

---

## Architecture Overview

Strike is a binary-outcome prediction market protocol where traders buy YES/NO outcome tokens via a Central Limit Order Book cleared in Frequent Batch Auctions.

### Trust Boundaries

```
Users (EOA/contracts)
  │
  ├─── OrderBook ──────── Vault (USDT escrow)
  │      │                   │
  │      └── BatchAuction ───┤
  │            │              │
  │            ├── OutcomeToken (ERC-1155)
  │            │
  │      MarketFactory ── PythResolver (oracle)
  │                           │
  │                        Pyth Core (external)
  │
  └─── Redemption ────── Vault + OutcomeToken
```

### Access Control

| Role | Holder | Grants access to |
|------|--------|-----------------|
| `DEFAULT_ADMIN_ROLE` | Deployer | Role management, emergency functions |
| `OPERATOR_ROLE` (OrderBook) | BatchAuction, MarketFactory | Order settlement, market registration, tree updates |
| `PROTOCOL_ROLE` (Vault) | OrderBook, BatchAuction, Redemption | Deposits, locks, settlement, pool operations |
| `MINTER_ROLE` (OutcomeToken) | BatchAuction, Redemption | Token minting/burning |
| `ESCROW_ROLE` (OutcomeToken) | BatchAuction | Burning tokens held in OrderBook escrow |
| `MARKET_CREATOR_ROLE` (MarketFactory) | Authorized creators | Market creation |

All role-gated functions verified correct. No privilege escalation paths identified.

---

## Findings

### Summary Table

| ID | Title | Severity | Status |
|----|-------|----------|--------|
| M-01 | ERC1155 reentrancy DoS on non-internal markets | Medium | Acknowledged — mitigated by `useInternalPositions` default |
| M-02 | No `batchInterval` enforcement on `clearBatch` — MEV exposure | Medium | Acknowledged — documented in NatSpec |
| L-01 | `placeOrders` / `replaceOrders` cast `params.length` to uint16 | Low | Acknowledged — not exploitable (gas limit) |
| I-01 | Sell fee dual `redeemFromPool` pattern is non-obvious | Informational | Documented |
| I-02 | PythResolver confidence threshold bypass when `confThresholdBps = 0` | Informational | Out of scope (PythResolver unchanged) |
| I-03 | Redemption uint128 truncation on large amounts | Informational | Not exploitable in practice |

### Detailed Findings

#### M-01: ERC1155 Reentrancy DoS on Non-Internal Markets

**Severity:** Medium
**Contract:** BatchAuction.sol, OrderBook.sol
**Status:** Acknowledged

Markets using `useInternalPositions = false` transfer ERC-1155 tokens via `safeTransferFrom`, which invokes `onERC1155Received` on the recipient. A malicious receiver contract could revert in the callback, blocking settlement for the entire batch.

**Impact:** DoS on batch settlement for affected market. Does not affect pool solvency or other markets.

**Mitigation:** Markets default to `useInternalPositions = true`, which uses Vault position tracking instead of ERC-1155 transfers. The `nonReentrant` guard on `clearBatch` prevents cross-function reentrancy but not callback reverts.

**Recommendation:** For production, use only `useInternalPositions = true` markets. If ERC-1155 markets are needed, implement a pull-based claim pattern or a `settlementActive` lock that skips reverting orders.

---

#### M-02: No `batchInterval` Enforcement — MEV Exposure

**Severity:** Medium
**Contract:** BatchAuction.sol — `clearBatch()`
**Status:** Acknowledged (documented in NatSpec, L87-100)

`clearBatch` can be called by anyone at any time. An attacker could front-run the call, place an order isolating a single user in a near-empty batch, and match at the user's limit price instead of the fair clearing price.

**Mitigation:** Price-proximity filtering keeps only near-price orders in the active batch, reducing the attack surface. The `batchInterval` field exists in the Market struct but is not enforced.

**Recommendation:** Enforce minimum batch duration or restrict `clearBatch` to a permissioned keeper for production deployment.

---

#### L-01: `params.length` Cast to uint16 in Batch Order Functions

**Severity:** Low
**Contract:** OrderBook.sol — `placeOrders` (L366), `replaceOrders` (L419-420)

`params.length` (uint256) is cast to `uint16` for `activeOrderCount` arithmetic. Values > 65535 would silently truncate, potentially bypassing the per-user order cap.

**Impact:** Not exploitable — 65536 `OrderParam` structs would far exceed the block gas limit on BSC. Code smell only.

**Recommendation:** Add `require(params.length <= MAX_USER_ORDERS, "OrderBook: batch too large")` before the cast.

---

#### I-01: Sell Fee Dual `redeemFromPool` Pattern

**Severity:** Informational
**Contract:** BatchAuction.sol — `_settleSellOrder`

Sell-side settlement makes two `redeemFromPool` calls — one for the seller's payout and one for the sell fee to the protocol collector. The total withdrawn equals the gross payout (`filledCollateral` at clearing price), which equals what the buy side deposited into the pool. Pool solvency is maintained.

Accounting trace:
```
Pool in:  +filledCollateral (from buy side via settleFill)
Pool out: -payout - sellFee = -grossPayout = -filledCollateral
Net:       0
```

The pattern is correct but non-obvious. Documented here for future reference.

---

#### I-02: PythResolver Confidence Threshold Bypass

**Severity:** Informational
**Contract:** PythResolver.sol

If `confThresholdBps` is set to 0, the confidence check is effectively bypassed (any confidence passes). This is a configuration concern, not a code bug. The admin controls this value.

---

#### I-03: Redemption uint128 Truncation

**Severity:** Informational
**Contract:** Redemption.sol — `redeemPosition` call (L73)

The `amount` parameter is cast to `uint128` when calling `vault.redeemPosition()`. Amounts > 2^128 would truncate silently. Not exploitable in practice — would require holding ~3.4 × 10^38 USDT worth of tokens.

---

## Invariant Analysis

### 1. Pool Solvency

**Invariant:** `marketPool[marketId] >= LOT_SIZE * outstandingLots` at all times.

| Match Type | Pool In | Pool Out | Net | Solvent? |
|-----------|---------|----------|-----|----------|
| Bid + Ask | 2 × filledCollateral | — | +2 × filledCollateral | Yes |
| Bid + SellYes | filledCollateral | grossPayout (= filledCollateral) | 0 | Yes (backed by original Bid+Ask deposit) |
| Bid + SellNo | filledCollateral | grossPayout (= filledCollateral) | 0 | Yes |
| Redemption | — | LOT_SIZE × lots | Covered by original deposits | Yes |

Pool solvency verified through end-to-end accounting traces and the `PoolSolvency.t.sol` test suite (fuzz tests with 100+ iterations).

### 2. `activeOrderCount` Consistency

**Invariant:** `activeOrderCount[user][marketId]` equals the number of orders with `lots > 0` owned by that user in that market.

All increment and decrement paths verified:
- Incremented on `placeOrder`, `placeOrders`, `replaceOrders` (new placements)
- Decremented on cancel (`_cancelCore`, `_cancelForReplace`), full fill, GTB expiry
- Not decremented on GTC partial fill (order remains active) — correct
- Reverts on underflow (`require > 0`) at all three decrement sites

### 3. Resting ↔ Tree Consistency

**Invariant:** If `isResting[orderId] == true`, the order's volume is NOT in the segment tree.

| Path | Tree Updated? | isResting Set? | Consistent? |
|------|--------------|----------------|-------------|
| `placeOrder` → far | Not added | true | Yes |
| `placeOrder` → near | Added | false | Yes |
| `pullRestingOrders` → pull in | Added | false | Yes |
| `_tryRollOrCancel` → far | Removed | true (via push) | Yes |
| `_tryRollOrCancel` → near | Not removed | false (stays in tree) | Yes |
| `_cancelCore` → resting | Not updated | false | Yes |
| `_cancelCore` → active | Removed | N/A | Yes |

### 4. Token Conservation

**Invariant:** Outcome tokens minted = tokens burned + tokens held by users + tokens in OrderBook escrow.

- Minted on fill (`mintSingle` or `creditPosition`)
- Burned on sell fill (`burnEscrow` or `consumeLockedPosition`)
- Burned on redemption (`redeem` or `redeemPosition`)
- Returned to seller on cancel/unfill (`transferEscrowTokens` or `unlockPosition`)

No path creates or destroys tokens without corresponding collateral movement.

---

## Previous Audit Findings

All findings from v1.1 and the initial v1.2 audit have been addressed:

| ID | Title | Severity | Fix Status |
|----|-------|----------|------------|
| v1.1 H-01 | Cross-contract ERC1155 reentrancy DoS | High | Mitigated — `useInternalPositions` default (see M-01 above) |
| v1.1 M-01 | PythResolver conf=0 bypass | Medium | Acknowledged (see I-02 above) |
| v1.1 M-02 | Redemption uint128 truncation | Medium | Acknowledged (see I-03 above) |
| v1.1 M-03 | Chunked settlement re-computes fills | Medium | **Fixed & Verified** — precomputed fills in `_precomputedFills` mapping |
| v1.1 L-01 | Unbounded GTC rollover | Low | **Fixed & Verified** — resting list + `MAX_ORDERS_PER_BATCH = 1600` |
| v1.1 L-02 | Sell orders pay zero fees | Low | **Fixed & Verified** — 50/50 fee split via `calculateHalfFee` / `calculateOtherHalfFee` |
| v1.1 L-03 | No batch interval enforcement | Low | Acknowledged (see M-02 above) |
| v1.2 M-01 | Resting list unbounded scan (gas grief) | Medium | **Fixed & Verified** — paginated scan with `MAX_RESTING_SCAN = 400` + `restingScanIndex` persistence |
| v1.2 M-02 | Dead `_hasPrecomputed` mapping | Medium | **Fixed & Verified** — mapping and all writes/deletes removed |
| v1.2 L-01 | `activeOrderCount` saturating decrement | Low | **Fixed & Verified** — replaced with `require > 0` at all 3 sites |
| v1.2 L-02 | `restingScanIndex` unused | Low | **Fixed & Verified** — now used by paginated `pullRestingOrders` |
| v1.2 I-02 | `_isTickFar` public with internal naming | Info | **Fixed & Verified** — renamed to `isTickFar` / `isTickNear` |
| v1.2 stale lots | Partial fill passes original lots to `_tryRollOrCancel` | Medium | **Fixed & Verified** — creates `remaining` copy with correct lots in both buy/sell paths |

---

## Test Coverage

**347 tests, all passing.** Test suite includes:

| Test File | Tests | Coverage |
|-----------|-------|----------|
| `AuditFixes.t.sol` | 43 | All v1.2 fixes: order caps, proximity filtering, chunked settlement, fee splits, paginated scan, stale lots, underflow revert |
| `BatchAuction.t.sol` | 55 | Clearing mechanics, settlement, GTC rollover, multi-chunk |
| `OrderBook.t.sol` | 44 | Order placement, cancellation, tree updates, batch tracking |
| `SellOrders.t.sol` | 30 | SellYes/SellNo flows, partial fills, fee deductions |
| `PoolSolvency.t.sol` | 8 | Fuzz-tested pool solvency across all match types |
| `Integration.t.sol` | 18 | End-to-end flows from placement to redemption |
| `VaultInvariant.t.sol` | 1 | Invariant testing: balance >= locked |
| Other test files | 148 | Individual contract unit tests |

**Remaining test gaps (low risk):**

| Gap | Risk | Recommendation |
|-----|------|----------------|
| Malicious ERC1155 receiver callback | Medium | Add reverting `onERC1155Received` test for non-internal markets |
| `isTickFar` boundary fuzz at `ref ± PROXIMITY_THRESHOLD` exactly | Low | Add fuzz test for boundary conditions |
| Resting list with > 200 entries (partial pull boundary) | Low | Test that `MAX_RESTING_PULL` cap is respected with large lists |

---

## Conclusion

Strike v1.2 is a well-engineered prediction market protocol with sound economic invariants and comprehensive access control. All previously identified vulnerabilities have been addressed through code fixes or documented mitigations.

**Key strengths:**
- Pool solvency maintained across all match types (verified by accounting traces and fuzz tests)
- Paginated resting list scanning bounds gas consumption per `clearBatch` call
- Chunked settlement with precomputed fills enables arbitrarily large batches
- Per-user order cap (20) limits Sybil griefing on resting list growth
- Clear separation of concerns across 10 focused contracts

**Residual risks (all acknowledged):**
- ERC1155 reentrancy DoS affects non-internal markets only (mitigated by default configuration)
- MEV exposure on `clearBatch` timing (mitigated by proximity filtering, not enforced by code)
- `params.length` uint16 truncation (not exploitable due to gas limits)

**Assessment:** The protocol is suitable for mainnet deployment with `useInternalPositions = true` markets. Non-internal-position markets should not be deployed until the ERC1155 reentrancy DoS is resolved.
