# Compose Multiplatform 与 Rust bridge：调研分析

## 1. 文档状态

| 项目 | 内容 |
| --- | --- |
| 文档版本 | `1.0` |
| 状态 | 初稿，可评审 |
| 日期 | `2026-11-10` |
| 目标源码 | `main` 基线 `5a1f6c8dd9d2a66dd2cb6c7d0f68b08fc9b88297` 加当前工作树 |
| 执行状态 | 文档调研完成；原型尚未执行 |

本文件只分析现有证据。结论见 [conclusion.md](conclusion.md)。

## 2. 调研方法与来源范围

1. 读取 JetBrains 的平台支持、打包、窗口、可访问性和测试文档。
2. 读取 Compose Multiplatform `v1.12.2` release。
3. 读取 Compose desktop 固定 commit 的窗口 API 源码。
4. 读取 Oracle JNI、`jpackage` 和 GitHub Releases 文档。
5. 读取 Rust Reference 的 FFI unwind 规则。
6. 读取 UniFFI `0.32` 文档和主分支 JNI backend 源码。
7. 读取 Microsoft Learn 的 Share、通知和字体文档。
8. 读取 Apple 字体许可。
9. 读取 Paseo `v0.15.4` 的可见性和重连源码。
10. 只读检查 Covio 当前 Rust、Windows host 和设计合同。

来源等级如下。
- A：规范、官方接口定义、许可或平台硬约束。
- B：当前仓库固定源码或配置。
- C：官方项目文档和厂商文档。
- D：本机实验和环境事实。
- E：第三方资料。本次没有用 E 级来源支持关键决策。

来源范围、证据编号和限制见 [evidence.md](evidence.md)。

## 3. 事实、推论和假设

### 3.1 事实

1. Compose Multiplatform 把 Android、iOS 和 desktop JVM 标为 Stable（`E-01`）。
2. Compose Multiplatform `1.12.2` 在 `2026-10-15` 发布（`E-02`）。
3. Compose Multiplatform 与 Jetpack Compose 共用 Compose compiler 和 runtime 原则（`E-03`）。
4. Android target 使用 Google Jetpack Compose 制品。desktop target 使用 JetBrains 制品（`E-03`）。
5. `jpackage` 分发包含 Java runtime。`jlink` 裁剪模块（`E-05`、`E-07`）。
6. Windows native distribution 支持 `.msi` 和 `.exe`（`E-05`）。
7. Windows package version 使用 `MAJOR.MINOR.BUILD`。三个字段有数值上限（`E-06`）。
8. Compose `ComposeWindow` 在 Windows 暴露 HWND（`E-08`）。
9. Compose desktop 在 Windows 使用 Java Access Bridge 提供无障碍支持（`E-09`）。
10. GitHub Release 每个资产必须小于 `2 GiB`。单个 release 最多 `1000` 个资产（`E-11`）。
11. UniFFI 默认 Kotlin 文档要求 JNA `5.12.0` 或更高版本（`E-13`）。
12. UniFFI 主分支存在实验性 JNI backend。此 backend 使用 `jni_sys`，不使用 JNA（`E-14`）。
13. `JNIEnv` 是线程局部值。线程不能共享 `JNIEnv`（`E-15`、`E-16`）。
14. Rust panic 不得穿过非 unwinding ABI 边界（`E-17`）。
15. 当前 `covio-ffi` 使用 ABI `1`、原始指针句柄和 `C-unwind` callback（`E-18`）。
16. 当前 C header 是手写文件。header 的能力枚举少于 Rust 能力枚举（`E-19`）。
17. 当前 bridge 使用 `protocol_version`、request ID、generation、revision 和 deadline（`E-20`）。
18. 当前 Windows egui host 使用透明无边框置顶窗口、托盘、全局热键、单实例和顶部边缘触发（`E-21`）。
19. 当前设计合同要求 SF Pro。生成器只生成 Swift 和 Rust 常量（`E-22`）。
20. Apple SF 字体许可只允许在 Apple OS 应用中使用。许可禁止在非 Apple OS 使用和嵌入（`E-23`）。
21. Windows 官方字体是 Segoe UI Variable。Selawik 是 Segoe UI 的开放度量兼容字体（`E-24`）。
22. Windows desktop 发送 Share Sheet 可以使用 `IDataTransferManagerInterop`。此路径支持 packaged 和 unpackaged app（`E-25`）。
23. Windows unpackaged app 可以发送 toast。点击激活需要额外注册（`E-25`）。
24. Paseo 使用 AppState 检测可见性。Paseo client 使用重连退避、liveness 和发送队列（`E-26`）。
25. Android 新设备要求共享库满足 16 KB page-size 对齐（`E-27`）。

