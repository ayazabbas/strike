# World Cup Multiplier Cross-Event Ticket Internal Review

**Date:** 2026-06-08
**Auditor:** Internal Codex-assisted security review
**Scope:** Candidate cross-event Prediction Ticket refactor across backend/indexer, frontend, portfolio/admin rendering, and `StrikeMultiplierPredictionVault` ticket-as-vault-event compatibility
**Verdict:** **Not release-ready for the cross-event ticket branch**. Contract compatibility passed, but backend/accounting and frontend idempotency blockers must be fixed before the cross-event ticket model is treated as production-ready.

---

## Executive summary

This is an internal, Codex-assisted review. It is not an external third-party audit.

The reviewed candidate branch adds true cross-event Prediction Tickets: one user-facing ticket can contain legs from multiple events, while the existing vault ABI is reused by representing each ticket as one synthetic vault event.

The contract compatibility strategy is sound at the ABI level, and focused vault tests passed. However, the current candidate implementation is **not release-ready** because the audit found blockers in backend settlement/accounting coverage for the new `/world-cup-multiplier/tickets` path and in frontend idempotency behavior for repeat identical tickets.

---

## Scope reviewed

The review covered the uncommitted candidate work on branch `feature/world-cup-cross-event-tickets` across:

- `/home/ubuntu/dev/strike-infra`
  - migration `047_world_cup_multiplier_cross_event_tickets.sql`
  - ticket creation endpoint and legacy route compatibility
  - ticket list/detail/portfolio receipt APIs
  - settlement projection and vault event synchronization
- `/home/ubuntu/dev/strike-frontend`
  - cross-event ticket builder and submit path
  - ticket API client types
  - portfolio and admin rendering
  - local ticket-builder tests and smoke script
- `/home/ubuntu/dev/strike`
  - `StrikeMultiplierPredictionVault` compatibility tests
  - ticket-as-vault-event documentation
  - public docs/security navigation state

---

## Verdict by area

### Contract compatibility: PASS

The existing `StrikeMultiplierPredictionVault` ABI can represent one cross-event ticket as one synthetic vault event:

- submit uses one `bytes32 eventId` for the synthetic ticket vault event;
- the ticket uses one `bytes32 predictionId`;
- payout can be claimed after settling the synthetic vault event with that prediction id;
- refund can be claimed after cancelling the synthetic vault event;
- the vault does not need to know the real per-leg event ids.

This means no Solidity ABI change is required for the pilot compatibility path.

### Backend/indexer candidate: BLOCKED

The new ticket tables and APIs are directionally correct, but the current implementation has release-blocking settlement/accounting gaps for pure `/world-cup-multiplier/tickets` submissions.

### Frontend candidate: BLOCKED

The ticket builder and portfolio/admin rendering are directionally correct, but the current submit path uses a deterministic idempotency key that can prevent users from creating a second independent ticket with the same legs and entry amount.

---

## Blocking findings

### B-01: Cross-event tickets are excluded from legacy settlement/accounting projection

**Severity:** Blocker

Pure `/world-cup-multiplier/tickets` submissions create rows in `multiplier_prediction_tickets` and `multiplier_prediction_ticket_legs`, but they do not create the legacy `multiplier_predictions` projection used by existing settlement accounting.

Observed risk:

- accepted or paid cross-event tickets can exist in the ticket tables;
- `prediction_pool_states` and related accounting still aggregate from `multiplier_predictions`;
- the legacy projection is only created for the legacy `/events/{id}/predictions` compatibility path;
- vault event sync updates existing projection rows but does not create a projection for pure ticket rows.

**Impact:** ticket acceptance, accounting, settlement visibility, and pool state can diverge for the new ticket endpoint.

**Required fix:** either create a reliable accounting projection for every accepted ticket or update accounting/settlement code to aggregate from the canonical ticket tables directly.

### B-02: Synthetic vault event settlement is not fully wired to real cross-event ticket settlement

**Severity:** Blocker

The compatibility model signs each ticket against a synthetic ticket-level `vault_event_id`, while local admin settlement updates legs based on their real event ids. The reviewed settlement projection recorded a vault-settlement TODO rather than settling/cancelling the synthetic vault event.

Observed risk:

- backend can mark ticket legs or ticket status locally;
- vault payout/refund state only changes when the synthetic vault event is settled or cancelled;
- if synthetic vault settlement is not performed consistently, user-facing ticket status can diverge from claim/refund availability.

**Impact:** funds can become operationally stuck or claims/refunds can be unavailable even when the ticket appears terminal off-chain.

**Required fix:** implement and test the full synthetic-vault-event lifecycle for win, loss, refund/cancel, and no-terminal-state cases before production release.

