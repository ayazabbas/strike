# Flap Token Pools

Flap Token Pools are Strike's public, creator-facing pool format for AI-resolved token markets. They use the native-token pool contracts: creators can launch multi-outcome parimutuel pools backed by a chosen BEP20 token, while traders buy into outcomes and claim or refund after resolution.

Flap Token Pools are live in beta at [app.strike.pm/flap](https://app.strike.pm/flap).

## What They Are

A Flap Token Pool has:

- **2–8 outcomes** — mutually exclusive choices selected by the creator.
- **BEP20 collateral** — the pool can use an external token instead of only USDT or STRIKE.
- **Creator prompt** — the resolution prompt is stored on-chain with the market.
- **FLAP AI resolution** — the resolver uses the fixed Strike-selected FLAP AI model for beta.
- **30 minute challenge window** — after AI proposes an outcome, users can challenge before finalization.
- **Creator bond** — official beta creation posts a `0.05 BNB` creator bond.

During beta, Strike covers the AI fee. Creators do **not** choose a model or pay a model-specific oracle fee in the public Flap Token Pool flow.

## Official Hosted Flow vs Permissionless Contracts

The contracts are permissionless: a user can call `createNativePoolMarket` directly on-chain.

The Strike app only shows pools created through the official hosted flow:

1. Creator fills the guided form at `/flap/create`.
2. Strike uploads hosted, hash-checked metadata.
3. The creator submits the on-chain transaction with the metadata hash/URI and prompt.
4. The indexer checks that the on-chain metadata hash matches hosted metadata before showing the pool.

Direct on-chain pools remain valid contract-level markets, but they are not automatically listed on the Strike app unless they use official, hash-bound metadata.

## Prompt Requirements

The current public Flap Token Pool beta is optimized for token-data markets. Prompts should be resolvable from Ave-supported token information such as:

- price,
- liquidity,
- volume,
- FDV / market cap,
- token-specific metrics available through the resolver's toolset.

Avoid prompts that require social/news/web evidence, exchange listing announcements, Discord or X activity, subjective judgments, or private evidence. These are not suitable for the current public Flap Token Pool flow.

A good prompt should include:

- exact token and chain,
- UTC timestamp or bounded UTC window,
- explicit threshold,
- equality rule,
- complete outcome mapping.

Example:

> Resolve using Ave token liquidity data for TOKEN on BNB Chain at 00:00 UTC on June 30, 2026. Choose "Above $100k" only if reported liquidity is strictly greater than $100,000; otherwise choose "At or below $100k".

## Lifecycle

1. **Create** — creator selects collateral, outcomes, trading close, resolution time, and prompt.
2. **Trade** — users buy into one or more outcome pools using the selected BEP20 collateral.
3. **Close** — buying stops at `tradingCloseTime`.
4. **Resolve** — after `resolutionTime`, the resolver requests a FLAP AI answer using the on-chain prompt.
5. **Challenge** — AI's proposed outcome enters a 30 minute challenge window.
6. **Finalize** — if unchallenged, the market finalizes to the proposed winner; otherwise admin review resolves the challenge.
7. **Claim / refund** — winners claim, or users refund if the market is invalid/cancelled.

## Economics

| Item | Beta behavior |
|---|---|
| Creator bond | `0.05 BNB` on create |
| AI fee | Covered by Strike during beta |
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
