# USDT Credit Reserve Notes

## Consumed credit principal and V3 settlement

`USDTCreditReserve` keeps USDT backing inside the reserve and settles user credit balances by ledger updates. `settleCreditPayout` remains available for pure credit ledger settlement where no USDT needs to leave the reserve.

For V3 mixed real/credit markets, event-authorized markets can use `settleCreditPayoutAndWithdraw` when consumed locked credit principal must fund real-USDT winners through the market or vault. The call consumes the user's locked credit, credits any reserve-ledger payout back to the user, records `marketWithdrawnTotal`, and transfers the requested USDT backing to the recipient.

Integration rules:

- Call only from an event-authorized market.
- Set `withdrawAmount` to the portion of `lockedCreditConsumed` that must move as real USDT to the market or vault.
- Keep `withdrawAmount <= lockedCreditConsumed`; excess winnings that remain credit should be represented by `creditPayout`.
- Use `settleCreditPayout` for pure credit payouts/refunds where the reserve should only update ledger balances.
- Reserve solvency is tracked as `freeTotal + lockedTotal + redeemedTotal + marketWithdrawnTotal <= fundedUsdt`, with the reserve's USDT balance required to cover `freeTotal + lockedTotal`.
- Market settlement funding uses a transfer-then-record pattern. Before an authorized market calls `fundFromMarketSettlement`, it must transfer the USDT backing into the reserve; the reserve requires its USDT balance to have increased by at least the credited `amount` since the last observed reserve balance before increasing `fundedUsdt`. This prevents an authorized market from recording settlement capacity out of already-accounted reserve surplus.
