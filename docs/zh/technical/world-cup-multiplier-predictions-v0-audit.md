# 世界杯倍数预测跨事件票据内部复核

**日期：** 2026-06-08
**审计方：** 内部 Codex 辅助安全复核
**范围：** 跨事件 Prediction Ticket 候选重构，覆盖后端/indexer、前端、Portfolio/Admin 展示，以及 `StrikeMultiplierPredictionVault` 的 ticket-as-vault-event 兼容性
**结论：** **当前跨事件票据分支尚未达到发布条件**。合约兼容性通过，但后端/accounting 与前端幂等性存在 blocker，必须修复后才能把跨事件票据模型视为生产就绪。

---

## 执行摘要

这是一份内部 Codex 辅助复核，不是外部第三方审计。

本次复核的候选分支加入了真正的跨事件 Prediction Ticket：一个用户票据可以包含来自多个事件的 legs，同时通过把每张票据表示为一个 synthetic vault event 来复用现有 vault ABI。

合约兼容策略在 ABI 层面可行，相关 vault 测试通过。但当前候选实现**尚未达到发布条件**，因为复核发现新的 `/world-cup-multiplier/tickets` 路径在后端结算/accounting 覆盖方面存在 blocker，前端重复提交相同票据时的幂等性行为也存在 blocker。

---

## 复核范围

复核覆盖 `feature/world-cup-cross-event-tickets` 分支上的候选改动：

- `/home/ubuntu/dev/strike-infra`
  - migration `047_world_cup_multiplier_cross_event_tickets.sql`
  - 票据创建 endpoint 与 legacy route 兼容
  - 票据列表/detail/portfolio receipt API
  - settlement projection 与 vault event 同步
- `/home/ubuntu/dev/strike-frontend`
  - 跨事件 ticket builder 与提交路径
  - ticket API client 类型
  - Portfolio 与 Admin 展示
  - 本地 ticket-builder 测试与 smoke 脚本
- `/home/ubuntu/dev/strike`
  - `StrikeMultiplierPredictionVault` 兼容性测试
  - ticket-as-vault-event 文档
  - public docs/security/navigation 状态

---

## 分模块结论

### 合约兼容性：PASS

现有 `StrikeMultiplierPredictionVault` ABI 可以把一张跨事件票据表示为一个 synthetic vault event：

- submit 使用一个 `bytes32 eventId` 表示 synthetic ticket vault event；
- 票据使用一个 `bytes32 predictionId`；
- synthetic vault event 结算后，可以用该 prediction id 领取 payout；
- synthetic vault event 取消后，可以用该 prediction id 领取 refund；
- vault 不需要知道真实的 per-leg event ids。

因此，pilot 兼容路径不需要 Solidity ABI 变更。

### 后端/indexer 候选实现：BLOCKED

新 ticket tables 与 API 方向正确，但当前实现对纯 `/world-cup-multiplier/tickets` 提交存在 release-blocking 的 settlement/accounting 缺口。

### 前端候选实现：BLOCKED

Ticket builder 与 Portfolio/Admin 展示方向正确，但当前提交路径使用确定性的 idempotency key，可能阻止用户用相同 legs 与 entry amount 创建第二张独立票据。

---

## Blocking findings

### B-01：跨事件票据没有进入 legacy settlement/accounting projection

**严重性：** Blocker

纯 `/world-cup-multiplier/tickets` 提交会写入 `multiplier_prediction_tickets` 与 `multiplier_prediction_ticket_legs`，但不会创建现有 settlement accounting 依赖的 legacy `multiplier_predictions` projection。

观察到的风险：

- accepted 或 paid 的跨事件票据可以存在于 ticket tables；
- `prediction_pool_states` 与相关 accounting 仍从 `multiplier_predictions` 聚合；
- legacy projection 只在 legacy `/events/{id}/predictions` 兼容路径创建；
- vault event sync 只更新已有 projection row，不会为纯 ticket row 创建 projection。

**影响：** 新 ticket endpoint 的 ticket acceptance、accounting、settlement visibility 与 pool state 可能发生分歧。

**必须修复：** 要么为每张 accepted ticket 创建可靠的 accounting projection，要么把 accounting/settlement 代码改为直接从 canonical ticket tables 聚合。

### B-02：Synthetic vault event settlement 尚未完整接入真实跨事件票据结算

**严重性：** Blocker

兼容模型会让每张票据使用 synthetic ticket-level `vault_event_id` 签名，而本地 admin settlement 基于真实 event ids 更新 legs。复核到的 settlement projection 记录的是 vault-settlement TODO，并没有实际 settle/cancel synthetic vault event。

观察到的风险：

- 后端可以在本地标记 ticket legs 或 ticket status；
- vault payout/refund 状态只有在 synthetic vault event 被 settle 或 cancel 后才会变化；
- 如果 synthetic vault settlement 未被一致执行，用户看到的 ticket 终态可能与 claim/refund 可用性不一致。

**影响：** 资金可能在运营层面卡住，或者 ticket 已显示终态但 claim/refund 不可用。

**必须修复：** 在生产发布前，实现并测试 win、loss、refund/cancel 与非终态场景的完整 synthetic-vault-event 生命周期。

