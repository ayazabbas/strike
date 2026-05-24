# 内部安全审计 - v1.2

**日期：** 2026-03-22
**审计方：** Internal Security Review
**范围：** `contracts/src/` 中的所有 Solidity 合约（10 个文件，约 2,780 行）
**框架：** Solidity ^0.8.25, Foundry
**链：** BNB Chain (BSC)
**测试套件：** 347 个 tests，全部通过

---

## 执行摘要

本报告覆盖 Strike 预测市场协议 v1.2 的完整代码库，且初始 v1.2 审计轮次中的所有修复均已应用（commit `9abf674`）。该协议实现了一个二元结果 CLOB，包含 Frequent Batch Auctions、ERC-20 抵押资产托管、ERC-1155 结果代币，以及 Pyth Core oracle 结算。

v1.2 引入了用户级活跃订单上限、基于价格接近度的 resting lists 与分页扫描、带预计算成交的分块结算，以及买卖双方 50/50 的费用拆分。v1.1 审计和初始 v1.2 审计轮次中的所有 findings 均已处理或正式确认。

**当前 findings：0 Critical，0 High，0 Medium，2 Low，2 Informational。**

**总体风险评估：LOW。** 代码库结构清晰，accounting invariants 正确，访问控制完整，测试覆盖充分。剩余 findings 均为低影响代码质量问题或已确认的架构决策。

---

## 范围

| Contract | File | Lines | Description |
|----------|------|------:|-------------|
| ITypes | `src/ITypes.sol` | 82 | 共享 types、enums、structs、`LOT_SIZE` 常量 |
| SegmentTree | `src/SegmentTree.sol` | 199 | 用于 99-tick orderbook 的 O(log N) segment tree library |
| OrderBook | `src/OrderBook.sol` | 761 | 下单、取消、resting list、segment trees |
| BatchAuction | `src/BatchAuction.sol` | 599 | Batch clearing、分块结算、预计算成交 |
| Vault | `src/Vault.sol` | 255 | USDT collateral escrow、lock/unlock、market pool、emergency withdrawal |
| MarketFactory | `src/MarketFactory.sol` | 308 | 市场生命周期、permissioned creation、状态转换 |
| FeeModel | `src/FeeModel.sol` | 85 | 统一费用计算，买卖 50/50 拆分 |
| OutcomeToken | `src/OutcomeToken.sol` | 139 | ERC-1155 YES/NO tokens、escrow burn |
| PythResolver | `src/PythResolver.sol` | 269 | 带 finality gate 的 Pyth Core oracle 结算 |
| Redemption | `src/Redemption.sol` | 82 | 结算后的 token redemption |
| **Total** | | **~2,780** | |

---

## 架构概览

### 协议说明

Strike 是完全链上的二元结果预测市场。交易者以 1-99 的 price ticks（每个 tick = 1% 概率）买入或卖出 YES/NO outcome tokens。订单进入 Frequent Batch Auctions，并通过 segment tree 聚合计算统一清算价格。所有成交都按 clearing tick 结算，而不是按 limit tick 结算。抵押资产为 USDT（ERC-20），由 Vault 持有；结果代币为 ERC-1155 或 internal positions。

### 信任边界图

```
                           ┌──────────────┐
                           │   Users      │
                           └──────┬───────┘
                                  │ approve + placeOrder/cancel/redeem
                           ┌──────▼───────┐
                           │  OrderBook   │◄──── ERC1155Holder (sell order custody)
                           └──────┬───────┘
                      OPERATOR_ROLE│
                           ┌──────▼───────┐
                           │ BatchAuction │
                           └──┬────┬──┬───┘
              PROTOCOL_ROLE   │    │  │ MINTER_ROLE / ESCROW_ROLE
                ┌─────────────▼┐ ┌▼──▼──────────┐
                │    Vault     │ │ OutcomeToken  │
                └──────────────┘ └───────────────┘
                                        ▲
                           ┌────────────┘ MINTER_ROLE
                           │
                    ┌──────▼───────┐      ┌──────────────┐
                    │  Redemption  │      │ PythResolver │
                    └──────────────┘      └──────────────┘
                                                 │
                           ┌─────────────────────▼──┐
                           │    MarketFactory       │
                           └────────────────────────┘
```

### 访问控制摘要

