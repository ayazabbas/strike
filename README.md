<p align="center">
  <img src="assets/strike-logo-with-text.svg" alt="Strike Logo" width="200" />
</p>

<h1 align="center">Strike — Onchain Prediction Markets</h1>

<p align="center">
  Fully onchain prediction markets on BNB Chain: FBA orderbooks for active binary trading and parimutuel pools for multi-outcome markets.
</p>

[![Built for BNB Chain](https://img.shields.io/badge/Built%20for-BNB%20Chain-F0B90B?style=flat-square)](https://www.bnbchain.org/)
[![Powered by Pyth](https://img.shields.io/badge/Powered%20by-Pyth%20Network-6B48FF?style=flat-square)](https://pyth.network/)
[![License: BUSL-1.1](https://img.shields.io/badge/License-BUSL--1.1-blue?style=flat-square)](LICENSE)

**Website:** [strike.pm](https://strike.pm) · **App:** [app.strike.pm](https://app.strike.pm) · **Docs:** [docs.strike.fun](https://docs.strike.fun)

---

## Agent Quick Context

This repo is the canonical source for Strike protocol contracts, docs, and the Rust SDK.

If you are a coding agent, start here:

1. **Read this README first.** It gives the product model, repo map, and safe commands.
2. **Read `docs/contracts/deployments.md` before touching addresses.** Local or chat context can be stale.
3. **For deployed mainnet/testnet changes, update all dependent repos** (`strike-infra`, `strike-frontend`, and sometimes `strike-mm`).
4. **Never commit private keys, `.env` secrets, or broadcast files containing secrets.** Foundry broadcast metadata is okay only after inspection.
5. **Prefer targeted tests first, then broader tests.** Parimutuel changes should run `forge test --match-path 'test/Parimutuel*.t.sol'` at minimum.

### High-signal files

| Area | Files |
|------|-------|
| CLOB contracts | `contracts/src/MarketFactory.sol`, `OrderBook.sol`, `BatchAuction.sol`, `Vault.sol`, `PythResolver.sol`, `AIResolver.sol`, `Redemption.sol` |
| Parimutuel contracts | `contracts/src/ParimutuelFactory.sol`, `ParimutuelPoolManager.sol`, `ParimutuelVault.sol`, `ParimutuelRedemption.sol`, `ParimutuelAIResolver.sol`, `ParimutuelPythResolver.sol`, `ParimutuelPricingLib.sol` |
| Shared types | `contracts/src/ITypes.sol`, `contracts/src/ParimutuelTypes.sol` |
| Deploy scripts | `contracts/script/DeployMainnet.s.sol`, `DeployTestnet.s.sol`, `DeployParimutuel.s.sol` |
| Contract tests | `contracts/test/*.t.sol` |
| Rust SDK | `sdk/rust/` |
| Public docs source | `docs/` |

---

## What is Strike?

Strike is an onchain prediction market protocol on BNB Chain with two first-class market engines.

### 1. FBA Orderbook Markets

Orderbook markets are binary markets for active trading. Traders buy or sell YES/NO style exposure through a fully onchain CLOB. Orders are not matched continuously; they clear through **Frequent Batch Auctions (FBA)** at a uniform clearing price with pro-rata fills on the oversubscribed side. This reduces speed races and MEV compared with continuous first-in-first-out matching.

Typical use cases:

- BTC/ETH/SOL 5-minute price markets
- binary AI markets such as “Will X happen by time T?”
- markets where active quoting, limit orders, and exits before expiry matter

### 2. Parimutuel Pool Markets

Parimutuel markets are pool-based markets with 2–8 outcomes. Users buy into an outcome pool directly. There is no orderbook and no sell/cashout in the current product model. Winners receive their winning principal back plus a pro-rata share of losing pools; invalid markets refund principal.

Parimutuel V2 has two separate timestamps:

- `tradingCloseTime` — when buying stops
- `resolutionTime` — when the outcome is evaluated by admin, AI, or Pyth

This supports markets where betting should close before the event result is known.

---

## System Architecture

```text
Orderbook traders ──→ OrderBook ──→ BatchAuction ──→ internal positions
                         │                 │
                         ▼                 ▼
                    Vault (USDT)      MarketFactory
                         │                 │
                         └──── Redemption ◄┘
                                  ▲
                         PythResolver / AIResolver

Pool traders ─────→ ParimutuelPoolManager ──→ ParimutuelVault
                         │
                         ▼
                  ParimutuelFactory ──→ ParimutuelRedemption
                         ▲
          ParimutuelAIResolver / ParimutuelPythResolver / admin
```

Related repos:

| Repo | Purpose |
|------|---------|
| [`strike-infra`](https://github.com/ayazabbas/strike-infra) | Rust indexer, API, keeper, migrations, production Ansible |
| [`strike-frontend`](https://github.com/ayazabbas/strike-frontend) | Main trading app at `app.strike.pm` |
| [`strike-mm`](https://github.com/ayazabbas/strike-mm) | Strike ↔ Polymarket market-making / hedging bot |
| [`strike-website`](https://github.com/ayazabbas/strike-website) | Marketing site at `strike.pm` |

---

## Contract Map

### Orderbook stack

| Contract | Purpose |
|----------|---------|
| `MarketFactory` | Creates markets, stores metadata, controls market lifecycle |
| `OrderBook` | Places/cancels/amends GTC/GTB orders and tracks active/resting liquidity |
| `BatchAuction` | Finds uniform clearing price and settles fills atomically |
| `Vault` | USDT escrow, locks/free balance accounting |
| `Redemption` | Redeems winning internal positions after resolution |
| `PythResolver` | Resolves price markets using Pyth Core on BSC |
| `AIResolver` | Resolves binary AI markets through the Flap AI provider |
| `FeeModel` | Protocol fee calculation |
| `OutcomeToken` | ERC-1155 support retained for compatibility/future use; current short markets use internal positions |

### Parimutuel stack

| Contract | Purpose |
|----------|---------|
| `ParimutuelFactory` | Creates pool markets and coordinates resolution lifecycle |
| `ParimutuelPoolManager` | Handles buys, pool accounting, probability/payout curve |
| `ParimutuelVault` | USDT escrow for pool markets |
| `ParimutuelRedemption` | Winner claims and invalid-market refunds |
| `ParimutuelAIResolver` | Flap AI resolution path and challenge/finality flow |
| `ParimutuelPythResolver` | Pyth threshold/bucket resolution path |
| `ParimutuelPricingLib` | Pool curve math |

---

## Important Protocol Conventions

- Solidity compiler: `0.8.25`, Foundry, `via_ir = true`.
- Chain: BNB Chain mainnet/testnet.
- Oracle: **Pyth Core on BSC**, not Pyth Lazer.
- Collateral: USDT / MockUSDT.
- Orderbook side enum: `Bid = 0`, `Ask = 1`, `SellYes = 2`, `SellNo = 3`.
- Orderbook tick range: 1–99 cents.
- `LOT_SIZE = 1e16`, so one lot is $0.01 collateral.
- Mainnet minimum order size is 100 lots.
- Orderbook market states: `Open = 0`, `Closed = 1`, `Resolving = 2`, `Resolved = 3`, `Cancelled = 4`.
- Parimutuel `close_time` in APIs may be a compatibility alias; new code should prefer `trading_close_time` and `resolution_time`.

---

## Development

### Prerequisites

- Foundry (`forge`, `cast`, `anvil`)
- Node.js 22+
- Rust 1.82+
- PostgreSQL 15+ when working with infra locally

### Install contract dependencies

```bash
cd contracts
npm install
forge install
```

### Build and test contracts

```bash
cd contracts
forge build
forge test

# Parimutuel-focused gate
forge test --match-path 'test/Parimutuel*.t.sol'

# Useful narrow examples
forge test --match-contract OrderBookAmend -vvv
forge test --match-contract PoolSolvency -vvv
```

### SDK

```bash
cd sdk/rust
cargo check
cargo test
```

### Docs

Docs source lives under `docs/`. Keep docs aligned with deployed behavior and ABI reality.

```bash
# lightweight markdown sanity
find docs -name '*.md' -maxdepth 3 -print
```

---

## Deployment / Address Updates

Canonical deployed addresses are documented in `docs/contracts/deployments.md`. When contracts are redeployed:

1. Update this repo's docs and generated ABI artifacts.
2. Copy generated ABIs into `strike-infra/crates/strike-common/abi/`.
3. Update `strike-infra` Ansible vars/templates and indexer start block.
4. Update `strike-frontend/src/lib/contracts.ts`.
5. Update `strike-mm` config if orderbook/vault/factory addresses changed.
6. Commit and push all touched repos before production deploy.

Production deploys are not done from this repo directly. Use `strike-infra/ansible`.

---

## Safety Notes for Agents

- Do not change production/mainnet addresses casually.
- Do not run broadcast scripts on mainnet unless explicitly asked.
- Do not assume testnet and mainnet ABIs are identical; verify deployed contract truth.
- For BSC testnet broadcasts, `--with-gas-price 2000000000 --slow` has worked better than `--gas-price` in prior deploys.
- If a change touches deployed event shapes, update indexer decoding, DB migrations, API responses, frontend hooks, and docs together.
- If a change touches order settlement or vault accounting, add or update solvency/invariant tests.

---

## Useful Links

- App: <https://app.strike.pm>
- Website: <https://strike.pm>
- Docs: <https://docs.strike.fun>
- BNB Chain: <https://www.bnbchain.org/>
- Pyth: <https://pyth.network/>
