# Technology Stack

**Project:** Strike - Binary UP/DOWN Prediction Market on BNB Smart Chain
**Researched:** 2026-02-10
**Confidence:** HIGH

## Recommended Stack

### Smart Contract Layer

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| **Foundry** | Latest nightly | Solidity development framework | 10-50x faster test execution than Hardhat. Native Solidity tests avoid JavaScript async boilerplate. Builder familiarity from Douro Labs. Perfect for 9-day hackathon where speed matters. Forge for testing, Anvil for local chain, Cast for CLI interactions. |
| **Solidity** | ^0.8.13+ | Smart contract language | Latest stable with known vulnerability fixes. BSC is EVM-compatible. Required for parimutuel market logic and Pyth oracle integration. OpenZeppelin v5 requires 0.8.13+. |
| **OpenZeppelin Contracts** | 5.4.0 | Security-audited contract libraries | Industry standard for Ownable, ReentrancyGuard, Pausable patterns. Prevents common vulnerabilities. Essential for production-ready contracts handling real funds. v5 required for new deployments. |
| **forge-std** | 1.14.0 | Foundry testing library | Provides cheatcodes (vm.warp for time manipulation, vm.prank for address impersonation) essential for testing time-based markets. Requires Solidity ^0.8.13+. |
| **@pythnetwork/pyth-sdk-solidity** | 4.3.1 | On-demand price oracle (Solidity) | Pull oracle model (permissionless updates). Supports BTC/BNB price feeds with sub-second update frequency. IPyth interface for consuming Pyth prices on EVM. Builder works at Douro Labs (Pyth) - deep expertise available. |

**BSC Deployment Details:**
- **Mainnet:** Chain ID 56
- **Testnet:** Chain ID 97 (BSC Chapel)
- **Pyth Contract (Mainnet):** `0x4D7E825f80bDf85e913E0DD2A2D54927e9dE1594`
- **Pyth Contract (Testnet):** `0x5744Cbf430D99456a0A8771208b674F27f8EF0Fb`

### Frontend Layer (Telegram Mini App)

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| **Next.js** | 16.1.6 | React framework | App Router with modern patterns, built-in TypeScript support, seamless Vercel deployment. Official Telegram Mini Apps templates use Next.js. Requires React 19.x. |
| **React** | 19.2.4 | UI library | Required by Next.js 16. Industry standard for complex UIs. Strong TypeScript support. Ecosystem standard for web3 frontends. |
| **TypeScript** | 5.9.3 | Type safety | Catches errors at compile time. Essential for blockchain interactions where bugs = lost funds. Strong IDE support speeds development. Type inference for contract ABIs via viem. |
| **@telegram-apps/sdk-react** | 3.3.9 | Telegram Mini App integration | Official React bindings for Telegram Mini Apps platform. Includes hooks and components for MainButton, BackButton, WebApp context, haptics, theme detection. |
| **TailwindCSS** | 4.1.18 | Styling | Utility-first CSS. 5x faster builds than v3. Zero config. Responsive design with utility classes. Small bundle size critical for Telegram WebView performance. |

### Web3 Integration Layer

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| **viem** | 2.45.2 | EVM interaction library | 27KB vs 130KB for ethers.js. TypeScript-first with superior type safety. Modular architecture - only import what you need. 2026 standard for modern web3 apps. Used internally by wagmi. |
| **wagmi** | 3.4.2 | React hooks for Ethereum | Type-safe React hooks for wallets, contracts, transactions. Built on viem + TanStack Query. Automatic cache invalidation. Maintained by same team as viem ensuring tight integration. Multi-chain support for future expansion. |
| **@reown/appkit** | 1.8.17 | Wallet connection UI | Formerly WalletConnect. Works with Telegram Mini Apps out-of-the-box (no iframe issues). Supports 600+ wallets across EVM chains including BSC. Provides Email/Social login for onboarding new users. Free unlimited support. |
| **@pythnetwork/pyth-evm-js** | 2.0.0 | Pyth price feeds (frontend) | Fetch price update data from Hermes for on-chain submission. Query current prices for UI display. Interact with EvmPriceServiceConnection to get BTC/BNB price updates. |
| **@tanstack/react-query** | 5.90.20 | Async state management | Server state caching for blockchain reads. Automatic refetching, optimistic updates, cache invalidation. Industry standard for data fetching in React. Built into wagmi. |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| **Forge** (Foundry) | Smart contract testing | Fuzz testing built-in. Gas snapshots. Solidity-native tests. Chisel REPL for rapid prototyping. 10-50x faster than Hardhat. |
| **Anvil** (Foundry) | Local blockchain | Fast local BSC fork for testing. Zero-config. Can fork BSC testnet/mainnet for integration tests. |
| **Cast** (Foundry) | CLI for chain interaction | Call contracts, send txs, convert data. Faster than Remix for testing. Useful for querying deployed contracts. |
| **Vercel** | Next.js hosting | Zero-config deployment for Next.js. Automatic HTTPS (required for Telegram Mini Apps). Edge network for global performance. Official Next.js platform. Free tier sufficient for hackathon. |
| **GitHub Actions** | CI/CD | Free for public repos. Run Foundry tests on push. Deploy to Vercel on merge to main. |
| **ESLint + Prettier** | Code quality | Standard Next.js setup. Enforce consistent style. Prevent common errors. |

