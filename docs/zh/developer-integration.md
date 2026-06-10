# 开发者集成指南

## ABI 位置

使用 `forge build` 构建后，完整 ABI 会输出到：

```
contracts/out/<ContractName>.sol/<ContractName>.json
```

提取 `abi` 字段供前端或脚本使用：

```bash
jq '.abi' contracts/out/MarketFactory.sol/MarketFactory.json > abi/MarketFactory.json
```

预先提取的前端 ABI 位于 `strike-frontend/src/lib/abi/`。

## 合约地址

部署脚本会以 JSON 形式将所有地址打印至 stdout。部署完成后，保存该输出并用于配置你的应用。当前已部署地址见 [Deployments](contracts/deployments.md)。

## 与合约交互

### 使用 wagmi/viem (TypeScript)

```typescript
import { readContract, writeContract } from '@wagmi/core';
import { parseEther } from 'viem';
import MarketFactoryABI from './abis/MarketFactory.json';
import VaultABI from './abis/Vault.json';
import OrderBookABI from './abis/OrderBook.json';

// Read market metadata
const meta = await readContract({
  address: MARKET_FACTORY_ADDRESS,
  abi: MarketFactoryABI,
  functionName: 'marketMeta',
  args: [factoryMarketId],
});

// Approve Vault for USDT (one-time)
await writeContract({
  address: USDT_ADDRESS,
  abi: erc20ABI,
  functionName: 'approve',
  args: [VAULT_ADDRESS, parseEther('1000')],
});
```

### 使用 ethers.js (v6)

```typescript
import { Contract, parseEther } from 'ethers';

// Approve Vault for USDT (one-time)
const usdt = new Contract(USDT_ADDRESS, erc20ABI, signer);
await usdt.approve(VAULT_ADDRESS, parseEther('1000'));

const orderBook = new Contract(ORDERBOOK_ADDRESS, OrderBookABI, signer);
const tx = await orderBook.placeOrder(
  orderBookMarketId,
  0,   // Side.Bid
  1,   // OrderType.GoodTilCancel
  60,  // tick
  10   // lots
);
```

## Market ID 类型

Strike 使用两套不同的 market ID 系统。理解二者区别非常重要。

| ID | Source | Used By |
|----|--------|---------|
| `factoryMarketId` | `MarketFactory` 中的顺序计数器 | MarketFactory, PythResolver, Redemption, frontend |
| `orderBookMarketId` | `OrderBook` 中的顺序计数器 | OrderBook, BatchAuction, Vault, OutcomeToken |

映射关系存储在 `MarketFactory.marketMeta[factoryMarketId].orderBookMarketId`。

**使用规则：**

- **面向用户 / API：** 始终使用 `factoryMarketId`。该 ID 作为 resolution、redemption 与展示层的规范 market identifier。
- **交易操作：** `OrderBook.placeOrder` 和 `BatchAuction.clearBatch` 使用 `orderBookMarketId`。
- **Token IDs：** `OutcomeToken` 从 `orderBookMarketId` 派生 UP/DOWN token IDs（`marketId*2` = UP，`marketId*2+1` = DOWN）。

## 关键流程

### 1. Approve Vault 使用 USDT

```solidity
usdt.approve(address(vault), type(uint256).max);
```

一次性授权。下单时，Vault 会使用 `safeTransferFrom` 拉取 USDT。

### 2. 下单

```solidity
uint256 orderId = orderBook.placeOrder(
    orderBookMarketId,           // from marketMeta
    Side.Bid,                    // 0 = Bid (UP), 1 = Ask (DOWN)
    OrderType.GoodTilCancel,     // 0 = GoodTilBatch, 1 = GoodTilCancel
    60,                          // tick (1-99, price = tick/100)
    10                           // lots (each = $0.01)
);
```

抵押资产会自动锁定于 Vault 中：

- Bid：`lots * LOT_SIZE * tick / 100`
- Ask：`lots * LOT_SIZE * (100 - tick) / 100`

其中 `LOT_SIZE = 1e16 = $0.01`。

### 3. Batch Clearing（原子化结算）

```solidity
// Anyone can trigger (keepers do this automatically)
batchAuction.clearBatch(orderBookMarketId);
```

通过 segment tree 找出 clearing tick，记录 `BatchResult`，并于同一笔交易中**原子化结算所有订单**：

- 已成交抵押资产（按清算价格）进入市场 redemption pool
- 超额退款（订单 tick 与 clearing tick 之间的差额）返还给 owner
- 统一费用（20 bps）扣除并发送给 `protocolFeeCollector`
- 未成交抵押资产返还（GoodTilBatch）或滚入下一 batch（GoodTilCancel）
- Positions 入账：Bid 成交获得 UP positions，Ask 成交获得 DOWN positions

不需要单独的 claim step，结算会内联完成。

### 4. 结算后赎回

