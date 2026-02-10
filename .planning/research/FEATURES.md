# Feature Research

**Domain:** Binary Parimutuel Prediction Markets (Telegram Mini-App, BNB Smart Chain)
**Researched:** 2026-02-10
**Confidence:** MEDIUM

## Feature Landscape

### Table Stakes (Users Expect These)

Features users assume exist. Missing these = product feels incomplete.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| **View active markets** | Users need to see what's available to bet on | LOW | Market list with time remaining, current pool sizes, strike price. Standard UI pattern. |
| **Place prediction (UP/DOWN)** | Core action — stake selection and amount entry | MEDIUM | Wallet transaction approval, input validation, transaction state handling (pending/confirmed/failed). |
| **See current pool distribution** | Users want to know how much is in each side before betting | LOW | Display total UP pool, total DOWN pool, implied odds. Read from contract state. |
| **Track active positions** | Users expect to see their open bets | MEDIUM | Query user's positions from contract, show market, side, stake amount, potential payout. |
| **View resolved markets** | Users want to see past results and verify fairness | LOW | Historical market data with final price, winning side, actual payouts. Trust builder. |
| **Wallet connection** | Standard Web3 UX — connect wallet to interact | MEDIUM | WalletConnect integration for Telegram mini-app. BSC network. Gas approval flow. |
| **Transaction status feedback** | Users need to know if their bet succeeded | LOW | Pending → Confirmed → Success/Fail states with clear messaging. Standard Web3 pattern. |
| **Minimum bet enforcement** | Prevents spam and ensures meaningful pool sizes | LOW | Smart contract validation (~0.001 BNB minimum). Display in UI before transaction. |
| **Auto-refresh market data** | Markets expire on schedule; UI must stay current | LOW | Poll contract state every 10-30s or use WebSocket events. Essential for time-sensitive markets. |
| **Protocol fee transparency** | Users expect to know the "house take" upfront | LOW | Display fee percentage (2-5%) before bet placement. Standard for betting platforms. |
| **Real-time price display** | Users need current BTC/BNB prices for context | LOW | Pyth Network integration provides sub-second price updates. Shows strike price vs current. |
| **Market countdown timer** | Users must know time remaining before market closes | LOW | Essential for 1hr/4hr/24hr fixed windows. JavaScript timer synced with block timestamp. |
| **Instant settlement** | Modern markets settle automatically; 99% expect immediate payouts | MEDIUM | Permissionless resolution already planned. Pyth oracle pull + payout distribution. |
| **Simple onboarding** | One-tap authentication, no complex wallet setup | MEDIUM | Telegram authentication critical for adoption. Reduces friction vs MetaMask setup. |
| **Claim winnings flow** | Clear UI for collecting payouts after resolution | MEDIUM | Must handle BNB distribution from winner pool minus protocol fee. |

### Differentiators (Competitive Advantage)

Features that set the product apart. Not required, but valuable.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **Permissionless resolution** | Anyone can trigger market resolution — no trust needed | MEDIUM | Anyone can call `resolve()` after expiry. Pulls Pyth price oracle. More trustless than admin-only resolution. |
| **Telegram-native experience** | Seamless betting without leaving Telegram | HIGH | Telegram Mini Apps SDK integration. Native wallet connect, in-app transactions, Telegram auth. High engagement potential. |
| **Auto-created markets on schedule** | Consistent availability — new market always starting | MEDIUM | Off-chain scheduler (cron/keeper) triggers market creation. Ensures liquidity concentration vs fragmented user-created markets. |
| **Real-time odds display** | Shows live pool distribution as bets come in | MEDIUM | Calculate potential payout based on current pool state. Updates as others bet. Helps users make informed decisions. |
| **Pyth oracle integration** | Fast, low-latency price feeds from institutional sources | MEDIUM | Already familiar to builder (works at Pyth). Sub-second updates. High trust oracle. |
| **Fixed time windows (1hr/4hr/24hr)** | Predictable market cadence — users know when markets resolve | LOW | Simpler than arbitrary expiry times. Easier to schedule around. Better for habit formation. |
| **Parimutuel model** | Winners split pool proportionally — pure P2P, no house edge | MEDIUM | Different from order book models (Polymarket) or AMM. Self-balancing, no liquidity providers needed. |
| **Zero-knowledge required** | Non-crypto users can participate via Telegram | HIGH | Telegram abstraction removes blockchain complexity. Lower barrier to entry than Web3 apps. |
| **Sub-hour markets** | 1hr windows for quick speculation vs multi-day markets | LOW | Fast feedback loop for users. Creates urgency and habit-forming engagement. |
| **Multiple timeframes** | 1hr, 4hr, 24hr windows for different risk profiles | MEDIUM | Flexibility in betting strategy. Short-term traders vs longer-term predictors. |

### Anti-Features (Commonly Requested, Often Problematic)