## Installation

### Smart Contracts (Foundry)

```bash
# Install Foundry (if not already installed)
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Initialize Foundry project
forge init contracts
cd contracts

# Install dependencies
forge install foundry-rs/forge-std@v1.14.0
forge install OpenZeppelin/openzeppelin-contracts@v5.4.0

# Install Pyth SDK (via npm for Solidity)
npm install --save-dev @pythnetwork/pyth-sdk-solidity@4.3.1

# Configure remappings in foundry.toml or remappings.txt
# @openzeppelin/contracts/=lib/openzeppelin-contracts/contracts/
# @pythnetwork/pyth-sdk-solidity/=node_modules/@pythnetwork/pyth-sdk-solidity/
# forge-std/=lib/forge-std/src/
```

### Frontend (Next.js + Telegram Mini App)

```bash
# Create Next.js app with TypeScript and Tailwind
npx create-next-app@latest frontend --typescript --tailwind --app --no-src-dir

cd frontend

# Core dependencies
npm install viem@2.45.2 \
            wagmi@3.4.2 \
            @tanstack/react-query@5.90.20 \
            @telegram-apps/sdk-react@3.3.9 \
            @reown/appkit@1.8.17 \
            @pythnetwork/pyth-evm-js@2.0.0

# Dev dependencies (TypeScript and Tailwind likely already installed by create-next-app)
npm install -D typescript@5.9.3 \
               tailwindcss@4.1.18 \
               @types/node@latest \
               eslint@latest \
               prettier@latest
```

### Environment Variables

```bash
# .env.local (frontend)
NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID=your_reown_project_id
NEXT_PUBLIC_BSC_RPC_URL=https://bsc-dataseed.bnbchain.org
NEXT_PUBLIC_BSC_TESTNET_RPC_URL=https://bsc-testnet-dataseed.bnbchain.org
NEXT_PUBLIC_PREDICTION_MARKET_ADDRESS=0x...
NEXT_PUBLIC_PYTH_HERMES_URL=https://hermes.pyth.network

# .env (contracts - for Foundry scripts)
BSC_RPC_URL=https://bsc-dataseed.bnbchain.org
BSC_TESTNET_RPC_URL=https://bsc-testnet-dataseed.bnbchain.org
PRIVATE_KEY=your_deployment_wallet_private_key
BSCSCAN_API_KEY=your_bscscan_api_key
```

## Alternatives Considered

