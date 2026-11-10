# Covio 共享设计合同

**结论：SwiftUI、Rust 和 Compose 只从同一份设计合同读取共享设计语义。**

## 1. 权威链

macOS 与 iOS 的 Apple 设计是视觉和交互权威。
`docs/covio-design-contract.json` 是机器可读投影。
生成物是消费端，不是第二个权威。

合同覆盖以下内容：

- 颜色、尺寸和动效令牌。
- 平台字体和排版角色。
- 语义角色和键盘焦点顺序。
- 平台覆盖记录。
- 视觉与行为验收 ID。

## 2. 平台字体

| 平台 | 主字体 | 回退 | 状态 |
| --- | --- | --- | --- |
| macOS | `SF Pro` | 无 | required |
| iOS | `SF Pro` | 无 | required |
| Windows | `Segoe UI Variable` | `Segoe UI` | required |
| Android | `Roboto` | `sans-serif` | deferred |

**警告：** Windows 不得加载或打包 `SF Pro`。Apple 字体许可不覆盖 Windows 产品。

Windows egui 先加载 `SegUIVar.ttf`。
Windows egui 在变量字体不可用时加载 `segoeui.ttf`。
Compose host 使用同一平台字体映射。

## 3. 共享语义

`semanticRoles` 把颜色、尺寸和排版组合为稳定角色。
`focusOrder` 定义每个作用域的键盘顺序。
模态焦序必须捕获焦点。
模态关闭后必须恢复原焦点。

`platformOverrides` 记录允许的平台差异。
每条覆盖记录包含稳定 ID、原因、行为和证据。
没有覆盖记录时，Compose host 不得改变共享值。

## 4. 验收 ID

`acceptanceCriteria` 同时包含 `visual` 和 `behavior` 条目。
视觉验收检查语义和层级。
行为验收检查焦序、无障碍和减少动态效果。
跨平台验收要求语义和视觉结果对齐。
跨平台验收不要求像素完全相同。

## 5. 生成物

生成命令：

```sh
python3 scripts/generate-contract-constants.py
```

生成物如下：

- `macosApp/src/Design/ContractCopy.swift`
- `macosApp/src/Design/ContractTokens.swift`
- `macosApp/src/Design/ContractSemantics.swift`
- `rust/crates/covio-core/src/contract_motion.rs`
- `rust/crates/covio-core/src/contract_design.rs`
- `composeApp/src/commonMain/kotlin/com/covio/design/GeneratedDesignContract.kt`

禁止手改生成物。

## 6. CI 门禁

CI 执行以下检查：

```sh
python3 -I scripts/generate-contract-constants.py --check
python3 -I scripts/validate-contract.py
```

第一条检查生成物漂移。
第二条检查合同引用和平台规则。

## 7. 证据

平台覆盖证据位于：

- `docs/research/compose-rust-bridge/evidence.md`
- `docs/design/windows-visual-language.md`
- `docs/process/interaction-contract.md`

UI PR 必须记录受影响的验收 ID。
视觉截图不能代替行为测试。
