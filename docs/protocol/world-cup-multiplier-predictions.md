# Multiplier Predictions Protocol

Strike Multiplier Predictions is the fixed-multiplier exact-result product used for event series such as the 2026 World Cup. This page covers protocol behavior, economics, coverage, settlement, API, and vault responsibilities.

For a user-facing walkthrough, see [Multiplier Predictions](../getting-started/world-cup-multiplier-predictions.md). The live app is available at [strike.fun/world-cup-multiplier-predictions](https://strike.fun/world-cup-multiplier-predictions).

## Event and ticket model

Each multiplier event has admin-configured outcomes. Outcomes represent exact, objectively resolvable fields for a supported event series, such as match score, winner, group-stage result, or another clearly defined event result. Each selectable outcome has an assigned multiplier.

The current product submits prediction tickets. A ticket contains one or more legs, and each leg references an event outcome. Tickets can span multiple events. The combined multiplier is the product of all leg multipliers. Settlement is all-or-nothing: every leg must resolve correctly for the ticket to win.

For vault compatibility, cross-event tickets are represented as synthetic vault events in backend/indexer accounting. The API and vault checks remain authoritative for accepted amount, coverage, settlement, claim, and refund state.

## Pools and economics

Multiplier Predictions use two pools:

- **Prediction Pool** — funded by accepted user prediction amounts.
- **Prediction Liquidity Pool** — funded by user contributions that may earn from leftover Prediction Pool rewards while providing payout coverage.

Current product economics:

- 100% of leftover Prediction Pool goes to Prediction Liquidity Pool contributors.
- 0% platform reserve or skim on leftover Prediction Pool.
- 0% fee on prediction amounts, winnings, and contributor rewards for this product direction.

If no prediction wins, or if winning predictions do not use the whole Prediction Pool, leftover Prediction Pool funds are distributed to Prediction Liquidity Pool contributors pro-rata. If winning payouts exceed the Prediction Pool, the Prediction Liquidity Pool can be used to cover the difference for accepted tickets.

## Coverage

Before requesting a quote, the frontend estimates whether the current Prediction Liquidity Pool can support the selected multiplier and entry amount. If coverage looks insufficient, the UI may show a reduced maximum entry amount.

This preflight is only a client estimate. The API quote and vault transaction checks are authoritative for accepted amounts and coverage limits. If coverage is exhausted, the quote may reduce the accepted amount or reject the ticket. The frontend should not imply that preview payout math is guaranteed before quote/vault acceptance.

Coverage checks should account for:

- selected legs and combined multiplier;
- requested entry amount;
- current Prediction Pool and Prediction Liquidity Pool balances;
- already accepted prediction exposure;
- event status and submission window;
- vault limits and transaction state.

## Settlement and payout flow

After result data is available, each event is settled against its configured outcomes. Each ticket is evaluated as all-or-nothing:

- If every ticket leg is correct, the ticket is eligible for its accepted payout.
- If any ticket leg is incorrect, the ticket does not receive a winning payout.
- If an event is cancelled or marked refundable, eligible receipts can expose refund actions.

Settlement determines winning payouts, leftover Prediction Pool funds, Prediction Liquidity Pool usage, contributor rewards, and final claim or refund availability.

## Earn and contributor risk

Prediction Liquidity Pool contributors may receive pro-rata rewards from leftover Prediction Pool funds. Contributions also carry downside risk because the pool can be used to cover accepted winning prediction payouts when the Prediction Pool is insufficient.

Contributor accounting must keep contribution balances, withdrawals, rewards, coverage obligations, and settlement state consistent. Withdrawals and contributor rewards can be limited while exposure is active or settlement is pending. The app can show estimates, but the API and vault are the authority for contribution, withdrawal, claim, refund, and settlement state.

## API responsibilities

The API is responsible for exposing event, quote, ticket, portfolio, settlement, and liquidity-pool data consistently to the frontend and admin surfaces.

Current public API routes include:

- `GET /v1/world-cup-multiplier/events`
- `GET /v1/world-cup-multiplier/events/{id}`
- `GET|POST /v1/world-cup-multiplier/events/{id}/predictions`
- `GET|POST /v1/world-cup-multiplier/tickets`
- `GET /v1/world-cup-multiplier/tickets/{id}`
- `GET /v1/world-cup-multiplier/portfolio/{wallet}`
- `GET /v1/world-cup-multiplier/backstop-pool`
- `GET|POST /v1/world-cup-multiplier/backstop-pool/contributions`
- `GET|POST /v1/world-cup-multiplier/backstop-pool/withdrawals`

The public product should call this the Prediction Liquidity Pool even where legacy API paths still use `backstop-pool`.

Expected API behavior includes:

- serving active and historical multiplier events;
- returning selectable outcomes and configured multipliers;
- quoting combined multiplier, accepted entry amount, and potential payout;
- enforcing event status, time windows, and coverage constraints;
- recording accepted prediction and ticket receipts;
- exposing Prediction Liquidity Pool contribution and withdrawal state;
- exposing claim, refund, and contributor reward availability;
- supporting admin settlement and event lifecycle operations.

API responses should make clear which values are estimates and which values are accepted or settled. Use the generated OpenAPI spec for exact schemas.

## Vault responsibilities

The vault is the authority for token movement and accepted on-chain state. User actions can require USDT approval followed by the relevant vault submission.

Vault responsibilities include:

- accepting prediction amounts for active events or tickets;
- accepting Prediction Liquidity Pool contributions;
- enforcing coverage and event-state checks at transaction time;
- retaining funds until settlement, claim, refund, withdrawal, or contributor reward distribution;
- paying eligible winning prediction claims;
- processing refunds for cancelled or refundable events;
- distributing eligible contributor rewards after settlement.

Frontend and API checks should reduce failed transactions, but vault checks remain authoritative.

## Receipts and portfolio

Portfolio receipts should show multiplier prediction tickets with status, legs, entry amount, potential payout or refund, transaction links, and claim or refund actions when available.

Contributor views should show Prediction Liquidity Pool contribution state, estimated or settled rewards, available withdrawals, and any risk or coverage state relevant to current exposure.

## Security and audit reference

The current internal review for the cross-event ticket model is available at [World Cup Multiplier Cross-Event Ticket Internal Review](../technical/world-cup-multiplier-predictions-v0-audit.md). It is an internal Codex-assisted review, not an external third-party audit. The follow-up review passed for the previously blocking backend/accounting, synthetic-vault lifecycle, frontend idempotency, smoke-unit, intent-only, and ticket-privacy areas.
