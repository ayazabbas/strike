# Redemption.sol

Post-resolution token redemption. Users burn winning outcome tokens 1:1 for BNB collateral.

## `redeem(factoryMarketId, amount)`

1. Verify market is in `Resolved` state
2. Determine winning outcome (YES or NO) from MarketFactory
3. Burn `amount` winning outcome tokens from caller via OutcomeToken
4. Pay out `amount * LOT_SIZE` BNB from market pool via `vault.redeemFromPool()`

## Dependencies

- **MarketFactory:** reads market state and outcome
- **OutcomeToken:** burns winning tokens (requires MINTER_ROLE)
- **Vault:** pays out from market pool (requires PROTOCOL_ROLE)

## Notes

- Only winning tokens can be redeemed (losing tokens have no value)
- Market pool is funded during `claimFills()` in BatchAuction
- Each outcome token represents 1 lot = LOT_SIZE (1e15 wei = 0.001 BNB)