| Role | Contract | Grantees |
|------|----------|----------|
| `OPERATOR_ROLE` | OrderBook | BatchAuction, MarketFactory |
| `PROTOCOL_ROLE` | Vault | OrderBook, BatchAuction, Redemption |
| `MINTER_ROLE` | OutcomeToken | BatchAuction, Redemption |
| `ESCROW_ROLE` | OutcomeToken | BatchAuction |
| `MARKET_CREATOR_ROLE` | MarketFactory | Authorized market creators |
| `ADMIN_ROLE` | MarketFactory | PythResolver, admin |
| `DEFAULT_ADMIN_ROLE` | All AccessControl contracts | Deployer/admin multisig |

所有受 role 保护的函数均已验证正确。未发现 privilege escalation paths。

---

## Findings

### Summary Table

| ID | Title | Severity | Status |
|----|-------|----------|--------|
| L-01 | Batch operations 中对 `params.length` 的 `uint16` cast | Low | Open |
| L-02 | `clearBatch` 未强制执行最小 batch interval | Low | Acknowledged |
| I-01 | Non-internal markets 上的 ERC-1155 callback reentrancy surface | Informational | Acknowledged |
| I-02 | Sell fee 的双 `redeemFromPool` 模式不够直观 | Informational | Documented |

### Detailed Findings

---

#### L-01: Batch Operations 中对 `params.length` 的 `uint16` Cast

**Severity:** Low
**Contract:** OrderBook.sol
**Functions:** `placeOrders` (L366, L368), `replaceOrders` (L419, L420)

**Description:**

```solidity
require(activeOrderCount[msg.sender][marketId] + uint16(params.length) <= MAX_USER_ORDERS, ...);
activeOrderCount[msg.sender][marketId] += uint16(params.length);
```

`params.length` 是 `uint256`。`uint16()` cast 会静默截断大于 65535 的值。如果 `params.length == 65556`，cast 结果为 `20`，理论上可能绕过 `MAX_USER_ORDERS` 上限检查。

**Impact:** 实际上不可利用，65536 个 `OrderParam` calldata structs 会让 gas 远超区块 gas limit。该问题仅属于代码质量问题。

**Recommendation:**

于 cast 前增加显式长度检查：

```solidity
require(params.length <= MAX_USER_ORDERS, "OrderBook: batch too large");
```

---

#### L-02: `clearBatch` 未强制执行最小 Batch Interval

**Severity:** Low
**Contract:** BatchAuction.sol
**Function:** `clearBatch` (L98)

**Description:**

`batchInterval` 存储在 `Market` 中，但 `clearBatch` 未强制检查该间隔。任何地址都可以在任意时间调用 `clearBatch`，从而产生 MEV sandwich 攻击面：攻击者可以 front-run `clearBatch`，提交订单，将单个用户隔离在几乎为空的 batch 中，并以该用户的 limit price 撮合，而不是以公平的清算价格撮合。

NatSpec（L87-96）中已将此记录为 latency 与 MEV resistance 之间的设计取舍。

**Impact:** 该问题带来 MEV 抽取面。价格接近度过滤会缓解该问题，因为远离当前价格的订单会进入 resting list，使攻击者更难于极端 tick 隔离用户。

**Recommendation:** 强制执行 `block.timestamp >= lastClearTimestamp + batchInterval`，或于 mainnet 部署中将 `clearBatch` 限制给 permissioned keeper。

---

#### I-01: Non-Internal Markets 上的 ERC-1155 Callback Reentrancy Surface

**Severity:** Informational
**Contract:** BatchAuction.sol, OrderBook.sol

**Description:**

使用 `useInternalPositions = false` 的 markets 会通过 `safeTransferFrom` 转移 ERC-1155 tokens，这会于接收方上调用 `onERC1155Received`。恶意接收方可以于 callback 中 revert，从而阻塞整个 batch 的 settlement。`ReentrancyGuard` 可以防止状态破坏，但不能防止 callback revert。

**Impact:** 只会对受影响 markets 的 batch settlement 造成 DoS。Markets 默认使用 `useInternalPositions = true`（通过 `createMarketWithPositions` 创建），完全避免 ERC-1155 transfers。

**Recommendation:** 生产环境只使用 `useInternalPositions = true` markets。如果确实需要 ERC-1155 markets，应实现 pull-based claim pattern，或使用 `settlementActive` lock 跳过会 revert 的订单。

---

