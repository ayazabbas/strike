# Vault.sol

Singleton collateral vault. Holds all BNB deposits and manages locked balances.

## Accounting

```
Available = deposited - locked
```

- **Deposited:** total BNB deposited by user
- **Locked:** collateral backing open orders or pending claims

## Functions

### `deposit()`
Payable. Adds `msg.value` to user's available balance.

### `withdraw(amount)`
Withdraw available (unlocked) balance. Reverts if insufficient.

### `lock(user, amount)` / `unlock(user, amount)`
Internal. Called by OrderBook on order placement/cancellation.

### `emergencyWithdraw()`
User can withdraw all funds after a timelock delay. Safety mechanism — admin cannot block withdrawals indefinitely.

## Integration Points

- **OutcomeToken minting:** `deposit → lock → mint pair` flow
- **OutcomeToken merging:** `burn pair → unlock → available`
- **Order placement:** `lock collateral` (bids) or `lock outcome tokens` (asks — tracked separately)
- **Fill claims:** `unlock → transfer` based on batch result
- **Redemption:** `burn winning token → unlock collateral → available`

## Security

- ReentrancyGuard on all external functions
- Checks-Effects-Interactions pattern
- No admin access to user funds (admin can only set protocol parameters)
