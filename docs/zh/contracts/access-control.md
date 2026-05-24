# 访问控制与 Role Graph

所有使用 role-based 访问控制的 STRIKE 合约都继承 OpenZeppelin 的 `AccessControl`。PythResolver 例外，它使用更简单的自定义 ownership model。

## Roles 概览

| Role | Defined 在 | 授予对象 | 目的 |
|------|-----------|------------|---------|
| `DEFAULT_ADMIN_ROLE` | 所有 AccessControl 合约 | 部署者 EOA | 可以授予或 revoke 任意 role |
| `OPERATOR_ROLE` | 订单簿 | BatchAuction, MarketFactory | 管理市场和结算订单 |
| `PROTOCOL_ROLE` | 金库 | 订单簿, BatchAuction, Redemption | 锁定、解锁、转账抵押资产 |
| `MINTER_ROLE` | OutcomeToken | BatchAuction, Redemption | 铸造和销毁结果代币 |
| `ESCROW_ROLE` | OutcomeToken | BatchAuction | 在成交时通过 `burnEscrow()` 销毁 escrowed sell-order 代币 |
| `ADMIN_ROLE` | MarketFactory | PythResolver | 管理市场状态 transitions |

## Role Definitions

### DEFAULT_ADMIN_ROLE（所有合约）

```
bytes32 公开constant DEFAULT_ADMIN_ROLE = 0x00;
```

由部署者 EOA 持有。它可以对任意 role 调用 `grantRole` 与 `revokeRole`。该 role 属于 OpenZeppelin 的默认管理员 role，负责管理所有其他 role。

### OPERATOR_ROLE（订单簿）

```
bytes32 公开constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
```

授予以下访问权限：
- `registerMarket(minLots, batchInterval, expiryTime)` -- 创建新交易市场。
- `haltMarket(marketId)` / `resumeMarket(marketId)` -- 暂停或恢复交易。
- `deactivateMarket(marketId)` -- 永久关闭市场。
- `reduceOrderLots(orderId, lotsToReduce)` -- 从订单中扣减已成交 lots。
- `updateTreeVolume(marketId, side, tick, delta)` -- 成交后调整线段树。
- `advanceBatch(marketId)` -- 递增批次计数器。

该 role 授予 **BatchAuction**（结算操作）和 **MarketFactory**（市场生命周期）。

### PROTOCOL_ROLE（金库）

```
bytes32 公开constant PROTOCOL_ROLE = keccak256("PROTOCOL_ROLE");
```

授予以下访问权限：
- `lock(user, amount)` -- 为开放订单锁定抵押资产。
- `unlock(user, amount)` -- 在取消或 prune 时解锁抵押资产。
- `transferCollateral(from, to, amount)` -- 在账户之间移动锁定资金。
- `settleFill(user, marketId, toPool, feeCollector, protocolFee, unlockAmount)` -- 执行合并结算。
- `addToMarketPool(user, marketId, amount)` -- 将资金移入赎回池。
- `redeemFromPool(marketId, to, amount)` -- 从赎回池支付资金。

该 role 授予 **订单簿**（下单和取消时锁定或解锁）、**BatchAuction**（结算）以及 **Redemption**（从 pool 支付）。

### MINTER_ROLE（OutcomeToken）

```
bytes32 公开constant MINTER_ROLE = keccak256("MINTER_ROLE");
```

授予以下访问权限：
- `mintPair(to, marketId, amount)` -- 铸造 YES + NO 代币 pair。
- `mintSingle(to, marketId, amount, isYes)` -- 铸造单个结果代币。
- `burnPair(from, marketId, amount)` -- 销毁 YES + NO 代币 pair。
- `redeem(from, marketId, amount, winningOutcome)` -- 销毁胜出代币。

该 role 授予 **BatchAuction**（在 `clearBatch` 原子化结算期间铸造代币）和 **Redemption**（赎回期间销毁胜出代币）。

### ESCROW_ROLE（OutcomeToken）

```
bytes32 公开constant ESCROW_ROLE = keccak256("ESCROW_ROLE");
```

授予以下访问权限：
- `burnEscrow(from, marketId, amount, isYes)` -- 批次结算中，当卖单（SellYes/SellNo）成交时，销毁由订单簿托管的 escrowed 结果代币。

该 role 授予 **BatchAuction**。当 SellYes 或 SellNo 订单成交时，相关代币已在下单时由订单簿托管。BatchAuction 会在结算流程中调用 `burnEscrow()` 销毁这些代币。

### ADMIN_ROLE（MarketFactory）

```
bytes32 公开constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
```

