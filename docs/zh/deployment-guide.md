# 部署指南

## 前置条件

- 已安装 [Foundry](https://book.getfoundry.sh/)（`forge`、`anvil`、`cast`）
- 用于支付 gas fees 的 BNB
- Deployer EOA private key
- BscScan API key（用于合约验证）

## 环境变量

```bash
export PRIVATE_KEY=0x...                # Deployer private key
export RPC_URL=https://...              # BSC RPC endpoint
export PYTH_ADDRESS=0x...              # Pyth Core contract address (see table below)
export ETHERSCAN_API_KEY=...           # BscScan API key for verification
```

### Pyth Oracle 地址

| Network | Chain ID | Pyth Core Address |
|---------|----------|-------------------|
| BSC Testnet | 97 | `0x5744Cbf430D99456a0A8771208b674F27f8EF0Fb` |
| BSC Mainnet | 56 | `0x4D7E825f80bDf85e913E0DD2A2D54927e9dE1594` |

## 部署顺序

BSC 的 canonical deploy entrypoint 是 `script/DeployTestnet.s.sol:DeployTestnetScript`。
虽然名称中包含 Testnet，但该脚本会感知 chain，并且当前同时用于 BSC testnet（`chainid=97`）与 BSC mainnet（`chainid=56`）。它也会部署并连接 `AIResolver`。

由于构造函数包含 immutable references，合约必须严格依照以下顺序部署：

```
1. Vault              -- no dependencies
2. OutcomeToken        -- no dependencies
3. FeeModel            -- no dependencies
4. OrderBook           -- needs Vault
5. BatchAuction        -- needs OrderBook, Vault, FeeModel, OutcomeToken
6. MarketFactory       -- needs OrderBook, OutcomeToken
7. PythResolver        -- needs Pyth oracle address, MarketFactory
8. Redemption          -- needs MarketFactory, OutcomeToken, Vault
```

### 构造函数参数

| Contract | Constructor Args |
|----------|-----------------|
| `Vault(admin, collateralToken)` | deployer address, USDT address |
| `OutcomeToken(admin)` | deployer address |
| `FeeModel(admin, feeBps, protocolFeeCollector)` | deployer, 20, deployer |
| `OrderBook(admin, vault, feeModel, outcomeToken)` | deployer, Vault address, FeeModel address, OutcomeToken address |
| `BatchAuction(admin, orderBook, vault, outcomeToken)` | deployer, OrderBook, Vault, OutcomeToken |
| `MarketFactory(admin, orderBook, outcomeToken)` | deployer, OrderBook, OutcomeToken |
| `PythResolver(pyth, factory)` | PYTH_ADDRESS, MarketFactory |
| `AIResolver(factory, treasury)` | MarketFactory, deployer or configured treasury |
| `Redemption(factory, outcomeToken, vault)` | MarketFactory, OutcomeToken, Vault |

## Role Wiring

所有合约部署完成后，授予以下 roles。Deployer 在每个 AccessControl 合约上持有 `DEFAULT_ADMIN_ROLE`，因此可以调用 `grantRole`。

### OrderBook.OPERATOR_ROLE

```solidity
orderBook.grantRole(OPERATOR_ROLE, address(batchAuction));
orderBook.grantRole(OPERATOR_ROLE, address(marketFactory));
```

BatchAuction 需要 OPERATOR_ROLE 来调用 `reduceOrderLots`、`updateTreeVolume` 和 `advanceBatch`。MarketFactory 需要该 role 来调用 `registerMarket` 和 `deactivateMarket`。生产部署中，keeper 也会被授予 `OPERATOR_ROLE`，以便驱动 batch clearing。

### Vault.PROTOCOL_ROLE

```solidity
vault.grantRole(PROTOCOL_ROLE, address(orderBook));
vault.grantRole(PROTOCOL_ROLE, address(batchAuction));
vault.grantRole(PROTOCOL_ROLE, address(redemption));
```

OrderBook 调用 `lock` 和 `unlock`。BatchAuction 调用 `settleFill` 和 `unlock`。Redemption 调用 `redeemFromPool`。

### OutcomeToken.MINTER_ROLE

```solidity
outcomeToken.grantRole(MINTER_ROLE, address(batchAuction));
outcomeToken.grantRole(MINTER_ROLE, address(redemption));
```

BatchAuction 于 inline settlement 中调用 `mintSingle`。Redemption 调用 `redeem`（销毁获胜 tokens）。

### MarketFactory.ADMIN_ROLE

```solidity
factory.grantRole(ADMIN_ROLE, address(pythResolver));
factory.grantRole(ADMIN_ROLE, address(aiResolver));
factory.grantRole(ADMIN_ROLE, keeper);
factory.grantRole(ADMIN_ROLE, resolutionKeeper);
factory.grantRole(MARKET_CREATOR_ROLE, deployer);
factory.grantRole(MARKET_CREATOR_ROLE, keeper);
factory.setAIResolver(address(aiResolver));
```

PythResolver 与 AIResolver 会调用 MarketFactory 上的结算函数。生产部署还会于 factory 上向 keeper 与 resolution-keeper 授予 admin access，并向 deployer 与 keeper 授予 market-creation rights。

### AIResolver Keeper Wiring

```solidity
aiResolver.grantRole(KEEPER_ROLE, keeper);
aiResolver.grantRole(KEEPER_ROLE, resolutionKeeper);
```

### PythResolver Admin

PythResolver 使用简单 ownership（并非 AccessControl）。Admin 于构造函数中设置为 `msg.sender`（即 deployer）。通过两步流程转移：

```solidity
pythResolver.setPendingAdmin(newAdmin);   // called by current admin
pythResolver.acceptAdmin();               // called by newAdmin
```

## 部署命令

### Local Devnet (Anvil)

用于本地开发和测试：

```bash
anvil --chain-id 31337

forge script script/Deploy.s.sol \
  --rpc-url http://localhost:8545 \
  --broadcast
```

仅用于本地的 `Deploy.s.sol` 脚本会部署一个 `MockPyth` 实例、连接全部 roles，并自动创建一个测试市场。

### BSC Testnet / Mainnet

```bash
forge script script/DeployTestnet.s.sol:DeployTestnetScript \
  --rpc-url $RPC_URL \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

`DeployTestnetScript` 会自动检测 `block.chainid`，为 BSC testnet 或 mainnet 选择正确的真实 Pyth address，部署 `AIResolver`，并连接生产 role set。

注意：`script/DeployMainnet.s.sol` 仍存在于 repo 中，但 canonical production path 是上方 chain-aware 的 `DeployTestnet.s.sol:DeployTestnetScript` 流程。

## Parimutuel 合约部署

Parimutuel stack 被有意与 binary CLOB contracts 隔离，并通过 `script/DeployParimutuel.s.sol:DeployParimutuelScript` 部署。

它会部署并连接：

1. `ParimutuelFactory`
2. `ParimutuelVault`
3. `ParimutuelPoolManager`
4. `ParimutuelRedemption`
5. `ParimutuelAIResolver`
6. `ParimutuelPythResolver`

必需 env：

```bash
export PRIVATE_KEY=0x...          # or DEPLOYER_PRIVATE_KEY
export USDT_ADDRESS=0x...         # BSC mainnet USDT or testnet mock USDT
export PYTH_ADDRESS=0x...         # Pyth Core for the target chain
```

推荐的 mainnet role env：

```bash
export PARIMUTUEL_FINAL_ADMIN=0xDA680a19C8E5a43a5B6280d2a1e1A5E2E8ACD874
export PARIMUTUEL_FEE_RECIPIENT=$PARIMUTUEL_FINAL_ADMIN
export PARIMUTUEL_MARKET_CREATOR=0x73f173D43Fa5284e85d8c4F20453E9bA2629Dd9A
export PARIMUTUEL_KEEPER=0x439d5804Bf14e97f1DA3449304f4167621ff9Cfe
```

`PARIMUTUEL_MARKET_CREATOR` 应当使用 keeper/admin-server signer，这样生产 admin tooling 才能创建 markets。`PARIMUTUEL_KEEPER` 应当使用 resolution keeper，因为 infra lifecycle task 会使用 resolution sender 驱动 AI/Pyth parimutuel resolution。

部署：

```bash
forge script script/DeployParimutuel.s.sol:DeployParimutuelScript \
  --rpc-url $RPC_URL \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

部署完成后，在启用 mainnet UI/keeper flows 之前，更新 address registry、`strike-infra` Ansible group vars，以及 `strike-frontend/src/lib/contracts.ts`。

## 合约验证

部署脚本会传入 `--verify`，并于 BscScan 上自动验证。手动验证合约：

```bash
forge verify-contract <CONTRACT_ADDRESS> src/MarketFactory.sol:MarketFactory \
  --chain-id 56 \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --constructor-args $(cast abi-encode \
    "constructor(address,address,address,address)" \
    $DEPLOYER $ORDERBOOK $OUTCOMETOKEN $FEECOLLECTOR)
```

对于构造函数参数复杂的合约，使用 `cast abi-encode` 生成正确编码。

## 部署后验证清单

1. **合约验证** - 所有合约均已于 BscScan 验证。

2. **Role wiring** - 确认每个 role grant：
   ```bash
   cast call $ORDERBOOK "hasRole(bytes32,address)(bool)" \
     $(cast keccak "OPERATOR_ROLE") $BATCH_AUCTION
   # Repeat for every grant listed above
   ```

3. **Role checks：**
   - `OrderBook.hasRole(OPERATOR_ROLE, BatchAuction)` - true
   - `OrderBook.hasRole(OPERATOR_ROLE, MarketFactory)` - true
   - `Vault.hasRole(PROTOCOL_ROLE, OrderBook)` - true
   - `Vault.hasRole(PROTOCOL_ROLE, BatchAuction)` - true
   - `Vault.hasRole(PROTOCOL_ROLE, Redemption)` - true
   - `OutcomeToken.hasRole(MINTER_ROLE, BatchAuction)` - true
   - `OutcomeToken.hasRole(MINTER_ROLE, Redemption)` - true
   - `MarketFactory.hasRole(ADMIN_ROLE, PythResolver)` - true

4. **测试市场创建** - 使用已知 Pyth price ID 调用 `MarketFactory.createMarket(...)`（需要 MARKET_CREATOR_ROLE），并确认市场出现在 `activeMarkets` 中。

5. **测试下单/取消流程** - 为 Vault approve USDT，调用 `OrderBook.placeOrder(...)`，并确认 USDT collateral 已托管至 Vault。取消订单后，确认 USDT 已返还至 wallet。

6. **Keepers 配置** - batch-keeper、market-keeper 与 resolution-keeper（位于 strike-infra）应指向正确的合约地址。

7. **Indexer 配置** - indexer（位于 strike-infra）应指向正确的 RPC 和合约地址，并监听所有相关 events。

8. **SDK / docs 更新** - 更新 SDK 默认值与已发布的 deployment docs/README，确保 integrators 使用新的 mainnet 与 testnet addresses。
