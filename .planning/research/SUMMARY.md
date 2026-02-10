# Research Summary: Strike Prediction Market

**Domain:** Binary UP/DOWN Prediction Markets on BNB Smart Chain with Telegram Mini-App Frontend
**Researched:** 2026-02-10
**Overall Confidence:** MEDIUM-HIGH

Stack decisions backed by official documentation and current ecosystem standards (HIGH). Feature prioritization informed by competitor analysis and Telegram Mini App best practices (MEDIUM-HIGH). Architecture patterns validated through Pyth integration guides and parimutuel contract examples (HIGH). Pitfalls catalogued from security audits, oracle documentation, and Web3 UX research (MEDIUM-HIGH).

## Executive Summary

Strike is positioned to deliver a functional prediction market MVP within the 9-day hackathon timeline by leveraging proven technologies and focusing ruthlessly on core betting mechanics. The research reveals four critical success factors:

**1. Technology Stack is Mature and Well-Integrated**

The recommended stack (Foundry + Solidity + Pyth + Next.js + Viem/Wagmi + Telegram SDK) represents current Web3 best practices as of Feb 2026. Each component has strong documentation, active maintenance, and demonstrated integration patterns. Foundry's 2-5x testing speed advantage over Hardhat directly addresses the tight timeline. Pyth's pull oracle model aligns perfectly with parimutuel market needs (price only needed at start and end). Telegram Mini Apps SDK provides the lowest-friction onboarding path for non-crypto users.

**2. Parimutuel Model Simplifies Complexity**

Compared to order book models (Polymarket) or AMM approaches (Azuro), parimutuel markets eliminate liquidity bootstrapping challenges and complex matching logic. All bets pool into two buckets (UP/DOWN), winners split the pot proportionally. This reduces smart contract complexity, testing surface area, and gas costs. PancakeSwap's successful deployment of parimutuel prediction markets on BSC provides validated reference implementation.

**3. Critical Pitfalls Have Known Prevention Patterns**

Seven critical pitfalls were identified, each with documented prevention strategies: reentrancy (use OpenZeppelin ReentrancyGuard), stale oracle prices (validate Pyth publishTime), division by zero (handle one-sided markets), timestamp manipulation (add lock periods), MEV front-running (separate market close from resolution), precision loss (use basis points), and oracle manipulation (verify Pyth confidence intervals). These are not novel research problems—they're solved patterns requiring disciplined implementation.

**4. Telegram Distribution Advantage Requires UX Discipline**

Telegram Mini Apps reach 900M+ users but have different UX expectations than Web3 dApps. Users expect instant engagement (no wallet-first prompts), mobile-optimized interfaces (90% on mobile), and Telegram-native interactions (BackButton, MainButton, haptics). WalletConnect requires Telegram-specific configuration to avoid connection failures. The research emphasizes showing value BEFORE requesting wallet connection—a departure from standard Web3 onboarding patterns.

### Key Insight

Strike's competitive advantage isn't technological innovation—it's **execution on proven patterns**. Parimutuel markets are validated, Pyth integration is documented, Telegram Mini Apps have templates. Success depends on avoiding known pitfalls and shipping a polished core loop: pick UP/DOWN → see potential payout → connect wallet → place bet → claim winnings. Everything else is secondary.

## Key Findings

### Stack

**Recommendation:** Foundry (contracts) + Next.js 15 (frontend) + Viem/Wagmi (Web3) + Pyth Network (oracle) + Reown AppKit (wallet) + Telegram SDK (platform)

