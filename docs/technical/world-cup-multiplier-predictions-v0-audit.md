# World Cup Multiplier Predictions V0 Historical Audit

**Date:** 2026-06-07
**Auditor:** Internal Codex-assisted security review
**Scope:** World Cup Multiplier Predictions V0 persistence, API, admin surfaces, frontend prototype and admin gating as of the review date, migrations 043 and 044
**Verdict:** PASS for V0 from a fund-theft and funds-stuck perspective

---

## Executive Summary

This is a historical internal, Codex-assisted audit report for the current state at the time of review. It is not an external third-party audit.

The reviewed World Cup Multiplier Predictions V0 implementation was OK for V0 from the specific fund-theft and funds-stuck perspective after the documented hardening. The final independent Codex review reported **PASS** with no remaining blocking findings.

At the time of this audit, V0 payment execution was disabled. The reviewed state did not perform token transfers, claims, refunds, contract writes, or mainnet broadcasts for World Cup Multiplier predictions. Public prediction creation recorded an off-chain prediction intent only.

See [Production Launch Smoke Addendum](#production-launch-smoke-addendum) for the later production smoke context.

---

## Scope

The review covered:

- World Cup Multiplier persistence, API, and admin surfaces
- Frontend prototype behavior and admin wallet default/gating at the time
- Database migrations `043_world_cup_multiplier_persistence.sql` and `044_world_cup_multiplier_security_hardening.sql`
- Backend current commits `3325997` and `4b92a02`
- Frontend current commits `1c4c71f` and `0c34854`

The review did not cover contract payment execution. At the time of review, V0 payment execution was disabled: no token transfers, no claims or refunds, no contract writes, and no mainnet broadcasts.

---

## Main Risks Reviewed

The review focused on the risks that could have turned the payment-disabled implementation reviewed at the time into an economic liability or created an unsafe admin path:

- False funded entitlement from unpaid prediction intents
- Funds stuck from lifecycle, cancellation, or settlement bugs
- Admin signature replay or signature reuse across routes, bodies, wallets, or environments
- Mutable material terms after an event opens or after the first prediction intent
- Race conditions between prediction creation and admin event patching
- Idempotency collisions across events, wallets, or changed request bodies
- Settlement accounting that includes unpaid rows
- Migration upgrade safety for databases that already applied migration 043

---

## Historical Current-State Hardening

The reviewed current state at the time included the following hardening:

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

## Production Launch Smoke Addendum

After the historical audit above, World Cup Multiplier Predictions was production-smoked through the frontend, backend API, and vault flows.

- Production route: `/world-cup-multiplier-predictions`
- Vault address: `0x6859109EEBd3E6A885150d7AF1dE1d3Cd97399f3`
- Tiny smoke event id: `2`
- Smoke coverage categories: submit prediction, contribute, settle, claim paid, finalize, portfolio/API/UI smoke

This addendum documents production smoke coverage only. It does not convert the historical internal review into a third-party audit and does not disclose or rely on any secret or private-key material.

---

## V0 Limitations

This report should be read as a historical V0 internal review of the state on 2026-06-07, plus the production smoke addendum above.

The most important original limitation was intentional: payment execution was disabled at the time of the audit. Later production smoke covered the live frontend wallet, API, and vault flows listed in the addendum, including claim paid and finalize verification for the tiny smoke event.
