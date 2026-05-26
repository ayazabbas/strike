# Flap Token Pools

Flap Token Pools are Strike's public, creator-facing pool format for AI-resolved token markets. They use the native-token pool contracts: creators can launch multi-outcome parimutuel pools backed by a chosen BEP20 token, while traders buy into outcomes and claim or refund after resolution.

Flap Token Pools are live at [app.strike.pm/flap](https://app.strike.pm/flap).

## Creator Guide

Use Flap Token Pools when you want to launch a simple AI-resolved token-data market for a public BEP20 token. The current hosted creator flow is designed for questions that the Strike/FLAP resolver can answer from Ave token data at the time resolution is requested.

Before creating a pool:

1. **Pick the collateral token** — choose the BEP20 token users will spend and receive. External collateral carries token risk, so avoid tokens with broken transfers, high transfer taxes, blocked approvals, or thin liquidity.
2. **Define 2-8 outcomes** — outcomes must be mutually exclusive and collectively cover every valid result. Include a clear fallback outcome when the threshold is not met.
3. **Set trading and resolution times** — buying stops at `tradingCloseTime`; the AI oracle is requested after `resolutionTime`. Give users enough time to trade before the market closes.
4. **Write a resolvable prompt** — describe the token, chain, metric, threshold, timing rule, equality rule, and exact outcome mapping.
5. **Review the quality checks** — the app may flag prompts that look subjective, unsupported, or outside the current Ave token-data scope.
6. **Post the creator bond** — official creation requires the configured `0.05 BNB` bond plus gas.
7. **Submit the create transaction** — Strike hosts hash-checked metadata, then your wallet submits the on-chain transaction containing the metadata hash/URI and prompt.

After creation, share the pool URL, monitor trading before close, and be prepared for the challenge window after AI proposes a winner. If a result is challenged or the AI path fails, Strike can resolve through the configured fallback/admin process.

## What They Are

A Flap Token Pool has:

- **2–8 outcomes** — mutually exclusive choices selected by the creator.
- **BEP20 collateral** — the pool can use an external token instead of only USDT or STRIKE.
- **Creator prompt** — the resolution prompt is stored on-chain with the market.
- **FLAP AI resolution** — the resolver uses the fixed Strike-selected FLAP AI model.
- **30 minute challenge window** — after AI proposes an outcome, users can challenge before finalization.
- **Creator bond** — official creation posts a `0.05 BNB` creator bond.

Strike covers the AI fee. Creators do **not** choose a model or pay a model-specific oracle fee in the public Flap Token Pool flow.

## Official Hosted Flow vs Permissionless Contracts

The contracts are permissionless: a user can call `createNativePoolMarket` directly on-chain.

The Strike app only shows pools created through the official hosted flow:

1. Creator fills the guided form at `/flap/create`.
2. Strike uploads hosted, hash-checked metadata.
3. The creator submits the on-chain transaction with the metadata hash/URI and prompt.
4. The indexer checks that the on-chain metadata hash matches hosted metadata before showing the pool.

Direct on-chain pools remain valid contract-level markets, but they are not automatically listed on the Strike app unless they use official, hash-bound metadata.

## Prompt Requirements

The current public Flap Token Pool flow is optimized for token-data markets. Prompts should be resolvable from current Ave-supported token information such as:

- price,
- liquidity,
- volume,
- FDV / market cap,
- token-specific metrics available through the resolver's toolset.

Avoid prompts that require historical prices, social/news/web evidence, exchange listing announcements, Discord or X activity, subjective judgments, or private evidence. These are not suitable for the current public Flap Token Pool flow.

A good prompt should include:

- exact token and chain,
- resolution-time data rule,
- explicit threshold,
- equality rule,
- complete outcome mapping.

Example:

> Resolve using Ave token liquidity data for TOKEN on BNB Chain when this market resolves. Choose "Above $100k" only if reported liquidity is strictly greater than $100,000; otherwise choose "At or below $100k".

## Current FLAP AI Oracle Limitations

The FLAP AI Oracle is useful for supported token-data questions, but it is not a general-purpose truth engine. Current public Flap Token Pools have these limitations:

- **Ave current-data only** — the public resolver path is expected to use Ave token information at AI invocation time. It should not be used for historical price checks, "before/after" comparisons, or claims that require past snapshots.
- **Limited evidence scope** — the public flow is not intended for social, news, exchange listing, governance, Discord, X, or private-information questions.
- **Fixed Strike-selected model** — creators cannot choose the AI model, tool configuration, or pay for a different model path in the hosted creator flow.
- **Numeric outcome callback** — the resolver returns one outcome index. Prompts must map every possible result cleanly to the listed outcomes.
- **Challenge/fallback required for edge cases** — ambiguous prompts, unavailable data, oracle failures, or challenged answers may require admin/fallback handling.
- **No guarantee for unsupported tokens** — if Ave cannot provide reliable data for a token, the market may be unsuitable or may need to be cancelled/refunded.

## Lifecycle

1. **Create** — creator selects collateral, outcomes, trading close, resolution time, and prompt.
2. **Trade** — users buy into one or more outcome pools using the selected BEP20 collateral.
3. **Close** — buying stops at `tradingCloseTime`.
4. **Resolve** — after `resolutionTime`, the resolver requests a FLAP AI answer using the on-chain prompt.
5. **Challenge** — AI's proposed outcome enters a 30 minute challenge window.
6. **Finalize** — if unchallenged, the market finalizes to the proposed winner; otherwise admin review resolves the challenge.
7. **Claim / refund** — winners claim, or users refund if the market is invalid/cancelled.

## Economics

| Item | Behavior |
|---|---|
| Creator bond | `0.05 BNB` on create |
| AI fee | Covered by Strike |
| Model choice | Fixed by Strike |
| Pool fee | 2% default in the public flow |
| Challenge window | 30 minutes |
| Collateral | Creator-selected BEP20 token |

External collateral can be risky. Tokens may be unverified, illiquid, malicious, or otherwise unsuitable. The UI warns users before creating or trading these pools.

## Contracts

The native-token pool stack is isolated from the orderbook and standard USDT/STRIKE parimutuel stacks:

- `NativeTokenParimutuelFactory` — creates markets and stores metadata hash/URI + on-chain prompt.
- `NativeTokenPoolManager` — handles buys and pool accounting.
- `NativeTokenPoolVault` — holds BEP20 collateral.
- `NativeTokenPoolRedemption` — handles claims, refunds, and creator/challenger payouts.
- `NativeTokenPoolAIResolver` — sends the stored prompt to the FLAP AI Oracle and finalizes outcomes.

See [Deployments](../contracts/deployments.md) for live addresses.
