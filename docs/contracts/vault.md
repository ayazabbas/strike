# Vault.sol

Internal escrow vault. Holds BNB collateral on behalf of the protocol contracts. Users never interact with Vault directly — collateral flows in and out automatically via OrderBook, BatchAuction, and Redemption.

## Accounting

```
Available = balance[user] - locked[user]
```

- **balance[user]:** total BNB held for the user
- **locked[user]:** subset reserved for open orders

## Functions

### `depositFor(user)` (PROTOCOL_ROLE only)
Called by OrderBook when a user places an order. Credits `msg.value` to the user's balance. Users do not call this directly.

### `withdrawTo(user, amount)` (PROTOCOL_ROLE only)
Sends BNB from a user's available balance to their wallet. Called by OrderBook (on cancel), BatchAuction (unfilled collateral refund), and Redemption.

### `lock(user, amount)` / `unlock(user, amount)` (PROTOCOL_ROLE only)
Reserve or release collateral backing open orders.

### `settleFill(user, marketId, toPool, feeCollector, protocolFee, unlockAmount, withdrawUser)` (PROTOCOL_ROLE only)
Combined settlement operation used by BatchAuction during inline settlement. Moves filled collateral to market pool, protocol fee to collector, unlocks unfilled collateral, and optionally refunds unfilled BNB to user's wallet — all in a single call.

### `emergencyWithdraw()`
User can withdraw all funds after a timelock delay. Safety mechanism — admin cannot block withdrawals indefinitely.

## Integration Points

- **Order placement:** `OrderBook.placeOrder{value}()` → `Vault.depositFor()` + `Vault.lock()`
- **Order cancel:** `OrderBook.cancelOrder()` → `Vault.unlock()` + `Vault.withdrawTo()`
- **Batch settlement:** `BatchAuction.clearBatch()` → `Vault.settleFill()` (fills to pool, refunds to wallet)
- **Redemption:** `Redemption.redeem()` → `Vault.redeemFromPool()` (pays out to wallet)

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
