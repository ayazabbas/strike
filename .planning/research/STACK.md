# Technology Stack

**Project:** Strike - Binary UP/DOWN Prediction Market on BNB Smart Chain
**Researched:** 2026-02-10
**Confidence:** MEDIUM-HIGH

## Recommended Stack

### Smart Contract Layer

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| **Foundry** | Latest nightly | Solidity development framework | 2-5x faster compile/test times than Hardhat. Native Solidity tests avoid JavaScript async boilerplate. Builder familiarity from Douro Labs. Perfect for 9-day hackathon where speed matters. |
| **Solidity** | ^0.8.28 | Smart contract language | Latest stable with known vulnerability fixes. BSC is EVM-compatible. Required for parimutuel market logic and Pyth oracle integration. |
| **OpenZeppelin Contracts** | ^5.x | Security-audited contract libraries | Industry standard for Ownable, ReentrancyGuard, Pausable patterns. Prevents common vulnerabilities. Essential for production-ready contracts handling real funds. |
| **Pyth Network SDK** | Latest (@pythnetwork/pyth-sdk-solidity) | On-demand price oracle | Pull oracle model (permissionless updates). Supports BTC/BNB price feeds with 400ms update frequency. Builder works at Douro Labs (Pyth) - deep expertise available. Low-latency critical for 1hr markets. |

### Frontend Layer (Telegram Mini App)

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| **Next.js** | 15.x (App Router) | React framework | Stable App Router with excellent SSR/SSG. Automatic code splitting. Official tma.js templates use Next.js. Fast dev experience matches 9-day timeline. DO NOT use Next.js 16 - too new, potential stability issues for hackathon. |
| **React** | 19.x | UI library | Required by Next.js 15. Industry standard for complex UIs. Strong TypeScript support. |
| **TypeScript** | ^5.9 | Type safety | Catches errors at compile time. Essential for blockchain interactions where bugs = lost funds. Strong IDE support speeds development. |
| **@tma.js/sdk** | ^3.1.4 | Telegram Mini App integration | Official SDK for Telegram WebView APIs. Handles back button, haptics, theme, cloud storage. Actively maintained (updated daily). |
| **TailwindCSS** | ^4.1 | Styling | 5x faster builds than v3. Zero config. Responsive design with utility classes. Small bundle size critical for Telegram WebView performance limits. |

### Web3 Integration Layer

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| **Viem** | ^2.45 | Ethereum interaction library | 35KB vs 130KB (ethers.js). TypeScript-first with superior type safety. Modular architecture - only import what you need. 2026 standard over ethers.js. |
| **Wagmi** | ^3.4 | React hooks for Ethereum | Built on Viem + TanStack Query. Handles accounts, transactions, contract calls with React hooks. Automatic cache invalidation. Multi-chain support for future expansion. |
| **Reown AppKit** (formerly WalletConnect) | ^1.8 (@reown/appkit-adapter-wagmi) | Wallet connection | Works with Telegram Mini Apps out-of-box. Supports 600+ wallets. Free unlimited support. Unified config with Wagmi adapter. Essential for mobile-first Telegram users. |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| **Forge** (Foundry) | Smart contract testing | Fuzz testing built-in. Gas snapshots. Solidity-native tests. Chisel REPL for rapid prototyping. |
| **Anvil** (Foundry) | Local blockchain | Fast local BSC fork for testing. Zero-config. |
| **Cast** (Foundry) | CLI for chain interaction | Call contracts, send txs, convert data. Faster than Remix for testing. |
| **ESLint + Prettier** | Code quality | Standard Next.js setup. Enforce consistent style across team. |
| **TanStack Query Devtools** | React state debugging | Built into Wagmi. Visualize cache state. Critical for debugging Web3 hooks. |

## Installation

```bash
# Smart Contracts (Foundry)
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Initialize Foundry project
forge init contracts
cd contracts
forge install OpenZeppelin/openzeppelin-contracts
forge install pyth-network/pyth-sdk-solidity

# Frontend (Next.js + Telegram Mini App)
npx create-next-app@15 frontend --typescript --tailwind --app --use-npm
cd frontend

# Core dependencies
npm install @tma.js/sdk@^3.1.4 \
            viem@^2.45 \
            wagmi@^3.4 \
            @tanstack/react-query@^5 \
            @reown/appkit-adapter-wagmi@^1.8

# Development dependencies
npm install -D @types/node@^20 \
               eslint@^9 \
               prettier@^3 \
               tailwindcss@^4.1

# Pyth Network (frontend price feed fetching)
npm install @pythnetwork/pyth-evm-js
```

