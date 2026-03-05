# Post-Phase Cleanup Plan

Identified during code review after Phases 1A–1C. Must be resolved before Phase 2.

---

## 🔴 Critical Fixes (correctness)

### 1. Fix settlement in `BatchAuction.claimFills`

Current: just calls `vault.unlock(owner, collateral)` for both sides — doesn't deliver anything.

Required behaviour:
- **Filled bid:** receive YES outcome tokens (mint via `OutcomeToken`) + unlock unfilled collateral
- **Filled ask:** receive BNB at clearing price (transfer from protocol/vault) + unlock unfilled collateral (the "NO side" BNB)
- Partial fills: pro-rata of the above

Settlement flow:
1. Compute `filledLots` (already done correctly)
2. For **bids**: mint `filledLots` YES tokens to `o.owner` via `outcomeToken.mint(owner, marketId, filledLots, YES)`
3. For **asks**: the clearing BNB (`filledLots * LOT_SIZE * clearingTick / 100`) should transfer from locked bidder collateral → ask owner's vault balance; asks also receive their unfilled collateral back
4. Apply taker fee (deduct from settlement) and maker rebate (add to maker)
5. Unlock unfilled portion of collateral for both sides

Note: This requires `BatchAuction` to hold a reference to `OutcomeToken` and have `MINTER_ROLE`.

### 2. Apply fees in `claimFills`

FeeModel is deployed and referenced but never called. Must:
- Call `feeModel.calculateTakerFee(settlementAmount)` and deduct from taker
- Call `feeModel.calculateMakerRebate(settlementAmount)` and add to maker
- Transfer net protocol fee to `feeModel.protocolFeeCollector()`

### 3. Fix `Redemption.sol`

`vault.unlock(user, payout)` assumes funds are still locked post-settlement — they're not.

Fix: After market resolves, the Vault should hold BNB representing the winning side's payout. Options:
- Keep a `marketCollateral[marketId]` pool in Vault funded during settlement
- Or: Redemption holds/receives BNB directly, not via Vault unlock

Simplest: During `claimFills` for filled bids, DON'T unlock the collateral paid by the bidder — keep it locked as "pending redemption pool". Then Redemption unlocks it when the user redeems their YES tokens.

### 4. Enforce batch interval in `clearBatch`

Add `lastClearTime[marketId]` tracking:
```solidity
require(block.timestamp >= lastClearTime[marketId] + market.batchInterval, "BatchAuction: too soon");
lastClearTime[marketId] = block.timestamp;
```

### 5. Fix `clearBatch` tick+1 override logic

Remove the suspicious post-hoc tick+1 check — it can override the correct clearing tick with one where cumAsk > cumBid. The segment tree algorithm already returns the correct answer. Delete those ~10 lines.

### 6. Grant `ADMIN_ROLE` to `PythResolver` on `MarketFactory`

In any deployment/test setup, `PythResolver` must be granted `ADMIN_ROLE` on `MarketFactory` so `setResolving` and `setResolved` can be called. Add this to Integration test setUp and document in deployment guide.

---

## 🟡 Design Fixes

### 7. Clarify ask collateral model

Current: asks lock `(100-tick)/100 * lots * LOT_SIZE` BNB.
Plan said: "ASK: lock outcome tokens".

Decision needed — pick one and implement consistently:
- **Option A (current):** Askers lock BNB (represents short-YES via minted pair). Simpler, no token pre-requirement.
- **Option B (plan):** Askers lock YES tokens they already own.

Recommend **Option A** — it's simpler, fully collateralised with BNB only, easier UX. Document this decision explicitly.

### 8. Move `LOT_SIZE` to `ITypes.sol`

Remove duplicate constants from `OrderBook` and `Redemption`. Add to ITypes as a top-level constant.

---

## 🟡 Test Cleanup

### 9. Remove low-value constructor tests

Delete these ~12 tests across files (pure boilerplate, no protocol value):
- `test_Constructor_SetsContracts`
- `test_Constructor_RevertZeroOrderBook` / `RevertZeroVault` / `RevertZeroFeeModel` / etc.

### 10. Add missing tests

- **Token delivery:** verify bidder receives YES tokens after `claimFills`
- **Ask settlement:** verify ask owner receives BNB after fill
- **Fee deduction:** verify taker fee applied, maker rebate applied, net fee to collector
- **Batch interval:** verify cannot call `clearBatch` twice within `batchInterval`
- **Redemption e2e:** create market → mint → place → clear → resolve → redeem → verify BNB received
- **PythResolver role:** verify resolution fails if ADMIN_ROLE not granted, succeeds when it is

---

## 📝 Documentation

### 11. Update `README.md`

- Complete contract architecture table (add MarketFactory, PythResolver, Redemption)
- Market lifecycle state diagram (Open → Closed → Resolving → Resolved / Cancelled)
- Pyth Lazer resolution rule (verifyUpdate, confidence threshold, finality gate)
- Gas benchmark table (from Integration.t.sol gas snapshots)
- Full project structure

### 12. Update docs site (`docs/`)

- `contracts/orderbook.md` — update Order struct (remove expiry field that doesn't exist, add batchId)
- `contracts/batch-auction.md` — document actual settlement flow once fixed
- `contracts/market-factory.md` — add state machine diagram
- `protocol/batch-auctions.md` — clarify ask collateral model (Option A: BNB not tokens)
- Add `contracts/redemption.md`

### 13. Create `contracts/CLAUDE.md`

Claude Code context file for the contracts repo:
- Project overview and architecture
- Key design decisions (ask collateral, Pyth Lazer, GTC/GTB order types)
- File structure guide
- How to run tests (`~/.foundry/bin/forge test`)
- Common gotchas (LOT_SIZE, OPERATOR_ROLE grants, Pyth feedId is uint32)

---

## Order of Operations

1. Fix 5 (remove bad tick+1 logic) — safest, isolated
2. Fix 8 (LOT_SIZE to ITypes) — trivial refactor
3. Fix 7 (document ask collateral decision)
4. Fix 4 (batch interval enforcement)
5. Fix 6 (PythResolver ADMIN_ROLE in tests)
6. Fixes 1+2+3 together (settlement rewrite — interdependent)
7. Fix 9+10 (test cleanup + new tests)
8. Fixes 11+12+13 (docs + README + CLAUDE.md)