| Category | Recommended | Alternative | Why Not Alternative |
|----------|-------------|-------------|---------------------|
| **Smart Contract Framework** | Foundry | Hardhat | Hardhat v3 added Solidity tests but Foundry still 10-50x faster (Paradigm benchmarks). JavaScript tests add async complexity. Foundry better for hackathon speed. Builder already knows Foundry from Douro Labs. |
| **Frontend Framework** | Next.js 16 | Next.js 15 | Next.js 16 is latest stable (Jan 2026). App Router mature. If concerned about stability, Next.js 15.x is proven alternative. Both work with React 19. |
| **Frontend Framework** | Next.js | Vite + React | Next.js has official Telegram Mini Apps templates. SSR/SSG better for initial load in Telegram WebView. Automatic routing saves time. Vite lacks these conveniences for mini apps. |
| **Web3 Library** | viem | ethers.js v6 | Ethers.js v5 deprecated. v6 has breaking changes. Viem has better TypeScript (27KB vs 130KB), modular imports. Wagmi v2+ built on viem, not ethers. Migration path clear. Ethers still viable for legacy codebases. |
| **Wallet Connection** | Reown AppKit | RainbowKit | RainbowKit has beautiful UI but AppKit has better Telegram Mini App support (handles iframe restrictions). 600+ wallets vs ~100. Free support. Multi-chain ready. AppKit = WalletConnect v3 rebranded. |
| **Styling** | TailwindCSS | shadcn/ui + Tailwind | shadcn/ui excellent for complex apps but overkill for hackathon. Prediction market UI is simple (bet buttons, price charts, history). Raw Tailwind faster to ship. Add shadcn later if needed. |
| **Telegram SDK** | @telegram-apps/sdk-react | @tma.js/sdk | Both are official. @telegram-apps/sdk-react has React-specific hooks (cleaner integration). @tma.js/sdk is framework-agnostic. Choose based on preference. |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| **ethers.js v5** | Deprecated. v6 has breaking changes. Viem is modern replacement with better DX, smaller bundle, TypeScript-first. | viem 2.45.2 + wagmi 3.4.2 |
| **Hardhat** | Slower than Foundry (10-50x compile/test). JavaScript tests add complexity. No advantage for this project given builder's Foundry experience. | Foundry (forge, anvil, cast) |
| **Upgradeable Contracts (OpenZeppelin Proxy pattern)** | Adds complexity (initializers, storage slots, upgrade security). Overkill for 9-day hackathon. Prediction markets are time-bounded - deploy new contracts for fixes. | Simple contracts, thorough testing, careful deployment |
| **TON Connect** | TON blockchain integration. Wrong chain - this is BSC/EVM project. Confusing because Telegram created TON but BSC is separate. | Reown AppKit with Wagmi (EVM-compatible) |
| **Web3.js** | Outdated API, poor TypeScript support, larger bundle than viem. Declining adoption in 2026. Last major update years ago. | viem + wagmi |
| **Truffle** | Development effectively ceased. 10-50x slower than Foundry. Limited Solidity testing. | Foundry |
| **Remix IDE** | Fine for prototyping but lacks testing framework for production. No version control integration. | Foundry for local development, deploy via forge scripts |
| **WalletConnect v1/v2** | Deprecated, security vulnerabilities. v2 sunset imminent. Telegram Mini App support lacking. | @reown/appkit 1.8.17 (WalletConnect v3 rebrand) |
| **HTTP-only hosting** | Telegram Mini Apps require HTTPS with valid SSL certificate. Users will see security warnings. | Vercel (auto HTTPS) or configure SSL on hosting provider |

## Stack Patterns by Variant

### For Smart Contracts

**Testing Pattern:**
```solidity
// Use Foundry's Solidity-native tests
contract PredictionMarketTest is Test {
    function testBetUp() public {
        vm.warp(block.timestamp + 1 hours); // Time manipulation
        vm.prank(user1); // Impersonate user
        market.placeBet{value: 1 ether}(BetDirection.UP);
        assertEq(market.totalUpBets(), 1 ether);
    }
}
```

**Security Pattern:**
```solidity
// Use OpenZeppelin's ReentrancyGuard for bet() and claim()
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract PredictionMarket is ReentrancyGuard {
    function placeBet(BetDirection direction) external payable nonReentrant {
        // Parimutuel markets handle funds - reentrancy protection critical
    }
}
```

**Oracle Pattern:**
```solidity
// Use Pyth's IPyth interface for price feed consumption
import {IPyth} from "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import {PythStructs} from "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";

contract PredictionMarket {
    IPyth public immutable pyth;
    bytes32 public immutable priceFeedId; // BTC/USD or BNB/USD

    function resolveMarket(bytes[] calldata priceUpdateData) external payable {
        uint256 fee = pyth.getUpdateFee(priceUpdateData);
        pyth.updatePriceFeeds{value: fee}(priceUpdateData);

        PythStructs.Price memory price = pyth.getPrice(priceFeedId);
        // Compare price to strike price, resolve market
    }
}
```

**Project Structure:**
```
contracts/
  src/
    PredictionMarket.sol
    interfaces/
    libraries/
  test/
    PredictionMarket.t.sol
  script/
    Deploy.s.sol
  foundry.toml
  remappings.txt
```

### For Frontend

**Wagmi Configuration:**
```typescript
import { createConfig, http } from 'wagmi'
import { bsc, bscTestnet } from 'wagmi/chains'

export const config = createConfig({
  chains: [bsc, bscTestnet],
  transports: {
    [bsc.id]: http(),
    [bscTestnet.id]: http(),
  },
})
```

**Contract Interaction Pattern:**
```typescript
import { useWriteContract, useReadContract } from 'wagmi'
import { parseEther } from 'viem'
import { abi } from './abi/PredictionMarket'

// Read contract state
const { data: currentPrice } = useReadContract({
  address: '0x...',
  abi,
  functionName: 'getCurrentPrice',
})

// Write to contract
const { writeContract, isPending } = useWriteContract()

const placeBet = () => {
  writeContract({
    address: '0x...',
    abi,
    functionName: 'placeBet',
    args: [BetDirection.UP],
    value: parseEther('0.1'), // Avoid floating point math
  })
}
```

