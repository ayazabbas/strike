# Strike 🐍

> Fully onchain prediction markets powered by Pyth oracles

**Hackathon:** Good Vibes Only: OpenClaw Edition (BNB Chain)

---

## What is Strike?

Strike lets you bet on whether an asset's price will go UP or DOWN by a specific time. Markets are:

- **Fully onchain** — All logic lives in smart contracts
- **Trustlessly resolved** — Pyth price feeds determine outcomes
- **Telegram-native** — Trade from your pocket

Coming soon: AI market makers you control with natural language.

---

## Quick Start

```bash
# Clone
git clone https://github.com/ayazabbas/strike
cd strike

# Install dependencies
cd contracts && forge install
cd ../app && npm install

# Run locally
# (instructions TBD)
```

---

## Architecture

```
Telegram Mini-App → Backend API → BNB Chain Contracts ← Pyth Oracle
```

See [PLAN.md](./PLAN.md) for full technical details.

---

## Status

🚧 **In Development** — Building for hackathon submission (Feb 19, 2026)

---

## Team

Built by [@ayazabbas](https://github.com/ayazabbas) + 🦀

---

## License

MIT