### B-03：确定性前端幂等 key 会阻止或合并重复相同票据

**严重性：** Blocker

前端基于 wallet、entry amount 与排序后的 leg selections 派生 ticket idempotency key。用户如果有意再次提交同样选择与金额，可能因为后端 idempotency retention 而拿到之前的 ticket 结果，而不是创建新的独立票据。

**影响：** 用户可能无法创建合法的重复 entries。

**必须修复：** 生成 per-submit-attempt idempotency key，并且只在同一次 in-flight 提交重试时复用。

---

## High-severity findings

### H-01：Intent-only tickets 在当前复核路径不会 settle 或 cancel

新 tickets 默认 `ticket_status = intent_recorded`。复核到的 settlement projection 只更新 `accepted` 或 `refund_pending` tickets。如果 payment-disabled 或 intent-only rows 仍可能存在，它们在 admin settle/cancel 后可能保持 stale。

**必须修复：** 明确定义 intent-only ticket 生命周期，并确保 admin settle/cancel 路径要么有意忽略并给出清晰状态，要么安全转换状态。

### H-02：Smoke 脚本金额与前端 base-unit 提交格式不一致

前端以 USDT base units 提交 entry amount。本地 smoke 脚本默认值为 `"1"`；如果 API 期待与前端相同格式，这代表一个 base unit，而不是 1 USDT。

**必须修复：** smoke 脚本应使用明确 base units，例如 1 USDT 用 `1000000`，或明确标注这是 one-base-unit dust smoke。

### H-03：Ticket detail endpoint 可通过数字 id 枚举

复核到的 ticket detail route 会按数字 id 返回 ticket，没有 wallet filter 或 authorization。

**必须修复：** 如果 ticket details、payment metadata 或 receipt data 被视为 wallet-private，应加入 wallet-scoped access，或避免在 unauthenticated numeric ids 下暴露敏感字段。

---

## Medium findings 与约束

- Vault event idempotency 仅按 `(tx_hash, log_index)` 唯一。共享 multi-chain database 应包含 chain 与 contract 上下文。
- Vault lifetime `MAX_TOTAL_PREDICTIONS = 1,000`。已取消或已 finalized 的 predictions 不会释放 slots。对 bounded pilot 可接受，但高流量生产需要 vault rotation 或 native redesign。
- 合约不验证真实 per-leg event ids、leg outcomes 或跨事件 ticket composition。这些事实由后端/admin settlement 正确性决定。
- 前端依赖新的 `/v1/world-cup-multiplier/tickets` endpoint。后端与前端必须原子部署，或者加入兼容 fallback。
- 本地 Playwright ticket-builder 测试与 app webServer config 耦合；复核环境中因已有 Next dev lock 而无法干净运行。

---

## 正向观察

- Ticket schema 将 ticket-level 数据与 per-leg rows 分离，并保留 legacy prediction model 以支持 rollout 兼容。
- Validation 覆盖正数 base-unit amount、最大 ticket legs、active/open events、lock times、重复 `(event_id, group_key)`、以及 active outcomes。
- 复核过的 SQL 路径使用 bound parameters 处理用户可控输入。
- Portfolio 展示同时支持 legacy selected-outcome receipts 与新的 `legs[]` shape。
- 合约测试证明 synthetic vault event 模型下的 win 与 refund 兼容性。

---

## 验证证据

本次复核报告的命令与检查包括：

- Backend/indexer：
  - `cargo test -p indexer world_cup_multiplier --no-default-features`
  - 结果：31 个 unit tests 通过；DB-backed SQLx tests 因测试数据库 hostname 在环境中不可用而无法执行。
- Frontend：
  - `npm run lint` — passed
  - `npx tsc --noEmit` — passed
  - `npm run build` — passed
  - `npx playwright test tests/world-cup-multiplier-ticket-builder.spec.ts` — 因本地 Next dev lock / webServer startup coupling 被阻塞
  - local smoke script — 本地环境 `/v1/world-cup-multiplier/events` 返回 404，无法完成
- Contracts：
  - `/home/ubuntu/.foundry/bin/forge test --match-contract StrikeMultiplierPredictionVaultTest` — 31 passed
  - full Foundry suite — 620 passed, 0 failed
- Docs：
  - 旧 public docs 仍描述 V0 historical/payment-disabled audit，因此需要替换为本次 current review。

---

## 发布建议

在修复以上 blocker findings 并完成复核前，不应把跨事件 Prediction Ticket 重构视为 production-ready。

后续 release-ready review 应重点验证：

1. 每张 paid/accepted ticket 都进入正确的 accounting source of truth；
2. 每个终态 ticket outcome 都会 exactly once settle 或 cancel synthetic vault event；
3. API 与 Portfolio receipts 中的 ticket status 与 claim/refund 可用性一致；
4. 相同 legs 与 entry amount 的重复提交会创建独立 entries，同时 retry 仍保持幂等；
5. smoke tests 使用明确 base-unit amounts，并能在兼容 API 上运行；
6. 只有在上述修复通过后，public docs 才应再次从 **blocked candidate review** 更新为 **release-ready review**。
