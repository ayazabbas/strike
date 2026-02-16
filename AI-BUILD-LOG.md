# AI Build Log

How Strike was built almost entirely with AI agents.

## Setup

- **AI Platform:** [OpenClaw](https://github.com/openclaw/openclaw) — an open-source AI agent framework that orchestrates Claude models with tool access (shell, browser, file system, web search, messaging)
- **Primary Model:** Claude Opus 4.6 (Anthropic) — planning, architecture, coordination
- **Coding Agent:** Claude Code CLI — writing and editing code, running tests, debugging
- **Research Agent:** Claude Sonnet 4 — parallel research tasks
- **Human:** Ayaz Abbas — direction, decisions, testing, deployment approval

## How It Worked

OpenClaw acts as a persistent AI assistant with access to the development machine. It can spawn background coding agents (Claude Code sessions) that write code, run commands, and report back. The human provides direction and makes key decisions; the AI executes.

Typical workflow:
1. Human describes what to build (e.g. "write the prediction market contracts")
2. OpenClaw creates a detailed task brief and spawns a Claude Code session
3. Claude Code writes the code, runs tests, fixes issues — autonomously
4. OpenClaw monitors progress and reports back
5. Human reviews, gives feedback, decides next steps

## Build Timeline

### Day 1 (Feb 10) — Architecture & Contracts

**AI tasks:**
- Researched hackathon requirements, BNB Chain docs, Pyth oracle integration patterns
- Generated project requirements document and 5-phase roadmap
- Wrote `Market.sol` — core parimutuel prediction market (bet, resolve, claim, refund)
- Wrote `MarketFactory.sol` — EIP-1167 minimal proxy factory for gas-efficient market creation
- Wrote 51 tests across `Market.t.sol` and `MarketFactory.t.sol` — all passing
- Scaffolded the Telegram bot with 8 command handlers, 4 services (Privy wallets, Pyth prices, blockchain interaction, notifications), SQLite database

**Human decisions:**
- Chose parimutuel pool model over orderbook
- Chose Telegram bot with embedded wallets over Mini App with WalletConnect (architectural pivot)
- Chose Privy for server-side wallet management
- Defined fee structure (3%), minimum bet (0.001 BNB), anti-frontrun lock (60s)

### Day 2-4 (Feb 11-14) — Iteration

**AI tasks:**
- Added permissioned keeper role for market resolution
- Implemented trading deadline (betting stops halfway through market duration)
- Changed fee model to only charge on winnings (not total pool)
- Added integration tests running against Anvil local devnet
- Added Docker setup for bot deployment
- Bug fixes across bot handlers and error handling

**Human decisions:**
- Reviewed contract changes and approved fee model
- Directed focus areas and priorities

### Day 5 (Feb 15) — Deployment & Wiring

**AI tasks:**
- Deployed contracts to BSC testnet via Foundry
  - MarketFactory: `0xDf8C8598392D664002CF8c5619e6161E65D91358`
  - Market Implementation: `0x6935A3BcC853640477646080646766136383D324`
- Wired bot to deployed contracts (config, RPC, ABIs, addresses)
- Fixed MarketFactory to accept BNB refunds from Pyth (added `receive()`)
- Created first test market on BSC testnet (BTC/USD)
- Ran smoke tests — market state, prices, pools all verified
- Scoped down to BTC/USD only, 5-minute markets (human decision)
- Updated all docs, README, and scripts to match final scope
- Pushed to GitHub

**Human decisions:**
- Approved deployment
- Narrowed scope: BTC/USD only, 5-minute rounds
- Created GitHub repo and directed the push

## AI Contribution Breakdown

| Component | AI-Written | Human-Written |
|-----------|-----------|---------------|
| Smart contracts (Market.sol, MarketFactory.sol) | ~100% | Architecture decisions |
| Test suite (51 tests) | ~100% | — |
| Telegram bot (handlers, services, DB) | ~100% | — |
| Deployment scripts | ~100% | — |
| Admin scripts (create-market, resolve) | ~100% | — |
| Docker setup | ~100% | — |
| README and docs | ~95% | Edits and scope |
| Project direction and architecture | — | ~100% |
| Contract deployment | ~90% | Approval and env setup |

**Estimated split: ~95% AI-generated code, 100% human-directed.**

## Tools & Models Used

| Tool | Role |
|------|------|
| OpenClaw | Agent orchestration, task management, monitoring |
| Claude Opus 4.6 | Primary brain — planning, coordination, code review |
| Claude Code CLI | Autonomous coding sessions (write, test, debug, fix) |
| Claude Sonnet 4 | Research sub-agent tasks |
| Claude Haiku 4.5 | Periodic health checks (heartbeat) |
| Foundry | Smart contract compilation, testing, deployment |
| grammY | Telegram bot framework |
| viem | Blockchain interaction |

## Key Moments Where AI Excelled

1. **Contract test coverage** — Claude Code wrote 51 comprehensive tests including edge cases (one-sided markets, exact price ties, anti-frontrun, emergency cancellation) without being asked for specific scenarios
2. **Architectural pivot** — When the human decided to switch from Telegram Mini App to a bot with embedded wallets, the AI restructured the entire frontend approach in a single session
3. **Bug discovery** — During deployment wiring, Claude Code found that MarketFactory needed a `receive()` function to handle Pyth fee refunds — a bug that would have blocked the entire betting flow
4. **Parallel execution** — Multiple Claude Code sessions ran simultaneously (contracts + tests, bot scaffolding, deployment scripts) cutting build time significantly

## What the Human Did That AI Couldn't

- Made the call to use parimutuel pools (product intuition)
- Decided Telegram bot > Mini App (UX judgment based on knowing the target user)
- Chose 5-minute BTC-only markets (scope discipline)
- Created the Telegram bot via BotFather and set up Privy account + server wallets
- Funded deployer wallet with BSC testnet BNB via faucet
- Created `.env` files with API keys and secrets
- Tested the live bot on Telegram
- Final review and approval of everything shipped
