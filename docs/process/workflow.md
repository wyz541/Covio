# 研发工作流

**明确事项直接进入 Issue。研究可以独立创建。大功能使用原生 sub-issue。**

版本 1.0 · 2026-11-03

## 1. 适用范围
本流程适用于 Covio 仓库。
适用范围是个人开发者至 15 人团队。
本流程不适用于需要外部合规取证的组织。

GitHub 个人账号没有 Issue Types 和 Issue Fields。
对象用标签区分。
字段用 Project 8 保存。

## 2. 三条路径
| 路径 | 何时使用 | 产出 |
| --- | --- | --- |
| 快速路径 | 可复现 Bug，或一个会话可完成的任务 | Issue → 一个 PR |
| 研究路径 | 问题明确，方法、成本或风险未知 | Research → 书面结论 |
| 功能路径 | 需要多个 PR、超过 5 个工作日，或先改设计 | Feature → 原生 sub-issue → PR |

Discussion 是可选入口。
Discussion 只用于范围、优先级或共识未定，以及需要开放交流的事项。
Discussion 不是 Issue 的前置条件，也不能成为原生的 Parent。

- 标签 `bug` 表示 Bug。
- 标签 `task` 表示一个小任务。
- 标签 `research` 表示研究。
- 标签 `feature` 表示功能容器。
- 标签 `verify` 表示独立验收，通常位于 Feature 下。

## 3. 对象边界
| 对象 | 负责 | 不负责 |
| --- | --- | --- |
| Bug | 修复一个缺陷，并交付一个 PR | 多 PR 功能 |
| Task | 实现一个可独立交付的改动 | 跨多个 PR 的最终验收 |
| Research | 回答一个问题，写结论和证据 | 合并研究代码 |
| Feature | 组织 Research、Task 和例外 Verify | 记录第二份子任务清单 |
| Verify | 保存跨 PR、真机或发布验收证据 | 重复保存单个 PR 的测试与截图 |
| ADR | 保存长期决策 | 记录普通实现细节 |

## 4. 路径规则

### 4.1 快速路径

1. 目标明确时，直接创建 Bug 或 Task。
2. Bug 写实际行为、预期行为和复现步骤。
3. Task 写目标和可判定的验收标准。
4. 一个 Task 使用一条分支和一个 PR。
5. PR 写测试、CI 和剩余风险。
6. PR 有 UI 代码变更时，补 `Visual verification`。
7. 合并 PR 后关闭 Issue。

快速路径不要求 Discussion、Feature、Research 或 Verify。

### 4.2 研究路径

1. 直接创建 Research Issue。
2. Research 可以独立存在。
3. Research 属于 Feature 时，使用原生 sub-issue 关联。
4. Research 写问题、预期产出和截止日期。
5. 默认时间盒是 2 个工作日，最长 3 个工作日。
6. 到期时把结论、依据和后续动作写回正文。
7. 需要实施时，创建 Task 或 Feature。
8. 形成长期决策时，创建 ADR。
9. 结论写回正文后关闭 Research。

Research 不要求同步评审。
Research 不要求其他成员回复。
Research 不要求决策占位符。
Research 的代码不合并到 `main`。

### 4.3 功能路径

1. 需要多个 PR、超过 5 个工作日，或先改设计时，创建 Feature。
2. 需要降低未知时，创建 Research sub-issue。
3. 可以实施时，创建 Task sub-issue。
4. 使用 GitHub 原生 `blocked by` 记录真实依赖。
5. 不按人员分配顺序。
6. 所有 Task 和适用 Verify 完成后关闭 Feature。

Feature 只是工作容器。
Feature 不表示已经承诺实施。

### 4.4 Verify 例外

只有满足任一项时，创建 Verify：

1. 验收跨越多个 Task 或 PR。
2. 验收需要真机、外接设备或人工交互。
3. 验收需要发布前复验。
4. 证据需要长期独立保存。

单个 PR 能完成的验收，写在 PR 中。

## 5. 关系与字段
原生 sub-issue、`blocked by` 和 linked PR 是关系的唯一来源。
不要在正文维护第二份层级或进度表。

文本回链只保留两种：

- Feature 已有 ADR 时，写 `decision: ADR-NNNN`。
- PR 合并后应关闭 Issue 时，写 `Closes #N`。

原生关系覆盖的内容，不重复写成正文清单。

Project 8 的常规字段只有三个：

- `Status`：随 Issue 状态更新。
- `Priority`：只给 Feature 使用。
- `Target date`：只给活跃 Feature 使用。

`Size`、`Start date` 和 `Estimate` 是历史字段。
新 Issue 不要求填写这些字段。
已有值保留，不批量删除。

## 6. 测试门禁

| 层级 | 何时运行 | 完成标准 |
| --- | --- | --- |
| 相关测试 | 本地迭代 | 直接相关用例通过 |
| 受影响模块 | 提交 PR 前 | 模块测试和跨边界用例通过 |
| Linux 托管门禁 | 每个代码 PR | Rust、Kotlin JVM 和可移植检查通过 |
| macOS 验收 | 发布 Mac 或手动工作流 | XCTest、helper、安装器和硬件验收通过 |
| 全量测试 | 高风险改动或正式发布 | `bash scripts/test-all.sh` 通过 |

满足任一项时，运行全量测试：
- 改动跨越两个以上模块。
- 改动配置、合同、协议或持久化。
- 改动发布脚本、CI 或构建配置。
- 无法判断影响范围。
- 准备正式发布。

PR 写本地测试、CI 和真机结果。自动 CI 不运行 macOS XCTest。本地未跑全量测试时，写明原因和对应 CI 作业。

## 7. UI 证据

Issue 写用户可观察的验收结果。
PR 保存 UI 代码变更的证据。

证据分级：

- 局部 UI 改动：记录受影响模式的一组 Before/After。
- 外观、导航或材质变化：记录亮色和深色两组 Before/After。
- 发布候选：记录亮色、深色和真机环境。

PR 记录日期、设备、系统、页面、状态和 commit。
截图默认附在 PR 中。
发布证据需要长期保存时，再归档到 `docs/design/previews/`。

普通 PR 不填写 `Design preview`。
UI 决策可以在 Issue 中保存候选截图和评审状态。
UI 代码 PR 缺少所需证据时，不得转为 ready 或合并。

## 8. ADR

ADR 只记录长期决策。
长期决策满足任一项：

- 影响多个模块。
- 修改成本高。
- 半年后仍会被问到。

ADR 的 PR 合并后生效。
Feature 有 ADR 时，写实际编号。
没有 ADR 时不写占位符。

## 9. PR 结构

PR 只保留四个主体段：

1. `What changed`
2. `Proof`
3. `Visual verification`
4. `Risk`

没有 UI 变化时，`Visual verification` 写 `Not applicable`。
PR 在测试通过前保持 draft。
测试失败时不得转入 ready 或合并。
