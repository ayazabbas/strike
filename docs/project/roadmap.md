# Roadmap

## ✅ Completed: PoC (v0)

Proof-of-concept built for the *Good Vibes Only: OpenClaw Edition* hackathon.

- Parimutuel pool model (no orderbook)
- `Market.sol` + `MarketFactory.sol` with 51 tests
- Telegram bot with Privy embedded wallets
- Pyth oracle resolution
- BSC testnet deployment
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
- [x] BSC testnet deployment + soak test
- [x] Documentation

## 🔮 Future

- **[AI-Resolved Markets](../coming-soon/ai-resolved-markets.md)** — qualitative event markets (geopolitics, sports, culture) resolved via Flap AI Oracle
- Multi-asset support (ETH, SOL, BNB + any Pyth feed)
- Variable market durations (1min, 5min, 15min, 1hr)
- BSC mainnet deployment
- API for programmatic trading
- Leaderboards
