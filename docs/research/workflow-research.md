# 研发工作流审计

- 状态：accepted
- 日期：2026-11-03
- 对应 Issue：#571
- 决策记录：ADR-0028

## 问题

Covio 的流程文档、Issue 模板和人工检查增加得很快。
开发时需要在多个对象中重复记录同一信息。
部分控制点没有稳定的实际使用数据。

本次审计回答一个问题：
哪些流程控制点应当删除、合并或降级？

## 结论

| 编号 | 结论 |
| --- | --- |
| C1 | 三个入口足够：快速、研究、功能。 |
| C2 | Issue 模板只保留完成当前对象所需的最少字段。 |
| C3 | Research 可以独立创建，不要求先建 Feature。 |
| C4 | Verify 适合跨 PR、真机或发布验收，不适合默认流程。 |
| C5 | 测试门禁和 UI 真机证据有质量价值，应保留。 |
| C6 | 人工周检和 `decision: pending` 没有形成可靠执行。 |

## 证据

### 流程体积

| 项目 | 审计值 |
| --- | ---: |
| `docs/process/workflow.md` | 519 行 |
| `AGENTS.md` | 102 行 |
| 5 个 Issue 模板 | 479 行 |
| PR 模板 | 65 行 |
| 核心流程文件合计 | 1,165 行 |
| 2026-10-13 至 2026-11-02 的流程文件提交 | 15 次 |

### Project 8

Project 8 共有 256 个条目。
17 个 Feature 中，Size 已填 8 个，Priority 已填 7 个。
Start date 已填 5 个，Target date 已填 2 个。
Issue 表单又要求填写 Priority 和 Size，形成重复输入。

### Research 与回链

30 个 Research 中，11 个没有 Parent Feature。
3 个开放 Research 都没有 Parent Feature。
3 个开放 Research 已超过 3 个工作日。
4 个开放 Issue 仍含 `decision: pending`。

### PR 模板

PR 模板启用后创建了 51 个 PR。
50 个填写 `Proof`，47 个填写 `Visual verification`。
32 个仍填写普通 PR 不需要的 `Design preview`。

## 决策

1. 流程改成三条入口路径。
2. 删除 S1-S7 的会话归位要求。
3. 删除 `decision: pending` 和人工周检清单。
4. Research 默认独立创建，属于 Feature 时才挂 sub-issue。
5. Verify 只在单个 PR 无法完成验收时创建。
6. Issue 模板减少必填字段。
7. Project 常规字段只保留 `Status`、`Priority` 和 `Target date`。
8. 保留风险分层测试和 UI 真机证据。
9. 普通 PR 删除 `Design preview`。
10. 原生关系优先，只保留 ADR 和关闭 Issue 两种文本回链。

## 风险

- 字段减少后，历史数据可能不一致。缓解：保留历史值，不批量删除。
- 证据分级依赖负责人判断。缓解：PR 模板写明三个等级。
- Research 独立后可能脱离 Feature。缓解：属于 Feature 时使用原生 sub-issue。
- 简化可能再次膨胀。缓解：校验脚本限制工作流和模板长度。

## 后续观察

1. 比较简化前后 Issue 创建时间和 PR 等待时间。
2. 检查 Research 截止日期执行率。
3. 检查 UI 证据缺失率。
4. 如果历史字段影响视图，再单独评估字段清理。

## 相关

- [研发工作流](../process/workflow.md)
- [Project 字段](../process/project-fields.md)
- [ADR-0028](../adr/adr-0028-slim-issue-workflow.md)
