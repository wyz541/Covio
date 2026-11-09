# 跨平台交互合同工作流

**结论：macOS 是共享交互与动效的唯一设计来源。Windows 只消费生成产物。**

版本 1.0 · 2026-11-09

## 1. 范围

共享交互合同定义 Windows 和 macOS 的一致触发行为与响应行为。
合同覆盖以下内容：

- 触发区域和显示器选择。
- 显示状态和隐藏状态。
- 状态转换方向和状态顺序。
- 几何参数和锚点。
- 时长、缓动曲线、延迟和冷却时间。
- 减少动态效果和中断处理。

本流程不共享平台 UI 代码。
本流程不替代视觉验收。

## 2. 权威链

| 顺序 | 产物 | 所有者 | 规则 |
| --- | --- | --- | --- |
| 1 | macOS 原生行为 | macOS | 定义交互和动效的设计结果 |
| 2 | macOS Swift 合同 | macOS | 保存共享合同值 |
| 3 | macOS 运行时 | macOS | 消费同一份 Swift 合同 |
| 4 | JSON 合同 | macOS 导出器 | 确定性生成并提交 |
| 5 | Rust 合同 | Windows 生成器 | 从 JSON 确定性生成 |
| 6 | Windows 运行时 | Windows | 只消费生成的 Rust 合同 |
| 7 | 一致性测试 | Windows 和 macOS | 验证用户可观察的行为 |

JSON 合同是导出物。
JSON 合同不是第二权威。
生成的 Rust 是导出物。
生成的 Rust 不是第二权威。

## 3. macOS 责任

- macOS 先修改原生交互。
- macOS 在类型化 Swift 合同中记录共享值。
- macOS 运行时读取同一份 Swift 合同。
- macOS 更新行为测试和 golden 测试。
- macOS 在 Apple Silicon Mac 验收交互和外观。
- macOS 用导出器确定性生成 JSON 合同。
- macOS 提交 Swift 合同、JSON 合同和测试。

macOS 的外观、时序和状态转换是 Windows 的验收基准。

## 4. Windows 责任

- Windows 从 JSON 合同生成 Rust 类型和常量。
- Windows 运行时只读取生成的 Rust 合同。
- Windows 不复制共享触发、几何、动效或状态转换值。
- Windows 适配层只处理平台 API 和 egui 能力差异。
- Windows 测试覆盖触发、状态、时序和几何。
- Windows 运行生成漂移检查。
- Windows 运行跨平台一致性测试。
- Windows PR 记录视觉验收结果。

## 5. 平台覆盖

Windows 只能因平台 API 或 egui 能力限制声明覆盖。
覆盖记录必须包含以下字段：

- 稳定 ID。
- 合同键。
- 平台。
- 原因。
- 可复核证据。
- 所属 Issue。

覆盖记录存放在显式白名单或 schema 中。
覆盖记录不存放在散落的条件分支中。
覆盖不得改变 macOS 基准，除非 macOS 合同也同步修改。
Windows 不得静默增加视觉调整。

## 6. 变更步骤

1. 修改 macOS 原生行为。
2. 更新 Swift 合同。
3. 更新 macOS 运行时消费。
4. 更新 macOS 行为测试。
5. 在 Apple Silicon Mac 验收。
6. 运行确定性 JSON 导出。
7. 提交导出的 JSON 合同。
8. 生成 Windows Rust 合同。
9. 更新 Windows 一致性测试。
10. 运行漂移检查和测试。
11. 在 PR 填写 `Contract impact`。

跨 PR 的合同变更使用原生 `blocked by`。
PR 不手填共享值，只消费生成产物。

## 7. PR 证据

共享交互或动效 PR 必须记录以下内容：

- 变更的合同键。
- macOS 权威来源文件。
- 导出的 JSON 合同文件。
- 生成的 Windows 文件。
- 导出命令和结果。
- 生成命令和结果。
- macOS 行为测试和视觉证据。
- Windows 一致性测试。
- 平台覆盖记录。

无合同影响时，PR 写 `Contract impact: Not applicable.`。
截图提供视觉证据。
截图不代替行为测试。

## 8. 合并门禁

以下条件全部满足后，PR 才能转为 ready：

- Swift 合同、macOS 运行时和 JSON 合同一致。
- Windows 生成文件与 JSON 合同一致。
- 一致性测试通过。
- 覆盖记录完整且可追溯。
- Windows 不存在共享值的独立来源。
- PR 包含所需的合同证据。

任一项不满足时，PR 不得转为 ready 或合并。

## 9. 硬失败

以下变更直接失败：

- 手改 JSON 导出物。
- 手改 Windows 生成物。
- 只在 Windows 修改共享值。
- 允许合同与运行时分叉。
- 使用无 ID、无理由或无证据的覆盖。

## 10. 迁移状态

`docs/covio-design-contract.json` 当前承载设计和动效令牌。
macOS Swift 合同接入后，JSON 只作为确定性导出物。
迁移期仍禁止 Windows 单独定义共享值。
迁移期的合同变更必须对应 macOS 行为变更或 macOS 设计决定。
相关 PR 必须说明临时来源和后续导出路径。