### B-03: Repeat identical tickets are blocked or deduplicated by deterministic frontend idempotency

**Severity:** Blocker

The frontend derives the ticket idempotency key from wallet, entry amount, and sorted leg selections. A user who intentionally submits the same selections and amount again can receive the prior ticket result instead of creating a new independent ticket, depending on backend idempotency retention.

**Impact:** users may be unable to create legitimate repeat entries.

**Required fix:** generate a per-submit-attempt idempotency key and reuse it only for retries of the same in-flight submission.

---

## High-severity findings

### H-01: Intent-only tickets do not settle or cancel in the reviewed path

New tickets default to `ticket_status = intent_recorded`. The settlement projection reviewed only updates `accepted` or `refund_pending` tickets. If payment-disabled or intent-only rows remain possible, they can stay stale after admin settle/cancel actions.

**Required fix:** define the intended lifecycle for intent-only tickets and ensure admin settle/cancel paths either ignore them deliberately with clear status or transition them safely.

### H-02: Smoke script amount is inconsistent with frontend base-unit submissions

The frontend submits entry amounts in USDT base units. The local smoke script defaulted to `"1"`, which is one base unit rather than 1 USDT if the API expects the same format.

**Required fix:** make the smoke script use explicit base units such as `1000000` for 1 USDT, or clearly label it as a one-base-unit dust smoke.

### H-03: Ticket detail endpoint is enumerable by numeric id

The reviewed ticket detail route returns a ticket by numeric id without wallet filtering or authorization.

**Required fix:** if ticket details, payment metadata, or receipt data are considered wallet-private, require wallet-scoped access or avoid exposing sensitive fields from unauthenticated numeric ids.

---

## Medium findings and constraints

- Vault event idempotency is unique by `(tx_hash, log_index)` only. A shared multi-chain database should include chain and contract context.
- The vault has a lifetime `MAX_TOTAL_PREDICTIONS = 1,000` cap. Cancelled or finalized predictions do not free slots. This is acceptable for a bounded pilot but not for high-volume production without vault rotation or a native redesign.
- The contract does not verify real per-leg event ids, leg outcomes, or cross-event ticket composition. Backend/admin settlement correctness is authoritative for those facts.
- The frontend depends on the new `/v1/world-cup-multiplier/tickets` endpoint. Backend and frontend deployment must be atomic, or a compatibility fallback must be added.
- The local Playwright ticket-builder test was coupled to the app webServer config and could not run cleanly in the audited workspace because an existing Next dev lock was present.

---

## Positive observations

- The ticket schema separates ticket-level data from per-leg rows and preserves the legacy prediction model for rollout compatibility.
- Validation covers positive base-unit amounts, maximum ticket legs, active/open events, lock times, duplicate `(event_id, group_key)` entries, and active outcomes.
- SQL paths reviewed use bound parameters for user-controlled values.
- Portfolio rendering supports both legacy selected-outcome receipts and the new `legs[]` shape.
- Contract tests demonstrate win and refund compatibility using the synthetic vault event model.

---

## Verification evidence

Commands and checks reported during this review:

- Backend/indexer:
  - `cargo test -p indexer world_cup_multiplier --no-default-features`
  - Result: 31 unit tests passed; DB-backed SQLx tests could not execute because the test database hostname was unavailable in the environment.
- Frontend:
  - `npm run lint` — passed
  - `npx tsc --noEmit` — passed
  - `npm run build` — passed
  - `npx playwright test tests/world-cup-multiplier-ticket-builder.spec.ts` — blocked by local Next dev lock / webServer startup coupling
  - local smoke script — could not run against localhost because `/v1/world-cup-multiplier/events` returned 404 in the local environment
- Contracts:
  - `/home/ubuntu/.foundry/bin/forge test --match-contract StrikeMultiplierPredictionVaultTest` — 31 passed
  - full Foundry suite — 620 passed, 0 failed
- Docs:
  - prior public docs still described the older V0 historical/payment-disabled audit and needed replacement with this current review.

---

## Release recommendation

Do not treat the cross-event Prediction Ticket refactor as production-ready until the blocker findings above are fixed and re-reviewed.

A follow-up release-ready review should specifically verify:

1. every paid/accepted ticket participates in the correct accounting source of truth;
2. synthetic vault events are settled or cancelled exactly once for every terminal ticket outcome;
3. claim/refund availability matches ticket status in API and portfolio receipts;
4. repeat identical tickets create independent entries while retries remain idempotent;
5. smoke tests use explicit base-unit amounts and run against a live compatible API;
6. public docs are updated again from **blocked candidate review** to **release-ready review** only after the fixes pass.
