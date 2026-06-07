# 世界杯倍数预测 V0 审计

**日期：** 2026-06-07
**审计方：** Internal Codex-assisted security review
**范围：** 世界杯倍数预测 V0 的持久化、API、管理端表面、前端原型与管理钱包门控、迁移 043 与 044
**结论：** 从 V0 的资金被盗与资金卡死视角看，结论为 PASS

---

## 执行摘要

本报告是内部、Codex 辅助的当前状态审计报告。它不是外部第三方审计，也不表示相关代码已经 push、部署或在生产环境启用。

经过已记录的安全加固后，当前世界杯倍数预测 V0 实现从资金被盗和资金卡死两个核心视角看可用于 V0。最终独立 Codex 复核结论为 **PASS**，没有剩余 blocking findings。

V0 支付执行仍然禁用。当前审查状态不会为世界杯倍数预测执行 token transfers、claims、refunds、contract writes 或 mainnet broadcasts。公开预测创建只记录链下预测意图。

---

## 范围

本次审查覆盖：

- 世界杯倍数预测的持久化、API 和管理端表面
- 前端原型行为和管理钱包默认值/门控
- 数据库迁移 `043_world_cup_multiplier_persistence.sql` 与 `044_world_cup_multiplier_security_hardening.sql`
- 后端当前 commits `3325997` 与 `4b92a02`
- 前端当前 commits `1c4c71f` 与 `0c34854`

本次审查不覆盖合约支付执行。V0 支付执行仍然禁用：没有 token transfers，没有 claims 或 refunds，没有 contract writes，也没有 mainnet broadcasts。

---

## 主要审查风险

本次审查重点关注可能让 payment-disabled 原型变成经济责任或产生不安全管理路径的风险：

- 未支付预测意图被错误视为已资金确认权益
- 生命周期、取消或结算 bug 导致资金卡死
- 管理签名 replay，或签名在不同 routes、bodies、wallets、environments 之间复用
- 事件打开后或首个预测意图后仍可修改关键条款
- 预测创建与管理端事件 patch 之间的 race conditions
- 不同事件、钱包或请求 body 之间的 idempotency collisions
- 结算 accounting 错误纳入未支付 rows
- 已应用迁移 043 的数据库升级安全性

---

## 当前状态加固

当前审查状态包含以下加固：

- 公开预测创建只记录意图。新 rows 使用 `prediction_status=intent_recorded` 和 `funding_status=payment_disabled`。
- Payment-disabled intents 不更新 Prediction Pool accounting，也不占用 Bonus Backstop Pool coverage。
- 结算、取消、权益更新和经济 accounting 都要求 `funding_status=confirmed`。
- 迁移 044 会将历史 `accepted` + `payment_disabled` rows 回填为 `intent_recorded`。
- 管理端 EIP-191 message 由服务端重建，并绑定 wallet、method、path、raw body SHA-256、`issued_at`、nonce 和 environment。
- 已使用的管理端 nonce 会持久化记录，并拒绝 nonce replay。
- 事件关键条款会在事件打开或任何预测意图存在后不可逆冻结。
- `create_prediction` 与 `admin_patch_event` 在读取或更新 outcomes 和 odds 前，会串行化在同一个 event row lock 上。
- Cancel、settle 和 finalize 路径使用 transactions 与 event row locks。
- 非退款结算要求 `winning_outcomes` 非空。
- 预测 idempotency 按 event、wallet 和 idempotency key 分区，并绑定 request body hash。
- 迁移 043 保持不变。迁移 044 是 forward、idempotent 的安全加固迁移。

---

## 验证

安全加固复核期间，以下验证命令已通过：

- `cargo fmt`
- `cargo check -p indexer`
- `cargo test -p indexer world_cup_multiplier`
- `git diff --check`
- 最终 Codex staged-diff security review

最终复核结果：

- 结论：**PASS**
- Blocking findings：无
- Non-blocking findings：无

---

## V0 限制

本报告应理解为 V0 当前状态内部复核，而不是生产发布证明。

最重要的限制是有意保留的：支付执行禁用。预测创建只记录意图，不移动 token，也不创建可 claim 的链上 position。未来任何启用 payments、contract writes、claims、refunds 或 mainnet broadcasts 的版本，都需要在发布前重新审查相关支付与结算路径。
