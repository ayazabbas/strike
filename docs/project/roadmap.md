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

## 🔨 In Progress: CLOB (v1)

### Phase 1A — Core Primitives
- [ ] OutcomeToken (ERC-1155)
- [ ] Segment tree library
- [ ] Collateral vault
- [ ] Fee model (maker/taker + bounties)
- [ ] Unit tests (40+)

### Phase 1B — Orderbook & Batch Auction
- [x] Order types (GoodTilCancel, GoodTilBatch)
- [ ] OrderBook contract
- [ ] BatchAuction clearing engine
- [ ] Claim-based settlement
- [ ] Order expiry & pruning
- [ ] Integration tests (50+)

### Phase 1C — Market Lifecycle & Resolution
- [ ] MarketFactory v2
- [ ] PythResolver with finality gate + challenge window
- [ ] Market state machine
- [ ] Outcome token redemption
- [ ] Full protocol tests (40+)

### Phase 2 — Keeper & Indexer Infrastructure
- [ ] Batch clearing keeper
- [ ] Market resolution keeper
- [ ] Order pruning keeper
- [ ] Event indexer + REST API + WebSocket
- [ ] Telegram bot integration

### Phase 3 — Web Frontend
- [ ] Next.js 15 trading terminal
- [ ] Real-time orderbook visualization
- [ ] Order management + portfolio
- [ ] Mobile optimization + PWA

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