**Pyth Price Feed Pattern:**
```typescript
import { EvmPriceServiceConnection } from '@pythnetwork/pyth-evm-js'

const connection = new EvmPriceServiceConnection(
  'https://hermes.pyth.network'
)

// BTC/USD price feed ID
const BTC_USD_PRICE_FEED = '0xe62df6c8b4a85fe1a67db44dc12de5db330f7ac66b72dc658afedf0f4a415b43'

// Fetch price update data for on-chain submission
const priceUpdateData = await connection.getPriceFeedsUpdateData([BTC_USD_PRICE_FEED])

// Submit to contract
writeContract({
  address: marketAddress,
  abi,
  functionName: 'resolveMarket',
  args: [priceUpdateData],
  value: updateFee, // Pyth charges small fee (~0.001 BNB)
})
```

**Telegram Mini App Setup:**
```typescript
// app/layout.tsx
import { init } from '@telegram-apps/sdk-react'

export default function RootLayout({ children }) {
  useEffect(() => {
    init() // Initialize Telegram SDK
  }, [])

  return <html>{children}</html>
}

// components/BetButton.tsx
import { MainButton } from '@telegram-apps/sdk-react'

function BetButton() {
  return (
    <MainButton
      text="Place Bet"
      onClick={handleBet}
      // Automatically styled to match Telegram theme
    />
  )
}
```

**Wallet Connection (Reown AppKit):**
```typescript
import { createAppKit } from '@reown/appkit/react'
import { bsc, bscTestnet } from 'viem/chains'
import { WagmiAdapter } from '@reown/appkit-adapter-wagmi'

const projectId = 'YOUR_REOWN_PROJECT_ID' // Get from reown.com

const wagmiAdapter = new WagmiAdapter({
  chains: [bsc, bscTestnet],
  projectId,
})

createAppKit({
  adapters: [wagmiAdapter],
  projectId,
  // Works in Telegram Mini Apps out-of-box
})
```

### For BSC Integration

**Use BSC Testnet first:**
```typescript
// Chain ID 97 for development
import { bscTestnet } from 'viem/chains'

// Get testnet BNB from faucet
// https://www.bnbchain.org/en/testnet-faucet
```

**RPC Configuration:**
```typescript
// Use public RPC for testing, paid for production
const transport = http(
  process.env.NODE_ENV === 'production'
    ? 'https://your-paid-rpc.com' // QuickNode, Ankr, etc.
    : 'https://bsc-testnet-dataseed.bnbchain.org'
)
```

**Gas Configuration:**
```typescript
// BSC doesn't use EIP-1559 (no maxFeePerGas)
// Use legacy gas pricing
const { data: hash } = await writeContract({
  // ... contract params
  gasPrice: parseGwei('3'), // BSC typically ~3 Gwei
})
```

**Pyth Contract Addresses:**
```typescript
const PYTH_CONTRACT = {
  [bsc.id]: '0x4D7E825f80bDf85e913E0DD2A2D54927e9dE1594',
  [bscTestnet.id]: '0x5744Cbf430D99456a0A8771208b674F27f8EF0Fb',
}
```

## Version Compatibility

| Package A | Compatible With | Notes |
|-----------|-----------------|-------|
| wagmi@3.4.2 | viem@2.x | Wagmi v2+ requires viem. DO NOT use ethers with wagmi v2+. Version pinning recommended. |
| Next.js 16.1.6 | React 19.2.4 | Next.js 16 requires React 19.x. Earlier Next.js versions incompatible with React 19. |
| @telegram-apps/sdk-react@3.3.9 | Next.js 13+ | Works with App Router and Pages Router. SSR-safe. React 18+ required. |
| @reown/appkit@1.8.17 | wagmi@3.x, viem@2.x | Ensure wagmi/viem versions align with AppKit requirements. Check AppKit docs. |
| TailwindCSS 4.1.18 | PostCSS 8+ | v4 uses native CSS features. Requires Safari 16.4+, Chrome 111+. OK for Telegram (evergreen browser). |
| forge-std 1.14.0 | Solidity ^0.8.13+ | Earlier Solidity versions use forge-std 1.13.0. |
| @openzeppelin/contracts 5.4.0 | Solidity ^0.8.20+ | v5 requires 0.8.20+. Breaking changes from v4, cannot mix. BSC supports latest EVM. |
| @pythnetwork/pyth-sdk-solidity 4.3.1 | Solidity ^0.6.0+ | Works with modern Solidity versions. BSC compatible. |
| TypeScript 5.9.3 | Next.js 16.1.6 | Next.js supports TS 5.x out-of-box. |
| @pythnetwork/pyth-evm-js 2.0.0 | viem 2.x | Works alongside viem for fetching price updates. |