### 3.2 推论

1. Windows 可以运行 Compose Multiplatform。Windows 与 Android 可以共享 Kotlin Compose UI 源码。
2. 共享发生在源代码层。Windows 与 Android 不共享二进制 UI 产物。
3. Windows 产品需要 JVM。发布包必须自带 runtime。
4. 默认 UniFFI Kotlin 绑定不满足“Windows host 不依赖 JNA”的约束。
5. 自定义 JNI 可以避开 JNA。自定义 JNI 需要维护 Kotlin native 声明、JNI 符号、线程和错误映射。
6. 实验性 UniFFI JNI backend 可以避开 JNA。此 backend 还不能作为稳定生产依赖。
7. 事件队列比 Rust 回调 Java 或 Swift 更容易保证线程和 panic 安全。
8. 当前原始指针句柄不适合长期 ABI。整数句柄加 generation 更安全。
9. 当前手写 header 已出现漂移。header 必须生成并做漂移测试。
10. 当前设计合同不能在 Windows 上直接使用。字体和平台映射需要变更。
11. Windows Share Sheet 发送路径不要求 package identity。Windows Share Target 接收路径仍可能需要 package identity。
12. Compose Windows 的无障碍支持通过 Java Access Bridge。发布包必须包含 `jdk.accessibility` 模块。
13. egui 到 Compose 的迁移需要独立原型门槛。官方支持不证明产品性能、视觉和安装可用。

### 3.3 假设

1. Windows 首版只支持 x64。
2. Windows 内部测试接受 JVM 冷启动和内存开销。
3. 首版不需要 Windows Share Target。
4. Windows 可以接受未签名 MSI 的 SmartScreen 提示。
5. Apple 设计合同可以增加 Windows 字体覆盖。
6. Compose 透明窗口、托盘和顶部边缘触发可以复现当前 egui 体验。
7. 业务状态可以全部留在 Rust。Compose 只保存显示状态。
8. 大文件读取使用内容句柄或流。文件内容不进入 JSON。

## 4. 领域模型

| 对象 | 所有者 | 说明 |
| --- | --- | --- |
| UI session | UI host | 一次 UI 进程内的 bridge 会话 |
| Handle | Rust bridge | 访问 session 的稳定句柄。句柄带 generation |
| Request | UI host | 带 request ID、generation、deadline 和操作名 |
| Response | Rust bridge | 与 request ID 对应。不回传大文件内容 |
| Event | Rust bridge | 带 sequence 的单调事件 |
| Snapshot | Rust bridge | 可替换 UI 显示状态的完整快照 |
| Content lease | 平台 adapter | 文件或目录的 OS 访问句柄 |
| Capability | Rust core | 平台能力状态和错误语义 |
| Design contract | 设计系统 | 令牌、文案、语义、状态和平台覆盖 |

## 5. 约束模型

### 5.1 Compose 约束

1. Windows desktop 使用 JVM。
2. Android 使用 ART。Windows 与 Android 只共享源码。
3. 部分 Android API 只能在 `androidMain` 使用。
4. 权限、设备、文件和 IO 不在 Compose Multiplatform 的 common API 范围内。
5. Windows 打包必须在 Windows 上执行。Compose 打包不支持跨平台构建（`E-05`）。
6. Windows MSI 或 EXE 需要 WiX `3.0` 或更高版本（`E-07`）。
7. Windows package version 不接受 SemVer pre-release 后缀（`E-06`）。
8. Windows 无障碍需要 Java Access Bridge 和 `jdk.accessibility`（`E-09`）。

### 5.2 JNI 约束

1. `JNIEnv` 只能在当前线程使用。
2. Rust 线程访问 JVM 前必须 attach。
3. JNI 调用不应长时间占用 UI 线程。
4. JNI 本地引用需要及时释放。
5. JNI 异常必须在 native 边界内处理。
6. Android 16 KB page size 需要检查 `.so` 对齐（`E-27`）。