#### I-02: Sell Fee 的双 `redeemFromPool` 模式不够直观

**Severity:** Informational
**Contract:** BatchAuction.sol
**Function:** `_settleSellOrder` (L540-L546)

**Description:**

Sell-side settlement 会调用两次 `vault.redeemFromPool`，一次支付 seller payout，一次将 sell fee 支付给 protocol collector：

```solidity
vault.redeemFromPool(o.marketId, o.owner, payout);                          // grossPayout - sellFee
vault.redeemFromPool(o.marketId, feeModel.protocolFeeCollector(), sellFee); // sellFee
```

总提款额 = `payout + sellFee = grossPayout = filledCollateral`（即 buy side 存入的金额）。Pool 的净变化为 0。Accounting 是正确的，但这种双调用模式需要仔细阅读才能验证 solvency。

**Recommendation:** 增加注释块，记录 Bid+SellYes 与 Ask+SellNo match types 的 pool flow。

---

## 之前的审计 Findings

v1.1 审计和初始 v1.2 审计轮次（修复前）中的所有 findings 如下。

### v1.1 Audit Findings

| ID | Title | Severity | Status | Resolution |
|----|-------|----------|--------|------------|
| v1.1-H-01 | Cross-contract ERC-1155 reentrancy DoS | High | Mitigated | 默认 `useInternalPositions = true` 避免 ERC-1155 transfers。见 I-01。 |
| v1.1-M-01 | PythResolver `conf == 0` bypass | Medium | Acknowledged | 按设计处理，`conf == 0` 表示未发布 confidence data，因此跳过检查。 |
| v1.1-M-02 | Redemption `uint128` truncation | Medium | Acknowledged | `lots` 字段为 `uint64`，`uint128` cast 对所有现实值安全。 |
| v1.1-M-03 | Chunked settlement re-computes fills (rounding drift) | Medium | **Fixed** | 第一 chunk 中将预计算成交存入 `_precomputedFills` mapping，后续 chunks 复用。 |
| v1.1-L-01 | Unbounded GTC rollover | Low | **Fixed** | 远离价格的 GTC orders 通过 `_tryRollOrCancel` 停放至 resting list。`MAX_ORDERS_PER_BATCH` 提高到 1600。 |
| v1.1-L-02 | Sell orders pay zero fees | Low | **Fixed** | 50/50 费用拆分：buy side 支付 `calculateOtherHalfFee`，sell side 从 payout 中扣除 `calculateHalfFee`。 |
| v1.1-L-03 | No batch interval enforcement | Low | Acknowledged | 已于 NatSpec 中记录。见 L-02。 |

### Initial v1.2 Audit Findings（修复前）

| ID | Title | Severity | Status | Resolution |
|----|-------|----------|--------|------------|
| v1.2-M-01 | Resting list unbounded scan - gas griefing | Medium | **Fixed** | `pullRestingOrders` 现在通过 `restingScanIndex` + `MAX_RESTING_SCAN = 400` bound 进行分页扫描。多次 `clearBatch` 调用会处理完整 list。 |
| v1.2-M-02 | `_tryRollOrCancel` receives stale lots after partial fill | Medium | **Fixed** | `_settleBuyOrder` 和 `_settleSellOrder` 现在会在调用 `_tryRollOrCancel` 前构造 `remaining` OrderInfo，并设置 `remaining.lots = o.lots - filledLots`。 |
| v1.2-L-01 | Dead `_hasPrecomputed` mapping wastes gas | Low | **Fixed** | `_hasPrecomputed` mapping 已完全移除。只使用 `_precomputedFills`。 |
| v1.2-L-02 | `uint16` cast on `params.length` | Low | Open | 见上方 L-01。由于 gas limits 不可利用，但仍属于代码质量问题。 |
| v1.2-L-03 | `activeOrderCount` saturating decrement masks bugs | Low | **Fixed** | `decrementActiveOrderCount` 现在使用 `require(activeOrderCount[user][marketId] > 0, ...)`。用户可触发的取消路径（`_cancelCore`、`_cancelForReplace`）也使用 `require`。 |
| v1.2-I-01 | `_isTickFar` public with internal naming convention | Informational | **Fixed** | 已重命名为 `isTickFar`。Internal counterpart `isTickNear` 也采用正确命名约定。 |

---

## Invariant Analysis

### 1. `activeOrderCount` Conservation

