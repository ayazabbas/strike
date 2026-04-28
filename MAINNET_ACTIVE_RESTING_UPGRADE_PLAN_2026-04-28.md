# Mainnet active→resting amendOrders upgrade plan — 2026-04-28

## Goals
- Deploy the active→resting `amendOrders` contract patch to BSC mainnet.
- Preserve all existing production DB data by archiving current live tables into `historical_*` before any live-table reset.
- Update all contract address references across Strike repos.
- Cut a new Rust SDK release tag after updating hardcoded mainnet addresses in `sdk/rust/src/config.rs`.

## Guardrails
- `memory/strike/addresses.md` is the canonical address registry; update it before declaring done.
- Do not clear or truncate `historical_*` tables.
- Do not run `reset-deployment-state` until after:
  - production services are stopped/frozen,
  - a DB backup exists,
  - live tables are archived into `historical_*`, and
  - archive counts match live counts.
- Use Ansible/source-of-truth deployment paths for production infra/frontend/MM; do not rely on ad-hoc prod edits.
- Push intended commits before Ansible deploy so remote hosts pull the right revision.

## Planned sequence
1. Update `contracts/script/DeployMainnet.s.sol` so it deploys/wires the full current stack:
   - FeeModel, OutcomeToken, Vault, OrderBook, BatchAuction, MarketFactory, PythResolver, AIResolver, Redemption.
   - Grant OrderBook/Vault/OutcomeToken roles.
   - Grant Factory admin to PythResolver, AIResolver, keeper, and resolution keeper.
   - Grant Factory market creator to deployer and keeper.
   - Set Factory AIResolver.
   - Grant AIResolver keeper role to keeper and resolution keeper.
   - Print machine-readable JSON with all addresses.
2. Run contract validation locally:
   - `forge test` from `~/dev/strike/contracts`.
   - compile/dry-run deploy script if possible without broadcasting.
3. Deploy new mainnet contracts with mainnet deployer key.
   - Capture first deploy block, final role/config tx/block, and all addresses.
4. Update references:
   - `memory/strike/addresses.md`.
   - `~/dev/strike-infra/ansible/playbooks/group_vars/all.yml` with new addresses + `indexer_from_block`.
   - `~/dev/strike-frontend/src/lib/contracts.ts` mainnet entries.
   - `~/dev/strike/sdk/rust/src/config.rs` mainnet hardcoded addresses.
   - `~/dev/strike-mm` mainnet config/address references if present.
   - docs/README/CLAUDE references across Strike repos.
5. Commit and push repo changes:
   - `strike` master.
   - `strike-infra` main if Ansible vars changed.
   - `strike-frontend` main.
   - `strike-mm` main if changed.
6. Freeze production services:
   - Stop keeper, indexer, and MM. Keep frontend only if safe/read-only; otherwise deploy maintenance/brief downtime.
7. Backup production state:
   - DB dump from mainnet host.
   - Copy current generated `/home/ubuntu/strike-infra/.env.mainnet`.
   - Copy current MM config.
   - Record `indexer_state.last_block` and live table counts.
8. Archive current live DB into historical tables using old live addresses:
   - deployment label: `mainnet-pre-active-resting-amend-20260428`.
   - script: `scripts/archive-live-deployment.sql`.
   - verify historical counts match live counts for markets/orders/batches/fills/events/positions.
   - verify `all_filled_orders` still includes archived fills.
9. Run `reset-deployment-state` only after archive verification.
10. Deploy/restart production services via Ansible:
    - infra/indexer/keeper with new addresses and start block.
    - frontend with new contract map.
    - MM from main with new addresses/config.
11. Post-cutover smoke tests:
    - indexer starts with new deployment fingerprint.
    - keeper creates/clears a new market.
    - API returns new live market(s).
    - frontend HTTP 200 and mainnet contract map correct.
    - MM quotes and uses `amendOrders` without active→resting revert.
    - archived historical counts remain present.
12. SDK release:
    - bump SDK version if required by current release convention.
    - run SDK checks.
    - commit version/address changes.
    - push a new SDK release tag after deployment is confirmed.
    - note tag in `memory/2026-04-28.md`.

## Execution status
- Completed 2026-04-28.
- Deployed mainnet contracts from block `95210316`.
- Archive label: `mainnet-pre-active-resting-amend-20260428`.
- DB dump: `/home/ubuntu/strike-mainnet-pre-active-resting-amend-20260428.dump` on mainnet host.
- Archived counts matched live counts: markets 1214, orders 27757, batches 12665, fills 34800, events 206852, positions 181.
- Repos pushed:
  - `strike`: `a66dd9d` address/SDK update, then `cf8c889` SDK gas-limit release fix.
  - `strike-infra`: `8642991` address update, then `b6b8648` optional empty address config fix.
  - `strike-frontend`: `0556442` address update.
- SDK tags pushed: `sdk-v0.2.13` (address update), then `sdk-v0.2.14` (superseding gas-limit fix for initial `placeOrders`).
- Smoke: services active; API returned fresh live market `2`; MM placed initial 4 orders with `gas_limit=1550000` and confirmed `amendOrders` after deployment.
