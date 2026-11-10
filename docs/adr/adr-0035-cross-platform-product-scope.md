# ADR-0035：Covio 跨平台产品范围与 UI 技术栈

- Status：accepted
- Kind：architecture
- Date：2026-11-10
- Supersedes：ADR-0030 的平台范围与 Windows UI 决策
- Updates：ADR-0034
- Implements：[Discussion #732](https://github.com/wyz541/Covio/discussions/732)
- 相关：[Paseo](https://github.com/getpaseo/paseo)、[跨设备内容研究](../research/cross-device-content-access/README.md)

## 背景

ADR-0030 决定 Windows 和 macOS 使用 Rust core 与平台原生 UI。
ADR-0030 同时把 Windows UI 固定为 egui。
ADR-0034 删除 KMP shared module，并禁止 Windows 产品路径包含 Kotlin、Compose、JVM 和 JNA。
这两项决策不符合新的产品方向。

Covio 的目标是成为独立跨平台产品。
第一版需要支持 macOS、Windows 和 iOS。
Android 在第一版之后进入。
Windows 与后续 Android 需要共享 Compose UI 和交互语义。
macOS 与 iOS 继续使用 SwiftUI。Apple 设计是视觉与交互权威源。
Rust core 继续拥有共享业务逻辑和平台能力合同。

文件共享参考 AirDrop。
设备信息查询只读。
配对使用二维码。
传输与安全参考 Paseo。
当前只做内部测试，通过 GitHub Releases 分发。

## 决策

1. Covio 是独立跨平台产品。
2. 第一版支持 macOS、Windows 和 iOS。
3. Android 不在第一版范围。Android 目标 UI 使用 Compose Multiplatform。
4. macOS 使用 Rust core、SwiftUI 与 AppKit。
5. iOS 使用 Rust core 与 SwiftUI。
6. Windows 目标 UI 使用 Compose Multiplatform。
7. Windows 的 Compose Multiplatform host 替换 egui host。
8. Windows 与 Android 共享 Compose UI 和交互语义。
9. macOS 与 iOS 的 Apple 设计是设计权威源。
10. SwiftUI 与 Compose 共享设计合同。Compose 在视觉效果上对齐 Apple 设计。
11. Rust 是业务逻辑、状态机、持久化、传输、权限策略和平台能力模型的唯一 owner。
12. Kotlin/Compose/JVM 只允许用于 UI host 和平台接入。
13. 不恢复 KMP shared module。ADR-0034 的仓库删除决策继续有效。
14. macOS 与 iOS 使用 C ABI。Windows 与 Android 的 Kotlin/Compose 使用 JNI。UniFFI 只用于验证后的 Swift 绑定或隔离试验。默认 UniFFI Kotlin/JNA 后端不进入首版产品路径。
15. 文件选择、分享面板、通知和后台任务由 Rust 定义统一能力模型、状态和错误语义。
16. 平台 adapter 只调用原生 OS API。UI 层不复制业务状态机。
17. 文件共享采用 AirDrop 式流程。发送方选择已配对设备，接收方确认接收。
18. 配对使用二维码。二维码绑定设备身份和临时配对信息。
19. 传输与安全参考 Paseo。首版优先局域网直连，并研究端到端加密 relay。
20. 移动端进入后台后暂停接收与续传。移动端回到前台后恢复任务。
21. 设备信息查询只读展示。
22. macOS 与 iOS 使用 Keychain。Windows 使用 Credential Manager。Android 后续使用 Keystore。
23. Rust 暴露统一凭据合同。平台 adapter 实现实际存储。
24. 原生安全存储只保护 32 字节根密钥。Rust 使用 AEAD 保存业务记录，并返回平台能力、用户动作和稳定错误码。通用 secret read 不进入产品 bridge。
25. 文件传输采用 `iroh 1.4.1` 作为首版底座。Covio 自建控制流、文件流、分片和恢复协议。
26. 首版使用 1 MiB 分块、8 MiB 窗口、BLAKE3 校验、SQLite 检查点、同卷暂存文件和原子提交。默认冲突策略是 `keep_both`。首版拒绝符号链接。
27. iOS 进入后台时暂停传输。iOS 回到前台后先验证连接，再从检查点恢复。
28. Compose host 使用有界事件队列、typed error、cancellation、deadline、句柄 generation 和 panic containment。JNI 不保存 `JNIEnv`，长任务不在 UI 线程执行。
29. Apple 设计继续是设计权威。允许平台字体映射。Windows 使用 Segoe UI Variable，不在 Windows 使用 SF Pro。
30. Windows 内部包使用 `jlink` 与 `jpackage`。产物使用 MSI 和便携 ZIP。资产通过 GitHub pre-release 分发，并附 SHA-256。
31. 当前只做内部测试。正式商店发布、正式更新和安装器方案暂缓。

## 当前状态与目标状态

| 平台 | 当前状态 | 目标 UI | Rust bridge |
| --- | --- | --- | --- |
| macOS | Rust core + SwiftUI/AppKit | SwiftUI + AppKit | C ABI；UniFFI 可选 |
| Windows | Rust core + egui | Compose Multiplatform | JNI |
| iOS | 未交付 | SwiftUI | C ABI；UniFFI 可选 |
| Android | 未交付，后续范围 | Compose Multiplatform | JNI |

Windows egui 是当前运行基线。
迁移完成前，Windows 继续交付 egui 产物。
CMP host 必须通过功能和视觉验收后才能替换 egui。

## 后果

### 正面

- 三个首版平台共享 Rust 业务语义。
- Windows 与后续 Android 可以共享 Compose UI 和交互行为。
- macOS 与 iOS 保持 Apple 原生体验。
- 设计合同有单一权威源。
- 文件传输、凭据和平台能力由 Rust 统一建模。
- KMP shared module 不恢复，业务逻辑不出现第二套状态机。

### 负面

- Windows UI 需要一次完整迁移。
- Windows 分发需要 JVM UI runtime 或等价打包方案。
- JNI、UniFFI、C ABI 和 Swift/Kotlin 绑定需要持续漂移检查。
- SwiftUI 与 Compose 需要额外的视觉与行为验收。
- iOS、Android 和文件传输扩大构建、测试与安全边界。
- 平台原生文件选择、分享、通知和后台能力不能只由 Rust 实现。

### 风险

- 风险：Compose Windows 打包体积和启动时间不可接受。缓解：先做最小 host 原型并记录基线。
- 风险：JNI、UniFFI 和 C ABI 形成多套合同。缓解：保持单一 schema 与生成式绑定检查。
- 风险：Compose 与 SwiftUI 设计漂移。缓解：Apple 权威合同、生成令牌和视觉回归。
- 风险：移动端后台能力不足。缓解：前台恢复模型、任务队列和真机验证。
- 风险：大文件或文件夹中断后数据损坏。缓解：内容校验、临时文件、原子提交和断点续传。
- 风险：凭据平台语义不一致。缓解：平台 adapter、能力查询和统一错误合同。
- 风险：Kotlin UI 层复制业务规则。缓解：code review 和 bridge conformance tests。

## 备选方案

### 备选 1：保留 Windows egui

该方案保留已完成的 Windows host。
该方案无法与 Android 共享 Compose UI 和语义。
该方案仍会产生两套 UI 实现。
未采纳。

### 备选 2：所有平台使用平台原生 UI

该方案保持每个平台的原生体验。
该方案需要维护 SwiftUI、egui 或 Compose、Android Compose 等多套 UI。
该方案不符合 Windows 与 Android 共享 UI 的目标。
未采纳。

### 备选 3：恢复 KMP shared module

该方案可以让 Kotlin 共用领域代码。
该方案会形成 Rust 与 Kotlin 两套业务所有权。
该方案与 Rust core 唯一 owner 的决策冲突。
未采纳。

### 备选 4：macOS 和 iOS 也使用 Compose Multiplatform

该方案共享更多 UI 代码。
该方案会丢失现有 SwiftUI、AppKit 和 Apple 原生体验。
该方案与 Apple 设计权威源的要求冲突。
未采纳。

## 未决事项

| 项目 | 状态 | 确认方法 |
| --- | --- | --- |
| 跨平台凭据合同 | research complete，decision recorded | [platform-credential-storage](../research/platform-credential-storage/README.md) |
| 文件传输语义 | research complete，decision recorded | [rust-file-transfer](../research/rust-file-transfer/README.md) |
| Paseo 传输与后台参考 | research complete | `rust-file-transfer` 研究中的 Paseo 证据 |
| Compose 与 Rust bridge | research complete，decision recorded | [compose-rust-bridge](../research/compose-rust-bridge/README.md) |
| Windows CMP 打包 | implementation pending | 最小 Windows host 原型 |
| iOS 产品工程 | pending | 独立 Task |
| Android 产品工程 | deferred | 第一版后建立 Feature |
| 正式发布与更新 | deferred | 正式发布前建立 ADR |
| 设计合同迁移 | complete | [#740](https://github.com/wyz541/Covio/issues/740)；见 [共享设计合同](../design/shared-design-contract.md) |

## 参考

- [Discussion #732](https://github.com/wyz541/Covio/discussions/732)
- [ADR-0030：Windows 与 macOS 使用 Rust core 和原生 UI](adr-0030-rust-core-platform-native-ui.md)
- [ADR-0034：删除仓库中的 KMP shared module](adr-0034-remove-kmp-shared-module.md)
- [Paseo](https://github.com/getpaseo/paseo)
- [跨平台凭据存储](../research/platform-credential-storage/README.md)
- [Rust 跨平台文件传输](../research/rust-file-transfer/README.md)
- [Compose Multiplatform 与 Rust bridge](../research/compose-rust-bridge/README.md)
- [跨设备内容读取能力研究](../research/cross-device-content-access/README.md)