Features that seem good but create problems.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| **User-created markets** | "Let users create any market they want" | Fragments liquidity across hundreds of low-volume markets. Oracle complexity for arbitrary events. Spam/troll markets. | Admin or auto-created markets for MVP. Focus liquidity. Add user creation in v2 with curation. |
| **Complex multi-outcome markets** | "Support more than UP/DOWN" | Increases smart contract complexity significantly. UI becomes harder to understand. Splits liquidity further. | Stick to binary for MVP. Proven parimutuel model. Add multi-outcome in v2 if validated. |
| **Leverage/margin trading** | "Let users bet more than they have" | Liquidation mechanisms add huge complexity. Risk management needed. Regulatory concerns increase. | Simple stake-what-you-have model. Parimutuel = no liquidations. Cleaner UX. |
| **Live in-market trading (order book)** | "Trade like a stock exchange during market" | Order book requires market maker incentives. Complex matching engine. Hurts parimutuel simplicity. | Parimutuel = locked bets until resolution. Simple, fair, no front-running. Consider AMM in v2. |
| **Early exit with guaranteed payout** | "Let me cash out before resolution" | Kills parimutuel model (pool shrinks unpredictably). Requires counter-party or AMM. High complexity. | Parimutuel = locked until resolution. Set expectations clearly. Future: secondary market, not guaranteed cashout. |
| **Fiat on-ramp in Telegram** | "Make it easy to buy crypto in-app" | Regulatory nightmare (KYC/AML). Payment processor integration complexity. Out of scope for hackathon. | Users bring their own crypto. Assume Telegram wallet or external wallet. Focus on core betting mechanics. |
| **Social features (chat, leaderboards)** | "Gamify it, show top traders" | Scope creep. Leaderboards can encourage gambling addiction. Chat moderation burden. | Defer to post-MVP. Focus on core prediction market functionality first. |
| **Real-time odds updates during round** | "Show changing odds as bets come in" | Complex recalculation, potential manipulation concerns, UI complexity. | Show odds at entry time, lock after bet placed. Display pool distribution but not live recalculated odds. |
| **Partial exits/early settlement** | "Let me sell part of my position early" | Requires secondary market or AMM. Smart contract complexity. Fragments liquidity. | All-or-nothing bets. Claim full position after resolution only. |
| **Native token/rewards** | "Launch a token for governance or rewards" | Token economics complexity. Regulatory risk. Distracts from core product. Hackathon rules prohibit. | Use BNB directly for MVP. No token needed. Focus on betting mechanics. |
| **Advanced analytics/charting** | "Build trading terminal with charts" | Over-engineering for MVP. Users can use external tools. Scope creep. | Basic position tracking only. Defer analytics to v2. Integrate TradingView if needed later. |
| **AMM liquidity pools** | "Let users provide liquidity for yield" | Requires collateral management, impermanent loss concerns, over-engineered. | Parimutuel is simpler and self-balancing. No liquidity providers needed. |

## Feature Dependencies

```
[Place Prediction]
    └──requires──> [Wallet Connection]
                       └──requires──> [WalletConnect Integration]

[Track Active Positions]
    └──requires──> [Wallet Connection]
    └──requires──> [Place Prediction] (user must have positions to track)

[View Resolved Markets]
    └──requires──> [Permissionless Resolution]
                       └──requires──> [Pyth Oracle Integration]

[Auto-created Markets]
    └──requires──> [Pyth Oracle Integration] (for strike price at creation)
    └──requires──> [Off-chain Scheduler/Keeper]

[Real-time Odds Display]
    └──requires──> [View Active Markets]
    └──enhances──> [Place Prediction] (informed betting)

[Instant Settlement]
    └──requires──> [Permissionless Resolution]
                       └──requires──> [Pyth Oracle Integration]

[Protocol Fee Transparency]
    └──enhances──> [Place Prediction] (trust building)

[Telegram-native Experience]
    └──provides──> [Simple Onboarding]
    └──provides──> [Mobile-first UX]
    └──requires──> [WalletConnect Integration]

[Parimutuel Model]
    └──conflicts with──> [Order Book Trading]
    └──conflicts with──> [AMM Pools]
    └──conflicts with──> [Early Exit with Guaranteed Payout]
    └──requires──> [Pool Share Calculation]
```

### Dependency Notes

- **Place Prediction requires Wallet Connection:** Users must connect wallet before placing bets. Standard Web3 flow.
- **Permissionless Resolution requires Pyth Oracle:** Resolution pulls Pyth price feed. Anyone can call, but oracle must be integrated.
- **Auto-created Markets require Pyth Oracle:** Strike price = current Pyth price at market creation time.
- **Auto-created Markets require Off-chain Scheduler:** Cron job or keeper network (Chainlink Keeper, Gelato) triggers `createMarket()` on schedule (e.g., every hour for 1hr markets).
- **Real-time Odds Display enhances Place Prediction:** Showing current pool distribution helps users decide which side to bet and how much.
- **Parimutuel Model conflicts with Early Exit:** Can't guarantee payout if pool shrinks before resolution. Would require AMM or order book (defeats parimutuel simplicity).

