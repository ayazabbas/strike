# World Cup Multiplier Cross-Event Ticket Internal Review

**Date:** 2026-06-08
**Auditor:** Internal Codex-assisted security review
**Scope:** Cross-event Prediction Ticket refactor across backend/indexer, frontend, smoke tooling, portfolio/admin rendering, and `StrikeMultiplierPredictionVault` ticket-as-vault-event compatibility
**Verdict:** **PASS for the reviewed cross-event ticket refactor.** The previous release blockers were fixed and a fresh independent review found no remaining release-blocking issues in scope.

---

## Executive summary

This is an internal, Codex-assisted review. It is not an external third-party audit.

The reviewed branch adds true cross-event Prediction Tickets: one user-facing ticket can contain legs from multiple prediction events, while the existing `StrikeMultiplierPredictionVault` ABI is reused by representing each ticket as one synthetic vault event.

A prior review blocked release on backend/accounting projection, synthetic vault lifecycle safety, deterministic frontend idempotency, intent-only ticket handling, smoke amount units, and numeric ticket privacy. Those items were fixed and re-reviewed. The fresh audit result is **PASS** for the reviewed refactor.

---

## Scope reviewed

The review covered branch `feature/world-cup-cross-event-tickets` across:

- `/home/ubuntu/dev/strike-infra`
  - migration `047_world_cup_multiplier_cross_event_tickets.sql`
  - `/v1/world-cup-multiplier/tickets` create/list/detail APIs
  - legacy `multiplier_predictions` projection and accounting compatibility
  - ticket settlement projection and vault event synchronization
  - DB-backed regression tests added for the refactor
- `/home/ubuntu/dev/strike-frontend`
  - cross-event ticket builder and submit path
  - ticket API client types
  - portfolio/admin rendering
  - ticket-builder tests and smoke script defaults
- `/home/ubuntu/dev/strike`
  - `StrikeMultiplierPredictionVault` cross-event ticket compatibility tests
  - docs/security/protocol references

---

## Verdict by area

### Contract compatibility: PASS

The existing vault ABI can represent one cross-event ticket as one synthetic vault event:

- submit uses one `bytes32 eventId` for the synthetic ticket vault event;
- the ticket uses one `bytes32 predictionId`;
- payout can be claimed after settling that synthetic vault event with the ticket prediction id;
- refund can be claimed after cancelling the synthetic vault event;
- the vault does not need to know the real per-leg event ids.

Focused vault tests and the full Foundry suite passed.

### Backend/indexer: PASS

The backend now creates and updates a reliable legacy projection for every ticket path reviewed:

- pure `/world-cup-multiplier/tickets` submissions upsert a `multiplier_predictions` projection using the first leg event as the projection event;
- legacy `/events/{id}/predictions` compatibility still projects through the requested event;
- idempotent retries update the projection rather than silently skipping it;
- projection receipt snapshots include the ticket id, projection event id, and ticket legs;
- event-level accounting can continue to read `multiplier_predictions` while the ticket tables remain the canonical ticket/leg source.

### Synthetic vault lifecycle and claim safety: PASS

The implementation keeps local ticket status claim-safe until the synthetic vault event lifecycle confirms the on-chain outcome:

- local per-leg settlement records the derived ticket outcome;
- confirmed tickets keep public `ticket_status = accepted` while `metadata.vaultSettlementPending.localTicketStatus` records the local terminal outcome;
- legacy projections are synced to the local terminal outcome so event-level accounting can update;
- vault event logs can still update ticket and projection status by `contract_prediction_id` or `vault_event_id`;
- this avoids showing a ticket as claimable/refundable before the vault event is actually settled or cancelled.

### Frontend idempotency: PASS

The frontend no longer derives ticket idempotency keys from wallet, entry amount, and legs.

- each submit attempt gets a nonce-based key;
- the key is reused only while the attempt is in flight;
- the key is cleared in `finally`, so an intentional repeat identical ticket receives a fresh key;
- focused Playwright/unit coverage verifies fresh repeat keys and in-flight retry reuse.

### Intent-only tickets: PASS

Intent-only or unfunded tickets are not converted into paid entitlements.

- settlement recomputation checks funding state;
- non-confirmed tickets can be locally cancelled when terminal/refund handling reaches them;
- cancellation records `localSettlementResult` metadata and keeps `funding_status <> confirmed` guarded.

