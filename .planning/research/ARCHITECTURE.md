# Architecture Research

**Domain:** Parimutuel Prediction Market on BSC with Telegram Mini-App
**Researched:** 2026-02-10
**Confidence:** MEDIUM-HIGH

## Standard Architecture

### System Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                      TELEGRAM MINI-APP LAYER                         │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │  Next.js Frontend (Vercel)                                    │   │
│  │  - Telegram SDK (@twa-dev/sdk)                                │   │
│  │  - WalletConnect/Reown AppKit for BSC                         │   │
│  │  - Real-time market display & betting UI                      │   │
│  └───────────┬──────────────────────────────┬───────────────────┘   │
└──────────────┼──────────────────────────────┼───────────────────────┘
               │ (WebSocket events)            │ (RPC calls)
               ↓                               ↓
┌──────────────┴───────────────────────────────┴───────────────────────┐
│                      INDEXING & STATE LAYER                           │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │  Event Indexer (Optional for 9-day MVP)                       │   │
│  │  - Direct RPC polling for hackathon                           │   │
│  │  - Future: Ormi, Goldsky, or The Graph Network (NOT hosted)   │   │
│  └──────────────────────────────────────────────────────────────┘   │
└───────────────────────────────────────────────────────────────────────┘
               ↑ (reads events)
┌──────────────┴───────────────────────────────────────────────────────┐
│                      SMART CONTRACT LAYER (BSC)                       │
│  ┌───────────────────────┐  ┌──────────────────────────────────┐    │
│  │  MarketFactory        │  │  Market (Minimal Proxy Clone)    │    │
│  │  - Create markets     │  │  - Accept bets (UP/DOWN)         │    │
│  │  - Track all markets  │  │  - Store pool state              │    │
│  │  - Registry lookup    │  │  - Finite state machine          │    │
│  └───────────┬───────────┘  │  - Resolve via Pyth              │    │
│              │              │  - Distribute payouts (pull)     │    │
│              │ deploys      └──────────────┬───────────────────┘    │
│              └─────────────────────────────┘                         │
│                                                                       │
│  ┌───────────────────────┐  ┌──────────────────────────────────┐    │
│  │  IPyth Interface      │  │  FeeCollector                    │    │
│  │  - Pull oracle reads  │  │  - Protocol fee storage          │    │
│  │  - Price verification │  │  - Fee withdrawal                │    │
│  └───────────────────────┘  └──────────────────────────────────┘    │
└───────────────────────────────────────────────────────────────────────┘
               ↓ (reads from)
┌──────────────┴───────────────────────────────────────────────────────┐
│                      ORACLE LAYER                                     │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │  Pyth Network (BSC deployment)                                │   │
│  │  - BTC/USD and BNB/USD price feeds                            │   │
│  │  - Pull-based updates (permissionless)                        │   │
│  │  - Cryptographic price verification                           │   │
│  └──────────────────────────────────────────────────────────────┘   │
└───────────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Typical Implementation |
|-----------|----------------|------------------------|
| **MarketFactory** | Creates markets using clone pattern, maintains registry, emits events | Solidity contract with `Clones.clone()` from OpenZeppelin, 50%+ gas savings per deployment |
| **Market** | Individual parimutuel pool with state machine (Open → Closed → Resolved → Cancelled), manages betting and payouts | Minimal proxy clone implementing initialization pattern, uses nested mappings for O(1) bet lookups |
| **IPyth Interface** | Reads and verifies Pyth oracle prices with staleness checks | Interface from `@pythnetwork/pyth-sdk-solidity`, pull-based updates only when needed |
| **FeeCollector** | Accumulates protocol fees (2-5% of winnings), owner withdrawal | Simple contract or integrated into Market with access control |
| **Telegram Mini-App** | User interface within Telegram messenger | Next.js 14+ with App Router, deployed to Vercel, Telegram SDK for native features |
| **WalletConnect Integration** | BSC wallet connection from Telegram (MetaMask, Trust Wallet, etc.) | Reown AppKit (formerly WalletConnect AppKit) with EVM chain support, works in Telegram out-of-box as of 2026 |
| **Event Indexer** | Syncs blockchain state to frontend, reduces RPC calls | Direct RPC for MVP (<1k users), Ormi/Goldsky/The Graph Network for production (hosted service deprecated 2026) |

## Recommended Project Structure

```
strike/
├── contracts/                    # Smart contracts (Foundry recommended)
│   ├── src/
│   │   ├── Market.sol           # Individual market logic with state machine
│   │   ├── MarketFactory.sol    # Factory deploying minimal proxy clones
│   │   ├── FeeCollector.sol     # Protocol fee management
│   │   └── interfaces/
│   │       ├── IMarket.sol
│   │       ├── IMarketFactory.sol
│   │       └── IPyth.sol        # From Pyth SDK
│   ├── test/
│   │   ├── Market.t.sol         # Solidity tests (2-5x faster than JS)
│   │   ├── MarketFactory.t.sol
│   │   └── integration/
│   │       └── EndToEnd.t.sol   # Full flow tests
│   ├── script/
│   │   ├── Deploy.s.sol         # Deployment script
│   │   └── CreateMarket.s.sol   # Market creation helper
│   └── foundry.toml
│
├── frontend/                     # Telegram mini-app
│   ├── app/                     # Next.js 14+ app directory
│   │   ├── layout.tsx
│   │   ├── page.tsx             # Main market list view
│   │   ├── market/[id]/
│   │   │   └── page.tsx         # Individual market detail & betting
│   │   └── positions/
│   │       └── page.tsx         # User positions & claim UI
│   ├── components/
│   │   ├── MarketCard.tsx       # Market display component
│   │   ├── BetForm.tsx          # UP/DOWN betting interface
│   │   ├── WalletButton.tsx     # WalletConnect button
│   │   └── ClaimButton.tsx      # Claim winnings button
│   ├── lib/
│   │   ├── contracts/           # ABIs, addresses by network
│   │   │   ├── abis/
│   │   │   └── addresses.ts     # Network-keyed addresses
│   │   ├── telegram.ts          # Telegram SDK integration
│   │   ├── wallet.ts            # WalletConnect/Reown setup
│   │   ├── blockchain.ts        # Web3 provider & contract instances
│   │   └── hooks/
│   │       ├── useMarkets.ts    # Fetch all markets with event listening
│   │       ├── useBet.ts        # Place bet transaction
│   │       ├── usePositions.ts  # User position tracking
│   │       └── useClaim.ts      # Claim payout transaction
│   ├── public/
│   └── package.json
│
├── scripts/                      # Automation (optional for hackathon)
│   ├── keeper-resolve.ts        # Resolver bot (checks expired markets)
│   └── auto-create-markets.ts   # Scheduled market creation
│
├── .env.example
├── README.md
└── PLAN.md
```

