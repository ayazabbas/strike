# Multiplier Predictions Protocol

Strike Multiplier Predictions is the fixed-multiplier exact-result product used for event series such as the 2026 World Cup. This page covers protocol behavior, economics, coverage, settlement, API, and vault responsibilities.

For a user-facing walkthrough, see [Multiplier Predictions](../getting-started/world-cup-multiplier-predictions.md). The live app is available at [strike.fun/world-cup-multiplier-predictions](https://strike.fun/world-cup-multiplier-predictions).

## Event model

Each multiplier event has admin-configured outcomes. Outcomes represent exact, objectively resolvable fields for a supported event series, such as match score, winner, or another clearly defined event result. Each selectable outcome has an assigned multiplier.

Users can select one or more outcomes in one prediction. The combined multiplier is the product of the selected outcome multipliers. A prediction wins only when every selected outcome resolves correctly.

## Pools and economics

Multiplier Predictions use two pools:

- **Prediction Pool** — funded by accepted user prediction amounts.
- **Bonus Backstop Pool** — funded by user contributions that may earn from leftover Prediction Pool rewards while providing backstop coverage.

Current product economics:

- 100% of leftover Prediction Pool goes to Bonus Backstop Pool contributors.
- 0% platform reserve or skim on leftover Prediction Pool.
- 0% fee on prediction amounts, winnings, and contributor rewards for this product direction.

If no prediction wins, or if winning predictions do not use the whole Prediction Pool, leftover Prediction Pool funds are distributed to Bonus Backstop Pool contributors pro-rata. If winning payouts exceed the Prediction Pool, the Bonus Backstop Pool can be used to cover the difference for accepted predictions.

## Coverage

Before requesting a quote, the frontend estimates whether the current Bonus Backstop Pool can support the selected multiplier and prediction amount. If coverage looks insufficient, the UI may show a reduced maximum prediction amount.

This preflight is only a client estimate. The API quote and vault transaction checks are authoritative for accepted amounts and coverage limits.

Coverage checks should account for:

- selected outcomes and combined multiplier;
- requested prediction amount;
- current Prediction Pool and Bonus Backstop Pool balances;
- already accepted prediction exposure;
- event status and submission window;
- vault limits and transaction state.

## Settlement and payout flow

After result data is available, the event is settled against the configured outcomes. Each prediction is evaluated as all-or-nothing:

- If every selected outcome is correct, the prediction is eligible for its accepted payout.
- If any selected outcome is incorrect, the prediction does not receive a winning payout.
- If an event is cancelled or marked refundable, eligible prediction receipts can expose refund actions.

Settlement determines winning payouts, leftover Prediction Pool funds, Bonus Backstop Pool usage, contributor rewards, and final claim or refund availability.

## Earn and contributor risk

Bonus Backstop Pool contributors may receive pro-rata rewards from leftover Prediction Pool funds. Contributions also carry downside risk because the pool can be used to cover accepted winning prediction payouts when the Prediction Pool is insufficient.

Contributor accounting must keep contribution balances, withdrawals, rewards, coverage obligations, and settlement state consistent. The app can show estimates, but the API and vault are the authority for contribution, withdrawal, claim, refund, and settlement state.

## API responsibilities

The API is responsible for exposing event, quote, receipt, portfolio, and settlement data consistently to the frontend and admin surfaces.

Expected API behavior includes:

- serving active and historical multiplier events;
- returning selectable outcomes and configured multipliers;
- quoting combined multiplier, accepted prediction amount, and potential payout;
- enforcing event status, time windows, and coverage constraints;
- recording accepted prediction receipts;
- exposing Bonus Backstop Pool contribution and withdrawal state;
- exposing claim, refund, and contributor reward availability;
- supporting admin settlement and event lifecycle operations.

API responses should make clear which values are estimates and which values are accepted or settled.

## Vault responsibilities

The vault is the authority for token movement and accepted on-chain state. User actions can require USDT approval followed by the relevant vault submission.

Vault responsibilities include:

- accepting prediction amounts for active events;
- accepting Bonus Backstop Pool contributions;
- enforcing coverage and event-state checks at transaction time;
- retaining funds until settlement, claim, refund, withdrawal, or contributor reward distribution;
- paying eligible winning prediction claims;
- processing refunds for cancelled or refundable events;
- distributing eligible contributor rewards after settlement.

Frontend and API checks should reduce failed transactions, but vault checks remain authoritative.

## Receipts and portfolio

Portfolio receipts should show multiplier prediction entries with status, selected outcomes, prediction amount, potential payout or refund, transaction links, and claim or refund actions when available.

Contributor views should show Bonus Backstop Pool contribution state, estimated or settled rewards, available withdrawals, and any risk or coverage state relevant to the current event.

## Security and audit reference

The current internal review for the candidate cross-event ticket model is available at [World Cup Multiplier Cross-Event Ticket Internal Review](../technical/world-cup-multiplier-predictions-v0-audit.md). It is an internal Codex-assisted review, not an external third-party audit, and it should be read together with the blocker findings before treating cross-event tickets as release-ready.
