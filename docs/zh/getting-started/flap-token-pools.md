# Flap 代币池

FLAP 代币池属于 STRIKE 中面向公开创建者的 pool 形式，用于由 AI 结算的代币市场。它们使用 native-token pool 合约：创建者可以发起以所选 BEP20 代币抵押的多结果 parimutuel pools，交易者买入结果，并在结算后领取收益或退款。

FLAP 代币池已在 [strike.fun/flap](https://strike.fun/flap) 上线。

## 创建者指南

当你想为公开 BEP20 代币创建一个简单、由 AI 结算的代币数据市场时，可以使用 FLAP 代币池。当前托管创建流程适合 STRIKE/FLAP resolver 能在请求结算时通过 Ave 当前代币数据回答的问题。

创建前：

1. **选择抵押代币** — 选择用户买入和领取时使用的 BEP20 代币。外部抵押资产存在代币风险，应避免转账异常、高转账税、approval 受限或流动性很薄的代币。
2. **定义 2-8 个结果** — 结果必须互斥，并覆盖所有有效情况。阈值不满足时也应有明确的 fallback outcome。
3. **设置交易与结算时间** — `tradingCloseTime` 后停止买入；`resolutionTime` 后请求 AI 预言机。应给用户留出足够交易时间。
4. **编写可结算 prompt** — 写清代币、链、指标、阈值、时间规则、相等情况处理方式，以及完整 outcome mapping。
5. **检查质量提示** — 如果 prompt 看起来主观、不受支持或超出当前 Ave 代币数据范围，应用可能会提示风险。
6. **提交创建者 bond** — 官方创建需要配置的 `0.05 BNB` bond 及 gas。
7. **提交创建交易** — STRIKE 会托管经过 hash 校验的 metadata，然后你的钱包提交包含 metadata hash/URI 和 prompt 的链上交易。

创建后，可以分享 pool URL，关注交易关闭前的买入情况，并在 AI 提出结果后留意挑战窗口。如果结果被挑战，或 AI 路径失败，STRIKE 可以通过配置的 fallback/admin 流程处理。

## 它们是什么

一个 FLAP Token Pool 包含：

- **2–8 个结果** — 由创建者选择的互斥选项。
- **BEP20 抵押资产** — pool 可以使用外部代币，而不只限于 USDT 或 STRIKE。
- **Creator prompt** — 结算 prompt 随市场一起存储在链上。
- **FLAP AI 结算** — resolver 使用 STRIKE 选定的固定 FLAP AI model。
- **30 minute 挑战 window** — AI 提出结果后，用户可以在最终确认前发起挑战。
- **Creator bond** — 官方创建流程会提交 `0.05 BNB` 创建者 bond。
- **Challenger bond** — 发起 challenge 需要提交配置的 `0.01 BNB` challenger bond。

STRIKE 承担 AI 费用。创建者在公开 FLAP Token Pool 流程中**不能**选择 model，也不需要支付特定 model 的预言机费用。

## Official Hosted 流程 vs Permissionless 合约

合约本身是无需许可的：用户可以直接在链上调用 `createNativePoolMarket`。

STRIKE 应用只展示通过 official hosted 流程创建的 pools：

1. Creator 在 `/flap/create` 完成引导式表单。
2. STRIKE 上传托管的、经过哈希校验的元数据。
3. 创建者提交链上交易，包含 metadata hash/URI 及 prompt。
4. 索引器检查链上 metadata hash 是否匹配托管元数据，然后再展示 pool。

直接创建的链上资金池仍是有效的合约级市场，但除非使用官方的哈希绑定元数据，否则不会自动列入 STRIKE 应用。

## Prompt 要求

当前公开 FLAP Token Pool 流程针对代币数据市场优化。Prompts 应可通过 Ave 支持的当前代币信息解析，例如：

- price；
- liquidity；
- volume；
- FDV / 市场 cap；
- resolver toolset 可用的代币相关指标。

避免使用需要历史价格、社交、新闻、网页证据、交易所上币公告、Discord 或 X 活动、主观判断或私有证据的 prompt。这些问题不适合当前公开 FLAP Token Pool 流程。

一个好的 prompt 应包含：

- 准确的代币和链；
- 结算时数据规则；
- 明确阈值；
- 相等情况的处理规则；
- 完整的结果 mapping。

示例：

> 结算时使用 BNB Chain 上该代币在本市场结算时的 Ave liquidity data。仅当 reported liquidity strictly greater than $100,000 时选择 "Above $100k"；否则选择 "At or below $100k"。

## 当前 FLAP AI 预言机限制

FLAP AI 预言机适合支持范围内的代币数据问题，但它不是通用真相引擎。当前公开 FLAP 代币池有以下限制：

- **Ave 当前数据 only** — 公开 resolver 路径预期使用 AI 调用时的 Ave 代币信息。不应把它用于历史价格检查、before/after 对比，或需要过去快照的问题。
- **证据范围有限** — 公开流程不适合社交、新闻、交易所上币、治理、Discord、X 或私有信息问题。
- **固定 STRIKE-selected model** — 创建者不能在托管创建流程中选择 AI model、tool configuration，或支付费用切换到其他 model path。
- **数字 outcome callback** — resolver 返回一个 outcome index。Prompt 必须把所有可能结果清晰映射到列出的 outcomes。
- **边界情况需要挑战/fallback** — 模糊 prompt、数据不可用、预言机失败或被挑战的答案，可能需要管理员/fallback 处理。
- **不保证支持所有代币** — 如果 Ave 无法为某个代币提供可靠数据，该市场可能不适合创建，或需要取消/退款。

## 生命周期

1. **Create** — 创建者选择抵押资产、结果、交易 close、结算 time 及 prompt。
2. **交易** — 用户使用选定的 BEP20 抵押资产买入一个或多个结果 pools。
3. **Close** — 在 `tradingCloseTime` 停止买入。
4. **结算** — `resolutionTime` 后，resolver 使用链上 prompt 请求 FLAP AI answer。
5. **挑战** — AI 提出的结果进入 30 minute 挑战 window。
6. **Finalize** — 如果无人挑战，市场最终确认为 proposed winner；否则由管理员 review 并解决挑战。
7. **Claim / 退款** — 获胜方 claim；如果市场无效或取消，用户可退款。

## Economics

| Item | Behavior |
|---|---|
| Creator bond | `0.05 BNB` 于 create |
| Challenger bond | `0.01 BNB` 用于发起 challenge |
| AI 费用 | 托管流程中由 STRIKE 覆盖 |
| Model 选择 | 固定为 STRIKE 选定的 FLAP AI model |
| Pool 费用 | 当前公开流程费用为 2%；由平台配置 |
| 挑战 window | 30 minutes |
| 抵押资产 | Creator-selected BEP20 代币 |

外部抵押资产可能有风险。代币可能未经验证、流动性不足、恶意设计，或在其他方面不适合作为抵押资产。UI 会在创建或交易这些 pools 前提醒用户。

## 合约

native-token pool stack 与订单簿和标准 USDT/STRIKE parimutuel stacks 相互隔离：

- `NativeTokenParimutuelFactory` — 创建市场，并存储 metadata hash/URI 和链上 prompt。
- `NativeTokenPoolManager` — 处理买入及 pool accounting。
- `NativeTokenPoolVault` — 持有 BEP20 抵押资产。
- `NativeTokenPoolRedemption` — 处理 claims、退款以及创建者/challenger payouts。
- `NativeTokenPoolAIResolver` — 将存储的 prompt 发送至 FLAP AI 预言机，并最终确认结果。

参见 [部署](../contracts/deployments.md) 获取实时地址。