- **Foundry over Hardhat:** 2-5x faster compile and test cycles, Solidity-native tests eliminate async complexity, critical for 9-day timeline
- **Viem over ethers.js:** 35KB vs 130KB bundle size, TypeScript-first design with ABIType for zero-config contract typing, wagmi v2+ built on viem (not ethers)
- **Reown AppKit over RainbowKit:** Better multi-chain support (BSC + future expansion), 600+ wallet compatibility, Telegram Mini App integration tested
- **Pyth pull oracle:** Pay for price updates only when needed (market start + end), not continuous push updates. Builder works at Douro Labs (Pyth)—deep expertise available
- **Next.js 15 App Router:** Official Telegram Mini App templates use Next.js. SSR/SSG support, automatic code splitting, Vercel one-click deploy with required HTTPS
- **What NOT to use:** ethers.js (outdated), Hardhat (slow tests), Web3.js (poor TS support), TON Connect (wrong chain), upgradeable contracts (overkill for MVP)

**Critical stack integration:** Pyth contract addresses vary by network (BSC mainnet vs testnet). Reown AppKit requires projectId from dashboard.reown.com (free). Telegram Mini Apps require HTTPS—Vercel provides auto-SSL. BSC uses fixed gas pricing, not EIP-1559.

**Sources:** Viem bundle size from official docs (HIGH confidence). Foundry speed advantage from Chainstack benchmark (MEDIUM-HIGH confidence). Pyth integration patterns from official Pyth Developer Hub (HIGH confidence). Next.js + Telegram templates from Telegram-Mini-Apps GitHub organization (HIGH confidence).

### Features

**MVP (Must-Have for Hackathon):**
1. Binary UP/DOWN betting (core mechanic)
2. Wallet connection via WalletConnect
3. Telegram Mini App container
4. Market countdown timer
5. Real-time price display
6. Payout preview
7. Permissionless resolution
8. Available markets list
9. Position tracking
10. Claim winnings flow

**Defer to Post-Hackathon:**
- Market history (builds trust but not MVP)
- Multiple timeframes (start with 1hr only)
- Leaderboards (engagement, not core validation)
- Portfolio analytics (nice-to-have)

**Anti-Features (Explicitly Avoid):**
- Order book trading (too complex)
- Custom market creation (abuse vectors)
- Social features (scope creep)
- AMM liquidity pools (overengineered)
- Fiat on/off ramps (regulatory complexity)
- Native token (distracts from core product)

**Critical finding:** 68% of prediction market trades happen on mobile. Telegram Mini App provides mobile-first distribution without app store friction. Instant settlement is table stakes (99% of modern markets auto-settle). Clear odds preview required BEFORE betting—parimutuel odds change dynamically, must show "IF you bet now" estimates.

**Sources:** Polymarket/PancakeSwap documentation for competitor analysis (MEDIUM confidence). Mobile usage stats from industry reports (MEDIUM confidence). Telegram Mini Apps features from official docs (HIGH confidence).

### Architecture

**Recommended Pattern:** Factory pattern for market creation + finite state machine for market lifecycle + pull-based oracle updates

**Component Boundaries:**
- **MarketFactory:** Creates PredictionMarket instances, maintains registry
- **PredictionMarket:** Manages single market (Open → Locked → Resolved states), tracks bets via nested mappings
- **Pyth Oracle:** Pull-based price feeds (pay per update, not continuous push)
- **Frontend:** Next.js with wagmi hooks for contract interaction

**Critical architectural decisions:**
1. **Factory Pattern:** Each market is isolated contract instance. Bugs affect only that market, not all markets. Enables gradual rollout and A/B testing.
2. **Finite State Machine:** Explicit states (Open/Locked/Resolved/Cancelled) prevent invalid operations. Lock period between market close and resolution prevents MEV front-running.
3. **Pull-Based Payouts:** Users call `claim()`, contract doesn't iterate over winners array. Avoids gas limit issues with 100+ winners.
4. **Permissionless Resolution:** Anyone can trigger after expiry. Small resolver fee (0.1-0.5%) incentivizes timely resolution. Prevents single point of failure.

**Data Flow:**
- **Betting:** User → WalletConnect → Wagmi → PredictionMarket.bet() → Update storage → Emit BetPlaced event
- **Resolution:** Resolver → Fetch Pyth update → PredictionMarket.resolve() → Validate price → Determine winner → Set Resolved state
- **Claiming:** User → PredictionMarket.claim() → Calculate payout → Transfer funds

