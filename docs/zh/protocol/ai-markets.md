# AI 市场

AI 市场是通过 **FLAP AI 预言机**结算的预测市场，而不是依赖直接价格源或纯管理员结果。STRIKE 在多个 pool 流程中使用 AI 结算，包括公开的 **FLAP 代币池**。

## Current AI 市场形态

| Surface | Creation | 抵押资产 | Prompt | Model / 费用 |
|---|---|---|---|---|
| Standard pool AI 市场 | Admin / 协议创建 | USDT 或 STRIKE，取决于市场 | 由 STRIKE/管理员配置 | 由协议配置 |
| FLAP 代币池 | Public 创建者流程 | Creator-selected BEP20 代币 | 由创建者提供并存储在链上 | beta 期间由 STRIKE 固定；AI 费用由 STRIKE 承担 |

对于公开 FLAP 代币池，创建者**不能**选择 AI model，也**不需要**支付特定 model 的预言机费用。他们只需提供市场 prompt，并提交 `0.05 BNB` 创建者 bond。

## AI 结算如何工作

1. **配置 Prompt** — 对 FLAP 代币池而言，创建者 prompt 存储于 native-token pool factory。
2. **市场 closes** — 在市场的交易 close time 停止买入。
3. **结算时间到达** — keeper/resolver 使用存储的 prompt 和结果数量请求 FLAP AI 答案。
4. **AI proposes an 结果** — 预言机返回 numeric 结果 choice。
5. **挑战 window opens** — 30 minute 挑战 window 允许在最终确认前 review。
6. **市场最终确认** — 如果无人挑战，AI 结果最终确认；如果被挑战，由管理员 review 并解决争议。
7. **用户 claim 或退款** — 获胜方 claim payout；无效/取消市场退还本金。

## Public FLAP Token Pool Prompt Scope

当前公开 beta 针对可通过 Ave-supported information 解析的**代币数据问题**优化，例如：

- price；
- liquidity；
- volume；
- FDV / 市场 cap；
- resolver 可用的其他代币相关指标。

避免使用需要社交、新闻、网页证据、交易所上币公告、Discord 或 X 活动、主观判断或私有证据的 prompt。这些问题不适合当前公开 FLAP Token Pool 流程。

## Writing Good Prompts

好的 prompt 应当 precise、bounded 且 machine-checkable。

它应包含：

1. **代币 + 链** — 例如 BNB Chain 上的代币合约。
2. **Data source scope** — 当前公开 FLAP pools 应使用 Ave 代币 data。
3. **Exact UTC time/window** — 避免使用 “today”、“soon” 或 “after launch” 这类模糊时间。
4. **Threshold 与 equality rule** — 明确定义 “above”、“at or below”、“greater than or equal” 等条件。
5. **结果 mapping** — 每个结果必须互斥，并覆盖所有可能情况。

### 示例

| 使用 case | Better prompt |
|---|---|
| Price threshold | “结算时使用 BNB Chain 上该代币的 Ave spot price data，以 June 30, 2026 00:00 UTC 为准。仅当价格 strictly greater than $0.10 时选择 `Above $0.10`；否则选择 `At or below $0.10`。” |
| Liquidity threshold | “结算时使用 BNB Chain 上该代币的 Ave liquidity data，以 June 30, 2026 00:00 UTC 为准。仅当 liquidity strictly greater than $100,000 时选择 `Above $100k`；否则选择 `At or below $100k`。” |
| FDV threshold | “结算时使用 BNB Chain 上该代币的 Ave FDV 或 market cap data，以 July 15, 2026 00:00 UTC 为准。仅当 FDV greater than or equal to $50,000,000 时选择 `Reached`；否则选择 `Not reached`。” |

### Avoid

| Avoid | Why |
|---|---|
| “这个项目会爆火吗？” | 主观问题，且无法通过代币数据结算。 |
| “Binance 会 list 这个代币吗？” | 需要当前公开 FLAP scope 之外的交易所/新闻证据。 |
| “团队会 announce 主网吗？” | 需要 social/web monitoring，而非 Ave 代币 data。 |
| “代币会表现好吗？” | 表述模糊，没有 threshold 或 time。 |

## 挑战 / Finality

AI proposals 采用 optimistic 机制。在 30 minute 挑战 window 内，参与者可以提交已配置的挑战 bond 来挑战 proposed result。成功挑战可以纠正结果；不成功的挑战可能根据 resolver rules 失去 bond。
