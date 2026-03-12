# Vault.sol

Internal escrow vault. Holds USDT (ERC-20) collateral on behalf of the protocol contracts. Users never interact with Vault directly — collateral flows in and out automatically via OrderBook, BatchAuction, and Redemption. Users must **approve the Vault** for USDT spending before placing orders.

## Accounting

```
Available = balance[user] - locked[user]
```

- **balance[user]:** total USDT held for the user
- **locked[user]:** subset reserved for open orders

## Functions

### `depositFor(user, amount)` (PROTOCOL_ROLE only)
Called by OrderBook when a user places an order. Transfers USDT from the user to the Vault via `safeTransferFrom(user, vault, amount)` and credits the user's balance. Users do not call this directly — they approve the Vault and call `placeOrder()` on OrderBook.

### `withdrawTo(user, amount)` (PROTOCOL_ROLE only)
Sends USDT from a user's available balance to their wallet via `safeTransfer(user, amount)`. Called by OrderBook (on cancel), BatchAuction (unfilled/excess collateral refund), and Redemption.

### `lock(user, amount)` / `unlock(user, amount)` (PROTOCOL_ROLE only)
Reserve or release collateral backing open orders.

### `settleFill(user, marketId, toPool, feeCollector, protocolFee, unlockAmount, withdrawUser)` (PROTOCOL_ROLE only)
Combined settlement operation used by BatchAuction during inline settlement:
1. Unlock filled + fee + excess collateral from user's locked balance
2. Move filled collateral (minus fee) to market pool
3. Send protocol fee to fee collector's balance
4. Optionally refund excess/unfilled USDT to user's wallet via `safeTransfer`

### `redeemFromPool(marketId, user, amount)` (PROTOCOL_ROLE only)
Pays out USDT from the market pool to a user during redemption. Decrements `marketPool[marketId]` and transfers USDT via `safeTransfer`.

### `emergencyWithdraw()`
User can withdraw all funds after a timelock delay. Safety mechanism — admin cannot block withdrawals indefinitely.

## Integration Points

- **Order placement:** User approves Vault for USDT → `OrderBook.placeOrder()` → `Vault.depositFor()` (transferFrom) + `Vault.lock()`
- **Order cancel:** `OrderBook.cancelOrder()` → `Vault.unlock()` + `Vault.withdrawTo()` (transfer)
- **Batch settlement:** `BatchAuction.clearBatch()` → `Vault.settleFill()` (fills to pool, fees to collector, excess/unfilled refund to wallet)
- **Redemption:** `Redemption.redeem()` → `Vault.redeemFromPool()` (USDT payout to wallet)

## Security

- ReentrancyGuard on all external functions
- Checks-Effects-Interactions pattern
- SafeERC20 for all USDT transfers (safeTransferFrom, safeTransfer)
- No admin access to user funds (admin can only set protocol parameters)

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