```solidity
redemption.redeem(factoryMarketId, tokenAmount);
```

销毁 `tokenAmount` 个获胜 outcome tokens，并从市场 redemption pool 支付 `tokenAmount * LOT_SIZE`（每 lot $0.01）USDT。

### 5. AI 结算市场与 Flap Token Pool 市场

AI-resolved markets 现在通过多个市场系列提供。公开创建者流程是 **Flap Token Pools**：创建者选择一个 BEP20 抵押 token，定义 2-8 个 outcomes，并存储链上 prompt。Strike 托管流程会在链上创建交易前上传经过 hash 校验的 metadata，以便 pool 可以在应用中展示。

对于公开 Flap Token Pool 流程：

- 创建者**不能**选择 AI model；
- Strike 覆盖 AI fee；
- 创建者提交配置的 `0.05 BNB` creator bond；
- prompt 应当是可通过 Ave 支持数据解析的 token-data question。

较旧的 `MarketFactory.createAIMarket(...)` orderbook 路径属于 admin/protocol integration surface，不是推荐的公开创建者流程。专用 Flap Token Pool SDK 发布前，公开集成应使用当前 app 流程与 indexer/API surfaces。

参见：

- [Flap Token Pools](getting-started/flap-token-pools.md)
- [AI Markets](protocol/ai-markets.md)
- [https://strike.fun/api-docs/](https://strike.fun/api-docs/)

## 抵押资产公式

所有数值均以 wei 计。`LOT_SIZE = 1e16`（$0.01）。

| Side | Collateral Required |
|------|---------------------|
| Bid (UP) | `lots * LOT_SIZE * tick / 100` |
| Ask (DOWN) | `lots * LOT_SIZE * (100 - tick) / 100` |

Tick 表示隐含概率（1-99%）。以 tick 60 提交 bid 表示“愿意为每 lot 的 UP exposure 支付 LOT_SIZE 的 60%”。

## 读取市场状态

```solidity
// Get full market metadata (factoryMarketId)
(bytes32 priceId, int64 strikePrice, uint256 expiryTime,
 address creator, MarketState state, bool outcomeYes, int64 settlementPrice,
 uint256 orderBookMarketId, bool useInternalPositions, bool isAIMarket) = factory.marketMeta(factoryMarketId);

// Get batch result (orderBookMarketId)
BatchResult memory result = batchAuction.getBatchResult(orderBookMarketId, batchId);
```

## 从 Pyth Hermes API 获取价格数据

PythResolver 需要 Pyth price update data。可从 Hermes REST API 获取：

```bash
# Get price update for BTC/USD
curl "https://hermes.pyth.network/v2/updates/price/latest?ids[]=0xe62df6c8b4a85fe1a67db44dc12de5db330f7ac66b72dc658afedf0f4a415b43"
```

TypeScript 示例：

```typescript
const HERMES_URL = 'https://hermes.pyth.network';

async function getPriceUpdate(priceId: string): Promise<string[]> {
  const resp = await fetch(
    `${HERMES_URL}/v2/updates/price/latest?ids[]=${priceId}`
  );
  const data = await resp.json();
  return data.binary.data.map((d: string) => '0x' + d);
}

// Use with PythResolver
const priceUpdateData = await getPriceUpdate(priceId);
const fee = await pythResolver.read.getPythUpdateFee([priceUpdateData]);

await pythResolver.write.resolveMarket(
  [factoryMarketId, priceUpdateData],
  { value: fee }
);
```

### 常见 Pyth Price Feed IDs

| Asset | Price Feed ID |
|-------|---------------|
| BTC/USD | `0xe62df6c8b4a85fe1a67db44dc12de5db330f7ac66b72dc658afedf0f4a415b43` |
| BNB/USD | `0x2f95862b045670cd22bee3114c39763a4a08beeb663b145d283c31d7d1101c4f` |

## Indexer REST API

Strike indexer 在 `/v1/` prefix 下提供 REST API（旧的无 prefix routes 会保留用于向后兼容）。

### 关键 Endpoints

| Endpoint | Description |
|----------|-------------|
| `GET /v1/markets` | 列出 markets（支持 `?status=active&limit=50&offset=0&since=`） |
| `GET /v1/orderbook/:market_id` | 聚合 bid/ask levels |
| `GET /v1/trades/:market_id` | 已清算 batches（默认过滤 empty batches） |
| `GET /v1/positions/:address` | 某个 wallet 的 open orders 与 filled positions |
| `GET /v1/stats` | 聚合协议统计（volume、active markets） |

所有 list endpoints 都返回分页响应：

```json
{
  "data": [...],
  "meta": { "total": 42, "limit": 50, "offset": 0 }
}
```

### WebSocket

实时订单簿更新与 batch clearing events 可通过 WebSocket 获取。详情见 [SDK Events](sdk/events.md) 页面或 strike-infra 文档。