## BSC-Specific Configuration

### RPC Endpoints

**Mainnet (Chain ID 56):**
- Official: `https://bsc-dataseed.bnbchain.org`
- PublicNode: `https://bsc-rpc.publicnode.com`
- Paid providers: QuickNode, Ankr, dRPC (recommended for production - rate limits, reliability)

**Testnet (Chain ID 97 - BSC Chapel):**
- Official: `https://bsc-testnet-dataseed.bnbchain.org`
- PublicNode: `https://bsc-testnet-rpc.publicnode.com`
- Ankr: Available

### Faucets (Testnet)

- Official: https://www.bnbchain.org/en/testnet-faucet
- Tatum: 0.002 tBNB every 24 hours
- QuickNode: 1 drip per 12 hours
- Bitbond: Available

### Block Explorers

- Mainnet: https://bscscan.com
- Testnet: https://testnet.bscscan.com
- Use for contract verification, transaction tracking, debugging

### Gas Considerations

- BSC is cheap (~3 Gwei typical, vs 20-50 Gwei on Ethereum)
- Gas limit similar to Ethereum (block gas limit ~140M)
- Does NOT support EIP-1559 (use legacy `gasPrice` not `maxFeePerGas`)
- Pyth updates require update fee (paid in native BNB, typically ~0.001 BNB)
- 3-second block time (vs 12s Ethereum) - faster finality

### Pyth Price Feed IDs

**Available on BSC:**
- BTC/USD: `0xe62df6c8b4a85fe1a67db44dc12de5db330f7ac66b72dc658afedf0f4a415b43`
- BNB/USD: Check https://pyth.network/developers/price-feed-ids
- 380+ total feeds available across all Pyth-supported chains

## Integration Points

### Smart Contract → Oracle (Pyth)

```solidity
import {IPyth} from "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import {PythStructs} from "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";

contract PredictionMarket {
    IPyth public immutable pyth;
    bytes32 public immutable priceFeedId;

    constructor(address _pyth, bytes32 _priceFeedId) {
        pyth = IPyth(_pyth);
        priceFeedId = _priceFeedId;
    }

    function resolveMarket(bytes[] calldata priceUpdateData)
        external
        payable
        nonReentrant
    {
        // Calculate fee required for update
        uint256 fee = pyth.getUpdateFee(priceUpdateData);
        require(msg.value >= fee, "Insufficient update fee");

        // Update price feeds (permissionless)
        pyth.updatePriceFeeds{value: fee}(priceUpdateData);

        // Get latest price
        PythStructs.Price memory price = pyth.getPrice(priceFeedId);

        // Resolve market based on price
        // price.price = price * 10^price.expo
        int64 currentPrice = price.price;
        // Compare to strike price, determine UP or DOWN winners
    }
}
```

### Frontend → Smart Contracts (wagmi + viem)

```typescript
import { useWriteContract, useReadContract } from 'wagmi'
import { parseEther, formatEther } from 'viem'
import { abi } from './abi/PredictionMarket'

function BetInterface() {
  // Read contract state
  const { data: marketPrice } = useReadContract({
    address: MARKET_ADDRESS,
    abi,
    functionName: 'getCurrentPrice',
  })

  const { data: totalUpBets } = useReadContract({
    address: MARKET_ADDRESS,
    abi,
    functionName: 'totalUpBets',
  })

  // Write to contract
  const { writeContract, isPending, isSuccess } = useWriteContract()

  const placeBet = (direction: BetDirection, amount: string) => {
    writeContract({
      address: MARKET_ADDRESS,
      abi,
      functionName: 'placeBet',
      args: [direction],
      value: parseEther(amount), // Convert "0.1" to wei
    })
  }

  return (
    <div>
      <p>Current Price: {formatEther(marketPrice || 0n)} BNB</p>
      <p>Total UP Bets: {formatEther(totalUpBets || 0n)} BNB</p>
      <button onClick={() => placeBet(BetDirection.UP, "0.1")} disabled={isPending}>
        {isPending ? 'Placing Bet...' : 'Bet UP'}
      </button>
    </div>
  )
}
```

### Frontend → Pyth Price Feeds

