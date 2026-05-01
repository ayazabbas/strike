# Parimutuel V2 Trading Close Progress

## 2026-05-01 16:16 UTC — Plan created

- Wrote implementation plan at `docs/parimutuel-v2-trading-close-plan.md`.
- Scope covers contracts, infra/indexer/keeper/admin/API, frontend, tests, and deploy strategy.
- Next: launch Codex to implement from the plan and keep this progress file updated.

## 2026-05-01 16:18 UTC — Codex launch blocked

- Attempted to start Codex from `/home/ubuntu/dev/strike` with writable access to `strike-infra` and `strike-frontend`.
- Command used Codex non-interactive exec with danger-full-access sandbox bypass, but no deployment/funds instructions.
- Codex failed before making code changes because local Codex auth is expired/broken:
  - `refresh_token_reused`
  - `token_expired`
  - websocket 401 Unauthorized
- No source implementation changes were made by Codex.
- Next step: Ayaz needs to re-auth Codex (`codex login`) or approve using Claude Code/manual implementation as fallback.

## 2026-05-01 18:45 UTC — Manual implementation completed locally

- Implemented Parimutuel V2 manually without a coding agent.
- Contracts now split `closeTime` into `tradingCloseTime` and `resolutionTime` in `ParimutuelMarketConfig`, `ParimutuelMarket`, and `ParimutuelMarketCreated`.
- Trading/buy close paths use `tradingCloseTime`; admin/AI/Pyth resolution, fallback, resolver, and invalidation gating uses `resolutionTime`; Pyth Hermes price lookup uses `resolutionTime`.
- Added contract tests for separate trading/resolution times and early-resolution reverts.
- Updated infra:
  - added DB migration `024_parimutuel_v2_times.sql` with `trading_close_time` and `resolution_time` while keeping `close_time` as a deprecated compatibility alias;
  - updated indexer ABI/event handling and DB writes;
  - updated keeper resolution queries and Pyth Hermes fetch timestamp;
  - updated admin server ABI/create-market payload validation;
  - rebuilt admin client dist.
- Updated frontend types/list/detail pages to display trading close and resolution time separately, with backward-compatible fallback to `close_time`.
- Verification:
  - `forge test --match-path 'test/Parimutuel*.t.sol'` from `contracts/`: 66 passed, 0 failed.
  - `cargo check -p strike-common -p strike-db -p indexer -p keeper`: passed with existing `resolution_block` dead-code warning.
  - `node --check admin/server.js`: passed.
  - `npm run build` in `admin/client`: passed.
  - `npm run lint` in `strike-frontend`: passed.
- Still no deploy or production action taken.
