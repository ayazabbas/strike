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
- [x] Fee model (maker/taker)
- [x] Unit tests (40+)

### Phase 1B — Orderbook & Batch Auction
- [x] Order types (GoodTilCancel, GoodTilBatch)
- [x] OrderBook contract
- [x] BatchAuction clearing engine
- [x] Claim-based settlement
- [x] Order expiry & pruning
- [x] Integration tests (50+)

### Phase 1C — Market Lifecycle & Resolution
- [x] MarketFactory v2
- [x] PythResolver with finality gate + challenge window
- [x] Market state machine
- [x] Outcome token redemption
- [x] Full protocol tests (40+)

*309 tests passing across all contract modules.*

### Phase 2 — Keeper & Indexer Infrastructure
- [x] Batch clearing keeper
- [x] Market resolution keeper
- [x] Order pruning keeper
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
- [ ] BSC testnet deployment + soak test
- [ ] Documentation + demo

## 🔮 Future

- Multi-asset support (ETH, SOL, BNB + any Pyth feed)
- Variable market durations (1min, 5min, 15min, 1hr)
- BSC mainnet deployment
- API for programmatic trading
- Leaderboards