```typescript
import { EvmPriceServiceConnection } from '@pythnetwork/pyth-evm-js'

const HERMES_URL = 'https://hermes.pyth.network'
const connection = new EvmPriceServiceConnection(HERMES_URL)

// BTC/USD price feed ID
const BTC_USD = '0xe62df6c8b4a85fe1a67db44dc12de5db330f7ac66b72dc658afedf0f4a415b43'

// Fetch current price for display (off-chain)
async function fetchPrice() {
  const priceFeeds = await connection.getLatestPriceFeeds([BTC_USD])
  const price = priceFeeds[0].getPriceUnchecked()
  return price.price * 10 ** price.expo // Convert to human-readable
}

// Fetch price update data for on-chain submission
async function getPriceUpdateData() {
  const priceUpdateData = await connection.getPriceFeedsUpdateData([BTC_USD])
  return priceUpdateData // bytes[] to submit to contract
}

// Usage with wagmi
const { writeContract } = useWriteContract()

const resolveMarket = async () => {
  const priceUpdateData = await getPriceUpdateData()
  const updateFee = parseEther('0.001') // Typical Pyth fee on BSC

  writeContract({
    address: MARKET_ADDRESS,
    abi,
    functionName: 'resolveMarket',
    args: [priceUpdateData],
    value: updateFee,
  })
}
```

### Telegram Mini App Setup

```typescript
// app/layout.tsx
'use client'
import { useEffect } from 'react'
import { init, backButton, mainButton } from '@telegram-apps/sdk-react'

export default function RootLayout({ children }) {
  useEffect(() => {
    // Initialize Telegram SDK on mount
    init()

    // Show back button
    backButton.show()

    // Configure main button (bottom of screen)
    mainButton.setParams({
      text: 'Place Bet',
      isVisible: true,
      isEnabled: true,
    })
  }, [])

  return (
    <html>
      <body>{children}</body>
    </html>
  )
}

// components/TelegramMainButton.tsx
import { mainButton } from '@telegram-apps/sdk-react'

function BetButton({ onBet }) {
  useEffect(() => {
    // Listen for main button clicks
    const handleClick = () => onBet()
    mainButton.onClick(handleClick)

    return () => mainButton.offClick(handleClick)
  }, [onBet])

  return null // Telegram renders the button, not React
}
```

### Wallet Connection (Reown AppKit)

```typescript
// config/appkit.ts
import { createAppKit } from '@reown/appkit/react'
import { WagmiAdapter } from '@reown/appkit-adapter-wagmi'
import { bsc, bscTestnet } from 'viem/chains'

const projectId = process.env.NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID!

const wagmiAdapter = new WagmiAdapter({
  chains: [bsc, bscTestnet],
  projectId,
})

createAppKit({
  adapters: [wagmiAdapter],
  projectId,
  chains: [bsc, bscTestnet],
  defaultChain: bscTestnet, // Start on testnet
  features: {
    email: true, // Enable email login for non-crypto users
    socials: ['google', 'github'], // Social login
  },
})

// Note: Works in Telegram Mini Apps automatically
// No need for window.open overrides with AppKit 1.8+
```

## Deployment Workflow

### Contracts (Foundry → BSC)

```bash
# 1. Write contracts in contracts/src/
# 2. Write tests in contracts/test/ using Solidity

# 3. Run tests
forge test -vvv

# 4. Create deployment script (contracts/script/Deploy.s.sol)
forge script script/Deploy.s.sol --rpc-url $BSC_TESTNET_RPC --broadcast --verify

# 5. Verify on BSCScan (if not done in step 4)
forge verify-contract <address> src/PredictionMarket.sol:PredictionMarket \
  --chain-id 97 \
  --etherscan-api-key $BSCSCAN_API_KEY \
  --constructor-args $(cast abi-encode "constructor(address,bytes32)" $PYTH_ADDRESS $PRICE_FEED_ID)

# 6. Deploy to mainnet (same command with mainnet RPC and chain ID 56)
forge script script/Deploy.s.sol --rpc-url $BSC_RPC_URL --broadcast --verify --chain-id 56
```

### Frontend (Next.js → Vercel)

```bash
# 1. Push to GitHub
git push origin main

# 2. Connect Vercel to repo (vercel.com)
# 3. Set environment variables in Vercel dashboard:
#    - NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID
#    - NEXT_PUBLIC_PREDICTION_MARKET_ADDRESS
#    - NEXT_PUBLIC_BSC_RPC_URL
#    etc.

# 4. Auto-deploys on push to main
# 5. HTTPS automatically configured (required for Telegram)
# 6. Get deployment URL: https://your-app.vercel.app

# 7. Set Telegram Bot's mini app URL
# In BotFather, set mini app URL to Vercel domain
```

### Testing in Telegram

