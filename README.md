<p align="center">
  <img src="assets/strike-logo-with-text.svg" alt="Strike Logo" width="200" />
</p>

<h1 align="center">Strike — Price Prediction Markets</h1>

<p align="center">
  Fully on-chain binary prediction market CLOB on BNB Chain with frequency batch auctions and Pyth oracle settlement.
</p>

[![Built for BNB Chain](https://img.shields.io/badge/Built%20for-BNB%20Chain-F0B90B?style=flat-square)](https://www.bnbchain.org/)
[![Powered by Pyth](https://img.shields.io/badge/Powered%20by-Pyth%20Network-6B48FF?style=flat-square)](https://pyth.network/)
[![License: BUSL-1.1](https://img.shields.io/badge/License-BUSL--1.1-blue?style=flat-square)](LICENSE)

**Website:** [strike.pm](https://strike.pm) · **App:** [app.strike.pm](https://app.strike.pm) · **Docs:** [docs.strike.pm](https://docs.strike.pm)

---

## What is Strike?

Strike is an on-chain orderbook for binary price prediction markets. Traders buy YES or NO outcome tokens on whether an asset's price will be above a strike price at expiry. Markets clear via **frequency batch auctions (FBA)** — uniform clearing price, pro-rata fills, no front-running. Settlement is trustless via Pyth oracle.

### How It Works

1. **Markets** are created with a price feed, strike price, and expiry time
2. **Traders** place GTC (Good-Til-Cancel) or GTB (Good-Til-Batch) orders at a tick (1-99 cents)
3. **Batches clear** every 12 seconds — all orders in a batch get the same clearing price
4. **At expiry**, Pyth oracle determines the outcome — YES tokens pay $1, NO tokens pay $0 (or vice versa)
5. **Winners redeem** their outcome tokens for USDT

### Key Properties

- **1 YES + 1 NO = 1 USDT** — fully collateralized, no counterparty risk
- **Batch auctions** eliminate MEV and front-running
- **Direct-from-wallet trading** — no deposit/withdraw flow
- **Permissionless redemption** — winners claim anytime after resolution

## Architecture

### Smart Contracts (Solidity / Foundry)

| Contract | Purpose |
|----------|---------|
| `MarketFactory` | Creates and manages market lifecycle (Open → Closed → Resolved) |
| `OrderBook` | GTC/GTB order placement, cancellation, and fill tracking |
| `BatchAuction` | Frequency batch auction engine — clears batches with uniform price |
| `Vault` | USDT escrow — locks collateral on order placement, releases on cancel/fill |
| `OutcomeToken` | ERC20 YES/NO tokens minted at fill, burned at redemption |
| `Redemption` | Post-resolution token redemption (1 winning token → 1 USDT) |
| `FeeModel` | Configurable fee structure (currently uniform 20bps) |
| `PythResolver` | Trustless market resolution using Pyth price updates |

### Infrastructure ([strike-infra](https://github.com/ayazabbas/strike-infra))

All backend services are written in **Rust** (axum, sqlx, alloy-rs, tokio).

| Service | Purpose |
|---------|---------|
| **Indexer** | Indexes on-chain events into PostgreSQL |
| **API** | REST API for markets, orderbook, positions, referrals |
| **Unified Keeper** | Single binary running 4 tasks: batch clearing (3s), market creation (scheduled), resolution (5s), pruning (10s) |
| **Market Maker** | Automated liquidity provision with inventory-aware quoting |

### Frontend ([strike-frontend](https://github.com/ayazabbas/strike-frontend))

Next.js + shadcn/ui + wagmi/viem. SIWE authentication, RainbowKit wallet connection.

### SDK

The **[Strike SDK](https://docs.strike.pm/sdk/overview)** (`strike-sdk` on [crates.io](https://crates.io/crates/strike-sdk)) lets you build trading bots and integrations in Rust. On-chain first — all live data comes directly from BSC via RPC/WSS.

```rust
use strike_sdk::prelude::*;

let client = StrikeClient::new(StrikeConfig::bsc_testnet())
    .with_private_key("0x...")
    .build()?;

client.orders().place(market_id, &[
    OrderParam::bid(50, 1000),
    OrderParam::ask(60, 1000),
]).await?;
```

📖 [SDK Docs](https://docs.strike.pm/sdk/overview) · 📦 [crates.io](https://crates.io/crates/strike-sdk) · 📂 [`sdk/rust/`](sdk/rust/)

## Development

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (forge, cast, anvil)
- Rust 1.82+
- Node.js 22+
- PostgreSQL 15+

### Build Contracts

```bash
cd contracts
forge build
forge test
```

### Run Tests

```bash
# All 302 contract tests
forge test -vvv

# Specific test
forge test --match-test testClearBatch -vvv
```

## Contract Addresses

### BSC Mainnet (deployed block `95210316`)

| Contract | Address |
|----------|---------|
| MarketFactory | `0x34E0BCC1619dBc6A00A23b70BbaD9F36b0483d82` |
| OrderBook | `0x71F7Bc523FFF296A049a45D08cBD39D39d3C047B` |
| BatchAuction | `0x9d66fa0Aad92bb4428947443c1135C06a0cbFFBb` |
| Vault | `0x43D5caC88a87560Db8040Bef16F0ce8871B4F7ee` |
| OutcomeToken | `0xdAA6810Ca9614e2246d2849Be2a9c818707e404B` |
| Redemption | `0xcC1687A27133f06dB96aF4e00E5bA91411f9c999` |
| FeeModel | `0xFd7538Ad9EFEe4fCE07924F65a30688044e0800C` |
| PythResolver | `0x3E0864BbC19ca92777BB4c2e02490fC0C7A44C5a` |
| AIResolver | `0x3e0D91480147802D9C41068d91b7878E7943a632` |
| USDT | `0x55d398326f99059fF775485246999027B3197955` |

### BSC Testnet (deployed block `104337216`)

| Contract | Address |
|----------|---------|
| MarketFactory | `0xB4a9D6Dc1cAE195e276638ef9Cc20e797Cb3f839` |
| OrderBook | `0xF890b891F83f29Ce72BdD2720C1114ba16D5316c` |
| BatchAuction | `0x743e60a7AE108614dDCb5bBb4468c4187002969B` |
| Vault | `0xb7dE5e17633bd3E9F4DfeFdF2149F5725f9092Fe` |
| OutcomeToken | `0x612AAD13FB8Cc41D32933966FE88dac3277f6d2a` |
| Redemption | `0x28de9b7536ecfeE55De0f34E0875037E08E14F88` |
| FeeModel | `0x78F6102Ee4C13c0836c4E0CCfc501B74F83C01CD` |
| PythResolver | `0x2a7fba2365CCbd648e5c82E4846AD7D53fa47108` |
| AIResolver | `0xE1C9DA3d9b00582951f25D35234F8580DE1646d9` |
| MockUSDT | `0xb242dc031998b06772C63596Bfce091c80D4c3fA` |

For the full canonical registry, including oracle and provider addresses, see [`docs/contracts/deployments.md`](docs/contracts/deployments.md).

## History

The original prototype was built as a hackathon MVP using a parimutuel pool model with a Telegram bot interface. That code is preserved in the [`poc`](https://github.com/ayazabbas/strike/tree/poc) branch. The current version is a complete rewrite with a proper CLOB, batch auctions, and a web frontend.
