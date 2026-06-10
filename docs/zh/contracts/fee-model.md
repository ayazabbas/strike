# FeeModel.sol

Strike CLOB 协议的费用计算合约。它不移动资金；Vault、BatchAuction 等调用方负责资金移动。

继承：`AccessControl`。

## 费用参数

| 参数 | 类型 | 说明 | 默认值 |
|------|------|------|--------|
| `feeBps` | `uint256` | 总费用，单位 bps | 20（0.20%） |
| `protocolFeeCollector` | `address` | 接收协议费用的地址 | deployer |

**常量：** `MAX_BPS = 10_000`（100%）。

费用不区分 maker/taker。买方与卖出 token/position 的订单成交时，总费用会在买方和卖方之间拆分；卖方侧拿到向上取整的一半。普通 Bid/Ask 成交时，买方下单时锁定的 fee 用于支付协议费用。

## 计算函数

### `calculateFee(amount)`

返回给定成交抵押金额对应的总费用。

公式：`fee = amount * feeBps / 10_000`

### `calculateHalfFee(amount)`

返回 `ceil(calculateFee(amount) / 2)`。BatchAuction 在 token/position 卖方收到 payout 时，将其作为卖方侧费用。

### `calculateOtherHalfFee(amount)`

返回 `calculateFee(amount) - calculateHalfFee(amount)`。BatchAuction 在买方与卖出 token/position 的订单成交时，将其作为买方侧费用。

## 管理函数

所有管理函数都需要 `DEFAULT_ADMIN_ROLE`。

### `setFeeBps(_feeBps)`

更新统一费率。若 `_feeBps > MAX_BPS` 则 revert。

### `setProtocolFeeCollector(_collector)`

更新协议费用接收地址。若 `_collector` 为零地址则 revert。

## Events

| Event | 参数 | 说明 |
|-------|------|------|
| `FeeBpsUpdated` | `uint256 feeBps` | fee 变化时发出 |
| `ProtocolFeeCollectorUpdated` | `address indexed collector` | fee collector 变化时发出 |

## 示例

当 `feeBps = 20`：

- 成交抵押金额：100 USDT
- 总费用：`100 * 20 / 10000 = 0.20 USDT`
- 拆分费用：整数取整前约 `0.10 USDT` / `0.10 USDT`
- 接收方：protocol fee collector
