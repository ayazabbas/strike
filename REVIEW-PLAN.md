# Strike Contracts + Docs — Review Fix Plan

Generated from deep review 2026-03-05. Fix everything in priority order.

---

## CONTRACTS

### Critical Fixes

#### 1. Fix GTC `claimFills` — partial fills must not destroy the entire order
**File:** `contracts/src/BatchAuction.sol`
- Currently, `claimFills` removes the entire order (`o.lots`) from the book even for GTC orders with partial fills
- Fix: after computing `filledLots` via pro-rata, only remove `filledLots` from the book
- The remaining `unfilledLots` must stay in the book with collateral still locked
- Only unlock collateral for the unfilled portion if order type is GTB
- GTC orders: remove only filled lots, leave unfilled lots resting
- GTB orders: remove all lots (current correct behaviour for GTB)
- Add tests: GTC order partial fill across 2 batches — remaining lots still in book after first claim

#### 2. Fix phantom clearing tick — return 0 when matched volume is zero
**File:** `contracts/src/SegmentTree.sol`
- `findClearingTick` currently returns a non-zero tick even when bids and asks don't overlap
- When the best candidate tick has `matchedLots = min(cumBid, cumAsk) = 0`, return 0
- OR: in `clearBatch`, after calling `findClearingTick`, check if `matchedLots == 0` and set `clearingTick = 0`
- Add test: market with bid at tick 30 and ask at tick 70 — `clearBatch` should result in zero fills and no orders destroyed

#### 3. Add Redemption contract to deploy scripts
**Files:** `contracts/script/Deploy.s.sol`, `contracts/script/DeployTestnet.s.sol`
- Deploy `Redemption` contract
- Grant `MINTER_ROLE` on `OutcomeToken` to `Redemption`
- Grant `PROTOCOL_ROLE` on `Vault` to `Redemption`
- Verify this matches what the integration tests do (they already wire it correctly — copy that pattern)

#### 4. Add state guard to `payResolverBounty`
**File:** `contracts/src/MarketFactory.sol`
- Add `require(meta.state == MarketState.Resolved, "MarketFactory: not resolved")` to `payResolverBounty`
- Add test: calling `payResolverBounty` on an Open market reverts

### High/Medium Fixes

#### 5. Replace `transfer()` with `.call{value:}()` in PythResolver
**File:** `contracts/src/PythResolver.sol:133`
- `payable(msg.sender).transfer()` only forwards 2300 gas — fails for multisigs and contract callers
- Replace with `(bool ok, ) = payable(msg.sender).call{value: refund}(""); require(ok, "refund failed");`

#### 6. Fix `closeMarket` / `cancelMarket` array consistency
**File:** `contracts/src/MarketFactory.sol`
- `closeMarket` appends to `closedMarkets` array
- `cancelMarket` never removes cancelled markets from `closedMarkets`
- Add removal from `closedMarkets` in `cancelMarket` if the market is present

#### 7. Add admin transfer function to PythResolver
**File:** `contracts/src/PythResolver.sol`
- Current hand-rolled admin pattern has no transfer mechanism — admin is permanently locked to deployer EOA
- Add `pendingAdmin` + two-step transfer: `setPendingAdmin(address)` + `acceptAdmin()`

#### 8. Add validation for `defaultMinLots` and `confThresholdBps`
**Files:** `contracts/src/MarketFactory.sol`, `contracts/src/PythResolver.sol`
- `setMinLots`: require `minLots > 0`
- `setConfThreshold`: require `bps <= 10000`

#### 9. Fix `Vault.receive()` — direct BNB sends are lost forever
**File:** `contracts/src/Vault.sol`
- Add `revert("Vault: use deposit()")` in the `receive()` function to prevent accidental ETH loss

#### 10. Emit event for `payResolverBounty`
**File:** `contracts/src/MarketFactory.sol`
- Add `event ResolverBountyPaid(uint32 indexed marketId, address indexed resolver, uint256 amount)`
- Emit it in `payResolverBounty`

### Missing Tests

#### 11. Write missing test cases
- **GTC multi-batch partial fill:** Place GTC order → partial fill in batch 1 → claim → verify remaining lots still in book → second batch fills remainder → claim again → order gone
- **NO-wins redemption:** Create market, resolve NO, redeem NO tokens for BNB — verify correct payout
- **Cancelled market redemption:** Cancel a market, verify both YES and NO holders get collateral back via Redemption
- **`payResolverBounty` on non-resolved market:** Should revert
- **Phantom clearing tick:** Non-overlapping orders survive clearBatch untouched
- **Fuzz `BatchAuction`:** Fuzz `placeOrder` with random tick/lots/side, then `clearBatch`, assert invariants
- **Fuzz `PythResolver`:** Fuzz price/confidence values around strikePrice boundary
- **Invariant test:** Total BNB in Vault == sum of all account balances + all market pool balances at all times

---

## DOCUMENTATION

Fix all 12 critical inaccuracies (search and replace throughout docs/):

1. Replace all "Pyth Lazer" references → "Pyth" in docs/ (code uses Pyth Core `IPyth`)
2. Replace `parsePriceFeedUpdatesUnique` → `parsePriceFeedUpdates` in oracle-resolution.md and anywhere else
3. Fix architecture.md — remove EIP-1167 minimal proxy clone references; describe actual singleton OrderBook with mapping
4. Fix pyth-resolver.md — remove `challengeResolution()` function reference; challenges are handled within `resolveMarket()`
5. Fix key-concepts.md and vault.md — "asks lock BNB" not outcome tokens; fix collateral formula description
6. Fix fees-and-incentives.md and security.md — remove order bonds and pruner bounties (not implemented); remove per-tick order caps (not implemented)
7. Fix batch-auction.md — claimFills uses `mintSingle()`, not `mintPair + burn`
8. Fix how-it-works.md and key-concepts.md — batch interval default is 60s (not ~3s)
9. Fix gas-and-costs.md — remove `modifyOrder` row (function doesn't exist)
10. Fix orderbook.md Order struct — use actual packed types (`uint64`, `uint32`, `uint8`) not `uint256`
11. Fix security.md — `createMarket()` is permissionless; remove "requires Admin role" claim
12. Update roadmap.md — mark Phase 1A/1B/1C/2/3 items as complete (297 tests passing, infra built)

#### Additional doc tasks:
- Add `FeeModel.sol`, `SegmentTree.sol`, `Redemption.sol` to `docs/SUMMARY.md`
- Write `docs/deployment-guide.md`: env vars, deployment order, role wiring, contract verification, post-deploy validation checklist
- Write `docs/developer-integration.md`: ABI locations, contract addresses, how to interact programmatically
- Document all events with parameters across all contracts (add to relevant contract docs pages)
- Add access control / role graph (which contract needs which role on which other contract)
- Add sequence diagrams for: place order → clear → claim → redeem
- Add local devnet setup guide
- Document the two market ID types (`factoryMarketId` vs `orderBookMarketId`)
- Archive/delete stale files: `PLAN.md`, `PROJECT_BRIEF.md`, `CLEANUP-PLAN.md` (move to `docs/archive/` or delete)
- Update `CLOB-PLAN.md` Phase 2 reference from "Pyth Lazer" to "Pyth Core"

---

## COMPLETION

When all tasks are done:
1. Run `forge test` — all tests must pass
2. Commit all changes with descriptive messages
3. Push to GitHub
4. Run: `openclaw system event --text "Done: strike contracts+docs review fixes complete" --mode now`
