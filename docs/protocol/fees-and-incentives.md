# Fees & Incentives

## Trading Fees

Strike uses a **maker/taker fee model**:

| Role | Fee | Rationale |
|------|-----|-----------|
| **Maker** | 0 bps (+ rebate) | Incentivize liquidity provision |
| **Taker** | 30 bps (configurable) | Revenue for protocol + maker rebates |

- **Maker** = order that rests on the book (adds liquidity)
- **Taker** = order that crosses the book (removes liquidity)
- Fees are deducted at **claim time**, not during batch clearing (keeps clearing gas-efficient)
- Maker rebates are funded from a portion of taker fees

## Protocol Revenue

A portion of taker fees goes to the protocol fee collector address. This funds development and operations.

## Resolver Bounty

Every market has a **resolver bounty** funded by the market creation bond (e.g., 0.005 BNB):

- Paid to whoever successfully calls `resolveMarket()` with valid Pyth data
- Incentivizes permissionless resolution — anyone can earn by resolving expired markets
- If the market auto-cancels (no resolution within 24h), the bond is returned to the market creator

## Pruner Bounty

Expired or stale orders consume storage. A small bounty incentivizes cleanup:

- Each order deposits a small **order bond** on placement
- Anyone can call `pruneExpiredOrders()` to remove expired orders
- The pruner receives the order bond as compensation
- This keeps the orderbook clean without relying on centralized maintenance

## Anti-Spam

| Mechanism | Purpose |
|-----------|---------|
| **Minimum lot size** | Prevents dust orders |
| **Order bond** | Economic cost to spamming orders (refunded on cancel/fill, paid to pruner on expiry) |
| **Per-tick order caps** | Bounds worst-case clearing gas cost |

## Market Creation Bond

Creating a market requires a bond that covers:
- Resolver bounty
- Gas cost buffer for keeper operations
- Returned (minus resolver bounty) when the market resolves or cancels

## Cost Estimates (BSC at 0.05 gwei)

| Action | Est. Gas | Est. Cost |
|--------|----------|-----------|
| Place order | ~250k | ~$0.008 |
| Cancel order | ~100k | ~$0.003 |
| Clear batch | ~1.5M | ~$0.047 |
| Claim fill | ~150k | ~$0.005 |
| Resolve market | ~300k | ~$0.009 |

*Based on BNB ≈ $628. Actual costs will be benchmarked on testnet.*
