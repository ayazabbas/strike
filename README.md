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

## Contract Addresses (BSC Testnet)

| Contract | Address |
|----------|---------|
| MarketFactory | `0x6415619262033090EA0C2De913a3a6d9FC1d9DE9` |
| OrderBook | `0xB59e3d709Bd8Df10418D47E7d2CF045B02D06E32` |
| BatchAuction | `0x414D9da55d61835fD7Bb127978a2c49B8F09BdD5` |
| Vault | `0xc9aA051e0BB2E0Fbb8Bfe4e4BB9ffa5Bf690023b` |
| OutcomeToken | `0x427CFce18cC5278f2546F88ab02c6a0749228A45` |
| Redemption | `0x4b55f917Ab45028d4C75f3dA400B50D81209593b` |
| FeeModel | `0xa044FF6E4385c3d671E47aa9E31cb91a50a3F276` |
| PythResolver | `0xDcb807de5Ba5F3af04286a9dC1F6f3eb33066b92` |
| MockUSDT | `0xb242dc031998b06772C63596Bfce091c80D4c3fA` |

## History

The original prototype was built as a hackathon MVP using a parimutuel pool model with a Telegram bot interface. That code is preserved in the [`poc`](https://github.com/ayazabbas/strike/tree/poc) branch. The current version is a complete rewrite with a proper CLOB, batch auctions, and a web frontend.