## Alternatives Considered

| Category | Recommended | Alternative | Why Not Alternative |
|----------|-------------|-------------|---------------------|
| **Smart Contract Framework** | Foundry | Hardhat | Hardhat v3 added Solidity tests but Foundry still 2-5x faster. JavaScript tests add async complexity. Foundry better for hackathon speed. Builder already knows Foundry. |
| **Frontend Framework** | Next.js 15 | Vite + React | Next.js has official tma.js templates. SSR/SSG better for initial load in Telegram WebView. Automatic routing saves time. Vite lacks these conveniences. |
| **Web3 Library** | Viem | ethers.js | Ethers.js v5 widespread but v6 changed APIs significantly. Viem has better TypeScript, smaller bundle (35KB vs 130KB), modular imports. Wagmi v2+ built on Viem, not ethers. Migration path clear. |
| **Wallet Connection** | Reown AppKit | RainbowKit | RainbowKit beautiful but AppKit has better Telegram Mini App support. 600+ wallets vs ~100. Free support. Multi-chain ready (Wagmi + Solana). AppKit = WalletConnect rebranded, trusted. |
| **Styling** | TailwindCSS v4 | shadcn/ui + Tailwind | shadcn/ui excellent for complex apps but overkill for hackathon. Prediction market UI is simple (bet buttons, price charts, history). Raw Tailwind faster to ship. Add shadcn later if needed. |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| **Next.js 16** | Released Jan 2026, too new. Potential bugs/instability during hackathon. Documentation not fully mature. | Next.js 15.x (stable, proven, good docs) |
| **ethers.js v5** | Deprecated. v6 has breaking changes. Viem is modern replacement with better DX. | Viem ^2.45 |
| **Hardhat** | Slower than Foundry (2-5x). JavaScript tests add complexity. No advantage for this project. | Foundry (forge, anvil, cast) |
| **Upgradeable Contracts (OpenZeppelin Proxy pattern)** | Adds complexity (initializers, storage slots, upgrade security). Overkill for 9-day hackathon. Prediction markets are time-bounded - deploy new contracts for fixes. | Simple contracts, thorough testing, careful deployment |
| **TON Connect** | TON blockchain integration. Wrong chain - this is BSC/EVM project. | Reown AppKit with Wagmi (EVM-compatible) |
| **Web3.js** | Outdated API, poor TypeScript support, larger bundle than Viem. Declining adoption in 2026. | Viem + Wagmi |

## Stack Patterns by Variant

**For Smart Contracts:**
- Use Foundry's forge test for unit tests (Solidity-native)
- Use Foundry's forge script for deployment scripts (not Hardhat's JavaScript)
- Use OpenZeppelin's ReentrancyGuard for bet() and claim() functions (parimutuel markets handle funds)
- Use Pyth's IPyth interface for price feed consumption (pull oracle pattern)
- Structure: /contracts/src for .sol files, /contracts/test for .t.sol tests, /contracts/script for .s.sol deploys

**For Frontend:**
- Use Next.js App Router (not Pages Router) - better async handling, React Server Components
- Use tma.js early in _app.tsx or layout.tsx (mount SDK before rendering UI)
- Use Wagmi's useWriteContract hook for bet transactions (handles gas estimation, error states)
- Use Viem's parseEther / formatEther for ETH/BNB conversions (avoid floating point math)
- Use TanStack Query's enabled option to defer queries until wallet connected

**For Telegram Mini App:**
- Call window.Telegram.WebApp.ready() immediately in layout.tsx
- Use tma.js's BackButton component for navigation (users expect Telegram back button)
- Use tma.js's HapticFeedback for bet confirmations (tactile feedback improves UX)
- Use tma.js's MainButton for primary actions (bet, claim) - styled to match Telegram theme
- Override window.open for WalletConnect (Telegram iframe restrictions) - see Reown docs

