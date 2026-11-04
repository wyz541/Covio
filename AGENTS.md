# Covio 工作约定

本文件是 agent 的强制契约。Codex 直接读本文件。Claude Code 通过 `CLAUDE.md` 导入。

## 1. 项目基线
- Covio 交付 Windows 和 macOS。macOS UI 在 `macosApp/`，Windows UI 在 `rust/apps/covio-windows/`。
- 共享逻辑是 Rust core，代码在 `rust/crates/`。`kmpDomain/` 只保留给未迁移平台和仓库检查。
- 仓库级 KMP 删除需要独立决定。
- Amper 0.12.1 仍管理 KMP 检查，不是 Gradle。
- 主干是 `main`。
- 项目版本遵循 Semantic Versioning 2.0.0。权威规则见 `docs/process/versioning.md`。

## 2. 工作流
流程细节见 `docs/process/workflow.md`。
- 明确 Bug 或小任务直接创建 Issue。
- 方法未知时直接创建 Research Issue。
- 需要多个 PR、超过 5 个工作日或先改设计时，创建 Feature。
- Verify 只用于跨 PR、真机、外部设备或发布验收。
- Discussion 只用于开放问题，不是 Issue 的前置条件。
- Research 可以独立存在。
- 一个 Task 对应一条分支和一个 PR。
- Feature 子项使用原生 sub-issue。
- 真实依赖使用原生 `blocked by`。
- 不要维护第二份子任务或进度清单。

最小必填内容：
- Bug：实际行为、预期行为、复现步骤。
- Task：目标、验收标准。
- Research：问题、预期产出、截止日期。
- Feature：目标、完成条件。
- Verify：验收目标与场景、证据要求。

## 3. 字段与回链
Project 8 的常规字段只有 `Status`、`Priority` 和 `Target date`。
`Priority` 和 `Target date` 只给 Feature 使用。
`Size`、`Start date` 和 `Estimate` 是历史字段，新 Issue 不要求填写。
- Feature 有 ADR 时，写 `decision: ADR-NNNN`。
- PR 应关闭 Issue 时，写 `Closes #N`。
- 不要写决策占位符。
- 不要使用人工周检清单。

## 4. 测试
日常迭代运行相关测试。
提交 PR 前运行受影响模块的测试。
满足任一项时运行 `bash scripts/test-all.sh`：
- 跨两个以上模块。
- 修改配置、合同、协议或持久化。
- 修改发布脚本、CI 或构建配置。
- 无法判断影响范围。
- 准备正式发布。

自动 CI 使用 Linux，运行 Rust、Kotlin JVM 和可移植检查。
macOS XCTest、helper、安装器和真机验收在发布 Mac 或手动工作流运行。
PR 写命令、结果、CI 和剩余风险。
测试失败时不得转入 ready 或合并。

## 5. UI 证据
UI Issue 写用户可观察的验收结果。
UI 代码 PR 必须填写 `Visual verification`。
- 局部 UI 改动：记录受影响模式的一组 Before/After。
- 外观、导航或材质变化：记录亮色和深色两组。
- 发布候选：记录亮色、深色和真机环境。

证据写日期、设备、系统、页面、状态和 commit。
截图默认附在 PR。
长期证据再存入 `docs/design/previews/`。
缺少所需证据时，不得转入 ready 或合并。

## 6. 文档
文档用中文。命令、路径、API 名称和版本号保留原文。
不写本机绝对路径。
改动涉及行为时，同步修改文档。
关键来源：
- 设计合同：`docs/covio-design-contract.json`
- 架构决策：`docs/adr/`
- 目标架构：`docs/design/`
- 研究结论：`docs/research/`
- 工作流：`docs/process/workflow.md`
- Project 字段：`docs/process/project-fields.md`
- 进度：[Project 8](https://github.com/users/wyz541/projects/8)

## 7. commit
标题使用英文祈使句。首字母大写，不超过 72 字符。
标题不加句号或 `feat:` 前缀。
有对应 Issue 时写 `Refs #N`。agent 提交添加 `Co-Authored-By` 行。
使用 `git commit -m`。

```text
Add the workbench store

Refs #27
Co-Authored-By: Claude Code <noreply@anthropic.com>
```

## 8. 禁止
1. 禁止直接向 `main` 推送。
2. 禁止使用 `git add -A` 或 `git add .`。
3. 禁止把本机绝对路径写入仓库文件。
4. 修改设计合同后，重跑 `scripts/generate-contract-constants.py`。
