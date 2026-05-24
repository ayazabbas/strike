# Gas 与成本

## 单项操作的估算 Gas

基于 EVM gas primitives 与 FBA CLOB feasibility report。**这些是估算值，实际 benchmarks 会于 BSC 主网上测量。**

| Operation | Gas (Low) | Gas (Typical) | Gas (High) |
|-----------|-----------|---------------|------------|
| Place order | 180k | 250k | 450k |
| Cancel order | 60k | 100k | 180k |
| Clear batch (atomic settle) | 1.0M | 2.0M | 4.0M |
| Pyth verify (1 feed) | 200k | 300k | 600k |
| Create market | ~440k | ~440k | ~440k |

## 美元成本 (BSC)

按 BNB ≈ $628 计算，不同 gas price 场景下：

| Action | @ 0.05 gwei | @ 0.2 gwei | @ 1.0 gwei |
|--------|-------------|------------|------------|
| Place order | $0.008 | $0.031 | $0.157 |
| Cancel order | $0.003 | $0.013 | $0.063 |
| Clear batch (atomic) | $0.063 | $0.251 | $1.257 |
| Resolve market | $0.009 | $0.038 | $0.189 |

BSC 2026 年的 gas price（约 0.05 gwei）让用户的所有操作成本低于 1 美分，也让 keeper 操作成本低于 5 美分。

## 成本驱动因素

### Storage Writes

- `SSTORE_SET`（0→nonzero）：20,000 gas，用于创建新订单
- `SSTORE_RESET`（nonzero→nonzero）：5,000 gas，用于更新已有值
- Segment tree updates：约 7 层 × 5,000 gas = 每次 update 约 35,000 gas

### Pyth Verification

- Wormhole attestation verification 的成本随 guardian count 线性增长
- Signed update payloads 的 calldata：每个非零字节 16 gas（EIP-2028）
- `resolveMarket()` 中最大的单项 Gas 组成部分

### Batch Clearing（原子化结算）

- Segment tree traversal：O(log 99) ≈ 7 次迭代
- Result storage：写入一个 struct
- Per-order settlement：unlock、transfer fees、mint tokens、refund excess
- 随订单数量线性增长，并受 MAX_ORDERS_PER_BATCH (1600) 限制
- 结算通过每次 `clearBatch` 调用 SETTLE_CHUNK_SIZE = 400 分块执行

## 优化目标

| Metric | Target | Rationale |
|--------|--------|-----------|
| Place order | < 250k | 保持在报告的 typical estimate 以内 |
| Clear batch | < 4.0M | 确保 keeper 成本仍然可行（包括原子化结算） |

Phase 4 的 optimization pass 会 benchmark 真实 Gas 用量，并根据需要调整 struct packing、storage layout 与 tree implementation。