每次下单都会递增计数器；每次最终移除（取消、完全成交、GTB 到期、GTB 零成交清理）都会递减计数器。GTC 部分成交不会递减（订单仍然活跃）。GTC 滚入 resting list 也不会递减（订单停放期间仍计入活跃订单）。

| Path | Increment | Decrement | Verified |
|------|-----------|-----------|----------|
| `placeOrder` | +1 | — | Yes |
| `placeOrders` | +`params.length` | — | Yes |
| `replaceOrders` | 取消后 +`params.length` | 每次 cancel 通过 `_cancelForReplace` -1 | Yes |
| `cancelOrder` / `cancelOrders` | — | 通过 `_cancelCore` -1 | Yes |
| `cancelExpiredOrder(s)` | — | 通过 `_cancelCore` -1 | Yes |
| Settlement: full fill | — | 通过 `decrementActiveOrderCount` -1 | Yes |
| Settlement: GTB non-participating | — | 通过 `decrementActiveOrderCount` -1 | Yes |
| Settlement: GTB zero-fill cleanup | — | 通过 `decrementActiveOrderCount` -1 | Yes |
| Settlement: GTC partial fill → roll | — | None（订单仍然活跃） | Correct |
| Settlement: GTC partial fill → resting | — | None（订单仍计数） | Correct |
| `pullRestingOrders` (cancelled entry) | — | None（lazy skip，取消时已递减） | Correct |

`decrementActiveOrderCount` 使用 `require(> 0)` 捕获 accounting bugs，而不是静默饱和。

### 2. Resting 与 Tree 的一致性

**Invariant:** 如果 `isResting[orderId] == true`，该订单的 volume 不位于 segment tree 中。

| Entry Point | Tree Updated? | `isResting` Set? | Consistent |
|-------------|---------------|------------------|------------|
| `placeOrder` / `_placeOne` → far | 不加入 tree | `true` | Yes |
| `placeOrder` / `_placeOne` → near | 加入 tree | `false` | Yes |
| `pullRestingOrders` → near | 加入 tree | 设置为 `false` | Yes |
| `_tryRollOrCancel` → far | 从 tree 移除 | `true`（通过 `pushRestingOrderId`） | Yes |
| `_tryRollOrCancel` → near | 不移除 | `false`（仍位于 tree 中） | Yes |
| `_cancelCore` → resting order | 不更新 tree | 设置为 `false` | Yes |
| `_cancelCore` → active order | 从 tree 移除 | N/A | Yes |
| `_cancelForReplace` → resting order | 不更新 tree | 设置为 `false` | Yes |
| `_cancelForReplace` → active order | 从 tree 移除 | N/A | Yes |

### 3. Fee Split 下的 Pool Solvency

对于所有 match types，pool inflows 与 outflows 都正确平衡：

**Bid + Ask match at clearing tick `t`:**

- Pool receives: `lots * t/100 * LOT_SIZE`（来自 Bid）+ `lots * (100-t)/100 * LOT_SIZE`（来自 Ask）= `lots * LOT_SIZE`
- 每组 lot-pair 都由 pool 中的 `LOT_SIZE` 支撑
- Fees: buy-side 从锁定的 excess 中向 fee collector 支付 `calculateOtherHalfFee`（不从 pool 中提取）
- Redemption: 获胜方每 lot 赎回 `LOT_SIZE`。Pool solvent。

**Bid + SellYes match at clearing tick `t`:**

- Pool receives from buyer: `filledCollateral = lots * t/100 * LOT_SIZE`（通过 `vault.settleFill`）
- Pool pays seller: `payout = grossPayout - sellFee`（通过 `vault.redeemFromPool`）
- Pool pays fee collector: `sellFee = calculateHalfFee(grossPayout)`（通过 `vault.redeemFromPool`）
- Total pool out: `payout + sellFee = grossPayout = filledCollateral`
- Net pool delta from this match: **0**
- 创建 seller tokens 的原始 Bid+Ask match 所提供的 backing 保持完整
- Seller 的 tokens 通过 `burnEscrow` 销毁，移除其 redemption claim
- Buyer 的新 YES tokens 由原始 pool deposit 支撑。Pool solvent。

**Ask + SellNo match:** 与 Bid + SellYes 对称。Pool solvent。