**Build Order (5 Phases):**
1. Core Contracts (PredictionMarket + Pyth integration + Factory)
2. Frontend Foundation (Wallet + Contract Interface + Market List)
3. Betting Flow (Bet Modal + Position Display + Real-time Updates)
4. Resolution & Claiming (Resolution Script + Claim UI + Refund Flow)
5. Automation & Polish (Auto-creation + History + Fee Collection)

**Scaling Bottlenecks:**
- **First:** RPC rate limits from frontend polling → Fix with The Graph event indexing + Redis caching
- **Second:** BSC gas costs → Fix with clone pattern for markets, batch operations
- **Third:** Frontend perf with 100+ markets → Fix with virtualized lists, pagination

**Sources:** Factory pattern from QuickNode guide (HIGH confidence). Pyth pull model from official docs (HIGH confidence). Parimutuel contract patterns from programtheblockchain.com (MEDIUM-HIGH confidence). State machine from OpenZeppelin patterns (HIGH confidence).

### Pitfalls

**7 Critical Pitfalls (Must Address in Phase 1):**

1. **Reentrancy in Withdrawal:** Attacker drains pool via recursive calls. **Prevention:** Use OpenZeppelin ReentrancyGuard, update state before transfers.

2. **Stale Pyth Price Acceptance:** Resolution with outdated price enables manipulation. **Prevention:** Validate `publishTime` within 60s of expiry, check confidence intervals.

3. **Division by Zero in Parimutuel:** No bets on winning side causes payout calculation to revert. **Prevention:** Handle one-sided markets explicitly (refund or pool to protocol).

4. **Block Timestamp Manipulation:** Miners adjust timestamp ±15s to game markets. **Prevention:** Add 60s buffer between market close and resolution eligibility.

5. **MEV Front-Running on Resolution:** Bots see pending resolution in mempool, place winning bet before it confirms. **Prevention:** Lock betting 60s BEFORE resolution window, use historical price at lock time.

6. **Integer Precision Loss:** Fee calculations round down to zero on small bets. **Prevention:** Use basis points (10000 = 100%), multiply before divide, enforce minimum bet (0.001 BNB).

7. **Oracle Manipulation via Flash Loans:** Flash loan attacks DEX price feeds. **Prevention:** Use Pyth's aggregated feeds (80+ exchanges), validate confidence intervals, implement circuit breakers for >10% price swings.

**12 Moderate Pitfalls (Address in Phases 1-2):**
- Gas limit exceeded (use pull payouts, not push)
- Unchecked Pyth fee (query getUpdateFee, include in msg.value)
- Missing price validation (timestamp must match expiry window)
- No emergency pause (use OpenZeppelin Pausable from start)
- Telegram wallet instability (test on Android + iOS, provide fallbacks)
- "Connect wallet" anti-pattern (show value first, delay wallet prompt)
- And 6 more detailed in PITFALLS.md

**Phase-Specific Warnings:**
- **Phase 1 (Contracts):** Rushing math validation leads to edge case bugs. Allocate 20% of time to testing zero bets, one-sided markets, precision loss.
- **Phase 2 (Frontend):** Building desktop-first when 90% of users on mobile. Design mobile UI first.
- **Phase 4 (Security):** Time pressure leads to skipping security review. Allocate 1 FULL DAY before demo, non-negotiable.

**"Looks Done But Isn't" Checklist:**
- Market resolution often missing staleness validation
- Payout calculation often missing zero-division guards
- Winner withdrawal often missing reentrancy protection
- Event emissions often incomplete (missing critical events)
- Test coverage often only happy paths (not edge cases)

**Sources:** Reentrancy from Cyfrin guide (HIGH confidence). Oracle manipulation from Smart Contract Security Field Guide (HIGH confidence). Telegram UX from FreeBlock Mini App guide (MEDIUM-HIGH confidence). Precision loss from Certora analysis (HIGH confidence).

## Implications for Roadmap

