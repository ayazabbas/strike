# 访问控制与 Role Graph

Strike 合约通常使用 OpenZeppelin `AccessControl`。`PythResolver` 使用较小的自定义 admin model。

## Roles 概览

| Role | Defined In | 授予对象 | 目的 |
|------|------------|----------|------|
| `DEFAULT_ADMIN_ROLE` | AccessControl contracts | Deployer/admin | 授予和撤销 roles |
| `OPERATOR_ROLE` | OrderBook | BatchAuction, MarketFactory | 市场生命周期和 batch 操作 |
| `PROTOCOL_ROLE` | Vault | OrderBook, BatchAuction, Redemption | 抵押资产和内部仓位记账 |
| `MINTER_ROLE` | OutcomeToken | BatchAuction, Redemption | 铸造/销毁结果代币 |
| `ESCROW_ROLE` | OutcomeToken | BatchAuction | 销毁 escrowed sell-order tokens |
| `ADMIN_ROLE` | MarketFactory | Deployer/admin, resolvers | 市场状态转换和协议参数 |
| `MARKET_CREATOR_ROLE` | MarketFactory | Approved creators/keepers | 创建 CLOB 市场 |

## OrderBook `OPERATOR_ROLE`

用于：

- `registerMarket(minLots, batchInterval, expiryTime, useInternalPositions)`
- `haltMarket(marketId)` / `resumeMarket(marketId)`
- `deactivateMarket(marketId)`
- `advanceBatch(marketId)`
- `setLastClearingTick(marketId, tick)`
- `pullRestingOrders(marketId)`

授予 **MarketFactory** 用于市场注册/生命周期，授予 **BatchAuction** 用于清算操作。

## Vault `PROTOCOL_ROLE`

用于抵押资产和仓位记账：

- `depositFor`, `withdrawTo`, `lock`, `unlock`
- `settleFill`, `redeemFromPool`
- `creditPosition`, `lockPosition`, `unlockPosition`, `redeemPosition`

授予 **OrderBook**、**BatchAuction** 和 **Redemption**。

## OutcomeToken Roles

- `MINTER_ROLE`：铸造和销毁 YES/NO 结果代币。
- `ESCROW_ROLE`：卖单成交时，销毁 OrderBook escrow 中的结果代币。

## MarketFactory Roles

`ADMIN_ROLE` 控制生命周期和管理员操作：

- `setResolving(factoryMarketId)`
- `setResolved(factoryMarketId, outcomeYes, settlementPrice)`
- `setCancelled(factoryMarketId)`
- `pauseFactory(paused)`
- `setDefaultParams(batchInterval, minLots, feeBps)`
- `setAIResolver(resolver)`

`MARKET_CREATOR_ROLE` 是调用 `createMarket`、`createMarketWithPositions` 和 `createAIMarket` 的必要 role。

## PythResolver Admin

`PythResolver` 有自定义 `admin`，采用两步转移：

```solidity
pythResolver.setPendingAdmin(newAdmin);
pythResolver.acceptAdmin();
```

Admin 可以更新 confidence threshold 参数。只要 Pyth data 和时间条件有效，resolution submission/finalization 是 permissionless 的。
