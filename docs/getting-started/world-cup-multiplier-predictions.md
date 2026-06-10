# Multiplier Predictions

Strike Multiplier Predictions is a fixed-multiplier, exact-result prediction product. The 2026 World Cup is the first event series and use case.

The live app is available at [strike.fun/world-cup-multiplier-predictions](https://strike.fun/world-cup-multiplier-predictions).

For protocol, economics, coverage, settlement, API, and vault details, see [Multiplier Predictions Protocol](../protocol/world-cup-multiplier-predictions.md).

## What it is

Each event lists clearly defined outcomes, such as match results, group-stage outcomes, or tournament outcomes. Every selectable outcome has a fixed multiplier.

A prediction ticket contains one or more legs. In the current World Cup flow, legs may come from multiple events. The combined multiplier is the product of all selected leg multipliers, and the ticket wins only if every leg is correct.

## Quick example

- Outcome A: 5x
- Outcome B: 10x
- Combined multiplier: 50x
- Entry amount: 10 USDT
- Potential payout if both legs are correct: 500 USDT

The app shows the combined multiplier and potential payout before you submit. The final accepted amount depends on the quote and vault checks.

## Submit a prediction ticket

1. Open [strike.fun/world-cup-multiplier-predictions](https://strike.fun/world-cup-multiplier-predictions).
2. Pick one or more event outcomes to add legs to your ticket.
3. Review the combined multiplier, entry amount, coverage, and potential payout.
4. Confirm the wallet flow: USDT approval if needed, then vault submission.
5. Check your portfolio receipt for ticket status, legs, entry amount, potential payout or refund, and transaction links.

## Earn and Prediction Liquidity Pool

The Earn tab lets users contribute USDT to the Prediction Liquidity Pool.

Contributors may earn when the Prediction Pool has leftover funds after settlement. The Prediction Liquidity Pool can also be used to cover accepted prediction payouts when the Prediction Pool is not enough, so contributions carry downside risk.

Review the app’s pool, coverage, and risk information before contributing. For the full economics, see [Multiplier Predictions Protocol](../protocol/world-cup-multiplier-predictions.md).

## Claim or refund

After an event or ticket is settled:

- Winning tickets can claim their eligible payout.
- Cancelled or refunded events can expose refund actions.
- Portfolio receipts show claim or refund actions when they are available.

If a claim or refund is not shown, the event may still be open, settlement may not be finalized, or the connected wallet may not have an eligible receipt.

## Important notes

- A multiplier prediction ticket is final once submitted.
- Exact-result rules matter: every ticket leg must be correct to win.
- Prediction Liquidity Pool contributors can earn rewards but also carry coverage risk.
- Always review the selected legs, combined multiplier, entry amount, potential payout, and wallet prompts before confirming.
