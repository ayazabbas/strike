# FeeModel.sol

用于 STRIKE CLOB 协议的纯费用计算合约。该合约不执行任何转账；所有资金变动都由调用方处理（金库、BatchAuction 等）。FeeModel 只负责计算金额。

Inherits: `AccessControl` (OpenZeppelin).

## 费用 Schedule

| Parameter | Type | Description | 默认 |
|-----------|------|-------------|---------|
| `feeBps` | `uint256` | 统一费用，单位为 basis points | 20 (0.20%) |
| `clearingBountyBps` | `uint256` | 清算 keeper 的 bonus（管理员可配置，当前 disabled） | 0 |
| `protocolFeeCollector` | `address` | 接收协议费用份额的地址 | 部署者 |

**Constant:** `MAX_BPS = 10_000` (100%).

不区分 maker/taker；交易双方各支付一半费用（50/50 split）。整数 rounding 产生的额外 wei 归协议所有（sell side 支付 `ceil`）。

## Calculation 函数

### calculateFee

```solidity
function calculateFee(uint256 amount) 公开view returns (uint256 fee)
```

返回给定成交抵押资产金额对应的总费用。

Formula: `fee = amount * feeBps / 10_000`

### calculateHalfFee

```solidity
function calculateHalfFee(uint256 amount) 公开view returns (uint256 fee)
```

返回 buy-side 的半数费用: `floor(calculateFee(amount) / 2)`。

### calculateOtherHalfFee

```solidity
function calculateOtherHalfFee(uint256 amount) 公开view returns (uint256 fee)
```

返回 sell-side 的半数费用: `calculateFee(amount) - calculateHalfFee(amount)`（即 `ceil(fee / 2)`）。sell-side 费用会在结算时从卖方的 USDT payout 中扣除。

## Admin 函数

所有管理员函数都需要 `DEFAULT_ADMIN_ROLE`。

### setFeeBps

```solidity
function setFeeBps(uint256 _feeBps) external
```

更新统一费用。如果 `_feeBps > MAX_BPS`，则 revert。

### setClearingBounty

```solidity
function setClearingBounty(uint256 _clearingBountyBps) external
```

设置清算 bounty 百分比（当前 disabled，预留供未来使用）。

### setProtocolFeeCollector

```solidity
function setProtocolFeeCollector(address _collector) external
```

更新协议费用收集器地址。如果 `_collector` 为 zero 地址，则 revert。

## 事件

| Event | 参数 | Description |
|-------|-----------|-------------|
| `FeeBpsUpdated` | `uint256 feeBps` | 费用变化时触发 |
| `ClearingBountyUpdated` | `uint256 clearingBountyBps` | 清算 bounty 变化时触发 |
| `ProtocolFeeCollectorUpdated` | `address indexed collector` | 费用收集器变化时触发 |

## 示例

默认参数 (feeBps=20):

- 已成交抵押资产: 100 USDT
- 总费用: 100 * 20 / 10000 = 0.20 USDT
- Buy-side 费用: floor(0.20 / 2) = 0.10 USDT
- Sell-side 费用: ceil(0.20 / 2) = 0.10 USDT
- 支付给协议费用收集器: 0.20 USDT（两边费用之和）
