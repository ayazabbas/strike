# Pitfalls Research

**Domain:** Parimutuel Prediction Market on BSC with Pyth Oracle and Telegram Mini-App
**Researched:** 2026-02-10
**Confidence:** HIGH (Pyth integration), MEDIUM (BSC/Telegram integration), MEDIUM (parimutuel contracts)

---

## Critical Pitfalls

### Pitfall 1: Stale Price Usage Leading to Incorrect Resolution

**What goes wrong:**
Market resolves with an outdated Pyth price, causing wrong winners and protocol reputation damage. Users betting on UP win when they should have lost (or vice versa) because the resolution used a price from 5 minutes before expiry instead of the actual expiry time.

**Why it happens:**
Pyth's pull-based model means prices aren't automatically updated onchain. Developers assume the latest onchain price is current, but it could be stale. The default Pyth SDK includes staleness checks, but if you bypass the SDK or set too-lenient staleness thresholds, you'll use old data.

**How to avoid:**
- Always use `getPriceNoOlderThan()` instead of raw price queries
- Set strict staleness threshold (30 seconds max for 1hr markets, 60 seconds for 24hr markets)
- Require fresh price update in the same transaction that resolves the market
- Never trust an onchain Pyth price without checking `publishTime`
- In resolution function: `updatePriceFeeds()` THEN `getPriceNoOlderThan()` in same tx

**Warning signs:**
- Resolution transaction doesn't include Pyth price update
- Price fetch doesn't check `publishTime` field
- No revert on stale price (contract continues with old data)
- Using deprecated `getPrice()` instead of `getPriceNoOlderThan()`

**Phase to address:**
Phase 1 (Core Contracts) — implement staleness checks from day one

**Severity:** CRITICAL — breaks core product integrity

---

### Pitfall 2: Rounding Errors in Parimutuel Payout Causing "Dust" Loss

**What goes wrong:**
Pool has 100 BNB, winners should get 95 BNB (after 5% fee). But due to integer division rounding, payouts sum to 94.97 BNB. The 0.03 BNB gets stuck in contract forever OR goes to protocol (creating unfair fee).

Worse case: User with small stake gets 0 payout due to rounding down, even though they won.

**Why it happens:**
Solidity doesn't have decimals. Division rounds down. When calculating `userPayout = winningPool * userStake / totalWinningStake`, small stakes round to zero. Even large stakes lose wei on each division.

Example:
```solidity
// BROKEN
function calculatePayout(uint256 userStake) public view returns (uint256) {
    return (winningPool * userStake) / totalStaked; // Rounds down, dust accumulates
}
```