## MVP Definition

### Launch With (v1.0 — Hackathon Deadline: Feb 19, 2026)

Minimum viable product — what's needed to validate the concept.

**Smart Contracts:**
- [ ] Parimutuel binary markets (UP/DOWN pools) — Core betting mechanism
- [ ] Auto-created markets on schedule (1hr, 4hr, 24hr for BTC/BNB) — Consistent market availability
- [ ] Pyth oracle integration for strike price — Current price when market created
- [ ] Pyth oracle integration for resolution price — Final price at expiry
- [ ] Permissionless resolution — Anyone can call `resolve()` after expiry
- [ ] Winner payout distribution (proportional to pool share) — Fair parimutuel distribution
- [ ] Protocol fee on winnings (2-5%) — Sustainability model
- [ ] Minimum bet size (~0.001 BNB) — Prevent spam

**Telegram Mini-App:**
- [ ] View active markets (list view with time remaining, pools) — Browse available markets
- [ ] Wallet connection (WalletConnect for BSC) — Web3 authentication
- [ ] Place prediction (select UP/DOWN, enter stake, approve tx) — Core user action
- [ ] Track active positions (your open bets) — Portfolio view
- [ ] View resolved markets (past results) — Transparency and trust
- [ ] Auto-refresh market data (poll every 10-30s) — Time-sensitive data
- [ ] Real-time price display (Pyth current price) — Context for betting decisions
- [ ] Market countdown timer — Urgency and clarity on expiry

**Must-haves for credibility:**
- [ ] Transaction status feedback (pending/confirmed/failed) — User knows what's happening
- [ ] Protocol fee transparency (show fee % before bet) — No hidden costs
- [ ] Current pool distribution display (UP vs DOWN) — Informed betting
- [ ] Claim winnings flow — UI to collect BNB from won positions

**Rationale:** These features form the minimum viable prediction market. Users can connect wallet, see available markets, place bets, track positions, and claim winnings. Everything else is enhancement.

### Add After Validation (v1.x — Post-Hackathon)

Features to add once core is working and validated.

- [ ] **Real-time odds display** — Show potential payout based on current pool state (enhances decision-making). **Trigger:** user feedback requests this.
- [ ] **Market performance history** — UP vs DOWN win rates over time (helps users spot trends). **Trigger:** 50+ resolved markets.
- [ ] **Push notifications** — Market expiring soon, position resolved, new market available. **Trigger:** user retention data shows need.
- [ ] **Additional assets** — Expand beyond BTC/BNB (ETH, SOL, etc.). **Trigger:** product-market fit confirmed.
- [ ] **Custom time windows** — 15min, 6hr, 48hr markets. **Trigger:** user requests for different timeframes.
- [ ] **Gas optimization round 2** — Batch operations, storage packing, event emission reduction. **Trigger:** gas costs become user complaint.
- [ ] **Simple onboarding guide** — Tutorial overlay for first-time users. **Trigger:** user confusion metrics.
- [ ] **Multiple wallet support** — MetaMask, Trust Wallet, etc. beyond WalletConnect. **Trigger:** wallet connection friction reports.

**Why defer:** These add engagement and retention but aren't needed to validate core prediction market mechanics. Focus on betting loop first.

### Future Consideration (v2+ — Long-term Vision)

Features to defer until product-market fit is established.

- [ ] **Secondary market for positions** — Let users trade positions before resolution via AMM or order book. (Complexity: HIGH. Changes parimutuel model.)
- [ ] **User-created markets** — Let users propose markets with curation/staking. (Complexity: HIGH. Liquidity fragmentation risk.)
- [ ] **Multi-outcome markets** — More than binary UP/DOWN (e.g., price ranges). (Complexity: MEDIUM. Splits liquidity.)
- [ ] **Social features** — Leaderboards, chat, social sharing. (Complexity: MEDIUM. Scope creep risk.)
- [ ] **Cross-chain deployment** — Deploy to other chains (Arbitrum, Base, Polygon). (Complexity: MEDIUM. Oracle availability varies.)
- [ ] **AI-powered insights** — Suggest which side to bet based on historical data. (Complexity: HIGH. Regulatory concerns around financial advice.)
- [ ] **Limit orders** — Place bets that execute only if pool ratio hits target. (Complexity: HIGH. Requires order matching engine.)
- [ ] **Portfolio analytics** — P&L tracking, win rate stats, performance history. (Complexity: MEDIUM. Requires data indexing.)
- [ ] **Rewards/loyalty program** — Incentivize volume with points or token rewards. (Complexity: HIGH. Token economics and regulatory risk.)
- [ ] **Mobile notifications** — Alert on market close, wins, new markets. (Complexity: MEDIUM. Push notification infrastructure.)
- [ ] **API access** — Let third parties build on top. (Complexity: MEDIUM. API design and rate limiting.)