### Recommended Phase Structure

Based on component dependencies and risk prioritization, 5-phase roadmap:

**Phase 1: Core Contract Development (Days 1-3)**
- **Why First:** All other phases depend on contracts. Security vulnerabilities here are catastrophic (funds lost). Math errors compound. Better to get contracts right early than rush and patch later.
- **Addresses:** Pitfalls 1-7 (all critical contract vulnerabilities)
- **Avoids:** Architectural rework by implementing state machine and factory pattern from start
- **Features:** Binary betting, parimutuel pools, Pyth strike price capture, permissionless resolution, emergency pause
- **Deliverable:** Fully tested contracts on BSC testnet with MockPyth for local development

**Phase 2: Frontend Foundation (Days 4-5)**
- **Why Second:** Validates contract integration before building advanced UI. Wallet connection is highest-risk frontend integration (Telegram constraints). Proving end-to-end flow (wallet → bet → confirm) de-risks remaining work.
- **Addresses:** Pitfall 12 (Telegram wallet instability), Pitfall 13 (wallet-first anti-pattern)
- **Avoids:** Building complex UI before proving basic contract interaction works
- **Features:** Wallet connection (WalletConnect/Reown), contract interface layer (wagmi hooks), market list view
- **Deliverable:** Users can connect wallet in Telegram Mini App and view active markets from factory contract

**Phase 3: Betting Flow (Day 6)**
- **Why Third:** Core user action. Once betting works, everything else is polish. Real-time updates enhance UX but not blocker for functionality.
- **Addresses:** Pitfall 14 (hardcoded gas), Pitfall 15 (rejected transactions)
- **Avoids:** Overengineering analytics before core loop works
- **Features:** Bet modal (UP/DOWN selection), position display, real-time pool updates
- **Deliverable:** Users can place bets, see their positions, track pool sizes live

**Phase 4: Resolution & Claiming (Day 7)**
- **Why Fourth:** Markets can be manually resolved during hackathon. Automation (Phase 5) is quality-of-life. Claiming is straightforward once resolution logic proven.
- **Addresses:** Pitfall 2 (stale prices), Pitfall 9 (Pyth fee), Pitfall 10 (price validation)
- **Avoids:** Complex automation before manual resolution proven
- **Features:** Resolution script (fetch Pyth updates, call resolve()), claim UI, refund flow for cancelled markets
- **Deliverable:** Markets resolve correctly with Pyth price, winners can claim payouts

**Phase 5: Automation & Polish (Days 8-9)**
- **Why Last:** Nice-to-have features that improve UX but aren't MVP blockers. Market history builds trust but isn't required for first bets. Automated creation is quality-of-life (can manually create markets during hackathon).
- **Addresses:** Pitfall 16 (missing metadata)
- **Avoids:** Scope creep delaying core functionality
- **Features:** Automated market creation (cron job), market history view, protocol fee collection UI, simple onboarding guide
- **Deliverable:** Markets auto-create on schedule, users see past results, polished UX for demo

### Phase Ordering Rationale

**Dependencies:**
- Frontend requires deployed contracts (Phase 2 depends on Phase 1)
- Betting requires wallet connection (Phase 3 depends on Phase 2)
- Resolution requires market state transitions (Phase 4 depends on Phase 1)
- Automation requires core flows working (Phase 5 depends on Phases 1-4)

**Risk Reduction:**
- **Phase 1 addresses 7/7 critical pitfalls** (highest ROI on risk mitigation)
- **Phase 2 de-risks Telegram integration early** (highest uncertainty)
- **Phase 3 proves core value prop** (betting works = MVP validated)
- **Phases 4-5 are polish** (low risk if time runs short)

**Timeline Realism:**
- 3 days for contracts (comprehensive testing, Pyth integration, factory pattern)
- 2 days for frontend foundation (Telegram constraints, wallet debugging)
- 1 day for betting flow (UI work, straightforward once foundation solid)
- 1 day for resolution (Pyth API integration, claim logic)
- 2 days for automation and polish (buffer for unexpected issues)

