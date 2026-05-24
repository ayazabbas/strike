# Flap 代币池

FLAP 代币池属于 STRIKE 中面向公开创建者的 pool 形式，用于由 AI 结算的代币市场。它们使用 native-token pool 合约：创建者可以发起以所选 BEP20 代币抵押的多结果 parimutuel pools，交易者买入结果，并在结算后领取收益或退款。

FLAP 代币池目前在 [app.strike.pm/flap](https://app.strike.pm/flap) 以 beta 形式上线。

## 它们是什么

一个 FLAP Token Pool 包含：

- **2–8 个结果** — 由创建者选择的互斥选项。
- **BEP20 抵押资产** — pool 可以使用外部代币，而不只限于 USDT 或 STRIKE。
- **Creator prompt** — 结算 prompt 随市场一起存储在链上。
- **FLAP AI 结算** — beta 阶段 resolver 使用 STRIKE 选定的固定 FLAP AI model。
- **30 minute 挑战 window** — AI 提出结果后，用户可以在最终确认前发起挑战。
- **Creator bond** — 官方 beta 创建流程会提交 `0.05 BNB` 创建者 bond。

beta 期间，STRIKE 承担 AI 费用。创建者在公开 FLAP Token Pool 流程中**不能**选择 model，也不需要支付特定 model 的预言机费用。

## Official Hosted 流程 vs Permissionless 合约

合约本身是无需许可的：用户可以直接在链上调用 `createNativePoolMarket`。

STRIKE 应用只展示通过 official hosted 流程创建的 pools：

1. Creator 在 `/flap/create` 完成引导式表单。
2. STRIKE 上传托管的、经过哈希校验的元数据。
3. 创建者提交链上交易，包含 metadata hash/URI 及 prompt。
4. 索引器检查链上 metadata hash 是否匹配托管元数据，然后再展示 pool。

直接创建的链上资金池仍是有效的合约级市场，但除非使用官方的哈希绑定元数据，否则不会自动列入 STRIKE 应用。

## Prompt 要求

当前公开 FLAP Token Pool beta 针对代币数据市场优化。Prompts 应可通过 Ave 支持的代币信息解析，例如：

- price；
- liquidity；
- volume；
- FDV / 市场 cap；
- resolver toolset 可用的代币相关指标。

避免使用需要社交、新闻、网页证据、交易所上币公告、Discord 或 X 活动、主观判断或私有证据的 prompt。这些问题不适合当前公开 FLAP Token Pool 流程。

一个好的 prompt 应包含：

- 准确的代币和链；
- UTC 时间戳或明确的 UTC window；
- 明确阈值；
- 相等情况的处理规则；
- 完整的结果 mapping。

示例：

> 结算时使用 BNB Chain 上该代币的 Ave liquidity data，以 June 30, 2026 00:00 UTC 为准。仅当 reported liquidity strictly greater than $100,000 时选择 "Above $100k"；否则选择 "At or below $100k"。

## 生命周期

1. **Create** — 创建者选择抵押资产、结果、交易 close、结算 time 及 prompt。
2. **交易** — 用户使用选定的 BEP20 抵押资产买入一个或多个结果 pools。
3. **Close** — 在 `tradingCloseTime` 停止买入。
4. **结算** — `resolutionTime` 后，resolver 使用链上 prompt 请求 FLAP AI answer。
5. **挑战** — AI 提出的结果进入 30 minute 挑战 window。
6. **Finalize** — 如果无人挑战，市场最终确认为 proposed winner；否则由管理员 review 并解决挑战。
7. **Claim / 退款** — 获胜方 claim；如果市场无效或取消，用户可退款。

## Economics

| Item | Beta behavior |
|---|---|
| Creator bond | `0.05 BNB` 于 create |
| AI 费用 | beta 期间由 STRIKE 承担 |
| Model choice | 由 STRIKE 固定 |
| Pool 费用 | 公开流程默认 2% |
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
