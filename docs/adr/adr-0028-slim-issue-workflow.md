# ADR-0028：精简研发工作流

- Status：accepted
- Kind：process
- Date：2026-11-03
- Supersedes：ADR-0023、ADR-0024（Discussion promotion model）
- Superseded by：none
- Implements：#571
- 相关：[工作流审计](../research/workflow-research.md)

## 背景

Covio 的工作流扩大到 519 行。
`AGENTS.md` 又重复了 102 行流程规则。
5 个 Issue 模板共有 28 个必填字段。
Project 8 的规划字段和 Issue 正文存在重复记录。

实际数据表明部分控制点没有稳定执行。
3 个开放 Research 超过 3 个工作日。
4 个开放 Issue 仍含 `decision: pending`。
17 个 Feature 中只有 2 个填写 Target date。

测试门禁和 UI 真机验证仍然有效。
本次决策只精简流程记录和默认对象。

## 决策

1. 使用三条入口路径：快速、研究、功能。
2. Bug 和 Task 直接创建 Issue。
3. Research 可以独立创建，属于 Feature 时才使用 sub-issue。
4. Verify 只用于跨 PR、真机、外部设备或发布验收。
5. Issue 模板只保留完成当前对象所需的最少必填字段。
6. Project 8 常规字段只保留 `Status`、`Priority` 和 `Target date`。
7. `Size`、`Start date` 和 `Estimate` 转为历史字段，保留旧值。
8. 删除 `decision: pending` 和人工周检清单。
9. 原生 sub-issue、`blocked by` 和 linked PR 是关系的唯一来源。
10. 文本回链只保留 Feature 到 ADR、PR 到 Issue 两种。
11. 保留风险分层测试。
12. UI 证据保留风险分级。普通 PR 删除 `Design preview`。

## 后果

### 正面

- Issue 创建时的必填字段从 5 至 7 项降到 2 至 3 项。
- Research 不再要求先创建 Feature。
- Flow 文档去掉 S1-S7 的会话归位成本。
- Project 不再要求重复填写规划字段。
- PR 只记录测试、UI 证据和剩余风险。

### 负面

- 负责人需要判断 Test 和 UI 证据的等级。
- 独立 Research 不再自动进入 Feature 进度。
- 历史 Size 和 Start date 数据不会进入新流程。

### 风险

- 简化规则可能再次膨胀。缓解：校验脚本限制文档和模板体积。
- 小 UI 改动的证据可能不足。缓解：PR 模板提供证据分级。
- 历史字段可能影响旧视图。缓解：保留旧值，不批量删除。

## 备选方案

### 备选 1：继续使用 S1-S7

未采纳。
三个入口已经覆盖实际路由。
S1-S7 增加了每次会话的阅读和归位成本。

### 备选 2：所有 Research 必须挂在 Feature 下

未采纳。
11 个 Research 没有 Parent Feature。
3 个开放 Research 也都没有 Parent Feature。

### 备选 3：删除 UI 真机证据

未采纳。
UI 真机证据验证真实 macOS 渲染。
本次只按风险分级，不删除证据。

## 未决事项

| 项目 | 状态 | 确认方法 |
| --- | --- | --- |
| 删除 Project 历史字段 | pending-data-review | 单独确认数据影响 |
| 自动检查 Research 截止日期 | proposed | 后续添加 Project 保存视图或自动化 |
| Discussion 使用率 | 待观察 | 统计 30 天未更新讨论 |

## 参考

- [研发工作流](../process/workflow.md)
- [工作流审计](../research/workflow-research.md)
- [ADR-0023](adr-0023-visual-verification-in-pull-requests.md)
- [ADR-0024](adr-0024-discussion-promotion-model.md)
- [Issue #571](https://github.com/wyz541/kmp-Covio/issues/571)