**Fee invariant:** 对所有 `x`，`calculateHalfFee(x) + calculateOtherHalfFee(x) == calculateFee(x)`。
已验证：`ceil(fullFee/2) + floor(fullFee/2) = fullFee`。

### 4. Token Conservation

- **Minting:** `mintSingle` 为每个成交 lot 创建一个 outcome token。仅可由 `MINTER_ROLE`（BatchAuction）调用。
- **Burning:** `burnEscrow` 于 sell-order tokens 成交时销毁它们。仅可由 `ESCROW_ROLE`（BatchAuction）调用。
- **Escrow:** OrderBook 通过 `ERC1155Holder` 持有 sell-order tokens。取消或未成交时返还，成交时销毁。
- **Redemption:** 按 1:1 销毁获胜 tokens，并从 pool 中赎回 `LOT_SIZE` USDT。
- **No double-processing:** `_settleOrder` 中的 `o.lots = 0` guard 防止重复结算。预计算成交防止跨 chunks 的 rounding drift。

---

## 测试覆盖

**17 个 test suites，共 347 个 tests，全部通过。**

**优势：**

- 专门的 `AuditFixes.t.sol`（836 行）覆盖所有 v1.2 features
- 用户级 cap：下单、取消、成交递减、GTB 零成交清理
- 费用拆分：相等费用、总额保持、rounding、fuzz solvency checks
- Multi-chunk settlement：3-chunk 场景、跨 chunks 部分成交、both-sides GTC
- Proximity filtering：far/near placement、pull-in、cancel resting、GTC roll-to-resting、lazy skip、paginated scan
- Batch operations：`placeOrders`、`replaceOrders` 与 proximity interactions
- Oracle resolution：Pyth integration、challenge mechanism、finality gate
- Emergency：timelock withdrawal、pool drain

**Coverage Gaps：**

| Gap | Risk | Recommendation |
|-----|------|----------------|
| Settlement 期间 malicious `IERC1155Receiver` callback | Low | 为 non-internal markets 增加 reverting/gas-griefing receiver 测试 |
| Resting list 中超过 `MAX_RESTING_PULL`（200+）entries | Low | 测试 paginated scan 能够通过多次 `clearBatch` 正确处理 |
| `replaceOrders` 混合取消 resting + active orders 并创建新订单 | Low | 测试混合 resting/active replace 下 `activeOrderCount` 的正确性 |
| `isTickFar` 在 `ref ± PROXIMITY_THRESHOLD` 边界处 | Low | 针对 threshold edges 增加 fuzz test boundary conditions |

---

## 结论

所有审计后修复应用完成后，Strike v1.2 代码库状态良好。初始 v1.2 审计轮次中的所有 Medium 与 Low findings 均已解决：

- **Paginated resting scan**（`restingScanIndex` + `MAX_RESTING_SCAN`）消除了无界 gas griefing 向量
- **Stale lots fix** 位于 `_tryRollOrCancel`，确保 GTC 部分成交会滚动正确的剩余数量
- **Dead code removal**（`_hasPrecomputed`）降低了分块结算中的 Gas 开销
- **Reverting `decrementActiveOrderCount`** 会捕获 accounting bugs，而不是静默吸收
- **`isTickFar` rename** 使命名约定与可见性一致

**主要优势：**

- 所有 match types（包括 Bid+SellYes）都保持 pool solvency，并通过 accounting traces 与 fuzz tests 验证
- Paginated resting list scanning 限制了每次 `clearBatch` 调用的 Gas 消耗
- 带预计算成交的分块结算支持任意规模的大型 batches
- 用户级订单上限（20）限制了 Sybil griefing surface
- 10 个聚焦合约之间职责分离清晰

**剩余风险（均为 low/acknowledged）：**

- ERC-1155 callback DoS 仅影响 non-internal markets（默认配置已缓解）
- `clearBatch` timing 带来 MEV exposure（通过 proximity filtering 缓解）
- `params.length` uint16 truncation（受 gas limits 限制不可利用）

**Mainnet Readiness:** 协议已准备好主网部署，并建议执行以下事项：

1. 所有 markets 默认使用 `useInternalPositions = true`（避免 ERC-1155 reentrancy surface）
2. 部署 permissioned keeper 执行 `clearBatch`，以降低 MEV exposure
3. 主网上线前增加显式的 `params.length <= MAX_USER_ORDERS` guard（小幅 hardening）