**Why defer:** These add engagement and retention but aren't needed to validate core prediction market mechanics. Focus on betting loop first.

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Place prediction (UP/DOWN) | HIGH | MEDIUM | P1 |
| Wallet connection | HIGH | MEDIUM | P1 |
| View active markets | HIGH | LOW | P1 |
| Permissionless resolution | HIGH | MEDIUM | P1 |
| Auto-created markets | HIGH | MEDIUM | P1 |
| Track active positions | HIGH | MEDIUM | P1 |
| View resolved markets | HIGH | LOW | P1 |
| Protocol fee transparency | MEDIUM | LOW | P1 |
| Current pool distribution | HIGH | LOW | P1 |
| Transaction status feedback | HIGH | LOW | P1 |
| Minimum bet enforcement | MEDIUM | LOW | P1 |
| Auto-refresh market data | HIGH | LOW | P1 |
| Real-time price display | HIGH | LOW | P1 |
| Market countdown timer | HIGH | LOW | P1 |
| Instant settlement | HIGH | MEDIUM | P1 |
| Simple onboarding | MEDIUM | MEDIUM | P1 |
| Claim winnings flow | HIGH | MEDIUM | P1 |
| Telegram Mini App container | HIGH | HIGH | P1 |
| Real-time odds display | MEDIUM | MEDIUM | P2 |
| Market performance history | MEDIUM | LOW | P2 |
| Push notifications | MEDIUM | MEDIUM | P2 |
| Additional assets (ETH, SOL) | MEDIUM | LOW | P2 |
| Custom time windows | LOW | LOW | P2 |
| Gas optimization (advanced) | MEDIUM | MEDIUM | P2 |
| Onboarding guide | MEDIUM | LOW | P2 |
| Multiple wallet support | MEDIUM | MEDIUM | P2 |
| Secondary market for positions | HIGH | HIGH | P3 |
| User-created markets | MEDIUM | HIGH | P3 |
| Multi-outcome markets | MEDIUM | MEDIUM | P3 |
| Social features | LOW | MEDIUM | P3 |
| Cross-chain deployment | MEDIUM | MEDIUM | P3 |
| AI-powered insights | LOW | HIGH | P3 |
| Portfolio analytics | MEDIUM | MEDIUM | P3 |
| Notifications | MEDIUM | MEDIUM | P3 |
| API access | LOW | MEDIUM | P3 |

**Priority key:**
- **P1:** Must have for hackathon MVP (Feb 19, 2026 deadline — 9 days)
- **P2:** Should have, add post-hackathon when validated
- **P3:** Nice to have, future consideration after product-market fit

## Competitor Feature Analysis

| Feature | Polymarket | PancakeSwap Prediction | Azuro | Strike (Our Approach) |
|---------|------------|----------------------|-------|-------------------|
| **Market Model** | Order book (continuous trading) | Parimutuel pools | Liquidity pool (parimutuel-style) | Pure parimutuel (locked bets) |
| **Settlement** | UMA optimistic oracle (dispute-based) | ChainLink oracle | Permissioned resolvers | Pyth oracle + permissionless triggering |
| **Platform** | Web app (Polygon) | Web app (BNB Chain) | Infrastructure layer for integrators | Telegram Mini App (native integration) |
| **Market Creation** | User-created + platform-curated | Auto-created on schedule | Developer-integrated | Auto-created BTC/BNB on schedule |
| **Time Windows** | Variable, often multi-day | Fixed 5-minute rounds | Event-based (sports matches) | 1hr/4hr/24hr — more variety than PancakeSwap |
| **Asset Coverage** | Politics, sports, crypto, events | BNB, BTC, ETH only | Sports-focused | BTC/BNB only for MVP — proven demand |
| **Liquidity** | $130M+ open interest, deep order books | Parimutuel auto-balancing | Shared liquidity pools across events | Parimutuel — no liquidity bootstrapping needed |
| **User Onboarding** | MetaMask, Web3 wallets | MetaMask, WalletConnect | Varies by frontend | Telegram — lowest friction for non-crypto users |
| **Mobile Experience** | Mobile web, responsive | Mobile web | Varies by integration | Native Telegram Mini App — 68% of users on mobile |
| **Social Features** | Leaderboards, follower networks | None | None | None for MVP — focus on core loop |
| **Analytics** | Third-party tools (PredictFolio, PolyTrack) | None | None | None for MVP — defer to v2 |
| **Early Exit** | Sell position anytime at market price | No early exit | No early exit | No early exit (MVP; consider for v2) |
| **Oracle** | UMA's optimistic oracle (human dispute resolution) | ChainLink | Permissioned resolvers | Pyth (sub-second institutional price feeds) |
| **Blockchain** | Polygon (low fees) | BNB Smart Chain | Multiple chains supported | BNB Smart Chain (BSC) |