授予以下访问权限：
- `setResolving(factoryMarketId)` -- 将市场转换为 Resolving 状态。
- `setResolved(factoryMarketId, outcomeYes, settlementPrice)` -- 最终确认结算。
- `payResolverBounty(factoryMarketId, resolver)` -- 将 creation bond 支付给 resolver。
- `pauseFactory(paused)` -- 暂停或恢复市场创建。
- `setDefaultParams(batchInterval, minLots)` -- 更新默认市场参数。
- `setCreationBond(bond)` -- 更新 creation bond 金额。
- `setFeeCollector(collector)` -- 更新费用收集器。

该 role 授予 **PythResolver**（结算状态转换）及 **部署者**（管理员控制）。注意：部署者也会通过 MarketFactory constructor 收到 `ADMIN_ROLE`。

### PythResolver Admin（自定义 ownership）

PythResolver 不使用 OpenZeppelin AccessControl。它有一个简单的 `admin` 地址，在构造函数中设置为 `msg.sender`。管理员转移采用两步模式：

```solidity
// Step 1: Current admin sets pending
pythResolver.setPendingAdmin(newAdmin);

// Step 2: New admin accepts
pythResolver.acceptAdmin();   // must be called by newAdmin
```

管理员可以调用：
- `setConfThreshold(newBps)` -- 更新 confidence interval threshold。

## Role Graph (ASCII)

```
                         Deployer EOA
                             |
              +--------------+--------------+
              |              |              |
       DEFAULT_ADMIN    DEFAULT_ADMIN   DEFAULT_ADMIN
       (OrderBook)      (Vault)         (OutcomeToken)
              |              |              |
              |              |              |
       OPERATOR_ROLE   PROTOCOL_ROLE   MINTER_ROLE
       (OrderBook)      (Vault)        (OutcomeToken)
         /      \        / | \           /      \
        v        v      v  v  v         v        v
  BatchAuction  MarketFactory          BatchAuction
                    |       OrderBook       |
                    |       BatchAuction    Redemption
                    |       Redemption
                    |
             DEFAULT_ADMIN + ADMIN_ROLE
              (MarketFactory)
                    |
               ADMIN_ROLE
              (MarketFactory)
                    |
                    v
              PythResolver ---------> admin (deployer EOA)
             (custom ownership)       setPendingAdmin / acceptAdmin
```

Detailed 流程 diagram:

```
  +---------------+  OPERATOR_ROLE   +-------------+
  | BatchAuction  |----------------->|  OrderBook  |
  +---------------+                  +-------------+
        |                                  |
        | PROTOCOL_ROLE                    | PROTOCOL_ROLE
        v                                  v
  +---------------+                  +-------------+
  |     Vault     |<-----------------| (lock/unlock)|
  +---------------+                  +-------------+
        ^
        | PROTOCOL_ROLE
        |
  +---------------+
  |  Redemption   |
  +---------------+
        |
        | MINTER_ROLE
        v
  +---------------+
  | OutcomeToken  |<---- MINTER_ROLE ---- BatchAuction
  +---------------+

  +---------------+  ADMIN_ROLE      +----------------+
  | PythResolver  |----------------->| MarketFactory  |
  +---------------+                  +----------------+
                                           |
                                           | OPERATOR_ROLE
                                           v
                                     +-------------+
                                     |  OrderBook  |
                                     +-------------+
```

## Wiring Commands

部署后运行以下命令（部署者必须在每个合约中持有 `DEFAULT_ADMIN_ROLE`）：

```solidity
// OrderBook: grant OPERATOR_ROLE
orderBook.grantRole(orderBook.OPERATOR_ROLE(), address(batchAuction));
orderBook.grantRole(orderBook.OPERATOR_ROLE(), address(marketFactory));

// Vault: grant PROTOCOL_ROLE
vault.grantRole(vault.PROTOCOL_ROLE(), address(orderBook));
vault.grantRole(vault.PROTOCOL_ROLE(), address(batchAuction));
vault.grantRole(vault.PROTOCOL_ROLE(), address(redemption));

// OutcomeToken: grant MINTER_ROLE
outcomeToken.grantRole(outcomeToken.MINTER_ROLE(), address(batchAuction));
outcomeToken.grantRole(outcomeToken.MINTER_ROLE(), address(redemption));

// OutcomeToken: grant ESCROW_ROLE
outcomeToken.grantRole(outcomeToken.ESCROW_ROLE(), address(batchAuction));

// MarketFactory: grant ADMIN_ROLE
factory.grantRole(factory.ADMIN_ROLE(), address(pythResolver));
```

## 安全说明

- 部署者持有所有合约中的 `DEFAULT_ADMIN_ROLE`。生产环境部署时应将其转移给 multisig 或 timelock。
- PythResolver 管理员也应通过 `setPendingAdmin` / `acceptAdmin` 转移给 multisig。
- Role grant 是累加式的；`grantRole` 不会 revoke 现有 holders。
- 缺少必要 role grant 会在运行时触发 `AccessControl: account... is missing role...` revert。
