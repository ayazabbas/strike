# Roadmap

## ✅ Completed: PoC (v0)

Proof-of-concept built for the *Good Vibes Only: OpenClaw Edition* hackathon.

- Parimutuel pool model (no orderbook)
- `Market.sol` + `MarketFactory.sol` with 51 tests
- Telegram bot prototype
- Pyth oracle resolution
- Keeper service (auto-create + auto-resolve)

Preserved on the `poc` branch.

## Completed: CLOB (v1)

### Phase 1A — Core Primitives
- [x] OutcomeToken (ERC-1155)
- [x] Segment tree library
- [x] Collateral vault
- [x] Fee model (uniform 20 bps)
- [x] Unit tests (40+)

### Phase 1B — Orderbook & Batch Auction
- [x] Order types (GoodTilCancel, GoodTilBatch)
- [x] OrderBook contract
- [x] BatchAuction clearing engine
- [x] Atomic inline settlement (clearBatch settles all orders in one tx)
- [x] Integration tests (50+)

### Phase 1C — Market Lifecycle & Resolution
- [x] MarketFactory with full state machine
- [x] PythResolver with finality gate + challenge window
- [x] Outcome token redemption
- [x] Full protocol tests (40+)

### Phase 1D — Sell Orders & Batch Operations
- [x] SellYes / SellNo order sides (4-sided orderbook)
- [x] Token custody — OrderBook is ERC1155Holder
- [x] `burnEscrow()` with ESCROW_ROLE on OutcomeToken
- [x] `placeOrders()` — batch order placement with single vault deposit
- [x] `replaceOrders()` — atomic cancel+place with net settlement
- [x] `OrderParam` struct for batch operations

*292 tests passing across all contract modules.*

### Phase 2 — Keeper & Indexer Infrastructure
- [x] Batch clearing keeper
- [x] Market resolution keeper
- [x] Event indexer + REST API + WebSocket
- [x] Telegram bot integration

### Phase 3 — Web Frontend
- [x] Next.js 16 trading terminal
- [x] Real-time orderbook visualization
- [x] Order management + portfolio
- [x] Mobile optimization + PWA

### Phase 4 — Integration, Hardening & Deployment
- [ ] End-to-end integration tests
- [ ] Gas optimization pass
- [ ] Security hardening (Slither, Mythril)
- [ ] Private submission support (BEP-322)
- [x] BSC deployment + soak test
- [x] Documentation

## Live / Recently Shipped

- **[AI Markets](../protocol/ai-markets.md)** — Flap AI Oracle resolution is live for supported market types.
- **[Parimutuel Pool Markets](../protocol/parimutuel-markets.md)** — USDT/STRIKE multi-outcome pool markets are live.
- **[Flap Token Pools](../getting-started/flap-token-pools.md)** — public creator flow is live for BEP20-collateral, AI-resolved token pools.

## 🔮 Future

- AI quality gate for official Flap Token Pool creation prompts.
- Broader multi-asset and Pyth-feed coverage where liquidity supports it.
- Variable market durations (1min, 5min, 15min, 1hr).

### Recently Completed
- [x] BSC mainnet redeployment and production cutover (block 95210316, previous live deployment archived before reset)
- [x] Canonical BSC testnet stack with `amendOrders` live (block 103312703)
- [x] Leaderboard (PNL + Volume tabs, 24H/7D/30D/All, username system)

- [x] Native / Flap Token Pools mainnet stack deployed and public frontend enabled.