### Structure Rationale

- **contracts/ with Foundry**: 2-5x faster compile and test times vs Hardhat. Solidity tests match contract language (no context switching). Better gas profiling. Modern DX. Critical for 9-day timeline.
- **frontend/app/**: Next.js 14 App Router for server components and API routes. Vercel deployment out-of-box. Telegram SDK requires React.
- **lib/ folder**: Centralized Web3 logic (wallet, blockchain, hooks) keeps components clean and testable. Addresses separated by network for easy testnet/mainnet switching.
- **Separation of concerns**: Contracts self-contained with own test suite. Frontend consumes ABIs and addresses. No tight coupling.
- **Optional scripts/**: Automation useful post-hackathon but not MVP blocker. Can manually create markets and resolve for 9 days.

## Architectural Patterns

### Pattern 1: Factory + Minimal Proxy (Clone) Pattern

**What:** MarketFactory deploys lightweight clones (EIP-1167) of a Market implementation contract. Each clone is a minimal proxy that delegates all calls to the implementation. Reduces deployment gas by 50%+ per market.

**When to use:** When deploying multiple instances of similar contracts. Perfect for auto-created markets (hourly, 4hr, 24hr windows). Industry standard for multi-instance contracts.

**Trade-offs:**
- **Pros**: 50%+ gas savings on deployment, clean separation of factory and market logic, easier upgrades (deploy new factory)
- **Cons**: Slight additional complexity (initialization pattern), clone contracts must use delegatecall-safe implementation

**Example:**
```solidity
// MarketFactory.sol
import "@openzeppelin/contracts/proxy/Clones.sol";

contract MarketFactory {
    address public immutable marketImplementation;
    address public immutable pythOracle;
    address[] public allMarkets;

    event MarketCreated(address indexed market, bytes32 priceId, uint256 expiry);

    constructor(address _pythOracle) {
        pythOracle = _pythOracle;
        marketImplementation = address(new Market());
    }

    function createMarket(
        bytes32 priceId,      // BTC/USD or BNB/USD Pyth price ID
        uint256 duration,     // 1hr, 4hr, or 24hr in seconds
        uint256 feePercent    // Protocol fee (e.g., 250 = 2.5%)
    ) external returns (address) {
        address clone = Clones.clone(marketImplementation);

        Market(clone).initialize(
            pythOracle,
            priceId,
            block.timestamp,
            block.timestamp + duration,
            feePercent
        );

        allMarkets.push(clone);
        emit MarketCreated(clone, priceId, block.timestamp + duration);
        return clone;
    }

    function getMarketCount() external view returns (uint256) {
        return allMarkets.length;
    }
}
```

### Pattern 2: Finite State Machine for Market Lifecycle

**What:** Each Market contract implements explicit state machine: `Open` (accepting bets) → `Closed` (betting ended) → `Resolved` (winner declared) or `Cancelled` (refunds). State transitions enforced via modifiers with automatic timeout handling.

**When to use:** Essential for parimutuel markets where actions are time-dependent and irreversible. Prevents invalid operations (betting after close, resolving before expiry).

**Trade-offs:**
- **Pros**: Clear lifecycle, impossible invalid state transitions, explicit error messages, easier reasoning
- **Cons**: Slightly higher gas for state checks, requires careful timeout handling

**Example:**
```solidity
// Market.sol
contract Market {
    enum State { Open, Closed, Resolved, Cancelled }
    State public state;

    uint256 public startTime;
    uint256 public expiryTime;
    uint256 public resolutionDeadline; // expiryTime + 24hr grace period

    modifier inState(State _state) {
        require(state == _state, "Invalid state");
        _;
    }

    // Automatic state transition based on time
    modifier checkTimeout() {
        if (state == State.Open && block.timestamp >= expiryTime) {
            state = State.Closed;
        }
        if (state == State.Closed && block.timestamp >= resolutionDeadline) {
            state = State.Cancelled; // Auto-cancel if not resolved
        }
        _;
    }

    function bet(bool predictUp) external payable inState(State.Open) checkTimeout {
        require(msg.value > 0, "Bet must be > 0");
        // Track bet in nested mapping...
    }

    function resolve(bytes[] calldata pythUpdateData)
        external
        payable
        inState(State.Closed)
        checkTimeout
    {
        // Permissionless resolution (anyone can call)
        // Fetch Pyth price and determine winner...
        state = State.Resolved;
    }

    function claim() external inState(State.Resolved) {
        // Winners pull their payouts...
    }

    function refund() external inState(State.Cancelled) {
        // All bettors get original bets back...
    }
}
```

### Pattern 3: Nested Mapping for Bet Tracking (Parimutuel Pool)

**What:** Use `mapping(bool => mapping(address => uint256))` for individual bets (outcome → user → amount) and `mapping(bool => uint256)` for totals per outcome. Enables O(1) lookups and gas-efficient storage.

**When to use:** Standard pattern for parimutuel betting. Need per-user bet amounts and per-outcome totals for proportional payout calculation.

**Trade-offs:**
- **Pros**: O(1) lookups, gas-efficient, no unbounded iterations, prevents gas limit issues
- **Cons**: Cannot enumerate all bettors on-chain (use events for indexing), must handle multiple bets from same user carefully

**Example:**
```solidity
contract Market {
    // Outcome (true=UP, false=DOWN) => User => Bet Amount
    mapping(bool => mapping(address => uint256)) public bets;

    // Outcome => Total Bets
    mapping(bool => uint256) public totalBets;

    uint256 public totalPool;
    bool public upWon;
    uint256 public feePercent; // In basis points (250 = 2.5%)

    function bet(bool predictUp) external payable inState(State.Open) checkTimeout {
        require(msg.value > 0, "Bet must be > 0");

        bets[predictUp][msg.sender] += msg.value;
        totalBets[predictUp] += msg.value;
        totalPool += msg.value;

        emit BetPlaced(msg.sender, predictUp, msg.value);
    }

    function claim() external inState(State.Resolved) {
        uint256 userBet = bets[upWon][msg.sender];
        require(userBet > 0, "No winning bet");

        // Calculate proportional payout:
        // (userBet / totalWinningBets) * (totalPool - fees)
        uint256 feeAmount = (totalPool * feePercent) / 10000;
        uint256 netPool = totalPool - feeAmount;
        uint256 payout = (userBet * netPool) / totalBets[upWon];

        // Prevent re-claiming
        bets[upWon][msg.sender] = 0;

        payable(msg.sender).transfer(payout);
        emit Claimed(msg.sender, payout);
    }
}
```

### Pattern 4: Pyth Pull Oracle Integration

**What:** Pyth uses pull model where anyone submits price updates on-chain before reading. Contracts call `pyth.updatePriceFeeds()` with signed data, then `getPriceNoOlderThan()` to read validated price. Only pay for updates when needed (not continuous pushes).

**When to use:** For strike price capture (market start) and resolution (market end). Not during betting phase. Reduces oracle costs 99%+ vs push oracles for sporadic reads.

**Trade-offs:**
- **Pros**: Gas-efficient (only update when needed), always fresh data, permissionless updates, cryptographically verified
- **Cons**: Resolver must fetch update data from Pyth Hermes API, small update fee required, slightly more complex than push oracle

**Example:**
```solidity
import "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";

contract Market {
    IPyth public immutable pyth;
    bytes32 public immutable priceId; // BTC/USD or BNB/USD

    int64 public strikePrice;
    int64 public resolutionPrice;

    function captureStrikePrice(bytes[] calldata pythUpdateData)
        external
        payable
        inState(State.Open)
    {
        require(strikePrice == 0, "Strike already captured");
        require(block.timestamp >= startTime, "Not started");

        // Pay Pyth update fee
        uint256 fee = pyth.getUpdateFee(pythUpdateData);
        require(msg.value >= fee, "Insufficient update fee");
        pyth.updatePriceFeeds{value: fee}(pythUpdateData);

        // Read validated price (max 60s staleness)
        PythStructs.Price memory price = pyth.getPriceNoOlderThan(priceId, 60);
        strikePrice = price.price;

        emit StrikePriceCaptured(strikePrice, block.timestamp);
    }

    function resolve(bytes[] calldata pythUpdateData)
        external
        payable
        inState(State.Closed)
        checkTimeout
    {
        // Pay Pyth update fee
        uint256 fee = pyth.getUpdateFee(pythUpdateData);
        pyth.updatePriceFeeds{value: fee}(pythUpdateData);

        // Read price at/after expiry
        PythStructs.Price memory price = pyth.getPriceNoOlderThan(priceId, 60);
        require(price.publishTime >= expiryTime, "Price too old");

        resolutionPrice = price.price;
        upWon = resolutionPrice > strikePrice;

        // Pay small resolver reward (incentivizes permissionless resolution)
        uint256 resolverReward = (totalPool * 50) / 10000; // 0.5%
        payable(msg.sender).transfer(resolverReward);

        state = State.Resolved;
        emit MarketResolved(upWon, resolutionPrice, msg.sender);
    }
}
```

### Pattern 5: Permissionless Resolution with Keeper Incentive

**What:** Allow anyone to call `resolve()` after market expiry. Pay resolver small fee (0.1-0.5% of pool) as economic incentive. Prevents markets from getting stuck if no one triggers resolution.

**When to use:** Critical for decentralization and liveness. Without this, markets depend on single resolver address (centralization risk).

**Trade-offs:**
- **Pros**: Censorship-resistant, no single point of failure, resolver competition ensures timely resolution, economically incentivized participation
- **Cons**: Small resolver fee reduces pool (typically 0.5%), potential for MEV if resolution timing is profitable

**Example:**
```solidity
contract Market {
    uint256 public constant RESOLVER_FEE = 50; // 0.5% in basis points

    function resolve(bytes[] calldata pythUpdateData)
        external
        payable
        inState(State.Closed)
    {
        require(block.timestamp >= expiryTime, "Not expired");

        // Fetch Pyth price and determine winner...
        // (see Pattern 4 for full implementation)

        // Reward resolver (msg.sender can be anyone)
        uint256 reward = (totalPool * RESOLVER_FEE) / 10000;
        payable(msg.sender).transfer(reward);

        state = State.Resolved;
        emit MarketResolved(upWon, resolutionPrice, msg.sender);
    }
}
```

### Pattern 6: Event-Driven Frontend State Sync

**What:** Frontend listens to contract events via WebSocket to update UI in real-time. Use React hooks to subscribe to events (`BetPlaced`, `MarketResolved`) and update local state without polling.

**When to use:** For live market updates, bet confirmations, resolution notifications. Significantly better UX than polling every 5-10 seconds.

**Trade-offs:**
- **Pros**: Real-time updates, lower RPC load (no constant polling), better UX, React hooks make it clean
- **Cons**: Requires WebSocket RPC provider, need reconnection logic, event ordering edge cases

**Example:**
```typescript
// lib/hooks/useMarkets.ts
import { useEffect, useState } from 'react';
import { marketFactoryContract } from '../blockchain';

interface Market {
  address: string;
  priceId: string;
  expiryTime: number;
  totalPool: bigint;
}

export function useMarkets() {
  const [markets, setMarkets] = useState<Market[]>([]);

  useEffect(() => {
    // Initial fetch of all markets
    async function loadMarkets() {
      const count = await marketFactoryContract.getMarketCount();
      const addresses = await marketFactoryContract.getAllMarkets();
      // Fetch details for each market...
      setMarkets(marketData);
    }
    loadMarkets();

    // Listen for new markets
    const filter = marketFactoryContract.filters.MarketCreated();

    const handleMarketCreated = (marketAddress: string, priceId: string, expiry: bigint) => {
      setMarkets(prev => [...prev, {
        address: marketAddress,
        priceId,
        expiryTime: Number(expiry),
        totalPool: 0n
      }]);
    };

    marketFactoryContract.on(filter, handleMarketCreated);

    // Cleanup listener on unmount
    return () => {
      marketFactoryContract.off(filter, handleMarketCreated);
    };
  }, []);

  return markets;
}
```

## Data Flow

### Flow 1: Market Creation (Automated)

```
Keeper Bot / Cron Job (every 1hr/4hr/24hr)
    ↓
MarketFactory.createMarket(priceId, duration, fee)
    ↓
Deploy minimal proxy clone of Market implementation
    ↓
Initialize clone: Market.initialize(pythOracle, priceId, times, fee)
    ↓
Store market address in allMarkets[] array
    ↓
Emit MarketCreated(marketAddress, priceId, expiry) event
    ↓
Frontend event listener catches event
    ↓
Add new market to UI market list (real-time)
```

**For 9-day hackathon:** Skip automated keeper. Manually call `createMarket()` via Foundry script or frontend admin panel.

### Flow 2: Placing a Bet

```
User opens Telegram mini-app
    ↓
Views market list (BTC 1HR UP/DOWN, BNB 4HR UP/DOWN, etc.)
    ↓
Clicks market → sees current strike price, time remaining, pool sizes
    ↓
Clicks "Bet UP" or "Bet DOWN"
    ↓
Enters bet amount (e.g., 0.1 BNB)
    ↓
WalletConnect modal prompts wallet approval (MetaMask, Trust Wallet)
    ↓
User signs transaction
    ↓
Market.bet(true) executes on BSC (true = UP, false = DOWN)
    ↓
Contract validates: state=Open, amount>0, timestamp<expiry
    ↓
Update storage: bets[isUp][user] += amount, totalBets[isUp] += amount, totalPool += amount
    ↓
Emit BetPlaced(user, isUp, amount) event
    ↓
Frontend event listener catches event
    ↓
Update UI: pool size, user position, potential payout
```

### Flow 3: Market Resolution (Permissionless)

```
block.timestamp >= expiryTime (market expired)
    ↓
Keeper bot (or any user) detects expired market
    ↓
Fetch Pyth price update data from Hermes API
    ↓
Call Market.resolve(pythUpdateData) with update fee
    ↓
Contract validates: state=Closed (auto-transitioned from Open), timestamp>=expiry
    ↓
Pay Pyth update fee → Pyth.updatePriceFeeds(pythUpdateData)
    ↓
Pyth contract verifies cryptographic signature, stores price
    ↓
Market reads: Pyth.getPriceNoOlderThan(priceId, 60)
    ↓
Compare resolutionPrice vs strikePrice
    ↓
Determine winner: upWon = (resolutionPrice > strikePrice)
    ↓
Pay resolver reward (0.5% of pool)
    ↓
Set state = Resolved
    ↓
Emit MarketResolved(upWon, resolutionPrice, resolver) event
    ↓
Frontend event listener catches event
    ↓
Update market status to "Resolved", show winning outcome
    ↓
Enable "Claim" button for winners
```

### Flow 4: Claiming Payout (Pull-Based)

```
User navigates to "My Positions" tab
    ↓
Frontend reads: Market.bets(upWon, userAddress)
    ↓
Show list of winning positions with "Claim" button
    ↓
User clicks "Claim"
    ↓
WalletConnect prompts signature
    ↓
Market.claim() executes
    ↓
Contract validates: state=Resolved, user has winning bet
    ↓
Calculate payout: (userBet / totalWinningBets) * (totalPool - fees)
    ↓
Set bets[upWon][user] = 0 (prevent re-claiming)
    ↓
Transfer payout to user
    ↓
Emit Claimed(user, payout) event
    ↓
Frontend removes position from claimable list
    ↓
User wallet balance updated
```

### Flow 5: Refund (Cancelled Market)

```
Market not resolved within grace period (expiryTime + 24hr)
    ↓
Automatic state transition: state = Cancelled
    ↓
User navigates to "My Positions"
    ↓
Frontend shows "Refund" button for positions in cancelled markets
    ↓
User clicks "Refund"
    ↓
Market.refund() executes
    ↓
Contract validates: state=Cancelled, user has bet
    ↓
Calculate refund: bets[true][user] + bets[false][user] (both sides)
    ↓
Set bets to 0
    ↓
Transfer original bet amount back to user
    ↓
Emit Refunded(user, amount) event
```

## Scaling Considerations

| Scale | Architecture Adjustments |
|-------|--------------------------|
| **0-1k users (9-day MVP)** | Direct RPC calls for market data. No indexer needed. Vercel frontend handles traffic. Single MarketFactory contract. Manual market creation and resolution acceptable. |
| **1k-10k users** | Add event indexer (Ormi, Goldsky, or The Graph Network - NOT hosted service). Cache market list in frontend with 5s TTL. Consider rate limiting on RPC provider (upgrade from free tier). WebSocket for event listening. |
| **10k-100k users** | **Must have** subgraph for efficient querying. Dedicated RPC node (Alchemy/QuickNode paid plan). Implement pagination for market lists. Add Redis cache for frequently accessed data. Multi-region frontend deployment. |
| **100k+ users** | Dedicated BSC archive node for historical queries. Multi-region RPC with failover. Consider L2 migration (opBNB optimistic rollup) for lower fees. Separate keeper infrastructure with redundancy. CDN for static assets. |

### Scaling Priorities

1. **First bottleneck (5k-10k users):** RPC rate limits hit when polling for markets and positions. **Fix:** Deploy subgraph for event indexing, batch RPC calls with multicall pattern, upgrade to paid RPC tier.

2. **Second bottleneck (50k+ users):** Market creation gas costs become prohibitive if creating many markets. **Fix:** Optimize clone implementation size (minimal storage in implementation), batch creations where possible, consider gas token for fee reduction.

3. **Third bottleneck (100k+ users):** BSC network congestion affects UX during peak times. **Fix:** Consider L2 (opBNB launched on BSC in 2024), implement Layer 2 bridges, or explore alternative chains.

**For 9-day hackathon:** Only worry about 0-1k users scale. Direct RPC polling every 5-10s is fine. Skip indexer completely.

## Anti-Patterns

### Anti-Pattern 1: Using The Graph Hosted Service in 2026

**What people do:** Follow old tutorials showing deployment to The Graph hosted service.

**Why it's wrong:** The Graph hosted service was **fully deprecated in 2026**. Subgraphs must now use The Graph Network (requires GRT staking and more complex setup) or alternative platforms.

**Do this instead:**
- For hackathon: Skip indexer entirely, poll RPC directly (sufficient for <1k users)
- For production: Use The Graph Network, Ormi, Goldsky, or Envio (all support BSC as of 2026)

### Anti-Pattern 2: Push Oracle for Continuous Price Updates

**What people do:** Subscribe to Chainlink-style push oracles that update prices every block or minute.

**Why it's wrong:** Extremely expensive. You only need prices at two moments: market start (strike) and market end (resolution). Paying for continuous updates wastes 99%+ of gas.

**Do this instead:** Use Pyth's pull-based model. Only fetch and verify price when needed (strike capture and resolution). Drastically cheaper for sporadic reads.

### Anti-Pattern 3: Storing All Bettors in Array for Payout Distribution

**What people do:** Maintain `address[] public bettors` and iterate to send payouts in `resolve()`.

**Why it's wrong:** Unbounded gas costs. Fails when array exceeds ~100-500 bettors (hits block gas limit). Makes contract unusable at scale.

**Do this instead:** Pull-based payouts with mappings. Users call `claim()` to pull their winnings. No iteration needed. O(1) gas cost per claim.

### Anti-Pattern 4: Insufficient Pyth Price Staleness Checks

**What people do:** Accept any Pyth price data without checking `publishTime`, assuming it's fresh.

**Why it's wrong:** In volatile markets, stale prices (even 1-2 minutes old) can be exploited. Attackers cherry-pick favorable timestamps if you don't enforce freshness.

**Do this instead:** Always use `pyth.getPriceNoOlderThan(priceId, 60)` with strict max age (30-60s). Reject resolution with stale data. Prevents price manipulation.

### Anti-Pattern 5: Centralized Resolution (Owner-Only)

**What people do:** Only allow contract owner or specific address to call `resolve()`.

**Why it's wrong:** Single point of failure. If resolver goes offline, markets stuck indefinitely. Users can't claim winnings. Defeats purpose of decentralized market.

**Do this instead:** Permissionless resolution. Anyone can call `resolve()` after expiry. Incentivize with small fee (0.5% of pool). Ensures liveness and censorship resistance.

### Anti-Pattern 6: Hardcoding Contract Addresses in Components

**What people do:** Put contract addresses directly in React component files.

**Why it's wrong:** Makes switching networks (testnet/mainnet) or redeployment painful. No single source of truth. Error-prone.

**Do this instead:**
```typescript
// lib/contracts/addresses.ts
export const ADDRESSES = {
  97: { // BSC Testnet
    marketFactory: "0x...",
    pyth: "0x..."
  },
  56: { // BSC Mainnet
    marketFactory: "0x...",
    pyth: "0x..."
  }
} as const;

// Usage in components
const chainId = useChainId();
const factoryAddress = ADDRESSES[chainId].marketFactory;
```

### Anti-Pattern 7: Assuming TON Wallet for Telegram Mini-Apps

**What people do:** Use TON Connect because many Telegram mini-app tutorials show TON blockchain integration.

**Why it's wrong:** Telegram supports **any** blockchain. BSC requires EVM wallets (MetaMask, Trust Wallet) via WalletConnect, not TON wallets.

**Do this instead:** Use Reown AppKit (formerly WalletConnect AppKit) which supports Telegram mini-apps with EVM chains including BSC out-of-box as of 2026. Configure BSC chain ID (56 mainnet, 97 testnet).

### Anti-Pattern 8: Iterating Over All Markets On-Chain

**What people do:** Loop through `allMarkets[]` array in contract view function to filter/aggregate data.

**Why it's wrong:** Unbounded gas even for view calls. RPC providers reject large responses. Doesn't scale past ~50-100 markets.

**Do this instead:** Emit events for market creation. Index events off-chain (subgraph or frontend). Use pagination for on-chain queries. Never iterate unbounded arrays.

## Integration Points

### External Services

| Service | Integration Pattern | Notes |
|---------|---------------------|-------|
| **Pyth Network** | Pull-based oracle via `IPyth` interface. Call `pyth.updatePriceFeeds()` with signed data from Hermes API, then `getPriceNoOlderThan()` to read validated price. | BSC Pyth address from [official docs](https://docs.pyth.network/price-feeds/core/pull-updates). Requires small update fee (~0.001 BNB). BTC/USD and BNB/USD price IDs available. |
| **WalletConnect/Reown AppKit** | SDK for wallet connection in Telegram mini-app. Configure with BSC chain ID and project ID from WalletConnect Cloud. | Works in Telegram mini-apps by default (2026). Test on mobile Telegram thoroughly. Handle user rejection gracefully. |
| **BSC RPC** | JSON-RPC via Alchemy, Infura, QuickNode, or public endpoints. Use ethers.js or viem. | Free tier sufficient for MVP (<1k users). Paid tier for production (higher rate limits, archive node). Consider fallback RPC URLs for redundancy. |
| **Pyth Hermes API** | REST API for fetching price update data. GET `/latest_price_feeds?ids[]=<priceId>` returns signed update data for on-chain submission. | Free API, no authentication needed. Returns VAA (Verifiable Action Approval) for on-chain verification. Cache responses for 30s max. |
| **Telegram SDK** | `@twa-dev/sdk` for mini-app context (user ID, theme, main button). Access via `window.Telegram.WebApp`. | Provides haptic feedback, theme colors, user data. Test with actual Telegram app, not just browser. |
| **Vercel** | Next.js deployment via GitHub integration. Set environment variables in dashboard (RPC URL, contract addresses). | Auto-deploys on push to main. Edge functions for API routes. Free tier sufficient for hackathon. |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| **Frontend ↔ Contracts** | ethers.js/viem via RPC. Read calls (view functions) are free. Write calls (transactions) require gas and wallet signature. | Use typed ABIs (generate with `wagmi generate` or manually). Handle errors: user rejection, insufficient gas, revert messages. |
| **Factory ↔ Market Instances** | Factory deploys markets via `Clones.clone()` but does not control them post-creation. Markets are independent contracts. | Minimal coupling. Factory only tracks addresses in `allMarkets[]`. Markets don't reference factory. Clean separation. |
| **Market ↔ Pyth Oracle** | Market calls Pyth contract's `updatePriceFeeds()` (payable) and `getPriceNoOlderThan()` (view). Pyth contract is external dependency. | Pyth address immutable in market initialization. If Pyth upgrades, deploy new markets with new address. Existing markets unaffected (isolation). |
| **Frontend ↔ Telegram** | Telegram SDK via `window.Telegram.WebApp`. Access user context, theme, buttons, haptic feedback. | One-way communication (frontend reads from Telegram). No backend Telegram Bot API needed for mini-app UI. |
| **Frontend ↔ Wallet** | WalletConnect modal for account connection and transaction signing. User approves each transaction in their wallet app. | Async operations. Handle pending states, user rejection, network errors. Test with actual wallets (MetaMask, Trust Wallet) not just test accounts. |

## 9-Day Hackathon Build Order

### Phase 1: Foundation (Days 1-2) — Parallel Workstreams

**Stream A - Smart Contracts (1-2 developers):**
1. Set up Foundry project (`forge init`)
2. Implement basic `Market.sol` (state machine, bet tracking, claim logic)
3. Write unit tests for market states and transitions
4. Add parimutuel payout calculation with tests
5. Mock Pyth interface for testing (hardcode prices)

**Stream B - Frontend Setup (1-2 developers):**
1. Set up Next.js project with Telegram SDK
2. Implement basic UI (market list, market detail pages)
3. Configure WalletConnect with BSC testnet
4. Test wallet connection in Telegram app (critical - deploy early to test!)
5. Create placeholder contract interaction hooks

**Goal by end of Day 2:** Disconnected pieces working independently. Contracts have basic betting logic with tests. Frontend can connect wallet in Telegram and show mock market data.

**Critical checkpoint:** If WalletConnect doesn't work in Telegram by Day 2, escalate immediately. This is a blocker.

### Phase 2: Integration (Days 3-5)

**Stream A - Contracts:**
1. Implement `MarketFactory.sol` with clone pattern
2. Integrate real Pyth interface (strike price capture, resolution)
3. Deploy to BSC testnet (get test BNB from faucet)
4. Test market creation + Pyth price reads on testnet
5. Add `FeeCollector.sol` and wire up protocol fees

**Stream B - Frontend:**
1. Connect frontend to deployed contracts (import ABIs, add addresses)
2. Implement market listing from factory (`getAllMarkets()`)
3. Implement bet placement UI with wallet transaction
4. Add position tracking (read user bets from contract)
5. Handle transaction states (pending, success, error)

**Integration tasks (both streams):**
- Share deployed contract addresses and ABIs
- Test complete flow: create market → view in frontend → place bet → see position
- Fix bugs in contract/frontend interaction

**Goal by end of Day 5:** Working end-to-end flow on testnet. User can view markets, place bets, see positions. Resolution can be done manually via Foundry script.

**Critical checkpoint:** If E2E flow not working by Day 5, cut features: skip factory pattern (single market contract), skip auto-creation (manual markets), focus on core betting + resolution.

### Phase 3: Polish & Features (Days 6-8)

**Both streams collaborate:**
1. Implement market resolution (either manual or simple keeper script)
2. Implement claim payout UI (winners call `claim()`)
3. Add real-time updates via event listeners (optional but nice UX)
4. Polish UI/UX: loading states, error messages, responsive design
5. Add market creation (simple admin panel or keep manual via script)
6. Test with multiple users and markets
7. Handle edge cases: cancelled markets, refunds, no bets on one side

**Optional features if time permits:**
- Automated market creation (cron job or manual schedule)
- Market countdown timers in UI
- Position profit/loss calculations
- Historical market view (past results)

**Goal by end of Day 8:** Production-ready MVP. All core features working: create market, bet, resolve, claim. UI is polished enough for demo.

**Critical checkpoint:** If core features not solid by Day 8, cut all optional features. Focus on bug fixes and demo preparation.

### Phase 4: Deploy & Demo (Day 9)

1. Final testing on testnet with full flow
2. **Decision point:** Deploy to BSC mainnet (if using real funds) OR stay on testnet (safer for hackathon)
3. Deploy frontend to Vercel (push to GitHub, auto-deploys)
4. Configure Telegram bot and mini-app link (Telegram BotFather)
5. Test complete flow in production Telegram app
6. Record demo video (3-5 min showing full user journey)
7. Prepare pitch deck / presentation (problem, solution, demo, tech stack)
8. Submit to hackathon platform before deadline

**Demo script:**
1. Open Telegram bot/mini-app
2. Connect wallet (show WalletConnect flow)
3. View active markets (BTC 1HR, BNB 4HR)
4. Place bet (UP on BTC)
5. Show position tracking
6. Manually resolve market (for demo timing control)
7. Claim winnings
8. Show protocol fee collection

**Goal:** Submitted project with working demo and clear value proposition.

### Critical Path Dependencies

```
Day 1-2: Contracts basic logic + Frontend basic UI (PARALLEL, no dependencies)
         ↓
Day 3: Deploy contracts to BSC testnet (BLOCKER for frontend integration)
         ↓
Day 3-4: Frontend connects to contracts (depends on deployed contracts)
         ↓
Day 4-5: End-to-end testing (depends on both working)
         ↓
Day 5: CHECKPOINT - Full betting flow must work (create → bet → resolve → claim)
         ↓
Day 6-8: Polish and features (can proceed if E2E working)
         ↓
Day 8: CHECKPOINT - Production-ready MVP (all core features solid)
         ↓
Day 9: Production deployment and demo (depends on stable MVP)
```

### Fallback Plan (Minimal Viable Product)

If falling behind schedule, cut to absolute minimum:

**Contracts:**
- Single `Market.sol` (no factory pattern)
- Manual market creation via Foundry script
- Manual resolution via Foundry script (no keeper)
- Manual Pyth price updates (fetch from Pyth website)

**Frontend:**
- Single market view (hardcode market address)
- Basic betting UI (UP/DOWN buttons)
- Claim payout button for winners
- No historical view, no multi-market support

**This still demonstrates:**
- Parimutuel betting logic ✓
- Pyth oracle integration ✓
- Telegram mini-app ✓
- BSC deployment ✓
- WalletConnect wallet integration ✓

**Build order for fallback:**
1. Day 1-2: Single market contract + basic frontend
2. Day 3-4: Deploy and integrate
3. Day 5-6: Test and fix bugs
4. Day 7-8: Polish demo flow
5. Day 9: Deploy and demo

## Architecture Decision Records

### ADR 1: Foundry vs Hardhat for Contract Development

**Decision:** Use Foundry.

**Rationale:**
- 2-5x faster compile and test times (critical for 9-day timeline)
- Solidity tests match contract language (no JS/TS context switching)
- Better gas profiling for optimization
- Modern DX with built-in formatting, fuzzing, symbolic execution
- Industry trend toward Foundry for new projects in 2026

**Alternatives considered:**
- Hardhat: Better for complex deployments and TypeScript integration, but slower tests
- Remix: Too limited for multi-contract project with tests

**Caveat:** If team has strong Hardhat experience (6+ months), stick with Hardhat. Tool familiarity > marginal speed gains for hackathon.

### ADR 2: Factory + Clone Pattern vs Single Monolithic Contract

**Decision:** Use factory with minimal proxy clones (EIP-1167).

**Rationale:**
- Need multiple markets (different assets, time windows, expiries)
- Clone pattern saves 50%+ gas per market deployment
- Clean separation: factory manages lifecycle, markets handle betting
- Industry standard for multi-instance contracts
- Easier to test individual markets in isolation

**Alternatives considered:**
- Single contract with `mapping(uint256 => Market)`: Complex state management, no gas savings, harder to reason about
- Full contract per market: 2-3x higher deployment costs, same benefits otherwise

### ADR 3: Direct RPC vs Subgraph for Market Data

**Decision:** Direct RPC polling for hackathon MVP. Add subgraph post-hackathon.

**Rationale:**
- The Graph hosted service deprecated in 2026 (can't use old tutorials)
- The Graph Network requires GRT staking and more complex setup
- Direct RPC sufficient for <1k users (hackathon scale)
- Saves 1-2 days of subgraph development time
- Can add Ormi/Goldsky/The Graph Network later for production

**Production path:** Deploy subgraph to Ormi or The Graph Network for >1k users scale.

### ADR 4: WalletConnect vs Other Wallet Solutions for Telegram

**Decision:** Use WalletConnect (Reown AppKit) for BSC wallet connection.

**Rationale:**
- Works with Telegram mini-apps out-of-box as of 2026
- Supports all major BSC wallets (MetaMask, Trust Wallet, Binance Wallet, etc.)
- Most crypto users already have compatible wallets
- Better UX than manual wallet address input
- Actively maintained with Telegram support

**Alternatives considered:**
- TON Connect: Only for TON blockchain, not BSC (wrong chain)
- Direct MetaMask injection: Doesn't work in Telegram mini-app context
- Magic Link / Web3Auth: Adds extra dependency, less crypto-native, custody concerns

### ADR 5: Automated Market Creation (On-Chain Scheduler vs Off-Chain Keeper)

**Decision:** Off-chain keeper (simple cron or manual) for hackathon. On-chain scheduler for production.

**Rationale:**
- On-chain scheduler adds 2-3 days development and testing time
- Hackathon doesn't require 24/7 automation (only 9 days)
- Can demonstrate with manual creation or simple cron job
- Easier to debug and modify during hackathon
- Economic incentives for on-chain scheduler require more design thought

**Production path:** Implement on-chain permissionless creation with incentive (anyone can call `createMarketIfDue()` and earn reward) or use Chainlink Automation/Gelato Network.

### ADR 6: Pull-Based Payouts vs Push-Based Distribution

**Decision:** Pull-based payouts (users call `claim()`).

**Rationale:**
- Gas-efficient: O(1) cost per claim, paid by user
- No unbounded iterations (doesn't fail at scale)
- Standard pattern for parimutuel markets
- Works with unknown number of winners
- Users pay gas only if they win (fair)

**Alternatives considered:**
- Push-based (contract sends to all winners in `resolve()`): Fails with >50-100 winners (gas limit), expensive, impractical

## Sources

### High Confidence (Official Documentation)
- [Pyth Network Developer Hub - Pull Oracle Integration](https://docs.pyth.network/price-feeds/core/pull-updates)
- [Pyth Network - Best Practices](https://docs.pyth.network/price-feeds/core/best-practices)
- [BNB Chain - Building Telegram Mini-dApps](https://www.bnbchain.org/en/blog/building-telegram-mini-dapps-on-bnb-chain)
- [OpenZeppelin - Clone Factory Pattern](https://soliditydeveloper.com/clonefactory)
- [Reown AppKit - Telegram Mini App Integration](https://reown.com/blog/how-to-build-a-telegram-mini-app)
- [The Graph - BSC Integration](https://www.bnbchain.org/en/blog/the-graph-brings-indexing-and-querying-to-binance-smart-chain)
- [Vercel - Next.js Deployment](https://vercel.com/frameworks/nextjs)

### Medium Confidence (Educational & Community Resources)
- [Chainstack - Foundry vs Hardhat Performance](https://chainstack.com/foundry-hardhat-differences-performance/)
- [Program the Blockchain - Parimutuel Wager Contract](https://programtheblockchain.com/posts/2018/05/08/writing-a-parimutuel-wager-contract/)
- [Smart Contract Research Forum - Keeper Bots](https://www.smartcontractresearch.org/t/keeper-transaction-automation-bots-in-the-smart-contract-ecosystem/478)
- [LogRocket - Factory Pattern Implementation](https://blog.logrocket.com/cloning-solidity-smart-contracts-factory-pattern/)
- [Medium - Solidity 2026 Patterns](https://medium.com/@Adekola_Olawale/solidity-2026-smart-contract-patterns-every-developer-should-know-a285923010e3)
- [Chainstack - Subgraph Indexing Platforms 2026](https://chainstack.com/top-5-hosted-subgraph-indexing-platforms-2026/)
- [MetaMask - Hardhat vs Foundry Comparison](https://metamask.io/news/hardhat-vs-foundry-choosing-the-right-ethereum-development-tool)

### Medium Confidence (2026 Market Research)
- [Reactive Network - Prediction Markets 2026](https://reactivenetwork.medium.com/prediction-markets-from-platforms-to-protocols-cbff3b9163e7)
- [iLink - Web3 Mini Apps in Telegram 2026](https://ilink.dev/blog/web3-mini-apps-in-telegram-why-this-is-the-fastest-way-to-launch-a-product)
- [SmartContract.tips - Pyth Oracle Integration](https://smartcontract.tips/en/post/leveraging-pyth-oracle-for-decentralized-applications)

### General Reference (Lower Confidence for Specific Implementation)
- [Wikipedia - Parimutuel Betting](https://en.wikipedia.org/wiki/Parimutuel_betting)
- [Web3 University - Smart Contract Integration](https://www.web3.university/article/integrating-your-smart-contract-with-the-frontend)
- [Consensys - Events and Logs in Ethereum](https://consensys.net/blog/developers/guide-to-events-and-logs-in-ethereum-smart-contracts/)

---
*Architecture research for: Strike - Parimutuel Prediction Market on BSC with Telegram Mini-App*
*Researched: 2026-02-10*
*Confidence: MEDIUM-HIGH*
*(Strong documentation for core patterns; Telegram+WalletConnect integration well-documented as of 2026; The Graph hosted service deprecation confirmed; Pyth pull oracle integration verified with official docs)*
