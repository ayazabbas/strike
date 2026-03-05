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
- **Order placement:** `lock BNB collateral` (both bids and asks — asks lock BNB, not outcome tokens)
- **Fill claims:** `unlock → transfer` based on batch result
- **Redemption:** `burn winning token → unlock collateral → available`

## Security

- ReentrancyGuard on all external functions
- Checks-Effects-Interactions pattern
- No admin access to user funds (admin can only set protocol parameters)
- `receive()` reverts — use `deposit()` instead

## Events

```solidity
event Deposited(address indexed user, uint256 amount);
event Withdrawn(address indexed user, uint256 amount);
event Locked(address indexed user, uint256 amount);
event Unlocked(address indexed user, uint256 amount);
event CollateralTransferred(address indexed from, address indexed to, uint256 amount);
event AddedToMarketPool(uint256 indexed marketId, uint256 amount);
event RedeemedFromPool(uint256 indexed marketId, address indexed to, uint256 amount);
event EmergencyModeActivated(uint256 timestamp);
event EmergencyWithdrawn(address indexed user, uint256 amount);
```
