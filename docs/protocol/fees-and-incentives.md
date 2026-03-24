# Fees & Incentives

## Trading Fees

Strike uses a **uniform fee model** with a **50/50 buyer–seller split**:

| Parameter | Rate | Description |
|-----------|------|-------------|
| **Total fee** | 20 bps (0.20%) | Split equally between buyer and seller |
| **Buy-side fee** | `floor(fee / 2)` | Deducted from buyer's filled collateral at settlement |
| **Sell-side fee** | `ceil(fee / 2)` | Deducted from seller's USDT payout at settlement |

- No maker/taker distinction — both sides pay half the fee
- The extra wei from integer rounding goes to the protocol (sell side pays `ceil`)
- Fees are deducted during atomic batch settlement (inline with clearing)
- All fees go to the `protocolFeeCollector` address
- `clearingBountyBps` exists (admin-configurable) but is currently set to 0

## Protocol Revenue

All trading fees flow to the protocol fee collector address. This funds development and operations.

## Resolver Bounty

Markets can be resolved permissionlessly by anyone with valid Pyth data. The resolver bounty mechanism is configurable via FeeModel but currently set to 0.

## Anti-Spam / DoS Prevention

| Mechanism | Purpose |
|-----------|---------|
| **Minimum lot size** | Prevents dust orders (MIN_LOTS = 1, i.e. $0.01) |
| **Full collateral locking** | Economic cost to placing orders (USDT locked until fill or cancel) |
| **ERC-20 approval required** | Users must approve Vault before placing orders |
| **Per-user active order cap** | MAX_USER_ORDERS = 20 per market — prevents a single address from flooding the book |

The per-user order cap is tracked via an `activeOrderCount` mapping and enforced on `placeOrder`, `placeOrders`, and `replaceOrders`. Orders freed by cancellation or settlement decrement the counter.

## Cost Estimates (BSC at 0.05 gwei)

| Action | Est. Gas | Est. Cost |
|--------|----------|-----------|
| Approve Vault (once) | ~46k | ~$0.001 |
| Place order | ~250k | ~$0.008 |
| Cancel order | ~100k | ~$0.003 |
| Clear batch (atomic) | ~2.0M | ~$0.063 |
| Resolve market | ~300k | ~$0.009 |

*Based on BNB ≈ $628. Settlement is included in clearBatch — no separate claim transaction needed.*