**For BSC Integration:**
- Use BNB Chain Testnet (chainId: 97) for development, not local Anvil
- Get testnet BNB from https://testnet.bnbchain.org/faucet
- Add BSC Mainnet (chainId: 56) to Wagmi config for production
- Set gasPrice explicitly (BSC uses fixed gas pricing, not EIP-1559)
- Use Pyth's BSC contract address: check https://docs.pyth.network/price-feeds/contract-addresses/evm

## Version Compatibility

| Package A | Compatible With | Notes |
|-----------|-----------------|-------|
| wagmi@3.4 | viem@^2.0 | Wagmi v2+ requires Viem. DO NOT use ethers with Wagmi v2+. |
| Next.js 15 | React 19 | Next.js 15 requires React 19. Earlier Next.js versions incompatible. |
| @tma.js/sdk@3.1 | Next.js 13+ | Works with App Router and Pages Router. SSR-safe. |
| @reown/appkit-adapter-wagmi@1.8 | wagmi@2+ or 3+ | Wagmi adapter requires Wagmi v2 minimum. Viem inherited from Wagmi. |
| TailwindCSS 4.1 | PostCSS 8+ | v4 uses native CSS features. Requires Safari 16.4+, Chrome 111+. OK for Telegram (evergreen browser). |
| Foundry | Solidity 0.8.28 | Foundry supports latest Solidity via nightly updates. Run foundryup regularly. |
| OpenZeppelin Contracts 5.x | Solidity ^0.8.20 | v5 requires 0.8.20+. BSC supports latest EVM, no issue. |

## Sources

### HIGH Confidence (Official Docs + Context7)
- [Foundry vs Hardhat Performance](https://chainstack.com/foundry-hardhat-differences-performance/) - MEDIUM confidence (multiple sources agree on 2-5x speed advantage)
- [Next.js 15 Release](https://nextjs.org/blog/next-15) - HIGH confidence (official release notes)
- [Viem Bundle Size Comparison](https://viem.sh/docs/introduction) - HIGH confidence (official docs, 35KB vs 130KB ethers.js)
- [Wagmi v3 Latest](https://www.npmjs.com/package/wagmi) - HIGH confidence (npm official registry, 3.4.2 as of Feb 2026)
- [@tma.js/sdk npm](https://www.npmjs.com/package/@tma.js/sdk) - HIGH confidence (official package, v3.1.4 latest)
- [TailwindCSS v4 Performance](https://tailwindcss.com/blog/tailwindcss-v4) - HIGH confidence (official blog, 5x faster builds)
- [Reown AppKit Wagmi Integration](https://docs.reown.com/appkit/react/core/installation) - HIGH confidence (official docs)

### MEDIUM Confidence (WebSearch + Multiple Sources)
- [BSC Smart Contract Best Practices](https://www.bnbchain.org/en/blog/best-practices-for-bnb-chain-project-security) - MEDIUM confidence (official BNB Chain blog)
- [Telegram Mini Apps Stack Guide](https://merge.rocks/blog/what-is-the-best-tech-stack-for-telegram-mini-apps-development) - MEDIUM confidence (industry article, aligns with official templates)
- [Pyth Pull Oracle Architecture](https://docs.pyth.network/price-feeds/core/pull-updates) - HIGH confidence (official Pyth docs)
- [OpenZeppelin Upgradeable Contracts](https://docs.openzeppelin.com/upgrades-plugins/writing-upgradeable) - HIGH confidence (official docs - used to explain what NOT to use)
- [Prediction Market Solidity Patterns](https://programtheblockchain.com/posts/2018/05/22/writing-a-prediction-market-contract/) - LOW-MEDIUM confidence (older 2018 tutorial, pattern still valid but needs adaptation)

### MEDIUM-LOW Confidence (WebSearch - flagged for validation)
- [WalletConnect Telegram Mini App Issues](https://github.com/WalletConnect/walletconnect-monorepo/discussions/4574) - LOW confidence (GitHub discussion, not official solution)
- Pyth on BSC contract address - NOT VERIFIED. Must check official Pyth docs at deployment time.
- TypeScript 5.9.3 as "latest" - MEDIUM confidence (npm shows 5.9.3, but 5.7/5.8 mentioned in other sources - verify at install)

---
*Stack research for: Binary Prediction Market on BNB Smart Chain with Telegram Mini App frontend*
*Researched: 2026-02-10*
*Context: 9-day hackathon (deadline Feb 19, 2026), builder at Douro Labs (Pyth expertise)*