**If Timeline Slips:**
- **Cut Phase 5 first:** Manually create markets, skip history view, defer automation to post-hackathon
- **Cut market history from Phase 5:** Users don't need past results to place first bets
- **Simplify Phase 3:** Manual gas price input instead of dynamic fetching, no real-time updates (poll on refresh)
- **Do NOT cut:** Any Phase 1 security features, Telegram wallet integration, core betting flow

### Research Flags for Phases

Phases likely to need deeper research before execution:

**Phase 1: Smart Contract Development**
- **Flag:** Pyth BSC contract addresses not verified in research. **Action:** Check docs.pyth.network for current mainnet/testnet addresses before deployment.
- **Flag:** Optimal Pyth staleness window for 1hr markets unclear. **Action:** Consult Pyth docs or Douro Labs colleagues for recommended maxAge parameter.
- **Flag:** One-sided market handling policy undecided. **Action:** Decide if no-bets-on-winning-side triggers refund, protocol fee collection, or reverts. Document in specification.

**Phase 2: Frontend Integration**
- **Flag:** Telegram Mini App WalletConnect configuration patterns sparse in research. **Action:** Review Reown's official Telegram integration guide, test early on mobile devices.
- **Flag:** BSC RPC provider selection (free vs paid) not researched. **Action:** Test with free BNB Chain RPC, upgrade to paid (QuickNode/Ankr) if rate limits hit during development.

**Phase 4: Resolution & Claiming**
- **Flag:** Pyth Hermes API usage for fetching price updates not detailed. **Action:** Read Pyth SDK documentation for `@pythnetwork/pyth-evm-js` before implementing resolution script.

**Unlikely to Need Additional Research:**
- **Phase 3 (Betting Flow):** Standard wagmi patterns, well-documented
- **Phase 5 (Automation):** Cron job or Chainlink Keeper, many examples available

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| **Stack** | HIGH | All core technologies verified from official docs, npm registries, or authoritative comparisons. Version numbers confirmed. Integration patterns documented. Only gap: specific Pyth BSC contract address (easily verified). |
| **Features** | MEDIUM-HIGH | Table stakes validated across Polymarket, PancakeSwap, Azuro. Differentiators based on Telegram Mini App research and Strike's positioning. Competitor feature matrix from official docs + industry analysis. Lower confidence on Telegram-specific UX patterns (emerging ecosystem). |
| **Architecture** | HIGH | Factory pattern, state machines, pull oracles, pull payouts are documented Solidity patterns. Pyth integration guide provides code examples. PancakeSwap parimutuel reference implementation exists. Build order based on dependency analysis. |
| **Pitfalls** | MEDIUM-HIGH | Critical pitfalls (reentrancy, oracle manipulation, precision loss) verified from multiple security sources (Cyfrin, OWASP, Certora). Pyth-specific pitfalls from official docs. Telegram UX pitfalls from FreeBlock guide (single source, MEDIUM confidence). Phase mapping based on dependency + risk analysis. |

**Overall Stack Confidence: HIGH**
- Foundry, Viem/Wagmi, Next.js, Pyth SDK all have mature documentation and active ecosystems
- OpenZeppelin contracts are industry standard (v5.4.0 latest stable)
- Telegram Mini Apps SDK has official templates and integration guides
- Only emerging technology: Reown AppKit (rebranded Web3Modal), but well-maintained with migration guides

**Validation Recommendations:**
1. **Before Phase 1:** Verify Pyth BSC contract addresses from official docs
2. **Before Phase 2:** Test Reown AppKit wallet connection in Telegram Desktop + Mobile (Android/iOS)
3. **Before Phase 4:** Review @pythnetwork/pyth-evm-js documentation for Hermes API usage
4. **During Phase 1:** Consult Douro Labs colleagues on Pyth best practices (builder works there)

## Gaps to Address

### Research Gaps (Known Unknowns)