### 5.3 C ABI 约束

1. 不暴露 Rust `String`、`Vec`、trait object 或 Rust enum 布局。
2. 使用固定宽度整数、`#[repr(C)]` 结构和 opaque handle。
3. 调用方不能释放 Rust 分配的内存。释放函数必须属于同一库。
4. panic 不得跨过 `extern "C"`。
5. header 必须由 FFI 定义生成，或进行严格漂移检查。
6. `bool` 和 `size_t` 不作为长期稳定协议字段。使用 `u8` 和固定宽度整数。

### 5.4 设计约束

1. Apple UI 是视觉权威。
2. Windows 保留 Windows 平台字体、窗口控件和输入习惯。
3. SF Pro 不能用于 Windows 产品。
4. Compose 无法逐像素复制 Apple 材质和字体渲染。
5. 设计合同必须区分共享语义和平台覆盖。
6. 视觉验收必须包含亮色、深色、缩放、动效和无障碍。

## 6. 控制路径与信任边界

```text
UI input
  -> UI state
  -> bridge request
  -> protocol validation
  -> Rust core state machine
  -> platform adapter / file handle / network
  -> event or response
  -> UI display state
```

信任边界如下。
1. UI 输入不可信。bridge 必须验证长度、UTF-8、版本和字段。
2. 平台 adapter 返回的路径或句柄不可信。Rust 必须验证类型、权限和生命周期。
3. 文件内容不进入控制消息。文件内容只通过受控句柄或流读取。
4. 凭据值不进入 UI 快照、事件、错误消息或日志。
5. OS 错误转换为稳定的 Covio 错误。原始 OS 文本不直接显示。
6. 任何 panic 都在 native 边界内捕获。

## 7. 能力矩阵

| 能力 | Compose Windows | Compose Android | SwiftUI Apple | Rust 责任 | 证据 |
| --- | --- | --- | --- | --- | --- |
| 页面布局 | 可共享 `commonMain` | 可共享 `commonMain` | SwiftUI 独立 | 提供数据 | `E-01`、`E-03` |
| 设计令牌 | Kotlin 生成 | Kotlin 生成 | Swift 生成 | 读取共享动效令牌 | `E-22` |
| 文案 | Kotlin 生成 | Kotlin 生成 | Swift 生成 | 不拥有 UI 文案 | `E-22` |
| 语义和测试 ID | Compose semantics | Compose semantics | Swift accessibility | 定义业务状态 | `E-09`、`E-10` |
| 文件选择 | 平台 adapter | SAF adapter | document picker adapter | 保存内容租约 | `E-04` |
| Share Sheet | Windows adapter | Android Sharesheet | UIActivity | 生成分享意图 | `E-25` |
| 通知 | Windows adapter | NotificationManager | UNUserNotification | 生成通知意图 | `E-25` |
| 后台任务 | 进程与托盘 | WorkManager 或前台服务 | 系统后台能力 | 保存状态和恢复点 | `E-26` |
| C ABI | 不使用 | 不使用 | 使用 | 导出稳定 C ABI | `E-18` |
| JNI | 使用 | 使用 | 不使用 | 导出 JNI | `E-15`、`E-16` |
| UniFFI | 可选 | 可选 | 可选 | 生成绑定 | `E-13`、`E-14` |

## 8. 候选方案对比

| 方案 | 成本 | 风险 | 成熟度 | 可维护性 | 结论 |
| --- | --- | --- | --- | --- | --- |
| Compose Windows + Android | 中 | JVM 启动、内存、打包和视觉差异 | desktop 与 Android Stable | 共享 UI 收益高 | 推荐 |
| Compose Windows + egui 保留 | 低 | 无法共享 UI | 高 | 两套 UI | 不满足目标 |
| SwiftUI 全部平台 | 高 | Windows 无 Apple 原生实现 | 低 | 多套平台 UI | 不适配 Windows |
| C ABI only for Kotlin | 低 | JNA 或无类型绑定 | 中 | 维护成本高 | 仅作 Apple |
| 自定义 JNI | 中高 | 手动维护 JNI 符号和线程 | 中 | 可控制、无 JNA | 推荐给 Kotlin |
| 默认 UniFFI Kotlin | 低中 | 依赖 JNA、额外运行时 | 中高 | 生成代码易维护 | 不进入首版 Windows |
| 实验性 UniFFI JNI | 中 | 实验 API、版本漂移、工具链 | 低中 | 潜在收益高 | 只做受控试验 |
| Rust 回调 Java/Swift | 中高 | 线程 attach、重入和异常复杂 | 中 | 难测试 | 不作为默认路径 |
| 事件队列加 polling | 中 | 需要专用线程 | 高 | 边界清晰 | 推荐 |