**How to avoid:**
- Track total distributed separately, let last claimer get remainder
- Use a withdrawal pattern where users claim individually (don't loop and send)
- Consider minimum stake size (0.001 BNB) to avoid dust-level positions
- Add dust sweep function to send remainder to last claimer or protocol
- Test with odd numbers: 3 BNB pool split among 7 winners

**Warning signs:**
- Payouts calculated in a loop and sent immediately
- No remainder tracking
- Sum of individual payouts < expected total
- No minimum stake requirement
- Tests only use easily divisible numbers

**Phase to address:**
Phase 1 (Core Contracts) — payout math is foundational

**Severity:** CRITICAL — financial loss, user trust damage

---

### Pitfall 3: Front-Running Market Resolution for Last-Second Bets

**What goes wrong:**
Attacker watches mempool. Market expires at block 1000. Attacker sees resolution tx in mempool showing price went UP. Attacker front-runs with massive UP bet at block 999, then lets resolution happen at block 1000. They win instantly with zero risk.

**Why it happens:**
Public mempool + predictable resolution outcome + accepting bets until exact expiry second. Once someone calls resolve with the price update, the outcome is known but bets might still be accepted if there's a timing gap.

**How to avoid:**
- Stop accepting bets BEFORE resolution can happen (e.g., 5 minutes before expiry for 1hr markets)
- Or: Use commit-reveal for resolution (harder, maybe overkill for hackathon)
- Or: Accept that small-scale front-running is possible but economically limited
- Document this as known limitation for MVP
- Future: Implement betting cutoff buffer

**Warning signs:**
- `placeBet()` only checks `block.timestamp < expiryTime`
- No betting cutoff buffer
- Resolution can be called at exact expiry second
- Large bets placed in same block as resolution

**Phase to address:**
Phase 1 (Core Contracts) — if adding cutoff, do it early. Otherwise document as "Phase 2: Anti-Gaming"

**Severity:** HIGH — exploitable but mitigatable with buffer, not protocol-breaking

---

### Pitfall 4: WalletConnect Broken Inside Telegram Mini-App (iframe issue)

**What goes wrong:**
User clicks "Connect Wallet" in your Telegram mini-app. WalletConnect modal opens but wallet doesn't respond. On mobile, deep links fail. On desktop, popup gets blocked. Users can't connect, can't use your app.

**Why it happens:**
Telegram mini-apps run inside an iframe. WalletConnect tries to open wallets via `window.open()` and deep links. These are heavily restricted in iframes for security. MetaMask deep links (`metamask://`) fail with `ERR_UNKNOWN_URL_SCHEME` on Android. Popup blockers kill desktop flows.

Known issue from WalletConnect GitHub: "WalletConnect won't function within an iframe" (Discussion #4574)

**How to avoid:**
- Use a wallet SDK designed for Telegram: Bitget's OmniConnect overrides `window.open()` specifically for Telegram iframes
- Or: Test with TON Connect instead (Telegram-native, but locks you into TON ecosystem)
- Or: Use Telegram's built-in wallet features (if available for BSC)
- Or: Provide web link fallback that opens outside Telegram
- **For hackathon:** Test WalletConnect EARLY (day 1) and pivot if it fails

**Warning signs:**
- WalletConnect integration never tested in actual Telegram app
- Only tested in browser, not Telegram mobile/desktop
- No fallback wallet connection method
- Assuming standard WalletConnect Web3Modal "just works"

**Phase to address:**
Phase 2 (Frontend Integration) — MUST validate this in first 2 days or risk total failure

**Severity:** CRITICAL — if wallet connection fails, app is unusable

---

### Pitfall 5: Pyth Price Update Costs Making Small Bets Unprofitable

**What goes wrong:**
User wants to bet 0.001 BNB (~$0.50). But updating Pyth price costs 0.0003 BNB in gas + Pyth fee. User pays 30% overhead just to place a bet. They don't bet, market has no liquidity.

**Why it happens:**
Pyth uses pull model: user pays gas to update price onchain. Every bet needs current price (for odds display). Every resolution needs price update. Gas + Pyth's 1 wei fee (minimal) + BSC gas adds up. For 1hr markets with frequent betting, this compounds.

BSC gas is low (~0.1 Gwei per current data) but price update is still ~50k-100k gas operation.

**How to avoid:**
- **For MVP:** Let users bet without triggering price updates (use last known price for odds display, update only on resolution)
- Batch price updates: only update if price older than 5 minutes
- Document minimum economical bet size based on gas costs
- Consider subsidizing price updates for first N users (hackathon demo boost)
- Show gas cost estimate BEFORE user signs transaction

**Warning signs:**
- Every `placeBet()` call includes `updatePriceFeeds()`
- No caching of recent price updates
- No gas cost warning in UI
- Minimum bet size doesn't account for gas overhead

**Phase to address:**
Phase 1 (Core Contracts) — decide update frequency. Phase 2 (Frontend) — show gas estimates

**Severity:** HIGH — affects user economics and adoption

---

### Pitfall 6: No Winners Edge Case Breaks Payout Logic

**What goes wrong:**
Market: "Will BTC be above $100k at 5pm?" Current price: $100,000.00 exactly. Market resolves at exactly $100,000.00. Neither UP nor DOWN wins. Payout function divides by zero (total winning stake = 0). Contract reverts. All funds locked forever.

Alternative: Everyone bet UP. Price goes DOWN. DOWN pool has 0 BNB. Division by zero.

**Why it happens:**
Parimutuel logic assumes there's a winning side with non-zero stake. Real-world scenarios: exact tie, or everyone bets same side. Standard payout formula `userPayout = winningPool * userStake / totalWinningStake` fails when `totalWinningStake = 0`.

**How to avoid:**
- Define tie behavior: if exact match, refund everyone (no winners)
- Handle empty pool: if no one bet the winning side, all losers get refund (or protocol keeps)
- Add safety checks:
  ```solidity
  if (winningPool == 0) {
      // Refund all bettors
  } else if (totalWinningStake == 0) {
      // Edge case: opposite side empty, send to protocol or refund
  }
  ```
- Test edge cases: all UP, all DOWN, exact price match

**Warning signs:**
- No zero-division checks in payout math
- No handling for "everyone bet wrong" scenario
- Tests only cover balanced pools
- No tie resolution logic

**Phase to address:**
Phase 1 (Core Contracts) — test edge cases early

**Severity:** HIGH — can lock user funds

---

### Pitfall 7: Telegram Mini-App State Loss on Background (localStorage unreliable)

**What goes wrong:**
User picks UP, enters bet amount, switches to another Telegram chat, comes back 2 minutes later. App reloaded fresh. Their form state is gone. They have to start over. Frustrated user abandons.

Worse: User places bet, tx is pending, they switch chats, come back, app doesn't show pending tx. They think it failed and bet again. Double bet.

**Why it happens:**
Telegram controls mini-app lifecycle. Switching chats can suspend OR kill the app. When user returns, Telegram might reload fresh. localStorage can be cleared between sessions (platform-dependent). In-memory React state is 100% gone.

**How to avoid:**
- Never rely on in-memory state for critical flows
- Save form state to Telegram.CloudStorage (Telegram's persistent storage, 5MB per user)
- For pending transactions: poll onchain status on every app load
- Show "Resuming..." if detecting partial state
- Use optimistic UI: assume bet succeeded, verify onchain
- Design for interruption: every screen should be enterable mid-flow

**Warning signs:**
- Only using React useState for bet flow
- No persistence layer
- Assuming user completes flow in one session
- Not testing "switch chat and return" scenario

**Phase to address:**
Phase 2 (Frontend Integration) — critical for Telegram UX

**Severity:** HIGH — kills conversion, causes user confusion

---

### Pitfall 8: Auto-Market Creation Fails and No Markets Exist

**What goes wrong:**
It's 3pm. Your scheduled cron job should have created the 3pm-4pm BTC market. Cron fails (server down, RPC timeout, insufficient gas). No market exists. Users open app, see "No active markets." They leave. Your hackathon demo has no markets to show.

**Why it happens:**
Auto-market creation depends on:
- Off-chain scheduler (cron, cloud function)
- RPC connection to BSC
- Wallet with gas
- No contract bugs

Any single point of failure = no markets. For hackathon timeline, this is high risk.

**How to avoid:**
- **For MVP:** Create markets manually or via simple script you run locally
- Add permissionless market creation: anyone can create next market (incentivized with small reward)
- Implement "create if not exists" logic: any user action triggers market creation check
- Have fallback: create 24 hours of markets upfront before demo
- Monitor market creation with alerts

**Warning signs:**
- Single point of failure for market creation
- No manual fallback for creating markets
- Cron job never tested under failure conditions
- No monitoring/alerts for missing markets

**Phase to address:**
Phase 3 (Market Automation) — but have manual backup for Phase 1 testing

**Severity:** MEDIUM — breaks demo but preventable with manual fallback

---

### Pitfall 9: Reentrancy in Payout Withdrawal Function

**What goes wrong:**
User calls `claimWinnings()`. Contract sends them 10 BNB. User's contract receives the BNB, immediately calls `claimWinnings()` again before the first call marks them as claimed. They drain the pool by claiming multiple times.

Classic reentrancy attack. Famously cost The DAO $150M in 2016. Still happening in 2023+ (~$350M total losses).

**Why it happens:**
```solidity
// VULNERABLE
function claimWinnings() external {
    uint256 amount = calculatePayout(msg.sender);
    payable(msg.sender).call{value: amount}(""); // External call BEFORE state update
    userClaimed[msg.sender] = true; // Too late!
}
```

External call hands control to attacker before state is updated.

**How to avoid:**
- **Checks-Effects-Interactions pattern:** Update state BEFORE external calls
  ```solidity
  function claimWinnings() external {
      uint256 amount = calculatePayout(msg.sender);
      require(!userClaimed[msg.sender], "Already claimed");
      userClaimed[msg.sender] = true; // State update FIRST
      payable(msg.sender).call{value: amount}(""); // External call LAST
  }
  ```
- Use OpenZeppelin's `ReentrancyGuard` modifier
- Use Solidity 0.8.0+ (has built-in overflow protection, not reentrancy)
- Pull pattern instead of push: user initiates withdrawal, you don't loop and send

**Warning signs:**
- External calls (`.call`, `.transfer`, `.send`) before state updates
- No `ReentrancyGuard` on payout functions
- Loop that sends ether to multiple addresses
- No reentrancy testing in test suite

**Phase to address:**
Phase 1 (Core Contracts) — security fundamental

**Severity:** CRITICAL — contract can be drained

---

### Pitfall 10: Contract Verification Fails on BSCScan, Demo Shows Unverified Contract

**What goes wrong:**
You deploy contract to BSC. BSCScan shows bytecode but no source. Hackathon judges see "Unverified Contract" and assume it's sketchy or not real. You lose credibility points.

**Why it happens:**
Verification requires exact match: same compiler version, same optimization settings, same dependencies. Common issues:
- GitHub imports fail: "File import callback not supported"
- Compiler version mismatch
- Optimization settings differ from deployment
- Flattening with OpenZeppelin imports breaks

**How to avoid:**
- Use Hardhat/Foundry's built-in verification: `forge verify-contract` or `hardhat verify`
- Test verification on testnet BEFORE mainnet
- Keep deployment script with exact compiler settings documented
- Use relative imports, not GitHub URLs
- Have contract flattened as backup (Hardhat flatten plugin)
- Verify immediately after deployment (don't wait until demo day)

**Warning signs:**
- Never verified a contract on BSCScan before
- Using GitHub imports in Solidity
- No verification script in deployment flow
- Waiting until last day to verify

**Phase to address:**
Phase 1 (Core Contracts) — verify first testnet deployment immediately

**Severity:** MEDIUM — doesn't break functionality but hurts hackathon scoring

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Hardcoded Pyth price feed IDs | Faster development, no config management | Can't easily add new assets, requires redeployment | Acceptable for hackathon MVP with only BTC/BNB |
| Manual market creation instead of automated | Simpler, no cron infrastructure | Not scalable, requires manual intervention | Acceptable for demo, must automate post-hackathon |
| No admin pause function | Less contract code, simpler audits | Can't stop market in emergency | Never acceptable — add pause from day one |
| Fixed protocol fee (no governance) | No governance complexity | Can't adjust fee without redeployment | Acceptable for MVP, add governance later |
| Skip commit-reveal for front-running | Simpler contract logic | Vulnerable to resolution front-running | Acceptable with betting cutoff buffer as mitigation |
| No market history/archive | Smaller contract, less storage | Users can't see past performance | Acceptable for MVP, track off-chain |
| Single contract for all markets | Easier deployment, less gas | Harder to upgrade specific market types | Acceptable for MVP with limited scope |
| localStorage for wallet state | No backend needed | Unreliable in Telegram, state loss | Never acceptable — use Telegram.CloudStorage |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Pyth Oracle | Using `getPrice()` without staleness check | Always use `getPriceNoOlderThan(maxAge)` |
| Pyth Oracle | Not updating price in resolution transaction | Call `updatePriceFeeds(updateData)` in same tx as resolution |
| Pyth Oracle | Forgetting to send update fee in msg.value | Include Pyth fee: `{value: updateFee}` when calling update |
| WalletConnect in Telegram | Using standard Web3Modal without iframe fixes | Use Telegram-specific wallet SDK or override window.open() |
| WalletConnect in Telegram | Only testing in browser, not actual Telegram app | Test in Telegram Desktop + Mobile from day 1 |
| BSC RPC | Relying on public RPC for all requests | Use paid RPC (Ankr, QuickNode) or expect rate limiting |
| Telegram Mini-App | Storing critical state in localStorage | Use Telegram.CloudStorage API for persistence |
| Telegram Mini-App | Assuming user stays in app for entire flow | Design for interruption, resume from any point |
| BSC Gas Estimation | Using eth_estimateGas as exact cost | Add 20% buffer, BSC gas can spike |
| Market Resolution | Allowing anyone to resolve at exact expiry second | Add resolution delay or betting cutoff buffer |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Fetching all historical markets onchain | App freezes loading 1000+ past markets | Paginate with offset/limit, or use subgraph/indexer | >100 markets |
| Calculating payouts for all users in one transaction | Resolution tx runs out of gas | Use pull-based withdrawals, not push | >50 users per market |
| Updating Pyth price on every bet | High gas costs per bet, slow UX | Only update if price >5min old, batch updates | Every single bet |
| Storing full market data onchain | High deployment/creation gas costs | Store minimal data onchain, metadata off-chain/IPFS | >10 market parameters |
| No event indexing for user positions | Frontend queries all markets to find user's bets | Emit events with indexed user address, use event logs | >20 markets total |
| Deep nesting in Telegram mini-app UI | Slow rendering, laggy on mobile | Flatten component tree, lazy load | >5 levels deep |
| Polling BSC RPC every second for tx status | Rate limiting, high costs | Use WebSocket subscriptions or poll every 3-5s | Continuous polling |

---

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| External call before state update (reentrancy) | Contract drained via recursive calls | Use Checks-Effects-Interactions pattern + ReentrancyGuard |
| No access control on market creation | Anyone creates spam markets | Require msg.sender == admin or permissioned creator |
| No validation on Pyth price feed ID | Wrong asset price used for resolution | Whitelist feed IDs, validate against expected asset |
| Accepting bets after market expiry | Late bets with known outcome | Require block.timestamp < expiryTime in placeBet() |
| No minimum bet enforcement | Dust bets break payout rounding | Enforce minimum stake (e.g., 0.001 BNB) |
| Division by zero in payout calculation | Contract reverts, funds locked | Check totalWinningStake > 0 before division |
| Unbounded loop in payout distribution | Gas limit exceeded, tx fails | Never loop over unbounded array, use pull withdrawals |
| Weak random number generation | Predictable if used for tiebreakers | Don't use block.timestamp or blockhash for randomness |
| No pause mechanism | Can't stop contract in emergency | Implement OpenZeppelin Pausable from day one |
| Hardcoded gas price in transactions | Tx stuck if network congestion spikes | Use dynamic gas estimation with buffer |

---

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| No gas cost preview before betting | User surprised by high tx cost, abandons | Show estimated gas + total cost before signing |
| Unclear odds display | User doesn't know potential payout | Show "If you bet X, you could win Y" with current odds |
| No pending transaction indicator | User bets, tx pending, they think it failed, bet again | Show spinner with tx hash link during confirmation |
| Market expiry time in UTC only | User confused about timezone | Show time in user's local timezone + countdown |
| No explanation of parimutuel model | User expects fixed odds, surprised by changing odds | Tooltip: "Odds change as more people bet. Final payout depends on pool split." |
| Can't see active positions easily | User forgets they have bets | Dashboard showing "Your Active Bets" front and center |
| No history of past bets | User can't learn from results | Show resolved markets with W/L and payout amount |
| Wallet connection fails silently | User clicks connect, nothing happens, rage quits | Show error message + fallback (try different wallet) |
| Long wallet address as identifier | Confusing in bet history | Show shortened address (0x1234...5678) with copy button |
| No confirmation before large bets | User accidentally bets 10 BNB instead of 0.1 | "You're betting 10 BNB (~$5000). Confirm?" for bets >1 BNB |

---

## "Looks Done But Isn't" Checklist

- [ ] **Pyth Integration:** Tested with REAL Pyth price updates on BSC testnet (not mocked prices)
- [ ] **Wallet Connection:** Tested inside actual Telegram app on mobile AND desktop (not just browser)
- [ ] **Market Resolution:** Verified permissionless resolution works (called by non-admin address)
- [ ] **Payout Distribution:** Tested with odd numbers and rounding (not just 100 BNB split between 2 users)
- [ ] **Edge Cases:** Tested no-winner scenario, all-one-side scenario, exact price tie
- [ ] **Gas Costs:** Calculated realistic gas costs on BSC mainnet (not just "it works on testnet")
- [ ] **Contract Verification:** Contract verified on BSCScan (not just deployed)
- [ ] **State Persistence:** Telegram mini-app state survives app reload/backgrounding
- [ ] **Error Handling:** Failed transactions show user-friendly errors (not just console.log)
- [ ] **Time Zones:** Market expiry displays correctly in different timezones
- [ ] **Mobile UX:** Tested on actual mobile device (not just browser DevTools mobile view)
- [ ] **RPC Reliability:** App handles RPC failures gracefully (fallback provider or retry logic)
- [ ] **Empty States:** UI for "no active markets" / "no positions" shows helpful message
- [ ] **Decimal Handling:** Price display doesn't show "0.0000000012 BTC" (formatted properly)

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Stale price used in resolution | HIGH | 1. Pause contract 2. Calculate correct winners 3. Manual airdrop to correct winners 4. Redeploy contract with fix 5. Reputation damage |
| Reentrancy attack drains pool | CRITICAL | No recovery — funds lost. Emergency pause if caught early. Insurance fund if planned ahead. |
| Rounding error locks small amounts | LOW | Add sweep function to collect dust and redistribute or donate |
| WalletConnect doesn't work in Telegram | MEDIUM | 1. Switch to different wallet SDK 2. Rebuild wallet integration 3. Re-test (2-3 days lost) |
| Auto-market creation fails | LOW | Manually create markets via script, add monitoring for future |
| No winners edge case locks funds | MEDIUM | 1. If caught in testing: redeploy with fix 2. If in production: manual refund tx from admin wallet |
| Contract not verified | LOW | Run verification script post-deployment, 30 minutes max |
| State loss in Telegram app | MEDIUM | Implement CloudStorage, refactor state management (1 day) |
| Front-running discovered post-launch | MEDIUM | 1. Add betting cutoff buffer 2. Redeploy contract 3. Migrate users (if significant funds) |
| Pyth fee not included in msg.value | HIGH | 1. Redeploy contract 2. Users must rebind to new contract 3. Lose existing positions (if not migrated) |

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Stale price usage | Phase 1: Core Contracts | Unit test with manipulated timestamps, verify reverts on stale price |
| Rounding errors in payout | Phase 1: Core Contracts | Fuzz testing with odd pool sizes, verify dust < 0.0001 BNB |
| Front-running resolution | Phase 1: Core Contracts | Document cutoff buffer, test betting restriction after expiry - buffer |
| WalletConnect in Telegram broken | Phase 2: Frontend Integration | Test in Telegram Desktop + Mobile within first 2 days |
| Pyth update costs too high | Phase 1: Core + Phase 2: Frontend | Calculate gas costs, show estimate in UI, test with real BSC gas prices |
| No winners edge case | Phase 1: Core Contracts | Test all-UP, all-DOWN, exact-tie scenarios in unit tests |
| Telegram state loss | Phase 2: Frontend Integration | Test: open app, place bet, switch chat, return — bet state persists |
| Auto-market creation fails | Phase 3: Market Automation | Manual fallback for MVP, automated with monitoring post-hackathon |
| Reentrancy vulnerability | Phase 1: Core Contracts | Reentrancy test suite, formal audit if time permits |
| Contract verification fails | Phase 1: Core Contracts | Verify immediately after first testnet deployment |

---

## Hackathon-Specific Time Traps

### Time Trap 1: WalletConnect Integration Hell (2-3 days lost)
**What happens:** You spend day 1-2 building contracts. Day 3 you start frontend. Day 4 you integrate WalletConnect. It doesn't work in Telegram. You spend day 5-6 debugging, trying different SDKs. Day 7 you discover it's an unfixable iframe issue. You pivot to different wallet solution. Day 8-9 you rebuild integration. No time left for polish.

**Prevention:** Test wallet connection in Telegram on DAY 1. Validate it works before building everything else.

---

### Time Trap 2: BSC Testnet Faucet Limits (half day lost)
**What happens:** You need testnet BNB to test. Faucet gives 0.5 BNB per day per wallet. You burn through it in 20 test transactions. You create new wallet, request more. Faucet rate-limits you. You wait 6 hours. Testing grinds to halt.

**Prevention:**
- Request max testnet BNB from ALL available faucets on day 1
- Create 5 different wallets, get BNB for each
- Use local Hardhat/Foundry fork for most testing (free, unlimited)
- Only use testnet for final integration tests

---

### Time Trap 3: Pyth Price Feed ID Confusion (4 hours lost)
**What happens:** You integrate Pyth. Contract deploys. You try to fetch BTC price. Returns 0. You debug for hours. Turns out you used wrong price feed ID for BSC (used Ethereum's ID, not BSC's).

**Prevention:**
- Check Pyth's official price feed IDs for BSC: https://www.pyth.network/developers/price-feed-ids
- Verify feed ID in Pyth's contract before deploying
- Test price fetch in isolation BEFORE integrating into market contract

---

### Time Trap 4: Over-Engineering the Demo (2 days lost)
**What happens:** You build fancy UI animations, beautiful charts, mobile-responsive design. Day 8 arrives, core functionality still has bugs. You submit broken app with pretty UI. Judges can't complete basic flow.

**Prevention:**
- Ugly UI that works > Pretty UI that's broken
- For hackathon: Build only "happy path" (create market, place bet, resolve, claim)
- Skip: bet history, charts, animations, mobile optimization
- Polish ONLY if everything works with 24 hours to spare

---

### Time Trap 5: Last-Minute Contract Redeployment Cascade (1 day lost)
**What happens:** Day 8, you find critical bug in contract. You redeploy. Frontend has old contract address hardcoded. You update address. ABI changed. You regenerate bindings. Something breaks in integration. You debug. More issues surface. Chain reaction of fixes.

**Prevention:**
- Use environment variables for contract addresses (never hardcode)
- Generate ABI in build script automatically
- Test full redeploy flow on day 3 (practice deploying fresh contract, updating frontend, testing end-to-end)
- Keep deployment script that does: deploy + verify + update frontend config

---

### Time Trap 6: Subgraph/Indexer Rabbit Hole (never finishes)
**What happens:** You think "I'll use The Graph to index events." You spend day 5-6 learning subgraph development, writing schema, debugging deployment. Day 7 it's still not working. You abandon it and query contracts directly. Time wasted.

**Prevention:**
- For 9-day hackathon: NO subgraphs, NO indexers
- Query contract events directly with `eth_getLogs` via ethers.js
- Cache results in frontend state
- It's fine if "view all historical markets" takes 3 seconds

---

### Time Trap 7: Testing in Production (no time left to fix)
**What happens:** You test on testnet sporadically. Day 8 you deploy to mainnet for demo. Judges test it. Gas costs are 10x higher than expected. Users rage. You have 12 hours to fix. You can't redeploy (already shared contract address in submission).

**Prevention:**
- Deploy to testnet by day 5 MAX
- Test complete user flow on testnet: create market, 5 people bet, wait for expiry, resolve, claim
- Estimate REAL gas costs on BSC mainnet (use gas estimation tools)
- Deploy to mainnet on day 8 with buffer for issues

---

### Time Trap 8: Telegram Bot Approval Delay (no delay, but plan for it)
**What happens:** You assume Telegram bots need approval. You submit for review. You wait. Demo day arrives, bot not approved. Panic.

**Reality:** Telegram mini-apps don't need approval for testing. You get bot token instantly from @BotFather. But you might THINK you need approval and waste time worrying.

**Prevention:**
- Know the process: @BotFather gives instant token, no approval needed for testing
- Create bot on day 1 to confirm
- Don't confuse mini-apps with bot store submissions (different process)

---

### Time Trap 9: Perfectionist Documentation (1 day lost)
**What happens:** You write beautiful README, detailed architecture docs, inline comments everywhere. Day 9 arrives, you're still commenting code. Demo isn't polished.

**Prevention:**
- For hackathon: Ship code > document code
- Write minimal README: "What it does, how to run it, demo video link"
- Skip architecture docs
- Comment only critical/confusing sections
- Focus on demo video script, not documentation

---

### Time Trap 10: Not Recording Demo Early Enough (submission panic)
**What happens:** 2 hours before deadline, you record demo. Something breaks. You debug frantically. You record again. Audio is bad. You re-record. You run out of time. You submit buggy demo or miss deadline.

**Prevention:**
- Record demo video on day 7 (even if features incomplete)
- Script it: "Hi, I'm showing Strike. Step 1: ... Step 2: ..."
- Practice twice, record third time
- Have backup: screenshots + voiceover if live demo fails
- Submit 6 hours early, not 6 minutes early

---

## Confidence Assessment by Category

| Category | Confidence | Source Basis |
|----------|------------|--------------|
| Pyth Oracle Integration | HIGH | Official Pyth docs, builder works at Pyth Network |
| BSC Smart Contract Security | MEDIUM | General Solidity best practices, BSC-specific issues from forums |
| Telegram Mini-App Limitations | MEDIUM | GitHub issues, dev blogs, official Telegram docs |
| WalletConnect in Telegram | MEDIUM | Multiple GitHub discussions confirming iframe issues |
| Parimutuel Contract Logic | MEDIUM | General prediction market patterns, some project examples |
| Hackathon Time Traps | HIGH | Common hackathon failure patterns, web3 specific issues |
| Gas Optimization | HIGH | Documented Solidity patterns, BSC gas data |
| Rounding/Math Errors | HIGH | Known Solidity integer division behavior |
| Front-Running Risks | MEDIUM | DeFi attack patterns, prediction market specific vectors |
| Edge Case Handling | HIGH | Standard contract testing best practices |

---

## Sources

### Pyth Oracle Integration
- [Best Practices | Pyth Developer Hub](https://docs.pyth.network/price-feeds/core/best-practices)
- [Fees | Pyth Developer Hub](https://docs.pyth.network/price-feeds/core/how-pyth-works/fees)
- [Current Fees | Pyth Developer Hub](https://docs.pyth.network/price-feeds/core/current-fees)

### Telegram Mini-App Issues
- [Wallet connect not work on telegram mini app · WalletConnect/walletconnect-monorepo · Discussion #4574](https://github.com/WalletConnect/walletconnect-monorepo/discussions/4574)
- [Connect wallet with web3Modal when using telegram miniapp/ external browser is not stable · Issue #2021](https://github.com/telegraf/telegraf/issues/2021)
- [Telegram Mini App Integration | Bitlayer](https://docs.bitlayer.org/docs/Build/DeveloperResources/Telegram-Mini-App-Integration/)
- [Everything You Need to Know About Telegram Mini Apps — 2026 Guide](https://magnetto.com/blog/everything-you-need-to-know-about-telegram-mini-apps)
- [Tips and tricks | The Open Network](https://docs.ton.org/v3/guidelines/dapps/tma/guidelines/tips-and-tricks)

### Smart Contract Security
- [Reentrancy Attacks](https://owasp.org/www-project-smart-contract-top-10/2025/en/src/SC05-reentrancy-attacks.html)
- [Welcome back: A systematic literature review of smart contract reentrancy and countermeasures](https://www.sciencedirect.com/science/article/pii/S2096720925000740)
- [Frontrunning - Smart Contract Security Field Guide](https://scsfg.io/hackers/frontrunning/)
- [Front-Running In Blockchain: Real-Life Examples & Prevention](https://hacken.io/discover/front-running/)

### Parimutuel Contract Patterns
- [Program the Blockchain | Writing a Parimutuel Wager Contract](https://programtheblockchain.com/posts/2018/05/08/writing-a-parimutuel-wager-contract/)
- [Parimutuel Betting on Blockchain: A Case Study on Horse Racing](https://www.researchgate.net/publication/390753436_Parimutuel_Betting_on_Blockchain_A_Case_Study_on_Horse_Racing)

### Solidity Math Issues
- [Arithmetic Underflow and Overflow Vulnerabilities In Solidity](https://www.halborn.com/blog/post/arithmetic-underflow-and-overflow-vulnerabilities-in-solidity)
- [Integer division rounding errors · Issue #54](https://github.com/stakewise/contracts/issues/54)
- [Bugs in code: Understanding Rounding Issues](https://0xfave.beehiiv.com/p/bugs-code-understanding-rounding-issues)

### Prediction Market Edge Cases
- [On-Chain Parlay Prediction Markets with Deep Liquidity](https://medium.com/@gwrx2005/on-chain-parlay-prediction-markets-with-deep-liquidity-e359e6040116)
- [How Prediction Markets Handle Liquidity, Noise, and Manipulation](https://aashishreddy.substack.com/p/prediction-markets-objections)

### Oracle Resolution and Disputes
- [Resolution - Polymarket Documentation](https://docs.polymarket.com/developers/resolution/UMA)
- [Oracle Manipulation in Polymarket 2025 | Orochi Network](https://orochi.network/blog/oracle-manipulation-in-polymarket-2025)
- [Why Is Polymarket's UMA Controversial? | Webopedia](https://www.webopedia.com/crypto/learn/polymarkets-uma-oracle-controversy/)

### BSC Deployment
- [BSC Smart Contracts: Ultimate Guide to Development & DeFi Integration](https://www.rapidinnovation.io/post/how-to-create-a-smart-contract-on-bsc)
- [Help Verifying BSC smart contract on BSCScan - OpenZeppelin Forum](https://forum.openzeppelin.com/t/help-verifying-bsc-smart-contract-on-bscscan/9337)
- [BNB Smart Chain Gas Price Tracker](https://www.quicknode.com/gas-tracker/bsc-bnb-smart-chain)

### Gas Optimization
- [Gas optimization tips to improve smart contract efficiency](https://www.nadcab.com/blog/gas-optimization-in-smart-contracts)
- [GasAgent: A Multi-Agent Framework for Automated Gas Optimization](https://arxiv.org/abs/2507.15761)
- [Smart Contract Gas Optimization: Reduce Blockchain Costs](https://fxis.ai/edu/smart-contract-gas-optimization/)

### Hackathon Best Practices
- [Hackathon 101: The Ultimate Survival Guide for First-Time Web3 Developers](https://medium.com/@BizthonOfficial/hackathon-101-the-ultimate-survival-guide-for-first-time-web3-developers-4f3d51fbab0d)
- [3 Effective Tips for Managing Your Time During a Hackathon](https://tips.hackathon.com/article/3-effective-tips-for-managing-your-time-during-a-hackathon)
- [Avoid These Five Pitfalls at Your Next Hackathon | MIT Sloan](https://sloanreview.mit.edu/article/avoid-these-five-pitfalls-at-your-next-hackathon/)

### Testing
- [Testing smart contracts | ethereum.org](https://ethereum.org/developers/docs/smart-contracts/testing/)
- [Smart Contract Unit Testing: Complete Guide 2024](https://www.krayondigital.com/blog/smart-contract-unit-testing-complete-guide-2024)

---

*Pitfalls research for: Strike Prediction Market (BSC + Pyth + Telegram)*
*Researched: 2026-02-10*
*Confidence: HIGH (Pyth), MEDIUM (BSC/Telegram integration), MEDIUM (parimutuel patterns)*
