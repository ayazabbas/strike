# World Cup Multiplier Predictions

Strike Multiplier Predictions is a World Cup campaign product for structured exact-result predictions with fixed multipliers.

The live app is available at [strike.fun/world-cup-multiplier-predictions](https://strike.fun/world-cup-multiplier-predictions).

## How it works

Each multiplier event has a set of admin-configured outcomes, such as exact match result fields or other clearly defined World Cup outcomes. Every selectable outcome has an assigned multiplier.

To submit a prediction:

1. Choose an active multiplier event.
2. Select one or more outcomes.
3. Review the combined multiplier and potential payout.
4. Enter a prediction amount in USDT.
5. Confirm the wallet flow: USDT approval, then vault submission.

A prediction wins only if **every selected outcome is correct**. If any selected outcome is wrong, the multiplier prediction does not win.

## Combined multipliers

When you select multiple outcomes in one event, the UI multiplies the selected outcome multipliers together and shows the combined multiplier before you submit.

Example:

- Outcome A: 2×
- Outcome B: 3×
- Combined multiplier: 6×
- Prediction amount: 10 USDT
- Potential payout if all selected outcomes are correct: 60 USDT

The quoted payout is only available for accepted predictions that pass the API and vault coverage checks.

## Prediction Pool and Bonus Backstop Pool

Multiplier Predictions use two pools:

- **Prediction Pool** — funded by user prediction amounts.
- **Bonus Backstop Pool** — contributed by users who want to earn from leftover Prediction Pool rewards while also providing backstop coverage.

If no prediction wins, or if winning predictions do not use the whole Prediction Pool, the leftover Prediction Pool is distributed to Bonus Backstop Pool contributors pro-rata.

Current product economics:

- 100% of leftover Prediction Pool goes to Bonus Backstop Pool contributors.
- 0% platform reserve / skim on leftover Prediction Pool.
- 0% fee on prediction amounts, winnings, and contributor rewards for this product direction.

## Earn: contributing to the Bonus Backstop Pool

The Earn tab lets users contribute USDT to the Bonus Backstop Pool through the vault.

Contributors may earn when the Prediction Pool has leftover funds. However, the Bonus Backstop Pool may also be used to cover accepted prediction payouts when the Prediction Pool is not enough.

This means contributors have downside risk. The app shows risk and coverage information before contribution or prediction submission, and the API/vault checks remain the authority for accepted amounts, withdrawals, claims, refunds, and settlement state.

## Coverage preflight

Before requesting a quote, the frontend estimates whether the current Bonus Backstop Pool can support the selected multiplier and prediction amount.

If coverage looks insufficient, the UI may show a reduced maximum prediction amount. This is a client estimate only; the API quote and vault transaction checks are still authoritative.

## Settlement, claims, and refunds

After an event is settled:

- Winning predictions can claim their eligible payout.
- Cancelled or refunded events can expose refund actions.
- Portfolio receipts show multiplier prediction entries, status, selected outcomes, prediction amount, potential payout/refund, transaction links, and claim/refund actions when available.

## Important notes

- A multiplier prediction is final once submitted.
- Exact-result rules matter: every selected outcome must be correct to win.
- Bonus Backstop Pool contributors can earn rewards but also carry backstop risk.
- Always review the event, selected outcomes, combined multiplier, prediction amount, potential payout, and wallet prompts before confirming.
- The audit and smoke addendum are available at [World Cup Multiplier Predictions V0 Historical Audit & Smoke Addendum](../technical/world-cup-multiplier-predictions-v0-audit.md).
