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
# All 244 contract tests
forge test -vvv

# Specific test
forge test --match-test testClearBatch -vvv
```

## Contract Addresses (BSC Testnet — V4)

| Contract | Address |
|----------|---------|
| MarketFactory | `0x4460F2Bc7d4405fc3DBd9344F40D5A0f4a4dF4f0` |
| OrderBook | `0x31EFda3d089CB5150b6aee57adDA3a7Aa97151A3` |
| BatchAuction | `0xF22db29C2Fe828c5F31C6764d042b39419CBD3fd` |
| Vault | `0xe19bB1799ed8C369980cb346014c68f83df1C294` |
| OutcomeToken | `0x2C7E4d5b838D61141252b1c4c09618478C561f49` |
| Redemption | `0xdBd7dFFEbf8F7a2a3772832D03Ed0a87a57Fb776` |
| FeeModel | `0x958AA4E008765C1146b46701c5286eB5c57bd7E3` |
| PythResolver | `0x9ffc6b4A6D86034fDD9a3758bC25361BFC994972` |
| MockUSDT | `0x35c2731E24d88198cDc0128dD42fC2Ee969fB3fa` |

## History

The original v0 was built as a hackathon MVP using a parimutuel pool model with a Telegram bot interface. That code is preserved in the [`poc`](https://github.com/ayazabbas/strike/tree/poc) branch. V2 is a complete rewrite with a proper CLOB, batch auctions, and a web frontend.
