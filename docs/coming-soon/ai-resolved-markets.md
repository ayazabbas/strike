# AI-Resolved Markets

> **Status: Coming Soon** — This feature is under active development.

## Overview

Strike currently resolves all markets using **Pyth price feeds** — deterministic, on-chain price data. This works perfectly for quantitative markets ("Will BTC be above $90k at expiry?") but limits the types of events Strike can support.

**AI-Resolved Markets** extend Strike to support **qualitative and subjective events** — geopolitics, culture, politics, sports, and more — by integrating the [Flap AI Oracle](https://docs.flap.sh/flap/developers/preview/flap-ai-oracle) as an alternative resolution source.

### What This Unlocks

| Current (Pyth-only) | With AI Resolution |
|---|---|
| BTC above $X by date? | Will Iran close the Strait of Hormuz by March? |
| ETH price at expiry? | Will there be a Russia/Ukraine ceasefire by Q2? |
| BNB above/below? | Who wins the 2026 FIFA World Cup? |
| — | Will GTA VI release before June 2026? |
| — | Oscars Best Picture winner? |

These are exactly the market categories generating the highest volumes on existing prediction platforms — geopolitics alone drove **$529M+ in weekly volume** in March 2026.

## How It Works

AI-resolved markets use a **commit-and-reveal** oracle pattern (similar to Chainlink VRF, but for LLM reasoning):

```
┌─────────────┐     ① prompt + fee     ┌──────────────────┐
│             │ ──────────────────────► │                  │
│   Strike    │                         │  Flap AI Oracle  │
│  Resolver   │ ◄────────────────────── │    (on-chain)    │
│             │   ⑤ callback: choice    │                  │
└─────────────┘                         └────────┬─────────┘
                                                 │
                                        ② emit event
                                                 │
                                        ┌────────▼─────────┐
                                        │  Oracle Backend   │
                                        │  (off-chain)      │
                                        │                   │
                                        │  ③ LLM reasoning  │
                                        │  ④ IPFS proof     │
                                        └──────────────────┘
```

1. **Market expires** → the `FlapAIResolver` contract sends the market question as a prompt to the Flap AI Oracle, paying the model fee in BNB
2. **Oracle backend** picks up the request event, feeds the prompt to the selected LLM (Gemini Flash, Claude Sonnet, or DeepSeek R1)
3. **LLM reasons** over the question using current information and returns a numeric choice
4. **Proof is pinned** to IPFS — full reasoning trace, model version, temperature, and salt are permanently auditable
5. **Oracle calls back** with the result → the resolver maps the choice to a market outcome (Yes/No) and settles the market

### Resolution Prompt Pattern

For a binary geopolitical market, the on-chain prompt would look like:

```
Based on publicly available news and information as of [expiry date]:
Has [event description] occurred?

0 = No — the event has not occurred
1 = Yes — the event has occurred

Consider only verified reports from major news agencies.
Respond with only the number of your choice.
```

The oracle returns a `uint8` choice, and the resolver maps `0 → No` and `1 → Yes` for market settlement.

## Architecture

AI-resolved markets plug into Strike's existing market infrastructure with minimal changes:

### FlapAIResolver

A new resolver contract sits alongside the existing `PythResolver`:

```solidity
contract FlapAIResolver is FlapAIConsumerBase, IResolver {
    // Market question stored at creation time
    mapping(uint256 => string) public marketPrompts;
    mapping(uint256 => uint256) public pendingRequests; // marketId => requestId

    function resolveMarket(uint256 marketId) external {
        // Build prompt from market metadata
        string memory prompt = _buildPrompt(marketId);

        // Send to Flap AI Oracle
        IFlapAIProvider provider = IFlapAIProvider(_getFlapAIProvider());
        uint256 fee = provider.getModel(MODEL_ID).price;
        uint256 requestId = provider.reason{value: fee}(MODEL_ID, prompt, NUM_CHOICES);

        pendingRequests[marketId] = requestId;
    }

    function _fulfillReasoning(uint256 requestId, uint8 choice) internal override {
        uint256 marketId = _getMarketForRequest(requestId);
        // Map choice to outcome and settle
        _settleMarket(marketId, choice);
    }
}
```

### MarketFactory Changes

`MarketFactory` gains a `resolverType` parameter at market creation:

- `ResolverType.PYTH` → existing price-feed resolution (unchanged)
- `ResolverType.FLAP_AI` → AI oracle resolution

### Market Categories

AI-resolved markets are organized into categories based on resolution characteristics:

| Category | Examples | Resolution Frequency |
|---|---|---|
| **Geopolitics** | Ceasefires, regime changes, military actions | Weekly/monthly rolling |
| **Politics** | Elections, nominations, policy decisions | Event-driven |
| **Culture & Tech** | Game releases, awards, product launches | Event-driven |
| **Sports** | Tournament winners, MVP awards | Seasonal |

## Verifiability & Trust

Every AI resolution is permanently auditable:

- **IPFS proof** — the full LLM reasoning (inputs, outputs, model version, temperature, salt) is pinned to IPFS and the CID is stored on-chain
- **Anyone can verify** — retrieve the proof via `getReasoningCid(requestId)` and check the LLM's reasoning
- **Model transparency** — the model used (e.g., Claude Sonnet 4.6) and all parameters are part of the proof

```solidity
// Verify any past resolution
string memory cid = IFlapAIProvider(oracle).getReasoningCid(requestId);
// Fetch from: https://ipfs.io/ipfs/<cid>
```

### Trust Considerations

AI resolution introduces different trust assumptions than Pyth price feeds:

| | Pyth Resolution | AI Resolution |
|---|---|---|
| **Data source** | Cryptographically signed price data | LLM reasoning over public information |
| **Determinism** | Deterministic (earliest valid update wins) | Non-deterministic (LLM judgment) |
| **Oracle trust** | Decentralized publisher network | Centralized oracle operator |
| **Verifiability** | On-chain signature verification | IPFS proof (post-hoc audit) |
| **Challenge mechanism** | Procedural (earlier update wins) | Dispute window + re-query option |
| **Best for** | Price/numeric outcomes | Qualitative/event outcomes |

## Dispute Resolution

To mitigate the risks of LLM errors or edge cases, AI-resolved markets include a **dispute window**:

1. Oracle fulfills the resolution → market enters `PendingAIResolution` state
2. **Dispute window opens** (e.g., 24 hours) — anyone can flag the resolution
3. If disputed → a second query is sent (potentially to a different LLM model) for confirmation
4. If both agree → resolution is finalized
5. If they disagree → market is flagged for manual review or cancellation
6. If no dispute → resolution auto-finalizes after the window closes

## Supported Models

The Flap AI Oracle currently supports:

| Model | Cost per Resolution | Best For |
|---|---|---|
| Gemini 3 Flash | 0.01 BNB | High-frequency, lower-stakes markets |
| Claude Sonnet 4.6 | 0.05 BNB | Complex reasoning, nuanced judgment |
| DeepSeek R1 | 0.03 BNB | Balanced cost/quality |

Resolution costs are factored into the market creation bond. Market creators select the model tier at creation time.

## Target Market Types

Based on analysis of prediction market demand (March 2026 data), the highest-volume categories suitable for AI resolution:

### 🔥 Geopolitics (Highest Priority)
- Iran-related events — $529M+ weekly volume across platforms
- Ceasefire/conflict markets — rolling monthly resolution
- Regime change predictions

### 🏆 Sports & Entertainment
- Award shows (Oscars, Eurovision)
- Tournament outcomes
- Game/media release dates

### 🗳️ Politics
- Election outcomes
- Nomination races
- Policy decisions

### 💻 Tech & Crypto
- Product launches and release dates
- Acquisition predictions
- Regulatory decisions

## Roadmap

- [ ] `FlapAIResolver` contract implementation
- [ ] Dispute window mechanism
- [ ] MarketFactory v3 with resolver type selection
- [ ] BSC testnet integration with Flap AI Oracle
- [ ] Frontend: AI market creation flow
- [ ] Frontend: resolution proof viewer
- [ ] First live AI-resolved market (geopolitics category)
- [ ] Multi-model consensus resolution (v2)
