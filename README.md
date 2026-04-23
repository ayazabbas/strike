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

### BSC Mainnet (deployed block `94290419`)

| Contract | Address |
|----------|---------|
| MarketFactory | `0xcbBC04B2a3EfE858c7C3d159c56f194AF2a7eBac` |
| OrderBook | `0x1E7C9b93D2C939a433D87b281918508Eec7c9171` |
| BatchAuction | `0xCdd122520E9efbdb5bd1Cc246aE497c37c70bdBE` |
| Vault | `0x2a6EA3F574264E6fA9c6F3c691dA01BE6DaC066f` |
| OutcomeToken | `0xdcA3d1Be0a181494F2bf46a5a885b2c2009574f3` |
| Redemption | `0x9a46D6c017eDdA49832cC9eE315246d0B55E5804` |
| FeeModel | `0x10d479354013c20eC777569618186D79eE818D8a` |
| PythResolver | `0x101383ef333d5Cb7Cb154EAbcA68961e3ac5B1a4` |
| AIResolver | `0xb0606b7984a2AA36774e8865E76689f98D39eE6e` |
| USDT | `0x55d398326f99059fF775485246999027B3197955` |

### BSC Testnet (deployed block `103312703`)

| Contract | Address |
|----------|---------|
| MarketFactory | `0xa1EA91E7D404C14439C84b4A95cF51127cE0338B` |
| OrderBook | `0x9CF4544389d235C64F1B42061f3126fF11a28734` |
| BatchAuction | `0x8e4885Cb6e0D228d9E4179C8Bd32A94f28A602df` |
| Vault | `0xEd56fF9A42F60235625Fa7DDA294AB70698DF25D` |
| OutcomeToken | `0x92dFA493eE92e492Df7EB2A43F87FBcb517313a9` |
| Redemption | `0x98723a449537AF17Fd7ddE29bd7De8f5a7A1B9B2` |
| FeeModel | `0x5b8fCB458485e5d63c243A1FA4CA45e4e984B1eE` |
| PythResolver | `0x9ddadD15f27f4c7523268CFFeb1A1b04FEEA32b9` |
| AIResolver | `0xe2aAec0A169D39FB12b43edacB942190b152439b` |
| MockUSDT | `0xb242dc031998b06772C63596Bfce091c80D4c3fA` |

For the full canonical registry, including oracle and provider addresses, see [`docs/contracts/deployments.md`](docs/contracts/deployments.md).

## History

The original prototype was built as a hackathon MVP using a parimutuel pool model with a Telegram bot interface. That code is preserved in the [`poc`](https://github.com/ayazabbas/strike/tree/poc) branch. The current version is a complete rewrite with a proper CLOB, batch auctions, and a web frontend.
