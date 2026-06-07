# World Cup Multiplier Predictions V0 Audit

**Date:** 2026-06-07
**Auditor:** Internal Codex-assisted security review
**Scope:** World Cup Multiplier Predictions V0 persistence, API, admin surfaces, frontend prototype and admin gating, migrations 043 and 044
**Verdict:** PASS for V0 from a fund-theft and funds-stuck perspective

---

## Executive Summary

This is an internal, Codex-assisted current-state audit report. It is not an external third-party audit and does not claim that the reviewed code has been pushed, deployed, or enabled in production.

The reviewed World Cup Multiplier Predictions V0 implementation is OK for V0 from the specific fund-theft and funds-stuck perspective after the documented hardening. The final independent Codex review reported **PASS** with no remaining blocking findings.

V0 payment execution remains disabled. The reviewed state does not perform token transfers, claims, refunds, contract writes, or mainnet broadcasts for World Cup Multiplier predictions. Public prediction creation records an off-chain prediction intent only.

---

## Scope

The review covered:

- World Cup Multiplier persistence, API, and admin surfaces
- Frontend prototype behavior and admin wallet default/gating
- Database migrations `043_world_cup_multiplier_persistence.sql` and `044_world_cup_multiplier_security_hardening.sql`
- Backend current commits `3325997` and `4b92a02`
- Frontend current commits `1c4c71f` and `0c34854`

The review did not cover contract payment execution. V0 payment execution remains disabled: no token transfers, no claims or refunds, no contract writes, and no mainnet broadcasts.

---

## Main Risks Reviewed

The review focused on the risks that could turn a payment-disabled prototype into an economic liability or create an unsafe admin path:

- False funded entitlement from unpaid prediction intents
- Funds stuck from lifecycle, cancellation, or settlement bugs
- Admin signature replay or signature reuse across routes, bodies, wallets, or environments
- Mutable material terms after an event opens or after the first prediction intent
- Race conditions between prediction creation and admin event patching
- Idempotency collisions across events, wallets, or changed request bodies
- Settlement accounting that includes unpaid rows
- Migration upgrade safety for databases that already applied migration 043

---

## Current-State Hardening

The reviewed current state includes the following hardening:

- Public prediction creation is intent-only. New rows use `prediction_status=intent_recorded` and `funding_status=payment_disabled`.
- Payment-disabled intents do not update Prediction Pool accounting and do not reserve Bonus Backstop Pool coverage.
- Settlement, cancellation, entitlement updates, and economic accounting require `funding_status=confirmed`.
- Migration 044 backfills legacy `accepted` + `payment_disabled` rows to `intent_recorded`.
- Admin EIP-191 messages are reconstructed by the server and bound to wallet, method, path, raw body SHA-256, `issued_at`, nonce, and environment.
- Admin nonce replay is rejected with persisted consumed nonces.
- Material event terms freeze irreversibly once an event opens or once any prediction intent exists.
- `create_prediction` and `admin_patch_event` serialize on the same event row lock before reading or updating outcomes and odds.
- Cancel, settle, and finalize paths use transactions and event row locks.
- Non-refund settlements require non-empty `winning_outcomes`.
- Prediction idempotency is scoped to event, wallet, and idempotency key, and is bound to the request body hash.
- Migration 043 is preserved. Migration 044 is a forward, idempotent hardening migration.

---

## Verification

The following verification commands passed during the hardening review:

- `cargo fmt`
- `cargo check -p indexer`
- `cargo test -p indexer world_cup_multiplier`
- `git diff --check`
- Final Codex staged-diff security review

Final review result:

- Verdict: **PASS**
- Blocking findings: none
- Non-blocking findings: none

---

## V0 Limitations

This report should be read as a V0 current-state internal review, not a production launch attestation.

The most important limitation is intentional: payment execution is disabled. Prediction creation records intent but does not move tokens or create a claimable on-chain position. Any future version that enables payments, contract writes, claims, refunds, or mainnet broadcasts needs a fresh review of those payment and settlement paths before release.