**Strike's Competitive Position:**

- **Distribution advantage:** Telegram Mini App vs web apps — tap into Telegram's 900M+ users
- **Onboarding simplicity:** No MetaMask setup, Telegram authentication is one-tap
- **Proven model:** Parimutuel like PancakeSwap (not experimental AMM or complex order books)
- **Trusted oracle:** Pyth Network (builder works at Pyth) vs ChainLink — first-party knowledge, institutional data sources
- **BNB Chain native:** Lower fees than Polygon, existing DeFi ecosystem
- **Permissionless trustless:** Anyone can resolve vs UMA disputes or admin-only resolution
- **Trade-off:** Limited to crypto price predictions vs Polymarket's event variety — but focused scope fits 9-day timeline

## User Flow Expectations

### First-Time User Journey
1. **Discover** — User opens Telegram mini-app (shared link, bot interaction, or search)
2. **Browse** — Sees active markets (BTC 1hr UP/DOWN, BNB 4hr UP/DOWN, etc.) with time remaining, current pools
3. **Learn** — Taps market → sees strike price, current price, expiry time, pool distribution, potential payout range
4. **Connect** — Taps "Place Prediction" → prompted to connect wallet (WalletConnect for BSC)
5. **Bet** — Selects UP or DOWN, enters stake (e.g., 0.01 BNB), sees protocol fee deduction, approves transaction
6. **Confirm** — Sees pending → confirmed → success with position added to "My Positions"
7. **Wait** — Market resolves at expiry (user can watch countdown, check current price vs strike)
8. **Resolve** — Anyone triggers resolution (permissionless), Pyth price pulled, winners calculated
9. **Claim** — If user won, payout shown in "My Positions", tap to claim (or auto-distributed)
10. **Repeat** — User sees resolved market in history, checks result, notices next active market

**Expected friction points:**
- Wallet connection first time (WalletConnect approval)
- Gas fee understanding (need BNB for transaction)
- Parimutuel payout uncertainty (estimated payout changes as others bet)
- Waiting for market resolution (manage expectations on timing)

### Returning User Journey (Habit Loop)
1. **Open app** — Check active positions, see time remaining on open bets
2. **New market** — Notice new 1hr BTC market just started (auto-created on schedule)
3. **Quick bet** — Familiar flow: UP/DOWN, stake, approve (muscle memory)
4. **Check results** — Previous market resolved, see if won, view payout, claim if applicable
5. **Repeat** — Consistent availability (new market always starting) builds habit

**Habit formation factors:**
- Fixed schedule (new 1hr market every hour) → predictable availability
- Short durations (1hr) → fast feedback loop
- Telegram notifications (P2 feature) → re-engagement triggers
- Auto-created markets → always something to bet on

### Edge Cases to Handle
- **Market expires while user is placing bet** — Transaction should fail gracefully with clear error ("Market expired, bet next round")
- **User has no BNB for gas** — Show gas estimate before transaction, warn if insufficient balance, offer link to get BNB
- **Resolution delayed** — Show "Awaiting resolution, anyone can trigger" with CTA button to trigger resolution (earn small incentive?)
- **User bets on both sides** — Allow (some users hedge), track separately in "My Positions"
- **Pool heavily imbalanced (99% on one side)** — Show warning: "Low payout if you win (pool imbalanced)" for transparency
- **No bets on losing side** — Handle edge case where all users bet same side, losers get nothing, winners split pool
- **Oracle price stale** — Reject resolution if Pyth price too old, require fresh update, notify users of delay

## Technical Complexity Breakdown

### Smart Contracts (Solidity)
- **Parimutuel pool logic** — MEDIUM: Track two pools (UP/DOWN), calculate proportional payouts, handle edge cases (no bets on losing side, single bettor)
- **Auto-creation** — LOW: Simple factory pattern, keeper calls `createMarket(asset, duration)`, emit event
- **Pyth integration (strike price)** — LOW: Fetch current price on market creation, store in contract state (builder familiar with Pyth)
- **Pyth integration (resolution)** — MEDIUM: Pull Pyth price at expiry timestamp, validate data age, handle staleness, compare to strike price
- **Permissionless resolution** — LOW: Public `resolve()` function, anyone can call after expiry, pays gas, triggers payout calculation
- **Fee distribution** — LOW: Deduct protocol fee (2-5%) from winner pool before proportional payout calculation
- **Payout calculation** — MEDIUM: `userPayout = (userStake / winnerPoolTotal) * (totalPool - protocolFee)` with edge case handling
- **Gas optimization** — MEDIUM: Storage packing (use uint128 for amounts, uint32 for timestamps), minimize storage writes, batch operations, emit events efficiently (P2 priority)

