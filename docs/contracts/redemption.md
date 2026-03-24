# Redemption.sol

Post-resolution token redemption. Users burn winning outcome tokens 1:1 for USDT collateral.

## `redeem(factoryMarketId, amount)`

1. Verify market is in `Resolved` state
2. Determine winning outcome (YES or NO) from MarketFactory
3. Burn `amount` winning outcome tokens from caller via OutcomeToken
4. Pay out `amount * LOT_SIZE` USDT from market pool via `vault.redeemFromPool()`

## Dependencies

- **MarketFactory:** reads market state and outcome
- **OutcomeToken:** burns winning tokens (requires MINTER_ROLE)
- **Vault:** pays out from market pool (requires PROTOCOL_ROLE)

## Notes

- Only winning tokens can be redeemed (losing tokens have no value)
- Market pool is funded during atomic settlement in `clearBatch()`
- Each position unit represents 1 lot = LOT_SIZE (1e16 = $0.01)
- For `useInternalPositions` markets (current 5-minute markets), redemption works with internal position balances instead of ERC-1155 tokens

## Events

- `Redeemed(uint256 indexed factoryMarketId, address indexed user, uint256 amount, bool outcomeYes)`
