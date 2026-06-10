# PythResolver.sol

使用 Pyth 价格更新结算订单簿市场。

## 结算流程

1. 市场到期后，任何人都可以调用 `resolveMarket(...)` 提交 Pyth update data。
2. Resolver 从 `msg.value` 支付 Pyth update fee；多余 ETH/BNB 会退回。
3. Pyth 验证 update data，并返回市场配置 feed 在有效结算窗口内的价格。
4. 如果这是首次有效提交，市场进入 `Resolving`，并启动 90 秒 finality window。
5. 在 finality window 内，任何人都可以提交更早且会改变结果的有效 update。
6. finality 后，任何人都可以调用 `finalizeResolution(...)`；结果规则为 `price >= strike` → YES 胜出，`price < strike` → NO 胜出。

## 主要函数

```solidity
function resolveMarket(uint256 factoryMarketId, bytes[] calldata priceUpdateData)
    external
    payable

function finalizeResolution(uint256 factoryMarketId) external
```

`resolveMarket` 要求 `msg.value` 至少覆盖 `pyth.getUpdateFee(priceUpdateData)`。当前核心 CLOB 合约不支付 resolver bounty。

## 说明

- Price ID 以 `bytes32` 存在 `MarketFactory.marketMeta` 中。
- 结算是 permissionless 的，但通常由托管 keeper 执行。
- Confidence check 会拒绝价格不确定性过高的 update。
- 如果市场无法使用有效 Pyth data 结算，factory 可以进入配置的 fallback / cancellation 流程。