## 9. 目标产品源码分析

### 9.1 `covio-bridge`

事实：
1. `PROTOCOL_VERSION` 为 `1`。
2. 控制消息最大 `1 MiB`。
3. 请求包含 request ID、generation、deadline 和 payload。
4. 响应包含 request ID、generation、revision 和 result。
5. 事件包含 generation、revision、event 和 payload。
6. 多个 envelope 使用 `deny_unknown_fields`。
7. 事件没有 sequence 字段。
8. 截止时间是 Unix milliseconds。

推论：
1. 当前协议可以承载小型控制消息。
2. 当前协议不适合直接承载大文件内容。
3. `deny_unknown_fields` 会阻碍同一 major 版本增加字段。
4. 事件需要 sequence，才能发现丢包和乱序。
5. 截止时间使用绝对时钟。跨语言和休眠恢复时容易产生时钟问题。

### 9.2 `covio-ffi`

事实：
1. `ABI_VERSION` 为 `1`。
2. 多个 API 使用 `*mut CovioAppHandle` 或 `*mut CovioEngineHandle`。
3. 两个 event callback 类型使用 `extern "C-unwind"`。
4. `ffi_guard` 使用 `catch_unwind`。
5. C header 是手写文件。
6. C header 的 `CovioCapability` 只到 `SECURE_STORAGE`。
7. Rust `CapabilityKind` 已扩展到 `FilePicker`。
8. Header 包含 `bool` 和 `size_t` 参数。

推论：
1. 当前原始指针句柄依赖调用方严格管理生命周期。
2. 当前 `C-unwind` callback 不适合作为长期跨语言合同。
3. 手写 header 已出现漂移。需要生成和 CI 检查。
4. 当前 ABI 不能直接满足 Windows Kotlin 的多线程和异步任务需求。
5. `bool` 和 `size_t` 应替换为固定宽度字段。

### 9.3 `covio-platform`

事实：
1. 现有 `CapabilityKind` 包含 filesystem、process、socket、notification、power、update、secure storage、clipboard、screenshot、startup 和 file picker。
2. 现有枚举不包含 Share Sheet、背景任务和 app lifecycle。
3. Windows 已有 file picker、clipboard、notification、startup 和 Credential Manager smoke。
4. macOS capability set 的 notification、file picker、clipboard 和 screenshot 仍为 unavailable。

推论：
1. 平台能力模型需要新增 Share Sheet、background task 和 lifecycle。
2. Windows 现有 adapter 可以作为迁移参考。
3. Apple 端 adapter 仍需独立接入。
4. 能力不可用必须返回 typed status。UI 不应把缺失能力当作内部错误。

### 9.4 Windows egui host

事实：
1. egui host 使用透明、无边框、无阴影、无任务栏和置顶窗口。
2. egui host 有托盘、全局热键、单实例和顶部边缘触发。
3. 当前 capability smoke 覆盖 Credential Manager、clipboard、startup、file picker、notification 和 update handoff。
4. 当前 host 通过 `eframe` 和 `wgpu` 渲染。

推论：
1. Compose host 必须复现这些窗口和生命周期行为。
2. Compose `Window` 支持透明、无边框、`alwaysOnTop` 和 `focusable`。
3. Compose 的托盘、任务栏隐藏、顶部边缘触发和 JAB 无障碍仍需原型验证。
4. 迁移不是只替换页面绘制。迁移包含窗口、托盘、安装、原生能力和性能。

### 9.5 设计合同

事实：
1. 当前设计合同 `schemaVersion` 为 `1.4.0`。
2. `metadata.fonts` 要求 SF Pro。`usage` 写为 `All Covio delivery pages`。
3. `platform/system/materials` 仍写 `egui drawable surfaces`。
4. `platform/system/accessibility` 仍写 `egui accessibility semantics`。
5. 生成器当前只生成 Swift 文案、Swift 令牌和 Rust 动效常量。
6. 生成器没有 Kotlin 输出。
7. 生成器支持 `--check`，但没有 Kotlin 漂移检查。

