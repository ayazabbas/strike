# AI Markets

AI markets are prediction markets resolved by the **Flap AI Oracle** instead of a direct price feed or manual-only admin result. Strike uses AI resolution in multiple pool flows, including public **Flap Token Pools**.

## Current AI Market Surfaces

| Surface | Creation | Collateral | Prompt | Model / fee |
|---|---|---|---|---|
| Standard pool AI markets | Admin / protocol-created | USDT or STRIKE, depending on market | Configured by Strike/admin | Configured by protocol |
| Flap Token Pools | Public creator flow | Creator-selected BEP20 token | Supplied by creator and stored on-chain | Fixed by Strike during beta; AI fee covered by Strike |

For public Flap Token Pools, creators do **not** choose the AI model and do **not** pay a model-specific oracle fee. They provide the market prompt and post the `0.05 BNB` creator bond.

## How AI Resolution Works

1. **Prompt is configured** — for Flap Token Pools, the creator prompt is stored on-chain in the native-token pool factory.
2. **Market closes** — buys stop at the market's trading close time.
3. **Resolution time arrives** — the keeper/resolver requests a FLAP AI answer using the stored prompt and outcome count.
4. **AI proposes an outcome** — the oracle returns a numeric outcome choice.
5. **Challenge window opens** — a 30 minute challenge window allows review before finalization.
6. **Market finalizes** — if unchallenged, the AI outcome finalizes; if challenged, admin review resolves the dispute.
7. **Users claim or refund** — winners claim payout; invalid/cancelled markets refund principal.

## Public Flap Token Pool Prompt Scope

The current public beta is optimized for **token-data questions** resolvable from Ave-supported information, such as:

- price,
- liquidity,
- volume,
- FDV / market cap,
- other token-specific metrics available to the resolver.

Avoid prompts that require social/news/web evidence, exchange listing announcements, Discord or X activity, subjective judgments, or private evidence. Those are not suitable for the current public Flap Token Pool flow.

## Writing Good Prompts

Good prompts are precise, bounded, and machine-checkable.

They should include:

1. **Token + chain** — e.g. token contract on BNB Chain.
2. **Data source scope** — current public Flap pools should use Ave token data.
3. **Exact UTC time/window** — no vague “today”, “soon”, or “after launch”.
4. **Threshold and equality rule** — define “above”, “at or below”, “greater than or equal”, etc.
5. **Outcome mapping** — every outcome must be mutually exclusive and cover all possible results.

### Examples

| Use case | Better prompt |
|---|---|
| Price threshold | “Resolve using Ave spot price data for TOKEN on BNB Chain at 00:00 UTC on June 30, 2026. Choose `Above $0.10` only if price is strictly greater than $0.10; otherwise choose `At or below $0.10`.” |
| Liquidity threshold | “Resolve using Ave liquidity data for TOKEN on BNB Chain at 00:00 UTC on June 30, 2026. Choose `Above $100k` only if liquidity is strictly greater than $100,000; otherwise choose `At or below $100k`.” |
| FDV threshold | “Resolve using Ave FDV or market cap data for TOKEN on BNB Chain at 00:00 UTC on July 15, 2026. Choose `Reached` only if FDV is greater than or equal to $50,000,000; otherwise choose `Not reached`.” |

### Avoid

| Avoid | Why |
|---|---|
| “Will the project go viral?” | Subjective and not token-data-resolvable. |
| “Will Binance list this token?” | Requires exchange/news evidence outside the current public Flap scope. |
| “Will the team announce mainnet?” | Requires social/web monitoring, not Ave token data. |
| “Will TOKEN do well?” | Vague, no threshold or time. |

## Challenge / Finality

AI proposals are optimistic. During the 30 minute challenge window, a participant can challenge a proposed result by posting the configured challenge bond. A successful challenge can correct the result; an unsuccessful challenge can lose the bond according to the resolver rules.

## Verification

AI resolution data is exposed through the indexer where available. The canonical market prompt and chosen outcome are tied back to on-chain events and contract state.

## Related Pages

- [Flap Token Pools](flap-token-pools.md)
- [Parimutuel Pool Markets](parimutuel-markets.md)
- [Oracle Resolution](oracle-resolution.md)
- [Deployments](../contracts/deployments.md)