1. **Pyth Network BSC Contract Addresses:** Research didn't retrieve specific contract addresses for BSC mainnet and testnet. **Impact:** Required for deployment, but low risk (easily found in official docs). **When to address:** Before Phase 1 deployment.

2. **Pyth Hermes API Usage Patterns:** Frontend SDK (@pythnetwork/pyth-evm-js) identified, but specific usage for fetching price updates not detailed. **Impact:** Required for Phase 4 resolution script. **When to address:** Before Phase 4.

3. **Telegram-Specific WalletConnect Configuration:** General Reown AppKit integration documented, but Telegram webview-specific constraints and workarounds not fully researched. **Impact:** High risk for Phase 2 if connection fails on mobile. **When to address:** Early in Phase 2 via official Reown Telegram guide + live testing.

4. **Optimal Pyth Staleness Window:** Recommended maxAge for 1hr, 4hr, 24hr markets not specified. Pyth docs may have guidance. **Impact:** Security parameter, affects oracle manipulation resistance. **When to address:** During Phase 1 contract development.

5. **BSC Gas Price Behavior:** Research mentions BSC uses fixed gas pricing (not EIP-1559), but optimal gas estimation strategy not detailed. **Impact:** User experience (failed transactions if gas too low). **When to address:** Phase 2 frontend integration.

### Execution Gaps (Undecided Design Choices)

1. **One-Sided Market Handling:** If all bets on UP and UP wins, payout calculation has zero denominator. Should contract refund? Send pool to protocol? Revert? **Decision needed:** Before Phase 1 implementation.

2. **Resolver Incentive Amount:** Permissionless resolution requires small fee (0.1-0.5% suggested). Exact percentage not decided. **Decision needed:** Before Phase 1 deployment (gas costs vs incentive balance).

3. **Market Creation Schedule:** Auto-create markets hourly? Every 4 hours? Different schedules for BTC vs BNB? **Decision needed:** Before Phase 5 automation, can manually create during hackathon.

4. **Minimum Bet Amount:** Research suggests 0.001-0.01 BNB to prevent precision loss and spam. Exact threshold not decided. **Decision needed:** Before Phase 1 deployment.

5. **Protocol Fee Percentage:** 2-5% suggested, exact value not decided. **Decision needed:** Before Phase 1 deployment (affects payout calculations).

6. **Market Lock Duration:** How long between market close and resolution window? 60s suggested for MEV prevention, but could be longer. **Decision needed:** Before Phase 1 implementation.

7. **Multiple Timeframes:** MVP could launch with 1hr only (simplest) or 1hr + 4hr + 24hr (more variety). **Decision needed:** Early Phase 1 (affects contract design if supporting multiple durations).

8. **BSC RPC Provider:** Use free BNB Chain RPC or paid provider (Alchemy, Ankr, QuickNode)? **Decision needed:** Phase 2 frontend integration (can start free, upgrade if rate limits hit).

### Process Gaps (Procedural Unknowns)

1. **Testnet BNB Acquisition:** Official BNB testnet faucet requires 0.002 BNB on mainnet. Builder may need to acquire mainnet BNB first. **Impact:** Blocks testnet deployment. **When to address:** Before Phase 1 testnet deployment.

2. **Contract Verification on BscScan:** Foundry has forge verify command, but BscScan API key required. **Impact:** Transparency, trust for hackathon judges. **When to address:** During Phase 1 deployment.

3. **Telegram Bot Registration:** Mini App must be registered with @BotFather, requires HTTPS URL (Vercel provides). **Impact:** Blocks Telegram testing. **When to address:** Phase 2 after frontend deployed to Vercel.

4. **Reown Project ID Acquisition:** Free but requires dashboard.reown.com account. **Impact:** Blocks wallet connection. **When to address:** Before Phase 2.

### No Research Needed (Standard Patterns)

These topics were initially considered but don't require additional research—standard implementations exist:

