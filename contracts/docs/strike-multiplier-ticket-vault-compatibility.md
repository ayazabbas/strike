# Strike Multiplier Ticket Vault Compatibility

Task 10 conclusion: the ticket-as-vault-event strategy is compatible with the deployed
`StrikeMultiplierPredictionVault` ABI.

The contract does not know about backend real event ids. It only accepts a `bytes32 eventId`
and a `bytes32 predictionId` for prediction admission and settlement accounting. For
cross-event tickets, the backend can therefore create one synthetic `vault_event_id` for the
ticket, submit the ticket as one `contract_prediction_id`, and keep the real per-leg event ids
off-chain.

Claim and refund compatibility:

- Winning ticket: backend settles the synthetic `vault_event_id` with the winning
  `contract_prediction_id`; the user claim path calls `claimPredictionPayout(predictionId)`.
- Refundable ticket: backend cancels the synthetic `vault_event_id`; the user refund path calls
  `claimRefund(predictionId)`.

Capacity risk:

- `MAX_TOTAL_PREDICTIONS = 1_000` is enforced against the vault's `_predictionIds.length`, which
  is append-only. This is a lifetime accepted-prediction cap for the deployed vault instance.
- `MAX_PREDICTIONS_PER_EVENT = 128` applies to each vault event. One vault event per ticket keeps
  each synthetic event at one prediction, so this cap is not the short-term constraint.
- One vault event per ticket is operationally acceptable for a short pilot or bounded rollout, but
  high-volume production use needs either additional vault instances or a later Solidity-native
  ticket design.

No Solidity ABI changes are required for this compatibility path.
