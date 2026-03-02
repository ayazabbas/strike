<p align="center">
  <img src="assets/strike-logo-with-text.svg" alt="Strike Logo" width="200" />
</p>

<h1 align="center">Strike — Price Prediction Markets</h1>

<p align="center">
  Frequency batch auction CLOB for binary price prediction markets on BNB Chain, resolved by Pyth oracle.
</p>

[![Built for BNB Chain](https://img.shields.io/badge/Built%20for-BNB%20Chain-F0B90B?style=flat-square)](https://www.bnbchain.org/)
[![Powered by Pyth](https://img.shields.io/badge/Powered%20by-Pyth%20Network-6B48FF?style=flat-square)](https://pyth.network/)

## What is Strike?

Strike is an on-chain orderbook for price prediction markets. Traders buy and sell binary outcome tokens — YES or NO on whether an asset's price will be above a strike price at expiry. Markets clear via **frequency batch auctions** every ~3 seconds, with a uniform clearing price and pro-rata fills. Settlement is fully trustless using Pyth oracle price feeds.

**Docs:** [docs site link TBD]

## PoC (v0 — Hackathon MVP)

The original proof-of-concept was built for the *Good Vibes Only: OpenClaw Edition* hackathon on BNB Chain. It used a parimutuel pool model (no orderbook) with a Telegram bot interface and Privy embedded wallets. Contracts: `Market.sol` (parimutuel pools, 51 tests) + `MarketFactory.sol` (EIP-1167 clones). The PoC is preserved in the `poc` branch.