推论：
1. 当前设计合同不是 Windows 可执行合同。
2. Windows 使用 SF Pro 违反 Apple 字体许可。
3. Compose UI 无法从合同生成完整令牌。
4. 设计合同更新必须先于 Compose 视觉实现。
5. 主题研究不能修改合同。合同变更需要独立任务和生成器更新。

## 10. 参考实现分析：Paseo

Paseo 是跨设备 agent 客户端。Paseo 使用本地 daemon 和可选加密 relay。Paseo 不是 Covio 的文件传输实现。本主题只参考生命周期和重连模式。

观察：
1. Paseo 使用 React Native `AppState` 判断 app 是否 active。
2. Paseo client 的重连基础延迟为 `1500 ms`，最大延迟为 `30000 ms`。
3. Paseo client 使用 liveness heartbeat。间隔为 `10000 ms`，超时为 `15000 ms`。
4. Paseo client 在连接恢复后 restore server info，并 flush pending send queue。
5. Paseo 在 app 不可见时停止部分 UI 事件处理。

推论：
1. Covio 应显式传递 foreground 和 background 状态。
2. Covio 应在回到前台后重连。移动端不应承诺后台持续接收。
3. Covio 应保存待发送队列和恢复点。
4. Covio 应使用退避和 liveness。不能无限快速重试。

限制：
1. Paseo 使用 daemon 和 relay。Covio 首版是局域网直连。
2. Paseo 的协议不能直接复用到 Covio。
3. Paseo 源码只能证明客户端模式。它不证明 iOS 或 Android 的后台传输配额。

## 11. 反证和限制

1. Compose Multiplatform desktop 是 Stable。Stable 不代表 Windows 安装包、启动时间和内存满足 Covio 门槛。
2. Compose desktop 支持透明和置顶窗口。文档未证明 `taskbar=false` 与顶部边缘触发体验完全等价。
3. Windows Share Sheet 支持 unpackaged desktop app 发送。接收 Share Target 仍需要单独确认 package identity。
4. `IDataTransferManagerInterop` 需要窗口句柄。Compose 已暴露 `windowHandle`。仍需验证窗口生命周期和 HWND 有效性。
5. 默认 UniFFI Kotlin 依赖 JNA。实验性 JNI backend 可以避免 JNA，但实验性 backend 不能作为稳定承诺。
6. Windows 无障碍使用 Java Access Bridge。JAB 默认关闭。安装包和测试环境必须显式处理。
7. Apple 字体许可禁止 Windows 使用 SF Pro。当前设计合同与此冲突。
8. GitHub Releases 支持大于常见安装包的资产。官方限制不等于当前 package 小于限制。构建后必须记录实际大小。
9. Compose 测试 API 中，跨平台 API 仍标记 Experimental。视觉回归必须分层。
10. 当前环境中没有 Kotlin 或 Gradle。没有执行 Compose 构建。

## 12. 已知缺口

1. 未构建 Windows Compose host。
2. 未构建 Windows MSI 或便携 ZIP。
3. 未验证 `jpackage` 的 JRE 体积和冷启动。
4. 未验证 Rust DLL 在 MSI 安装目录中的加载路径。
5. 未验证 JAB、JAWS 和 NVDA。
6. 未验证 Compose `Window` 的任务栏隐藏、托盘和顶部边缘触发。
7. 未验证 Windows Share Sheet 的 Compose HWND。
8. 未验证 unpackaged toast 的点击激活。
9. 未验证实验性 UniFFI JNI backend 是否进入正式 release。
10. 未完成 Android 16 KB page-size 构建检查。
11. 未完成 iOS C ABI、静态库和 XCFramework 验证。
12. 未完成设计合同平台字体和语义扩展。
13. 未完成视觉基线、缩放矩阵和截图工具。
14. 未定义正式签名和公证流程。

## 13. 关联文档

- [主题索引](README.md)
- [上下文](context.md)
- [结论](conclusion.md)
- [方案](solution.md)
- [证据](evidence.md)
- [验证计划](validation/README.md)