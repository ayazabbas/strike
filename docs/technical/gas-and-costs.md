# Gas & Costs

## Estimated Gas Per Operation

Based on EVM gas primitives and the FBA CLOB feasibility report. **These are estimates — actual benchmarks will be measured on BSC testnet.**

| Operation | Gas (Low) | Gas (Typical) | Gas (High) |
|-----------|-----------|---------------|------------|
| Place order | 180k | 250k | 450k |
| Cancel order | 60k | 100k | 180k |
| Clear batch (atomic settle) | 1.0M | 2.0M | 4.0M |
| Pyth verify (1 feed) | 200k | 300k | 600k |
| Create market | ~440k | ~440k | ~440k |

## Dollar Costs (BSC)

At BNB ≈ $628, across different gas price scenarios:

| Action | @ 0.05 gwei | @ 0.2 gwei | @ 1.0 gwei |
|--------|-------------|------------|------------|
| Place order | $0.008 | $0.031 | $0.157 |
| Cancel order | $0.003 | $0.013 | $0.063 |
| Clear batch (atomic) | $0.063 | $0.251 | $1.257 |
| Resolve market | $0.009 | $0.038 | $0.189 |

BSC's 2026 gas price (~0.05 gwei) makes all operations sub-cent for users and sub-5-cents for keepers.

## Cost Drivers

### Storage Writes
- `SSTORE_SET` (0→nonzero): 20,000 gas — placing a new order
- `SSTORE_RESET` (nonzero→nonzero): 5,000 gas — updating existing values
- Segment tree updates: ~7 levels × 5,000 gas = ~35,000 gas per update

### Pyth Verification
- Wormhole attestation verification scales linearly with guardian count
- Calldata for signed update payloads: 16 gas per nonzero byte (EIP-2028)
- Single biggest gas component in `resolveMarket()`

### Batch Clearing (Atomic Settlement)
- Segment tree traversal: O(log 99) ≈ 7 iterations
- Result storage: one struct write
- Per-order settlement: unlock, transfer fees, mint tokens, refund excess
- Scales linearly with order count, bounded by MAX_ORDERS_PER_BATCH (400)

## Optimization Targets

| Metric | Target | Rationale |
|--------|--------|-----------|
| Place order | < 250k | Stay within report's typical estimate |
| Clear batch | < 4.0M | Ensure keeper costs remain viable (includes atomic settlement) |

Optimization pass in Phase 4 will benchmark real gas usage and adjust struct packing, storage layout, and tree implementation if needed.
