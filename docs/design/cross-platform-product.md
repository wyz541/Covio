# Covio 跨平台产品规格

| 项目 | 内容 |
| --- | --- |
| 状态 | active specification |
| 日期 | `2026-11-12` |
| 决策 | [ADR-0035](../adr/adr-0035-cross-platform-product-scope.md) |
| 首版平台 | macOS、Windows、iOS |
| 后续平台 | Android |
| 执行 Feature | [#734](https://github.com/wyz541/Covio/issues/734)、[#716](https://github.com/wyz541/Covio/issues/716) |

本文定义 Covio 的产品范围、平台状态、所有权、共享合同和验收边界。
本文不记录 Task 状态。
本文不维护第二份子任务清单。

## 1. 结论与术语

Covio 是独立跨平台产品。
第一版支持 macOS、Windows 和 iOS。
Android 在第一版之后进入。
Covio 在已配对设备之间传输文件。
Covio 只读展示本机和已配对设备的信息。
Covio 保留 macOS 电源和截图工具。

术语定义如下：

- **设备配对**：用户使用二维码建立两台设备的信任关系。
- **文件传输**：用户发送或接收单文件与目录快照。
- **设备信息**：设备系统、版本、在线状态和能力的只读快照。
- **共享合同**：macOS 定义交互、动效和视觉值，其他平台消费生成结果。
- **Cutover**：Windows 默认产物从 egui 切换到 Compose host 的发布变更。
- **Platform adapter**：调用原生 OS API 的平台接入层。
- **纵向切片**：覆盖一条完整用户流程的小范围实现。

第一版新增以下产品能力：

1. 使用二维码配对设备。
2. 在配对设备之间传输单文件。
3. 在配对设备之间传输目录快照。
4. 提供传输进度、暂停、恢复、取消和稳定错误。
5. 只读展示本机和已配对设备的信息。
6. 通过 GitHub Releases 分发内部测试产物。

第一版仅用于内部测试。
第一版不使用账号、云端文件或实时目录同步。

## 2. 用户场景

| 场景 | 用户可观察结果 |
| --- | --- |
| 配对设备 | 用户扫描两个二维码。两端显示同一确认码。用户确认后建立信任关系。 |
| 发送单文件 | 发送方选择已配对设备和文件。接收方确认报价。双方看到传输进度。 |
| 接收单文件 | 接收方确认报价。Rust core 校验内容并原子写入收件区。 |
| 发送目录快照 | 发送方选择目录。接收方收到快照清单。冲突文件按 `keep_both` 保存。 |
| 中断与恢复 | 网络中断或应用进入后台后，任务保存检查点。连接恢复后，任务从检查点继续。 |
| 查看设备信息 | 用户看到本机和已配对设备的系统、版本、在线状态及能力。能力不可用时，UI 不显示虚假入口。 |
| Windows 交互 | Workbench 的触发、显示、隐藏和减少动态效果与 macOS 合同一致。 |

首版验收覆盖以下设备组合：

- macOS ↔ Windows。
- macOS ↔ iOS。
- Windows ↔ iOS。

## 3. 平台状态与目标

| 平台 | 当前状态 | 目标 UI | Rust bridge | 凭据存储 |
| --- | --- | --- | --- | --- |
| macOS | 现有产品已交付。跨设备 host 已实现；三平台真机证据尚未完成。 | SwiftUI + AppKit | C ABI；UniFFI 可选 | Keychain |
| Windows | egui 是当前产品基线。Compose 是 opt-in prototype。 | Compose Multiplatform | JNI | Credential Manager |
| iOS | 纵向切片与统一发布工具已实现；签名制品和真机证据尚未完成。 | SwiftUI | C ABI；UniFFI 可选 | Keychain |
| Android | 第一版不交付。后续平台目标。 | Compose Multiplatform | JNI | Keystore |

Windows 当前继续交付 egui 产物。
Compose host 是独立 opt-in 路径。
Compose host 通过以下条件后才能替换 egui：

1. 功能验收通过。
2. 视觉验收通过。
3. 打包验收通过。
4. 性能验收通过。
5. 跨平台交互一致性测试通过。
6. Windows 真机验收通过。

Cutover 完成前，Windows 保留 egui 回滚路径。
Cutover 完成后，Windows 与 Android 共享 Compose UI 和交互语义。
macOS 使用 SwiftUI + AppKit。
iOS 使用 SwiftUI。
两者保持 Apple 原生体验。

详细平台方案见以下文档：

- [Windows Compose host](windows-compose-host.md)
- [iOS SwiftUI 宿主](ios-host.md)
- [跨平台交互合同](../process/interaction-contract.md)

## 4. 所有权与系统边界

| 层 | 拥有 | 不拥有 |
| --- | --- | --- |
| Rust core | 业务规则、状态机、持久化、传输、权限策略、能力模型和错误合同 | 窗口、绘制、系统 share sheet |
| Rust bridge | C ABI、JNI、UniFFI、句柄、取消、deadline、事件队列和 panic containment | UI 状态和平台界面 |
| Apple UI host | Apple 界面、输入、可访问性和 app lifecycle | 业务状态副本 |
| Compose UI host | Windows 与 Android 界面、输入和 UI lifecycle | 业务状态副本 |
| egui UI host | 当前 Windows 界面和输入 | 业务状态副本和共享值定义 |
| Platform adapter | 文件选择、share sheet、通知、后台任务、安全存储和 OS 权限 | 业务规则、持久化规则和传输状态机 |
| Design contract | Apple 权威视觉、交互、动效和平台覆盖 | 运行时业务数据 |

以下约束对所有平台生效：

- Rust core 是业务逻辑和持久化的唯一 owner。
- Kotlin、Compose 和 JVM 只用于 UI host 与平台接入。
- ADR-0034 的 KMP shared module 删除决定继续有效。
- UI host 不复制 Rust 状态机。
- Platform adapter 只调用原生 OS API。
- UI 不直接判断业务能力。UI 使用 Rust 返回的能力结果。
- Secret 不进入普通日志、UI snapshot 或通用 bridge 返回值。
- 文件内容不进入普通 JSON control envelope。

Bridge 必须支持以下边界：

1. 每个请求带 protocol version、request ID、generation 和 deadline。
2. 每个异步任务支持 cancellation。
3. callback 和事件队列有大小上限。
4. 大文件使用句柄或数据流。
5. Rust panic 在 bridge 边界转换为 typed error。
6. JNI 不跨调用保存 `JNIEnv`。
7. 长任务不在 UI 线程执行。
8. Platform adapter 返回稳定错误码、用户动作和能力状态。

Bridge 详细合同见 [Covio bridge 合同](bridge-contract.md)。

## 5. Rust 能力模型

Rust core 定义以下产品能力：

- 设备发现与身份。
- 二维码配对、授权和撤销。
- 传输队列、分块、暂停、恢复、取消和续传。
- 内容校验与原子提交。
- 文件冲突策略和目录快照语义。
- 后台暂停与前台恢复状态。
- 文件选择结果和 share target。
- 通知事件。
- 凭据访问合同。
- 设备信息快照。
- 稳定错误合同。

Platform adapter 提供以下原生能力：

- 文件选择器。
- Share sheet。
- 通知。
- 后台任务和前台恢复。
- Keychain、Credential Manager 和 Keystore。
- 网络接口和 OS 权限。
- 相机二维码扫描。

平台实现见以下文档：

- [Covio 凭据仓库](credential-vault.md)
- [Covio 设备身份与二维码配对](device-pairing.md)
- [Covio 单文件传输](single-file-transfer.md)
- [Covio 目录传输](directory-transfer.md)
- [macOS 跨设备传输入口](macos-device-transfer.md)

## 6. 跨平台交互合同

macOS 是共享交互、动效和外观的权威源。
合同权威链如下：

1. macOS 定义原生交互和动效行为。
2. macOS 使用类型化 Swift 合同保存共享值。
3. macOS 运行时读取同一份 Swift 合同。
4. macOS 导出器确定性生成 JSON 合同。
5. 生成器从 JSON 生成平台消费代码。
6. 各平台运行同一组行为向量。
7. CI 检查生成漂移和用户可观察差异。

JSON 合同不是第二权威。
平台生成物不是第二权威。
Compose host 不复制共享触发、几何、状态转换、动效或外观值。
egui host 在迁移期只消费生成的 Rust 合同。
Compose host 在 cutover 后消费生成的 Compose 合同。
两类生成物必须来自同一份 JSON 合同。

平台覆盖必须记录以下字段：

- 稳定 ID。
- 合同键。
- 平台。
- 原因。
- 可复核证据。
- 所属 Issue。

平台覆盖不得静默改变共享值。
共享值变化必须同步修改 macOS Swift 合同、导出的 JSON 和生成消费物。
合同测试不能替代视觉验收。
视觉截图不能替代行为测试。

完整流程见 [跨平台交互合同](../process/interaction-contract.md)。

## 7. Feature 边界

| Feature | 负责 | 不负责 |
| --- | --- | --- |
| [#734](https://github.com/wyz541/Covio/issues/734) | 跨平台文件传输、设备信息、Rust 能力、平台 host、打包和真机验收 | 共享交互合同值 |
| [#716](https://github.com/wyz541/Covio/issues/716) | macOS 权威交互合同、生成物、一致性测试和 Windows 采用证据 | 产品业务规则和传输状态机 |

原生 sub-issue 是任务层级来源。
原生 `blocked by` 是依赖来源。
本文只记录边界和验收。
本文不复制 Feature 的子任务。
本文不记录 Task 完成百分比。

Feature 的详细完成条件以对应 Issue 正文为准。

## 8. 验收与证据

| 类别 | 通过条件 | 必须保存的证据 |
| --- | --- | --- |
| 产品功能 | 三个首版平台完成配对、单文件传输和目录快照传输 | 设备组合、操作步骤和结果 |
| 传输可靠性 | 中断、取消、恢复、冲突和空间不足有稳定结果 | 日志、检查点状态和错误码 |
| 设备信息 | 本机和已配对设备只显示正确能力 | 页面状态和设备信息快照 |
| 交互合同 | 共享值来自单一权威链，漂移检查通过 | 合同键、生成物、命令和 CI |
| Windows 交互 | 触发、显示、隐藏和减少动态效果对齐 macOS | 亮色、深色、录屏和一致性测试 |
| 平台接入 | 文件选择、通知、分享和生命周期行为可用 | 真机操作记录和平台日志 |
| 打包发布 | 三个平台使用同一 commit、版本号和 build number | Release 清单、SHA-256 和下载记录 |
| 真机验收 | macOS、Windows 和 iOS 完成三种配对组合 | 日期、设备、OS、build、commit 和结果 |

验收证据必须包含日期、设备型号、OS、artifact、commit、页面或状态。
自动化验收还必须包含命令、结果和 CI 链接。
截图默认附在 PR。
长期证据存入 `docs/design/previews/`。
UI PR 必须填写 `Visual verification`。
合同 PR 必须填写 `Contract impact`。
缺少必需证据时，PR 不得转为 ready 或合并。

## 9. 非目标与暂缓事项

第一版明确排除以下内容：

- Android 交付。
- App Store 和 Google Play 发布。
- 正式更新器和正式商店签名流程。
- 账号体系。
- 云端文件存储。
- 公网 relay 作为首版完成条件。
- 实时目录同步。
- 远程写入或任意设备控制。
- iOS 后台持续接收。
- 恢复 KMP shared module。
- Apple 与 Compose 共享平台 UI 实现代码。
- 在 UI 层建立第二套业务状态机。

正式发布、商店分发和正式更新方案必须在第一版之后单独决策。

## 10. 风险与限制

1. Windows Compose 的启动时间和包体积可能不可接受。Cutover 必须包含性能与打包门槛。
2. C ABI、JNI 和 UniFFI 可能产生合同漂移。每个 bridge 必须使用单一 schema 和生成检查。
3. SwiftUI、egui 和 Compose 可能产生行为差异。共享合同必须包含行为向量和一致性测试。
4. iOS 后台能力受系统限制。产品只承诺前台恢复，不承诺后台持续接收。
5. 局域网发现和 relay 行为可能随网络环境变化。真机验收必须记录网络条件。
6. 大文件和目录传输可能中断。实现必须保存检查点、校验内容并原子提交。
7. 凭据平台语义可能不同。平台 adapter 必须返回能力状态和稳定错误。
8. 目标状态可能被误读为已交付状态。本文分别记录当前状态和目标 UI。
9. Discussion #458 来自旧仓库上下文。该讨论只作为历史输入。

风险决策细节见 [ADR-0035](../adr/adr-0035-cross-platform-product-scope.md)。

## 11. 来源与优先级

内容冲突时，使用以下优先级：

1. [ADR-0035](../adr/adr-0035-cross-platform-product-scope.md)。
2. 本文。
3. Feature #734、Feature #716 和详细设计文档。
4. Discussion #732、Discussion #715 和 Discussion #458。

输入与执行入口如下：

- [Discussion #732](https://github.com/wyz541/Covio/discussions/732)：跨平台文件与设备信息方向。
- [Discussion #715](https://github.com/wyz541/Covio/discussions/715)：macOS 权威的跨平台交互与动效合同。
- [Discussion #458](https://github.com/wyz541/Covio/discussions/458)：Windows Compose Multiplatform 与 macOS 互通的早期背景。
- [Feature #734](https://github.com/wyz541/Covio/issues/734)：跨平台能力交付。
- [Feature #716](https://github.com/wyz541/Covio/issues/716)：跨平台交互合同交付。

补充文档如下：

- [ADR-0030](../adr/adr-0030-rust-core-platform-native-ui.md)
- [ADR-0034](../adr/adr-0034-remove-kmp-shared-module.md)
- [跨平台凭据存储研究](../research/platform-credential-storage/README.md)
- [Rust 跨平台文件传输研究](../research/rust-file-transfer/README.md)
- [Compose Multiplatform 与 Rust bridge 研究](../research/compose-rust-bridge/README.md)
- [跨设备内容读取能力研究](../research/cross-device-content-access/README.md)