### Oracle Integration (Pyth)
- **Price feed subscription** — LOW: Standard Pyth SDK, BTC/USD and BNB/USD feeds available on BSC
- **Strike price capture** — LOW: Query Pyth `getPrice(feedId)` on market creation, store price and timestamp in contract
- **Resolution price validation** — MEDIUM: Ensure price update is fresh (< 60 seconds old), handle edge cases (oracle downtime, stale data)
- **Staleness handling** — MEDIUM: Reject stale prices in `resolve()`, require recent Pyth update, revert transaction if price too old

### Frontend (Telegram Mini-App)
- **Telegram Mini Apps SDK** — HIGH: Learning curve for builder (new to Telegram SDK); but official docs and examples available
- **WalletConnect integration** — MEDIUM: Standard Web3 wallet flow (connect, approve, sign), but Telegram context adds complexity (mobile-only, in-app browser)
- **Real-time data refresh** — LOW: Poll contract state every 10-30s (active markets, user positions) or WebSocket events for new blocks
- **Transaction state management** — MEDIUM: Pending → Confirmed → Success flow with error handling, retry logic, user feedback
- **Responsive design** — LOW: Mobile-first (Telegram is mobile-dominant), single-column layout, large touch targets
- **Market countdown timers** — LOW: JavaScript `setInterval` timer logic, sync with blockchain timestamp, update every second
- **Pool distribution visualization** — LOW: Simple bar chart or percentage display (UP: 60%, DOWN: 40%)

### Off-chain Infrastructure
- **Market creation scheduler** — MEDIUM: Cron job or keeper network (Chainlink Keeper, Gelato, custom script) to call `createMarket()` on schedule (e.g., every hour for 1hr markets)
- **Resolution triggers** — LOW: Anyone can call (permissionless), but may need backup keeper to ensure timely resolution (operational reliability)
- **Price feed monitoring** — MEDIUM: Track Pyth oracle health (uptime, freshness), alert if feeds go stale, automated fallback or pause mechanism (operational monitoring)
- **Backend API (optional)** — MEDIUM: Index blockchain events (market created, bet placed, market resolved) for faster UI queries vs direct RPC calls (scalability optimization)

## Parimutuel-Specific UX Considerations

### Information Asymmetry (Early vs Late Bets)

**Challenge:** In traditional parimutuel betting, late bettors have more information (see pool distribution) than early bettors, creating perceived unfairness. Research shows "professional gamblers often place their bets at the last possible minute" because they have better information about expected dividends.

**Strike's approach:**
- Display current pool distribution in real-time (transparency for all bettors)
- Show estimated payout range based on current pools: "If you bet 0.01 BNB UP now, you get ~0.018 BNB if you win (current estimate)"
- Update estimate in real-time as pools change (inform early bettors of odds movement)
- Short market durations (1hr, 4hr) reduce late-betting information advantage vs 24hr+ markets
- Accept this as inherent to parimutuel model; educate users with tooltip: "Payout depends on final pool distribution"
- Consider betting cutoff (e.g., bets close 5 min before expiry) to reduce last-second manipulation (P2 consideration)

**User education needed:**
- "Unlike fixed odds, your payout depends on how many people bet each side"
- "Bet early to influence the pool, or wait to see how others bet"

### Payout Uncertainty

**Challenge:** Users don't know exact payout until market closes (unlike fixed odds where "bet $100 at 3/1 odds = $300 win"). Research shows this frustrates early bettors when odds shorten: "if a horse is at 5/1 odds three hours before a race and you place $100, you might expect a $500 win; however, if more money comes in on that horse and the odds move to 3/1 by race time, you would win only $300 instead."

**Strike's approach:**
- Show current payout estimate prominently: "Current estimate: 0.018 BNB" with warning icon
- Clearly label "ESTIMATE — Final payout depends on total pool at market close"
- After betting window closes (market expires but before resolution), show LOCKED payout: "Your payout: 0.0175 BNB (final)"
- Consider "lock-in" feature (P3): let users lock odds at current rate by taking counter-party from AMM (hybrid model, complex)
- Use color coding: Green for favorable odds movement (payout estimate increased), Red for unfavorable (estimate decreased)

**Transparency messaging:**
- "Your share of the winner pool: 2.5%"
- "If UP wins, you get 2.5% of total pool minus 3% protocol fee"

### Liquidity Concentration

**Challenge:** User-created markets fragment liquidity across hundreds of low-volume markets, creating cold start problem. Research shows "when new markets launch, liquidity is low and traders face poor execution with high slippage and price impact making trading unprofitable."