### Smoke tooling and privacy: PASS

- The cross-event smoke script now defaults to explicit 1 USDT base units: `1000000`.
- Numeric ticket detail access now requires a `wallet` query parameter.
- Ticket detail loading filters by `lower(wallet)` and returns not found for a mismatched wallet.
- Ticket listing already remains wallet-scoped.

---

## Previously blocking findings: resolution

### B-01: Cross-event tickets excluded from legacy settlement/accounting projection

**Status:** Resolved.

Every reviewed ticket creation/idempotent path now calls `upsert_legacy_prediction_projection_tx`. The projection uses a deterministic projection event, updates on conflict, and includes ticket metadata needed to identify the projection as ticket-derived.

### B-02: Synthetic vault event settlement not fully wired to claim-safe ticket lifecycle

**Status:** Resolved for the reviewed compatibility model.

The backend now separates local per-leg settlement from public claim/refund readiness. Confirmed tickets remain accepted until the vault event confirms settlement/cancellation, while local terminal outcome is recorded in metadata and projected into accounting.

### B-03: Repeat identical tickets deduplicated by deterministic frontend idempotency

**Status:** Resolved.

Ticket submission idempotency keys are now nonce-based per submit attempt and reused only for the active in-flight attempt.

---

## High-severity findings: resolution

### H-01: Intent-only tickets do not settle or cancel

**Status:** Resolved for safe local handling.

Unfunded/non-confirmed tickets can transition to local cancelled state without creating a paid entitlement. Confirmed tickets remain claim-safe until vault confirmation.

### H-02: Smoke script amount ambiguous

**Status:** Resolved.

The smoke script default is now explicit base units: `ONE_USDT_BASE_UNITS = '1000000'`.

### H-03: Ticket detail endpoint enumerable by numeric id

**Status:** Resolved.

The detail endpoint now requires a wallet query and filters the loaded ticket by wallet.

---

## Remaining constraints and non-blocking notes

- This remains an internal Codex-assisted review, not a third-party audit.
- The vault has a lifetime `MAX_TOTAL_PREDICTIONS = 1,000` cap. Cancelled/finalized predictions do not free slots, so high-volume production should use vault rotation or a native redesign.
- The contract does not verify real per-leg event ids, leg outcomes, or ticket composition. Backend/admin settlement remains authoritative for those facts.
- Backend and frontend should be deployed atomically because the frontend depends on the new `/v1/world-cup-multiplier/tickets` endpoint.
- A shared multi-chain deployment should ensure vault event idempotency includes chain/contract context where relevant.
- Non-blocking hardening suggested by the fresh reviewer:
  - add an explicit HTTP handler regression test for wallet-scoped ticket detail access;
  - add an explicit non-refund terminal intent-only test if product policy expects local cancellation on every terminal leg type.

---

## Verification evidence

Commands/checks completed for the reviewed changes:

- Backend/indexer:
  - `cargo fmt` — passed
  - `cargo check -p indexer` — passed, with pre-existing dead-code warnings
  - `cargo test -p indexer world_cup_multiplier --lib --no-run` — passed
  - `cargo test -p indexer cross_event_ticket --lib` — environment-blocked for DB-backed SQLx tests because the configured test database hostname could not resolve; pure validation tests in that filter passed before DB setup failures
- Frontend:
  - `npm run lint` — passed
  - `npx tsc --noEmit` — passed
  - `npm run build` — passed
  - `npx playwright test tests/world-cup-multiplier-ticket-builder.spec.ts --config=/tmp/strike-frontend-playwright-no-webserver.config.cjs` — 7 passed
- Contracts:
  - `/home/ubuntu/.foundry/bin/forge test --match-contract StrikeMultiplierPredictionVaultTest` — 31 passed
  - `/home/ubuntu/.foundry/bin/forge test` — 620 passed, 0 failed
- Independent review:
  - Fresh cross-repo audit of the current diffs returned PASS with no release-blocking findings.
- Docs:
  - This page replaces the prior blocked candidate review with the current PASS review.

---

## Release recommendation

The reviewed cross-event Prediction Ticket refactor passes the internal review for the previously blocking areas.

Before public production use, deploy backend and frontend together, verify the live ticket create/list/detail APIs, run the cross-event smoke script against the live API with explicit base-unit amounts, and confirm portfolio/API claim/refund states match the synthetic vault lifecycle.