```bash
# 1. Deploy frontend to Vercel (get URL)
# 2. Create Telegram bot via @BotFather
# 3. Set mini app URL: /setminiappurl
# 4. Open bot, launch mini app
# 5. Test wallet connection, betting, etc.
# 6. Iterate: push to GitHub → Vercel auto-deploys → test in Telegram
```

## Testing Strategy

### Smart Contracts (Foundry)

```bash
# Unit tests (Solidity-native, fast)
forge test -vvv

# Gas reporting
forge test --gas-report

# Fork BSC testnet locally for integration tests
anvil --fork-url $BSC_TESTNET_RPC --fork-block-number 45000000

# Test specific contract
forge test --match-contract PredictionMarketTest

# Test specific function
forge test --match-test testBetUp

# Coverage
forge coverage
```

### Frontend (Next.js + TypeScript)

```bash
# Type checking (catches contract ABI mismatches)
npm run type-check

# Build check (catches env var issues, import errors)
npm run build

# Local dev (won't work in Telegram context - use for UI development)
npm run dev

# Test in Telegram: Deploy to Vercel preview, add to Telegram bot
```

### Integration Testing

```bash
# 1. Deploy contracts to BSC testnet
# 2. Deploy frontend to Vercel preview (PR creates preview)
# 3. Configure Telegram bot with preview URL
# 4. Test full flow: connect wallet → place bet → resolve market
# 5. Monitor BSCScan for transactions
# 6. Check Vercel logs for errors
```

## Timeline Recommendations (9-day hackathon)

Given February 19, 2026 deadline:

### Days 1-2: Smart Contracts
- Foundry project setup
- Core prediction market logic (parimutuel, time windows)
- Pyth integration (resolve with price feeds)
- OpenZeppelin security (ReentrancyGuard, Pausable, Ownable)
- Unit tests (forge test)
- Deploy to BSC testnet
- Verify on BSCScan

### Days 3-5: Frontend Foundation
- Next.js + TypeScript setup
- Telegram SDK integration (MainButton, BackButton, haptics)
- Wallet connection (Reown AppKit)
- Contract interaction (wagmi/viem hooks)
- Pyth price display (fetch from Hermes)
- Basic UI (Tailwind CSS)

### Days 6-7: Integration + Features
- Connect frontend to deployed contracts
- Bet placement flow (wallet → contract → confirmation)
- Market resolution (fetch Pyth update → submit to contract)
- User balance display, bet history
- Real-time price updates (polling or websockets)
- UI polish (animations, loading states, error handling)

### Days 8-9: Testing + Deployment
- End-to-end testing in Telegram on testnet
- Bug fixes, edge case handling
- Mainnet deployment (contracts + frontend)
- Final polish, demo preparation
- Documentation (README, contract comments)

### Rationale for Stack Choices with 9-Day Timeline

**Foundry over Hardhat:**
- 10-50x faster tests = faster iteration
- No JavaScript test boilerplate = faster writing
- Builder already knows it = no learning curve

**Next.js + Vercel:**
- Zero deployment config = no DevOps time
- Automatic HTTPS = Telegram requirement met
- Official templates = less debugging

**Telegram Mini Apps SDK:**
- Official library = less debugging
- React hooks = clean integration
- Maintained by Telegram = reliable

**Pyth Network:**
- Builder's expertise (Douro Labs) = faster integration
- Sub-second updates = better UX for 1hr markets
- Pull model = permissionless resolution

**viem + wagmi:**
- TypeScript-first = catch errors early (save debugging time)
- Smaller bundle = faster loads in Telegram
- Modern stack = better docs, community support

**No Complex Patterns:**
- No upgradeable contracts (KISS principle)
- No complex deployment scripts (Foundry handles it)
- No over-engineering (hackathon MVP, not production v1)

## Sources

### High Confidence (Official Docs, npm Registry, Verified Contracts)

