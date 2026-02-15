# What is Strike?

**Strike** is a parimutuel prediction market on BNB Chain. Bet UP or DOWN on BTC price movements in 5-minute rounds. Fully onchain resolution via Pyth oracle price feeds. Telegram bot interface with embedded wallets.

## The Idea

Every 5 minutes, a new market opens with a simple question:

> **Will BTC be above or below the current price in 5 minutes?**

Players bet UP ⬆️ or DOWN ⬇️ by staking tBNB. When the market expires, the Pyth oracle provides the resolution price. Winners split the entire pool proportionally.

No house edge. No counterparty. Just a pool of players betting against each other, resolved trustlessly by an oracle.

## Why Strike?

- **Simple** — Binary UP/DOWN. No complex options, no spreads, no order books.
- **Fast** — 5-minute rounds. Know your result quickly.
- **Fair** — Parimutuel model means the market sets the odds, not the house.
- **Trustless** — Pyth oracle resolves every market. No human intervention.
- **Accessible** — Works inside Telegram. No wallet extensions, no websites.

## Tech Stack

| Component | Technology |
|-----------|-----------|
| Smart Contracts | Solidity 0.8.25, Foundry, OpenZeppelin v5 |
| Blockchain | BNB Chain (BSC Testnet) |
| Oracle | Pyth Network |
| Bot | grammY (TypeScript) |
| Wallets | Privy Server Wallets |
| Database | SQLite |
| Proxy Pattern | EIP-1167 Minimal Proxy Clones |

## Links

- **GitHub:** [ayazabbas/strike](https://github.com/ayazabbas/strike)
- **Hackathon:** Good Vibes Only: OpenClaw Edition ($100k prize pool)

---

Built for the **Good Vibes Only: OpenClaw Edition** hackathon on BNB Chain.
