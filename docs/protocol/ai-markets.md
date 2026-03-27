# AI Markets

AI markets are prediction markets resolved by a large language model (LLM) instead of a price feed. They extend Strike beyond quantitative price markets to cover qualitative events — geopolitics, culture, politics, sports, and more.

## How They Differ from Price Markets

| | Price Markets | AI Markets |
|---|---|---|
| **Question** | "Will BTC be above $90k at expiry?" | "Will the Fed cut rates in May?" |
| **Resolution source** | Pyth price feed | Flap AI Oracle (LLM) |
| **On-chain data** | `priceId` (bytes32) + strike price | `prompt` (string) + model ID |
| **Creation fee** | None (beyond gas) | BNB fee (varies by model) |
| **Trading** | Identical — same orderbook, same FBA mechanism | Identical |

## Supported Models

The Flap AI Oracle supports multiple LLM models. Market creators choose the model at creation time and pay the corresponding fee in BNB.

| Model | Model ID | Fee (BNB) | Best For |
|---|---|---|---|
| Gemini 3 Flash | 0 | 0.01 | High-frequency, lower-stakes markets |
| Claude Sonnet 4.6 | 1 | 0.05 | Complex reasoning, nuanced judgment |
| DeepSeek R1 | 2 | 0.03 | Balanced cost and quality |

> **Note:** Fees are queried from the oracle contract at runtime via `getModel(modelId).price`. The values above are current as of launch but may change.

## Market Lifecycle

### 1. Creation

A market creator calls `createAIMarket(prompt, modelId, expiryTime, minLots)` on `MarketFactory`, sending the model fee in BNB. The prompt is stored on-chain in the `AIResolver` contract.

Example prompts:
- "Will BNB reach $1000 by June 2026?"
- "Will the Fed cut interest rates at the May 2026 FOMC meeting?"
- "Will GTA VI release before June 2026?"

### 2. Trading

Trading works identically to price markets — the same 4-sided orderbook (Bid, Ask, SellYes, SellNo), the same Frequent Batch Auction clearing, the same USDT collateral. Traders buy YES or NO positions based on whether they think the answer to the prompt is affirmative or negative.

### 3. Expiry

When the market expires, a keeper calls `AIResolver.resolveMarket(marketId)`. This sends the prompt to the Flap AI Oracle with the pre-deposited BNB fee.

### 4. AI Resolution (~90 seconds)

The oracle's off-chain backend:
1. Receives the prompt via an on-chain event
2. Feeds it to the selected LLM with current information
3. The LLM reasons over the question and returns a binary choice (0 = YES, 1 = NO)
4. Pins the full reasoning trace to IPFS
5. Calls back `AIResolver.fulfillReasoning(requestId, choice)` on-chain

### 5. Liveness Window (5 minutes)

After the oracle callback, the proposed resolution enters a **5-minute liveness window**. If no one challenges, anyone can call `finalise(marketId)` to settle the market.

### 6. Finalised

The market resolves with the AI's proposed outcome. Winning positions pay out normally via the Redemption contract.

## Challenge Process

During the 5-minute liveness window, anyone who disagrees with the AI's proposed outcome can challenge it.

### How to Challenge

1. Call `AIResolver.challenge(marketId)` with a **0.1 BNB bond**
2. The liveness window extends to a **24-hour review period**
3. A protocol admin reviews the challenge

### Challenge Outcomes

| Outcome | What Happens |
|---|---|
| **Admin confirms** (AI was correct) | Original resolution stands. Challenger loses their 0.1 BNB bond (sent to treasury). |
| **Admin overrides** (AI was wrong) | Resolution is corrected. Challenger receives their 0.1 BNB bond back plus a 0.01 BNB reward. |

### Timeline

```
Expiry → resolveMarket() → [~90s] Oracle callback
  → Proposed resolution (5-min liveness)
    → No challenge → finalise() → Resolved
    → Challenge (0.1 BNB) → 24h admin review
      → Confirmed → Resolved (original outcome)
      → Overridden → Resolved (corrected outcome)
```

## IPFS Verification

Every AI resolution produces a verifiable proof pinned to IPFS. The proof contains:

- **Full prompt** sent to the LLM
- **Reasoning steps** — the model's chain-of-thought
- **Tool calls** — any real-time data the model fetched (e.g., price lookups)
- **Model metadata** — model version, temperature, and other parameters
- **Final choice** — the numeric outcome returned

### How to Verify

1. Get the IPFS CID from the indexer: `GET /v1/markets/{id}/ai-resolution` → `ipfs_cid` field
2. Fetch the proof: `https://ipfs.io/ipfs/{cid}`
3. Review the full reasoning trace

The CID is also available on-chain via `FlapAIProvider.getRequest(requestId)` (decode the struct to extract the CID field).

## Example Prompts

| Category | Prompt |
|---|---|
| **Crypto** | "Will BNB reach $1000 by June 2026?" |
| **Macro** | "Will the Fed cut interest rates at the May 2026 FOMC meeting?" |
| **Geopolitics** | "Will there be a Russia-Ukraine ceasefire agreement by Q2 2026?" |
| **Tech** | "Will GTA VI release before June 2026?" |
| **Sports** | "Will Argentina win the 2026 FIFA World Cup?" |

## Contract Reference

AI markets are managed by the `AIResolver` contract, which extends `FlapAIConsumerBase`. See [AIResolver.sol](../contracts/ai-resolver.md) for the full contract reference.

### Key Addresses

| Contract | Network | Address |
|---|---|---|
| Flap AI Oracle | BSC Testnet | `0xFfddcE44e8cFf7703Fd85118524bfC8B2f70b744` |
| Flap AI Oracle | BSC Mainnet | `0xaEe3a7Ca6fe6b53f6c32a3e8407eC5A9dF8B7E39` |