**Strike's approach:**
- Auto-created markets on fixed schedule (1hr/4hr/24hr for BTC/BNB only)
- Concentrates all liquidity into few predictable markets (e.g., max 6 active markets at once: BTC 1hr/4hr/24hr, BNB 1hr/4hr/24hr)
- Users know "new 1hr BTC market starts every hour at :00" → easier to plan around
- Reduces cold-start problem vs brand new user-created markets (every market starts fresh but predictably)
- Trade-off: Less variety (can't bet on ETH, SOL, custom events) but deeper liquidity per market

**Why this works:**
- PancakeSwap Prediction uses same model (fixed 5min rounds, BNB/BTC/ETH only) — proven to work
- Predictable schedule → habit formation → consistent participation → sufficient liquidity

### No Early Exit (MVP)

**Challenge:** Users locked into bet until resolution; no way to exit early if market moves against them (e.g., bet UP but price dropping). This creates anxiety and perceived lack of control.

**Strike's approach:**
- Accept this limitation for MVP (simplicity, faster development)
- Clearly communicate "Bet locks until market resolves" before transaction (set expectations)
- Use copy like "Prediction locks in — no early exit" with checkbox confirmation for first bet
- Show reassurance: "Market resolves in 45 minutes — short wait"
- Consider secondary market (AMM or order book for position trading) in v2 if users demand it
- Parimutuel = fair pool distribution, but sacrifices flexibility (trade-off users must accept)

**Educational messaging:**
- "Unlike trading, predictions lock until the market ends"
- "Think carefully before betting — you can't exit early"

**Future consideration (v2):**
- Secondary market where users can sell positions to others at discount before resolution
- Requires AMM (automated liquidity) or order book (peer-to-peer matching)
- High complexity but solves early exit problem if user demand is strong

### Pool Imbalance Warnings

**Challenge:** If 95% of bets are on UP and only 5% on DOWN, the DOWN bettors have huge potential upside (20x payout if they win) but UP bettors have minimal upside (1.05x payout). Users may not understand this imbalance.

**Strike's approach:**
- Show pool distribution prominently: "UP: 95% (0.95 BNB) | DOWN: 5% (0.05 BNB)"
- Calculate and display potential payout multiplier: "If you bet UP and win: 1.05x | If you bet DOWN and win: 20x"
- Warn on extreme imbalance: "⚠️ Pool heavily favors UP — low payout if UP wins"
- Encourage contrarian betting with messaging: "DOWN side has high payout potential (20x) but riskier"
- Let users make informed decisions (don't prevent imbalanced bets, just warn)

**Why this matters:**
- Transparent pool distribution helps users understand risk/reward
- Reduces complaints after resolution ("I didn't know payout would be so low!")

## Sources

**Prediction Market Mechanics:**
- [What Are Prediction Markets & How Do They Work? - Gambling Insider](https://www.gamblinginsider.com/in-depth/103484/what-are-prediction-markets)
- [How Prediction Markets Work - Kalshi News](https://news.kalshi.com/p/how-prediction-markets-work)
- [Prediction Markets Explained - Commodity.com](https://commodity.com/brokers/prediction-markets/)
- [Prediction Markets in 2026: How They Work - PokerOff](https://pokeroff.com/en/news/prediction-markets-in-2026/)

**Platform Comparisons:**
- [Crypto Magic: In-depth Analysis of Polymarket, SX Bet, Pred X and Azuro - Bitget News](https://www.bitget.com/news/detail/12560604252307)
- [Deep analysis of Polymarket, SX Bet, Pred X, and Azuro prediction markets - AiCoin](https://www.aicoin.com/en/article/414153)
- [What Is Polymarket? Decentralized Prediction Markets Guide - CoinGecko](https://www.coingecko.com/learn/what-is-polymarket-decentralized-prediction-markets-guide)
- [Best Prediction Market Platforms in 2026 - The Block](https://www.theblock.co/ratings/best-prediction-market-platforms-in-2026-388252)

**Parimutuel Betting:**
- [Parimutuel betting - Wikipedia](https://en.wikipedia.org/wiki/Parimutuel_betting)
- [Parimutuel Betting Guide - ReadWrite](https://readwrite.com/gambling/guides/parimutuel-betting/)
- [Pari-Mutuel Horse Racing: How Pool Betting Works - The Sports Geek](https://www.thesportsgeek.com/sports-betting/horse-racing/pari-mutuel-betting/)
- [The Timing of Parimutuel Bets - Ottaviani & Sørensen (PDF)](https://web.econ.ku.dk/sorensen/papers/TheTimingofParimutuelBets.pdf)
- [The Economics of Parimutuel Sports Betting - Medium](https://medium.com/@lloyddanzig/the-economics-of-parimutuel-sports-betting-367cb5ee1be1)

**Telegram Mini Apps & Wallet Integration:**
- [Build a Telegram Mini App with TON Connect - Medium](https://ocularmagic.medium.com/build-a-telegram-mini-app-with-ton-connect-a-step-by-step-guide-eb1847dff376)
- [TON Connect Overview - TON Docs](https://docs.ton.org/ecosystem/ton-connect/overview)
- [Everything You Need to Know About Telegram Mini Apps — 2026 Guide](https://magnetto.com/blog/everything-you-need-to-know-about-telegram-mini-apps)
- [Best practices for UI/UX in Telegram Mini Apps - BAZU](https://bazucompany.com/blog/best-practices-for-ui-ux-in-telegram-mini-apps/)
- [Telegram Mini Apps UI Kit - Figma](https://www.figma.com/community/file/1348989725141777736/telegram-mini-apps-ui-kit)

**Pyth Oracle:**
- [Pyth Network Price Feeds](https://www.pyth.network/price-feeds)
- [Pyth Network: Your 2026 Crypto Oracle Goldmine - Medium](https://medium.com/thecapital/pyth-network-your-2026-crypto-oracle-goldmine-26761c15ab72)
- [How Pyth Network Brings Secure Price Feeds to DeFi - CCN](https://www.ccn.com/education/crypto/pyth-network-secure-on-demand-price-feeds-defi/)

**BNB Chain Prediction Markets:**
- [Building the Next Wave of Prediction Markets on BNB Chain](https://www.bnbchain.org/en/blog/building-the-next-wave-of-prediction-markets-on-bnb-chain)

**Liquidity & UX Challenges:**
- [Bootstrapping Liquidity in BTC-Denominated Prediction Markets - arXiv](https://arxiv.org/html/2509.11990)
- [Why Prediction Markets Are Still in the Exploratory Stage - Bitget News](https://www.bitget.com/news/detail/12560605059167)
- [DeFi Outlook 2026: Friction Points - Metaverse Post](https://mpost.io/defi-outlook-2026-1inch-survey-finds-growing-confidence-among-experienced-users-despite-persistent-friction-points/)
- [Blockchain User Experience: What You Need to Know](https://austinwerner.io/blog/blockchain-user-experience)

**Smart Contract Optimization:**
- [Gas Optimization In Solidity - Hacken](https://hacken.io/discover/solidity-gas-optimization/)
- [RareSkills Book of Solidity Gas Optimization](https://rareskills.io/post/gas-optimization)
- [Gas Optimization Strategies 2026 - Medium](https://medium.com/coinmonks/gas-optimization-strategies-why-your-contract-costs-more-and-how-to-fix-it-d596ad8946fe)
- [12 Solidity Gas Optimization Techniques - Alchemy](https://www.alchemy.com/overviews/solidity-gas-optimization)

**Permissionless Resolution:**
- [Polymarket + UMA Resolution](https://legacy-docs.polymarket.com/polymarket-+-uma)
- [Ownable vs Permissionless Smart Contracts - JamesBachini.com](https://jamesbachini.com/permissionless-smart-contracts/)

**User Experience & Position Tracking:**
- [Crypto Prediction Markets - CoinMarketCap](https://coinmarketcap.com/prediction-markets/)
- [Trade Prediction Markets Directly in MetaMask](https://metamask.io/prediction-markets)

---

**Research Confidence Assessment:**

- **Table Stakes Features:** MEDIUM to HIGH — Verified across multiple platforms (Polymarket, PancakeSwap, Azuro) and prediction market research
- **Differentiators:** MEDIUM — Based on Telegram Mini App research, Pyth oracle capabilities, and Strike's unique positioning
- **Anti-Features:** MEDIUM — Derived from documented failures, complexity analysis, and scope management for 9-day timeline
- **Competitor Analysis:** MEDIUM — Official docs for some platforms (Polymarket, PancakeSwap), web research for others
- **Parimutuel UX Considerations:** MEDIUM — Based on academic research (Ottaviani & Sørensen), industry best practices, and traditional betting patterns
- **Technical Complexity:** MEDIUM to HIGH — Builder's familiarity with Pyth, Solidity experience, but new to Telegram Mini Apps SDK

**Key Limitations:**

1. Telegram Mini App prediction markets are emerging — limited direct precedent (mostly TON-based examples)
2. WalletConnect integration in Telegram context less documented than standard Web3 apps
3. Parimutuel vs order book trade-offs based on PancakeSwap model, not extensive research
4. 9-day timeline constraint heavily influences feature prioritization (aggressive MVP scope)
5. BNB Chain prediction market ecosystem less documented than Polygon/Ethereum

**Recommended Phase-Specific Research:**

- **Before development:** Deep dive on Telegram Mini App WalletConnect integration patterns for BSC (not TON)
- **During smart contract work:** Parimutuel pool math validation and edge cases (no bets on one side, single bettor, rounding errors)
- **Before launch:** Pyth Network oracle reliability testing on BNB Chain (uptime, latency, staleness handling)
- **Post-launch:** User behavior analysis on early vs late betting patterns (inform v2 features)

---
*Feature research for: Strike Binary Parimutuel Prediction Market*
*Researched: 2026-02-10*
*Confidence: MEDIUM (verified with multiple sources; some gaps on Telegram Mini Apps SDK specific to BSC wallet integration)*
