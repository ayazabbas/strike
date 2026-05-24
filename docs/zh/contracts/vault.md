# 金库.sol

内部托管金库。它代表协议合约持有 USDT (ERC-20) 抵押资产。用户不会直接与金库交互；抵押资产的流入和流出会通过订单簿、BatchAuction 与 Redemption 自动完成。用户在下单前必须先**授权金库**使用其 USDT。

## Accounting

```
Available = balance[user] - locked[user]
```

- **balance[用户]:** 为用户托管的 USDT 总额。
- **锁定[用户]:** 已预留给开放订单的部分。

## 函数

### `depositFor(user, amount)` (PROTOCOL_ROLE only)
订单簿在用户下单时调用。该函数通过 `safeTransferFrom(user, vault, amount)` 将 USDT 从用户转入金库，并记入用户的 balance。用户不应直接调用此函数；用户只需要授权金库并在订单簿中调用 `placeOrder()`。

### `withdrawTo(user, amount)` (PROTOCOL_ROLE only)
通过 `safeTransfer(user, amount)` 将用户的可用 balance 发送到其钱包。该函数由订单簿（取消订单时）、BatchAuction（退回未成交或多余抵押资产时）以及 Redemption 调用。

### `lock(user, amount)` / `unlock(user, amount)` (PROTOCOL_ROLE only)
预留或释放用于支持开放订单的抵押资产。

### `settleFill(user, marketId, toPool, feeCollector, protocolFee, unlockAmount, withdrawUser)` (PROTOCOL_ROLE only)
BatchAuction 在内联结算期间使用的合并结算操作：
1. 从用户的 locked balance 中解锁成交金额、费用以及多余抵押资产。
2. 将成交抵押资产（扣除费用后）转入市场池。
3. 将协议费用记入费用收集器的 balance。
4. 可选地通过 `safeTransfer` 将多余或未成交的 USDT 退回用户钱包。

### `redeemFromPool(marketId, user, amount)` (PROTOCOL_ROLE only)
赎回期间从市场池向用户支付 USDT。该函数会减少 `marketPool[marketId]`，并通过 `safeTransfer` 转账。

### `emergencyWithdraw()`
timelock delay 结束后，用户可以提取全部资金。这一安全机制可防止管理员无限期阻止提款。

## 集成点

- **下单:** 用户授权金库使用 USDT → `OrderBook.placeOrder()` → `Vault.depositFor()`（转账）+ `Vault.lock()`。
- **取消订单:** `OrderBook.cancelOrder()` → `Vault.unlock()` + `Vault.withdrawTo()`（转账）。
- **Batch 结算:** `BatchAuction.clearBatch()` → `Vault.settleFill()`（成交金额进入市场池、费用进入 collector、多余或未成交抵押资产退回钱包）。
- **Redemption:** `Redemption.redeem()` → `Vault.redeemFromPool()`（USDT 支付到钱包）。

## 安全

- 所有 external 函数都使用 ReentrancyGuard。
- 遵循 Checks-Effects-Interactions 模式。
- 所有 USDT 转账都使用 SafeERC20（safeTransferFrom、safeTransfer）。
- 管理员不能访问用户资金，只能设置协议参数。

## 事件

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
