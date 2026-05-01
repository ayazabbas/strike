# Parimutuel V2: Separate Trading Close and Resolution Time

## Goal

Support parimutuel markets where betting closes before the event/resolution timestamp.

Example product shape:

- Daily BTC price market
- Betting closes 12 hours into the day
- Market resolves from the Pyth BTC/USD price at end-of-day / configured resolution time

The current deployed parimutuel model has one `closeTime`, which is used for both buy cutoff and resolver timestamp. This plan introduces explicit `tradingCloseTime` and `resolutionTime` throughout contracts, infra, admin tooling, API, keeper, and frontend.

## Product semantics

A parimutuel market has two distinct times:

1. `tradingCloseTime`
   - Last timestamp before which buys are allowed.
   - After this, the market can be closed and no more positions can be opened.

2. `resolutionTime`
   - Timestamp used by the resolver as the market event time.
   - Pyth markets resolve against the price feed update at/around this timestamp.
   - AI/Admin markets should not be resolved before this timestamp unless the market is cancelled/invalidated by admin.

Lifecycle:

```text
Open/buyable -> Closed/not-buyable -> Resolving -> Resolved
       ^              ^                  ^
       |              |                  |
now < tradingClose    now >= tradingClose now >= resolutionTime
```

## Contract changes (`~/dev/strike`)

### Types

Update `ParimutuelMarketConfig`:

- Replace or deprecate `closeTime` with:
  - `uint64 tradingCloseTime`
  - `uint64 resolutionTime`

Update `ParimutuelMarket` storage similarly.

Recommended compatibility choice: this is a new deployment/version, so update structs directly rather than trying to preserve ABI shape.

### Validation

In `ParimutuelFactory.createMarket`:

- `tradingCloseTime > block.timestamp`
- `resolutionTime >= tradingCloseTime`
- keep current validations for outcome count, metadata hash, fee, curve, fallback resolver.

Optional stricter guard for Pyth markets:

- `resolutionTime > tradingCloseTime` is allowed but not required. Same-time markets should still be valid for 5m/instant-expiry cases.

### Buying

In `ParimutuelPoolManager._requireBuyableMarket`:

- require state `Open`
- require `block.timestamp < market.tradingCloseTime`

### Closing

In `ParimutuelFactory.closeMarket`:

- require `block.timestamp >= market.tradingCloseTime`
- state transition remains `Open -> Closed`

### Resolution

In `ParimutuelFactory.requestResolution` or resolver-specific validation:

- require `block.timestamp >= market.resolutionTime` before external resolver resolution proceeds.
- Admin `resolveToWinner` should also require `block.timestamp >= market.resolutionTime` unless explicitly using `resolveInvalid` / `cancelMarket`.

In `ParimutuelPythResolver.resolveMarket`:

- fetch price feed updates for `market.resolutionTime`
- use the same fallback window logic from `resolutionTime`, not trading close.

In `ParimutuelAIResolver`:

- block resolution request/finalisation flow until `resolutionTime` where applicable.

### Events

Update `ParimutuelMarketCreated` to emit both times:

- `tradingCloseTime`
- `resolutionTime`

Update tests and ABI bindings accordingly.

### Tests

Add/modify Foundry tests:

- can create a market with `tradingCloseTime < resolutionTime`
- cannot create if `tradingCloseTime <= now`
- cannot create if `resolutionTime < tradingCloseTime`
- can buy before trading close
- cannot buy at/after trading close
- can close after trading close, before resolution time
- cannot request/perform Pyth resolution before resolution time
- Pyth resolver uses `resolutionTime` in `parsePriceFeedUpdates`
- can resolve/finalize/claim after resolution time
- same-time `tradingCloseTime == resolutionTime` still works for short markets

## Infra changes (`~/dev/strike-infra`)

### ABI/bindings

- Regenerate/copy updated parimutuel ABIs into `crates/strike-common/abi`.
- Rebuild generated Rust bindings if the project requires it.

### Database

Add migration:

- `trading_close_time BIGINT`
- `resolution_time BIGINT`

Compatibility strategy:

- New V2 event should populate both fields.
- Existing `close_time` can remain for V1/read compatibility, but APIs should prefer new fields.
- For V1 rows, `trading_close_time = close_time` and `resolution_time = close_time` during migration/backfill if needed.

### Indexer

Update `ParimutuelMarketCreated` decoding:

- parse `tradingCloseTime`
- parse `resolutionTime`
- persist both fields.

Update row structs and API DTOs.

### Keeper

Current parimutuel keeper should change to:

- close expired open markets when `now >= trading_close_time`
- only trigger closed AI/Pyth resolutions when `now >= resolution_time`
- finalization behavior remains unchanged after resolver proposal/finality exists.

### Admin server/UI

Creation payload needs:

- `tradingCloseTime`
- `resolutionTime`

Maintain simple presets:

- same-time market: trading close == resolution time
- daily market: trading close 12h before resolution/end-of-day
- custom times

For Pyth resolver config, keep `priceId + thresholds`; do not encode timestamps in resolver config.

## Frontend changes (`~/dev/strike-frontend`)

### Contract map

After V2 deploy, update chain 56 and testnet contract addresses if redeployed.

### Types/hooks

Expose/display:

- `trading_close_time`
- `resolution_time`

Fallback for legacy API rows:

- if absent, use `close_time` for both.

### UI

Market detail page:

- show `Betting closes`
- show `Resolves at`
- buy form disabled after trading close.

Market cards/list:

- show status and key timestamp appropriately:
  - open: betting closes
  - closed/resolving: resolves at / resolving
  - resolved: resolved

## Deployment plan

Because contracts are immutable, this should be a new Parimutuel V2 deployment:

1. Implement and test contracts.
2. Update infra ABI/indexer/keeper/API/admin.
3. Update frontend.
4. Deploy to testnet.
5. Smoke test:
   - market closes trading in ~2 minutes
   - resolves ~2 minutes later
   - seed all outcomes
   - verify buy disabled after trading close
   - verify keeper waits until resolution time
   - verify Pyth resolution/finalization/claim
6. Deploy fresh mainnet V2 parimutuel stack.
7. Update address registry, Ansible group vars, frontend contract map.
8. Deploy infra/frontend via Ansible.
9. Run hidden mainnet smoke.
10. Disable/hide old V1 creation paths. Existing V1 market pages may remain readable if API supports them.

## Progress log

Codex should update `/home/ubuntu/dev/strike/docs/parimutuel-v2-trading-close-progress.md` as it works, with:

- timestamp
- repo/file areas changed
- tests/builds run
- blockers/questions
- next step
