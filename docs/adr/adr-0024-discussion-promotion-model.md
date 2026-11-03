# ADR-0024：用 Parent Feature 组织 Discussion、Research 与 Task

- Status：superseded
- Kind：process
- Date：2026-10-29
- Supersedes：none
- Superseded by：ADR-0028
- Implements：#445
- 相关：[研发工作流](../process/workflow.md)

## 背景

Covio 已启用 GitHub Discussions。现有流程只在 S1 中说明如何建帖和等待回应。流程没有说明 Discussion 何时收敛，也没有说明 Discussion、Research issue 和 Task issue 的层级关系。

现有模型先建独立 Research issue，再在结论明确后建 Feature。最终 Feature 只能通过文本引用 Research。Research 不进入主交付层级，进度不集中。

GitHub 的原生 parent 只能指向 Issue。Discussion 不进入 Project，也不能成为 Issue 的原生 parent。因此流程需要同时保留 Discussion 的开放探索作用，并提供可追踪的 Issue 层级。

## 决策

1. Discussion 只承载尚未收敛的问题、做法和产出。它不进入 Project。
2. Discussion 收敛后，创建一个 Parent Feature。Parent Feature 是工作容器，不表示已经承诺实施。
3. Research 和 Task 都是 Parent Feature 的原生 sub-issue。两者用标签与完成标准区分。
4. Research 只回答一个问题。Research 的完成条件是结论写回正文，产出一项任务。
5. Task 的完成条件是对应 PR 已合并。
6. Parent Feature 保存 `discussion:` 回链。原生 sub-issue 关系是 Research 与 Task 层级的唯一来源。
7. Research 否决方案时，关闭 Parent Feature 与未完成 sub-issue。关闭原因写 `not planned`。
8. Discussion 转入 Issue 后，原帖写结论和 Issue 链接，然后关闭。

## 后果

### 正面

- 一个想法从探索到交付只有一个 Parent Feature 作为追踪入口。
- Research 与 Task 都进入原生 sub-issue 进度。
- Discussion 保留开放式讨论能力，不进入 Project 的硬门禁。
- 调研否决时，可以关闭完整工作容器，不留下孤立 Research。

### 负面

- Parent Feature 会在调研结论前出现。
- 团队需要理解 Parent Feature 不是实施承诺。
- GitHub Discussion 仍需手工转入 Issue。

### 风险

- 团队可能把 Parent Feature 误当成已批准需求。缓解办法是在表单和流程中明确工作容器语义。
- Discussion 可能继续闲置。缓解办法是每周检查 30 天以上的 Discussion。
- 团队可能只做文本引用，不建原生层级。缓解办法是 Research 的完成标准包含 Parent Feature 已显示 sub-issue。

## 备选方案

### 备选 1：把 Discussion 作为 parent

GitHub 不支持 Discussion 作为 Issue 的原生 parent。此方案不能满足进度汇总要求。

### 备选 2：保持独立 Research，后续再建 Feature

这是旧模型。它允许在决策前不创建 Parent Feature，但 Research 与最终交付无法进入同一层级。

### 备选 3：所有想法直接建 Issue

此方案可以使用原生层级，但会把开放探索过早变成有完成条件的工作。Discussion 已启用，因此不采用此方案。

## 未决事项

| 项目 | 状态 | 确认方法 |
| --- | --- | --- |
| Discussion 的实际使用率 | 待观察 | 每周检查 30 天以上的 Discussion |
| Parent Feature 是否会给小功能带来过重负担 | 待观察 | 只对需要跟踪的调研或多步骤工作建 Parent Feature |

## 参考

- [研发工作流](../process/workflow.md)
- [工作流调研](../research/workflow-research.md)
- GitHub issue #445

## 补充（2026-10-29）

Parent Feature 的 child 类型增加 Verify。

1. Research、Task 与 Verify 都是 Parent Feature 的 sub-issue。
2. Verify 与 Task 同级，不是 Task 的 child。
3. Task 的产出是代码和一个 PR。
4. Verify 的产出是验收证据。Verify 不要求分支和 PR。
5. Verify 使用 `blocked by` 指向被验收的 Task。
6. 单个 PR 的 `Visual verification` 和 `Proof` 仍写在 PR。
7. 跨多个 Task 或 PR、需要真机、需要发布前复验或需要长期证据时，才创建 Verify issue。

补充不改变原决策。它只补齐 Parent Feature 下的验证对象。

## 补充（2026-11-01）

明确 Issue 与 Discussion 的入口分工。

1. Discussion 是可选入口，不是所有事项的起点。
2. 目标、范围、负责人和完成条件明确的 Bug 或小任务，直接建 Issue。
3. 明确的大功能直接建 Parent Feature。没有 Discussion 来源时不写 `discussion:` 回链。
4. 问题明确但方法未知时，直接建 Parent Feature，再挂 Research sub-issue。Discussion 不是前置条件。
5. Discussion 只用于方向、范围、优先级或共识未定，以及需要社区问答、公告或知识沉淀的事项。
6. Discussion 可以形成结论后保持开放。只有出现可执行事项时，才创建 Issue；Discussion 不要求产出任务。

本补充不改变 Discussion、Parent Feature、Research、Task 与 Verify 的层级关系。
