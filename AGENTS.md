# Covio 工作约定

本文件是 agent 的强制契约。Codex 直接读本文件。Claude Code 通过 `CLAUDE.md` 导入。

## 1. 项目基线
- Covio 是独立跨平台产品。第一版平台是 macOS、Windows 和 iOS；Android 在第一版之后进入。
- macOS/iOS UI 使用 SwiftUI，macOS 另用 AppKit。Windows 当前 UI 使用 egui，目标 UI 使用 Compose Multiplatform；Android 目标 UI 使用 Compose Multiplatform。
- 共享逻辑是 Rust core，代码在 `rust/crates/`。Rust 是业务逻辑、状态机、持久化、传输、权限策略和平台能力模型的唯一 owner。
- Kotlin、Compose 和 JVM 只允许用于 UI host 与平台接入。ADR-0034 的 KMP shared module 删除决策继续有效；Windows egui 是当前运行基线。
- macOS/iOS 使用 C ABI；Windows/Android 使用 JNI。UniFFI 只做可选绑定试验。macOS/iOS Apple 设计是设计权威源，Compose 共享设计合同并对齐视觉结果。
- 产品范围与 UI 决策见 ADR-0035。当前只做内部测试，产物通过 GitHub Releases 分发。主干是 `main`。项目版本使用 Semantic Versioning 2.0.0，正式发布规则可以重新设计。

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

GitHub Actions 运行 Linux、Windows 和可移植检查。
GitHub Actions 禁止 macOS 构建。macOS XCTest、helper、安装器和真机验收在本地 Apple Silicon Mac 运行。
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

## 6. 跨平台交互合同
- macOS 是共享交互、动效和外观的唯一设计来源。
- macOS 用类型化 Swift 合同定义共享行为。
- macOS 运行时消费同一 Swift 合同。
- JSON 合同由 macOS Swift 合同确定性导出。
- Compose host 消费生成的 Compose 合同；当前 egui host 在 cutover 前消费生成的 Rust 合同。
- Compose host 不得独立定义共享触发、几何、动效或状态转换参数。
- Compose 覆盖必须有稳定 ID、理由和证据。
- 禁止手改合同生成物。
- 相关 PR 必须填写 `Contract impact`。
- 缺少合同证据时，PR 不得转为 ready 或合并。

## 7. 文档
文档用中文。命令、路径、API 名称和版本号保留原文。
不写本机绝对路径。
改动涉及行为时，同步修改文档。
关键来源：
- 设计权威：macOS 与 iOS 的 Apple 设计
- 设计合同投影：`docs/covio-design-contract.json`
- 跨平台交互合同：`docs/process/interaction-contract.md`
- 架构决策：`docs/adr/`
- 目标架构：`docs/design/`
- 研究结论：`docs/research/`
- 工作流：`docs/process/workflow.md`
- Project 字段：`docs/process/project-fields.md`
- 进度：[Project 8](https://github.com/users/wyz541/projects/8)

## 8. commit
标题使用英文祈使句。首字母大写，不超过 72 字符。
标题不加句号或 `feat:` 前缀。
有对应 Issue 时写 `Refs #N`。agent 提交添加 `Co-Authored-By` 行。
使用 `git commit -m`。

```text
Add the workbench store

Refs #27
Co-Authored-By: Claude Code <noreply@anthropic.com>
```

## 9. 禁止
1. 禁止直接向 `main` 推送。
2. 禁止使用 `git add -A` 或 `git add .`。
3. 禁止把本机绝对路径写入仓库文件。
4. 修改设计合同后，重跑 `scripts/generate-contract-constants.py`。
5. 禁止手改合同生成物。
6. 禁止只在单一客户端修改共享交互或动效值。