- [Pyth Network EVM Integration](https://docs.pyth.network/price-feeds/core/use-real-time-data/pull-integration/evm) — Solidity SDK usage, pull oracle pattern
- [Pyth Contract Addresses (EVM)](https://docs.pyth.network/price-feeds/core/contract-addresses/evm) — BSC mainnet/testnet addresses VERIFIED
- [Pyth SDK Solidity GitHub](https://github.com/pyth-network/pyth-sdk-solidity) — SDK repository, examples
- [@pythnetwork/pyth-sdk-solidity npm](https://www.npmjs.com/package/@pythnetwork/pyth-sdk-solidity) — Version 4.3.1 confirmed
- [@pythnetwork/pyth-evm-js npm](https://www.npmjs.com/package/@pythnetwork/pyth-evm-js) — Version 2.0.0 confirmed
- [Telegram Apps SDK React Docs](https://docs.telegram-mini-apps.com/packages/telegram-apps-sdk-react/2-x) — Official React SDK
- [@telegram-apps/sdk-react npm](https://www.npmjs.com/package/@telegram-apps/sdk-react) — Version 3.3.9 confirmed
- [Reown AppKit Telegram Integration](https://docs.reown.com/appkit/integrations/telegram-mini-apps) — Official Telegram Mini Apps docs
- [Reown AppKit Blog](https://reown.com/blog/how-to-build-a-telegram-mini-app) — Telegram integration guide
- [@reown/appkit npm](https://www.npmjs.com/package/@reown/appkit) — Version 1.8.17 confirmed
- [BNB Chain Telegram Mini-dApps Guide](https://www.bnbchain.org/en/blog/building-telegram-mini-dapps-on-bnb-chain) — Official BSC + Telegram guidance
- [Foundry Book](https://book.getfoundry.sh/getting-started/installation) — Official Foundry documentation
- [forge-std Releases](https://github.com/foundry-rs/forge-std/releases) — Version 1.14.0 confirmed (Jan 5, 2026)
- [OpenZeppelin Contracts v5 Docs](https://docs.openzeppelin.com/contracts/5.x) — Current version documentation
- [wagmi npm](https://www.npmjs.com/package/wagmi) — Version 3.4.2 confirmed
- [viem npm](https://www.npmjs.com/package/viem) — Version 2.45.2 confirmed
- [@tanstack/react-query npm](https://www.npmjs.com/package/@tanstack/react-query) — Version 5.90.20 confirmed
- [BSC Testnet Faucet](https://www.bnbchain.org/en/testnet-faucet) — Official faucet
- [BSC RPC Endpoints](https://docs.bnbchain.org/bnb-smart-chain/developers/json_rpc/json-rpc-endpoint/) — Official RPC docs
- [Next.js npm](https://www.npmjs.com/package/next) — Version 16.1.6 confirmed
- [React npm](https://www.npmjs.com/package/react) — Version 19.2.4 confirmed
- [TypeScript npm](https://www.npmjs.com/package/typescript) — Version 5.9.3 confirmed
- [TailwindCSS npm](https://www.npmjs.com/package/tailwindcss) — Version 4.1.18 confirmed

### Medium Confidence (WebSearch, Multiple Sources Agree)

- [Foundry vs Hardhat Performance](https://metamask.io/news/hardhat-vs-foundry-choosing-the-right-ethereum-development-tool) — 10-50x speed difference cited
- [Foundry vs Hardhat (Chainstack)](https://chainstack.com/foundry-hardhat-differences-performance/) — Performance benchmarks, DX comparison
- [Foundry vs Hardhat (ThreeSigma)](https://threesigma.xyz/blog/foundry/foundry-vs-hardhat-solidity-testing-tools) — Testing comparison
- [Ethers vs Viem](https://jamesbachini.com/ethers-vs-viem/) — Bundle size comparison (27KB vs 130KB)
- [wagmi Ethers Adapters](https://wagmi.sh/react/guides/ethers) — Migration guidance, compatibility notes
- [Why Viem](https://viem.sh/docs/introduction) — Official docs, design rationale
- [Next.js Vercel Deployment](https://nextjs.org/learn-pages-router/basics/deploying-nextjs-app/platform-details) — Official deployment guide
- [TanStack Query Overview](https://tanstack.com/query/latest/docs/framework/react/overview) — Official docs
- [Pyth on BNB Chain Launch](https://www.pyth.network/blog/pyth-launches-price-oracles-on-bnb-chain-and-bas-testnet) — BSC integration announcement
- [Telegram Mini Apps React Template](https://github.com/Telegram-Mini-Apps/reactjs-template) — Official template showing Next.js usage
- [Building Telegram Mini Apps with React](https://blog.logrocket.com/building-telegram-mini-apps-react/) — Integration patterns
- [OpenZeppelin Foundry Upgrades](https://github.com/OpenZeppelin/openzeppelin-foundry-upgrades) — Upgradeable contracts (anti-pattern for hackathon)
- [BSC Testnet Info](https://thirdweb.com/binance-testnet) — Chain settings, RPC endpoints

### Low Confidence / Context
- None — All critical stack recommendations verified through official sources or npm registry as of 2026-02-10

---
*Stack research for: Strike - Binary Prediction Market on BNB Smart Chain with Telegram Mini App*
*Researched: 2026-02-10*
*Timeline: 9 days (hackathon deadline Feb 19, 2026)*
*Builder Context: Works at Douro Labs (Pyth), deep Pyth oracle expertise*