- ✅ **Smart Contract Testing:** Foundry's forge test is well-documented
- ✅ **Next.js Deployment to Vercel:** One-click deploy, official guide exists
- ✅ **Event Indexing (if needed):** The Graph has BNB Chain support, documented
- ✅ **TypeScript Configuration:** Next.js templates provide default config
- ✅ **Solidity Version Selection:** 0.8.28 confirmed compatible with OpenZeppelin v5.4.0 and Pyth SDK

## Final Recommendations

### For Roadmap Planning

1. **Stick to 5-Phase Structure:** Dependencies validated, risk prioritization sound, timeline realistic for 9 days with buffer.

2. **Phase 1 is Critical Path:** 3 days for contracts is NOT negotiable. Rushing contracts leads to security vulnerabilities, math errors, or architectural rework later. All 7 critical pitfalls must be addressed in Phase 1.

3. **Phase 2 Needs Live Testing:** Telegram wallet connection is highest uncertainty. Deploy to testbot early (day 4), test on real Android/iOS devices, NOT just desktop Telegram.

4. **Phase 5 is Buffer:** If time runs short, cut automated market creation and history view. These are quality-of-life, not MVP. Can manually create markets during hackathon demo.

5. **Security Review is Non-Negotiable:** Allocate 1 full day (part of Phase 4 or 5) for security checklist review. Contracts handle real funds; bugs = lost money = failed hackathon demo.

### For Implementation

1. **Start with Templates:** Use Telegram Mini Apps Next.js template, OpenZeppelin contract templates, Pyth SDK examples. Don't build from scratch.

2. **Test Edge Cases Early:** One-sided markets, zero bets, stale prices, rejected transactions. These bugs only appear in production when they cause maximum damage.

3. **Consult Douro Labs Colleagues:** Builder works at Pyth Network's parent company. Leverage internal expertise for Pyth integration best practices, BSC deployment guidance, oracle configuration.

4. **Mobile-First Design:** 90% of Telegram users on mobile. Build mobile UI first, expand to desktop later. Test on 320px screens.

5. **Document Decisions:** When choosing one-sided market handling, resolver fee percentage, lock durations—document WHY in code comments. Future you (or auditors) will thank present you.

### For Risk Mitigation

1. **Deploy Contracts as Upgradeable (OpenZeppelin UUPS):** For hackathon, allows fixing critical bugs post-deployment. For mainnet, migrate to immutable after audit.

2. **Implement Emergency Pause from Day 1:** OpenZeppelin Pausable takes 30 minutes to add, could save entire project if exploit discovered mid-hackathon.

3. **Use Multi-Sig for Owner Role (Post-Hackathon):** Single private key is acceptable for hackathon, MUST migrate to Gnosis Safe multi-sig before mainnet with real funds.

4. **Monitor Testnet Deployment:** Set up simple monitoring (could be as basic as a cron job checking contract balance). If testnet pool suddenly drains, you have a bug.

5. **Keep Scope Minimal:** Every feature added = more testing, more bugs, more time. Ruthlessly cut anything not in MVP list. Leaderboards, social features, analytics—all post-hackathon.

---

**Research Complete:** This summary synthesizes findings from STACK.md, FEATURES.md, ARCHITECTURE.md, and PITFALLS.md. All source files created and cross-validated. Roadmap implications based on dependency analysis, risk prioritization, and timeline realism for 9-day hackathon with Feb 19, 2026 deadline.

**Next Step:** Use this summary to create detailed phase specifications in roadmap planning. Each phase should reference specific sections from research files for implementation guidance.

---

**Sources:**
- STACK.md (this research, 2026-02-10)
- FEATURES.md (this research, 2026-02-10)
- ARCHITECTURE.md (this research, 2026-02-10)
- PITFALLS.md (this research, 2026-02-10)
- Additional web research conducted during summary synthesis

**Meta-Research Note:** This summary represents a synthesis of 4 comprehensive research documents totaling ~140KB of analyzed information from 80+ sources including official documentation, security audits, competitor analysis, and industry reports. Confidence levels assigned per section based on source authority and verification across multiple independent sources.
