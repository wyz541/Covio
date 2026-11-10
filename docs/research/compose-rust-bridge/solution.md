# Compose Multiplatform UI 与 Rust bridge：推荐方案

## 1. 文档状态

| 项目 | 内容 |
| --- | --- |
| 文档版本 | `1.0` |
| 状态 | 初稿，可评审 |
| 日期 | `2026-11-10` |
| 实施状态 | 尚未执行 |
| 回滚状态 | 可回滚到 egui 基线 |

本文件给出推荐架构、接口合同、设计合同、迁移阶段和验收门槛。
证据见 [evidence.md](evidence.md)。

## 2. 推荐架构

```text
macOS / iOS SwiftUI
  -> C ABI
  -> covio-ffi
  -> covio-bridge
  -> covio-core
  -> covio-platform

Windows / Android Compose
  -> JNI
  -> covio-jni
  -> covio-bridge
  -> covio-core
  -> covio-platform
```

### 2.1 UI host

| 平台 | UI | Runtime | Bridge |
| --- | --- | --- | --- |
| macOS | SwiftUI + AppKit | Native | C ABI |
| iOS | SwiftUI | Native | C ABI |
| Windows | Compose Multiplatform | JVM | JNI |
| Android | Compose Multiplatform | ART | JNI |

### 2.2 Rust core

`covio-core` 拥有业务规则、状态机、持久化、传输、错误和能力语义。
`covio-bridge` 拥有协议 envelope、限制、版本和验证。
`covio-ffi` 拥有 Apple C ABI 和 Swift 可导入 header。
`covio-jni` 拥有 Kotlin/JVM 和 Android JNI。
`covio-platform` 拥有 Windows 和 Apple OS adapter 接口。

### 2.3 UI 层不拥有业务状态

Compose 和 SwiftUI 只保存显示状态、输入状态、动画状态和平台生命周期状态。
UI 不复制传输状态机、冲突策略、校验逻辑、保留期限和权限策略。
UI 收到 snapshot 或 event 后更新显示状态。

## 3. 组件职责

| 组件 | 拥有 | 不拥有 |
| --- | --- | --- |
| Compose common UI | 页面、布局、设计组件、语义和显示状态 | 业务规则和持久化 |
| Compose desktop adapter | Windows 窗口、托盘、hotkey、HWND 和文件选择接入 | 传输状态机 |
| Compose Android adapter | Activity、SAF、Sharesheet、通知和后台任务 | Rust 业务规则 |
| SwiftUI host | Apple 页面、AppKit 接入、无障碍和 lifecycle | 业务规则 |
| `covio-ffi` | C ABI、header、句柄和错误转换 | UI 和平台界面 |
| `covio-jni` | JNI 符号、线程入口、句柄和错误转换 | UI 和平台界面 |
| `covio-bridge` | 协议版本、限制、请求、事件和取消 | UI toolkit |
| `covio-core` | 业务状态和状态机 | 窗口、绘制和 OS UI |
| `covio-platform` | OS capability 和 adapter 合同 | 业务持久化规则 |
| Design contract | 令牌、文案、语义、状态和平台覆盖 | 业务数据 |

## 4. 调用路径

### 4.1 Apple 调用路径

1. SwiftUI 创建 `CovioSession`。
2. Swift 调用 `covio_abi_info`。
3. Swift 调用 `covio_session_open`。
4. Rust 返回 `u64` session handle。
5. Swift 在专用队列调用 `covio_next_event`。
6. Swift 从事件队列读取事件。
7. Swift 调用 `covio_submit` 发起请求。
8. Swift 调用 `covio_cancel` 取消请求。
9. Swift 调用 `covio_session_close` 释放会话。

### 4.2 Kotlin 调用路径

1. Kotlin 从 Compose 资源目录加载 `covio_ffi.dll` 或 `libcovio_ffi.so`。
2. Kotlin 调用 `CovioNative.nativeAbiInfo`。
3. Kotlin 调用 `nativeOpenSession`。
4. Kotlin 在 `Dispatchers.IO` 专用线程调用 `nativeNextEvent`。
5. Kotlin 把事件转换为 `Flow<CovioEvent>`。
6. Kotlin 调用 `nativeSubmit` 发起请求。
7. Kotlin 调用 `nativeCancel` 取消请求。
8. Kotlin 调用 `nativeCloseSession` 释放会话。

### 4.3 UI 线程规则

1. UI 线程只做轻量调用。
2. `next_event` 只在专用线程执行。
3. 文件选择器和 Share Sheet 在 UI 线程执行。
4. 传输、校验和写盘在 Rust worker 执行。
5. UI 不等待文件内容通过 bridge 返回。
6. 关闭窗口时先停止新请求，再执行 graceful shutdown。

## 5. 建议文件位置

```text
docs/
  research/
    compose-rust-bridge/
rust/
  crates/
    covio-bridge/
    covio-core/
    covio-ffi/
    covio-jni/
    covio-platform/
  apps/
    covio-windows/          # 当前 egui 基线
ui/
  covio-compose/
    settings.gradle.kts
    build.gradle.kts
    composeApp/
      src/commonMain/
      src/desktopMain/
      src/androidMain/
      src/desktopTest/
      src/androidDeviceTest/
```

约束如下。
1. `ui/covio-compose` 不保存业务状态机。
2. `covio-jni` 不依赖 JNA。
3. `covio-ffi` 保留 Swift C ABI。
4. `covio-ffi` 和 `covio-jni` 使用同一 `covio-bridge`。
5. 现有 `covio-windows` egui host 在切换前保持可运行。

## 6. Bridge ABI 合同

### 6.1 ABI 信息

```c
typedef struct CovioAbiInfoV1 {
    uint32_t struct_size;
    uint16_t abi_major;
    uint16_t abi_minor;
    uint16_t protocol_major;
    uint16_t protocol_minor;
    uint64_t feature_bits;
    uint8_t build_id[16];
} CovioAbiInfoV1;
```

规则：
1. `struct_size` 用于检测 header 与库版本不一致。
2. `abi_major` 必须相同。`abi_minor` 可以高于客户端。
3. `protocol_major` 必须相同。`protocol_minor` 可以高于客户端。
4. `feature_bits` 声明能力。客户端不猜测能力。
5. `build_id` 只用于诊断。`build_id` 不包含敏感信息。

### 6.2 句柄

推荐使用 `u64` token。调用方不持有 Rust 原始指针。
句柄由 Rust session registry 管理。句柄包含 generation。
`0` 表示无效句柄。
关闭后的句柄返回 `invalid_handle`。句柄不得复用。
当前 `CovioAppHandle*` 和 `CovioEngineHandle*` 只保留兼容路径。

### 6.3 C ABI 函数

```c
uint32_t covio_abi_info(CovioAbiInfoV1 *out_info, CovioError *out_error);

uint32_t covio_session_open(
    const uint8_t *config_json,
    uint64_t config_len,
    uint64_t *out_handle,
    CovioError *out_error);

uint32_t covio_submit(
    uint64_t handle,
    const uint8_t *request_json,
    uint64_t request_len,
    CovioError *out_error);

uint32_t covio_cancel(
    uint64_t handle,
    const char *request_id,
    uint32_t reason,
    CovioError *out_error);

uint32_t covio_next_event(
    uint64_t handle,
    uint32_t timeout_ms,
    CovioOwnedBytes *out_event,
    CovioError *out_error);

uint32_t covio_shutdown(
    uint64_t handle,
    uint32_t mode,
    CovioError *out_error);

uint32_t covio_session_close(uint64_t handle);

void covio_owned_bytes_free(CovioOwnedBytes *bytes);
void covio_error_free(CovioError *error);
```

### 6.4 JNI 方法

```kotlin
package com.wyz.covio.bridge

internal object CovioNative {
    external fun nativeAbiInfo(): ByteArray
    external fun nativeOpenSession(configJson: ByteArray): Long
    external fun nativeSubmit(handle: Long, requestJson: ByteArray)
    external fun nativeCancel(handle: Long, requestId: String, reason: Int)
    external fun nativeNextEvent(handle: Long, timeoutMs: Int): ByteArray?
    external fun nativeShutdown(handle: Long, mode: Int)
    external fun nativeCloseSession(handle: Long)
}
```

规则：
1. JNI 方法名通过 `RegisterNatives` 注册。
2. Kotlin 包名和方法签名属于 ABI 合同。
3. JNI adapter 不保存 `JNIEnv`。
4. JNI adapter 不向 UI 线程回调。
5. JNI adapter 捕获 Rust panic。Kotlin 把状态码转换为 typed exception。

### 6.5 请求字段

```json
{
  "protocolMajor": 1,
  "protocolMinor": 0,
  "requestId": "01J...",
  "generation": 7,
  "timeoutMs": 30000,
  "op": "transfer.prepare",
  "payload": {}
}
```

字段规则：
1. `requestId` 在同一个 generation 内唯一。
2. `timeoutMs` 使用相对时间。避免系统时钟跳变。
3. `op` 使用点号分层。操作名保持稳定。
4. `payload` 有独立 schema。
5. 请求不做 base64 文件内容。
6. request body 上限初始为 `1 MiB`。

### 6.6 响应字段

```json
{
  "protocolMajor": 1,
  "protocolMinor": 0,
  "requestId": "01J...",
  "generation": 7,
  "status": "ok",
  "payload": {}
}
```

错误响应使用统一字段。

```json
{
  "protocolMajor": 1,
  "protocolMinor": 0,
  "requestId": "01J...",
  "generation": 7,
  "status": "error",
  "error": {
    "code": "permission_denied",
    "retryable": false,
    "userAction": "open_settings",
    "message": "文件访问权限不可用"
  }
}
```

### 6.7 事件字段

```json
{
  "protocolMajor": 1,
  "protocolMinor": 0,
  "generation": 7,
  "sequence": 42,
  "event": "transfer.progress",
  "payload": {}
}
```

规则：
1. `sequence` 在 generation 内单调递增。
2. 事件按 sequence 交付。
3. 终端事件不得丢弃。
4. 高频进度事件可以合并。
5. 队列溢出时发送 `snapshot_required`。
6. 控制事件上限初始为 `256 KiB`。

### 6.8 操作列表

| 操作 | 用途 |
| --- | --- |
| `app.snapshot` | 读取初始显示状态 |
| `lifecycle.foreground` | 报告前台状态 |
| `lifecycle.background` | 报告后台状态 |
| `pairing.start` | 启动二维码配对 |
| `pairing.complete` | 完成配对 |
| `device.snapshot` | 读取只读设备信息 |
| `transfer.prepare` | 创建传输任务 |
| `transfer.send` | 开始发送 |
| `transfer.accept` | 接收方接受任务 |
| `transfer.reject` | 接收方拒绝任务 |
| `transfer.resume` | 从校验点继续 |
| `transfer.cancel` | 取消任务 |
| `transfer.retry` | 重试可恢复错误 |
| `file_picker.open` | 请求文件选择 |
| `file_lease.close` | 释放内容租约 |
| `share.present` | 请求 native Share Sheet |
| `notification.post` | 请求 native 通知 |
| `background.acquire` | 请求后台执行租约 |
| `background.release` | 释放后台执行租约 |
| `diagnostics.snapshot` | 读取脱敏诊断状态 |

### 6.9 错误码

| 错误码 | 含义 | UI 动作 |
| --- | --- | --- |
| `invalid_handle` | 句柄过期或已关闭 | 重建 session |
| `invalid_argument` | 输入不合法 | 修正输入 |
| `invalid_utf8` | 文本不是 UTF-8 | 拒绝输入 |
| `payload_too_large` | 控制消息超过上限 | 改走句柄或流 |
| `protocol_version` | 协议不兼容 | 升级应用 |
| `stale_generation` | generation 过期 | 刷新快照 |
| `deadline_exceeded` | 请求超时 | 重试或取消 |
| `cancelled` | 用户取消 | 显示已取消 |
| `shutting_down` | session 正在关闭 | 等待退出 |
| `unsupported` | 能力不可用 | 显示限制 |
| `permission_denied` | 权限不足 | 打开系统设置 |
| `not_found` | 对象不存在 | 刷新状态 |
| `conflict` | 状态冲突 | 显示冲突 |
| `io` | 文件或网络失败 | 重试 |
| `backpressure` | 队列已满 | 稍后重试 |
| `internal` | 内部错误 | 重试或上报 |
| `internal_panic` | native 边界捕获 panic | 重建 session |

## 7. 线程、取消、错误和 panic 合同

### 7.1 线程

1. `submit` 只做验证和排队。`submit` 不执行长时间 I/O。
2. Rust worker 执行传输、校验、写盘和网络操作。
3. `next_event` 可以被一个专用线程阻塞等待。
4. UI 线程不调用 `next_event`。
5. JNI 调用每次从当前线程取得 `JNIEnv`。
6. Rust 不保存 JNI 本地引用。
7. Rust 不默认调用 Java 回调。
8. Swift 不默认接收 Rust callback。Swift 使用事件队列。

### 7.2 取消

1. UI 传 `requestId`。
2. Rust 在分块、网络和写盘边界检查取消标记。
3. 取消后返回 `cancelled`。
4. 取消不删除已完成的校验点。
5. UI 决定保留或删除临时文件。
6. 用户取消、超时和关闭使用不同取消原因。

### 7.3 错误

1. 错误使用稳定 code。
2. 错误带 `retryable`。
3. 错误带 `userAction`。
4. 错误消息不包含路径、凭据值或文件内容。
5. OS 错误映射为 Covio 错误。
6. UI 不解析 OS 错误文本。

### 7.4 Panic containment

1. 每个 C ABI 导出函数用 `catch_unwind` 包裹。
2. 每个 JNI 导出函数用 `catch_unwind` 包裹。
3. panic 转换为 `internal_panic`。
4. panic 不跨过 `extern "C"`。
5. 不使用 `C-unwind` callback 作为默认合同。
6. session 状态损坏时拒绝后续请求。UI 重建 session。
7. panic 日志只写脱敏信息。

### 7.5 Backpressure

1. 事件队列有上限。
2. 进度事件按 transfer 合并。
3. 终端事件不丢弃。
4. 队列满时保留最新快照和终端事件。
5. UI 收到 `snapshot_required` 后重新读取快照。
6. 请求并发数有上限。超限返回 `backpressure`。

## 8. 版本合同

1. ABI 使用 major/minor。major 不兼容。minor 向后兼容。
2. 协议使用 major/minor。major 不兼容。minor 可增加可选字段。
3. 同一 major 内忽略未知字段。
4. 删除字段必须提升 major。
5. 枚举新增值必须提升 minor。
6. 客户端把未知错误码显示为 `internal`。
7. Header、Kotlin DTO、Swift DTO 和 Rust DTO 由同一 schema 生成。
8. 生成物进入 CI 漂移检查。
9. `covio-ffi` 和 `covio-jni` 使用同一协议 fixture。
10. 当前 `deny_unknown_fields` 只用于必须严格校验的内部结构。可演进 envelope 不使用此属性。

## 9. UniFFI 决策

### 9.1 默认 UniFFI Kotlin 后端

默认 Kotlin 后端使用 JNA。官方文档要求 JNA `5.12.0` 或更高版本（`E-13`）。
Windows 首版需要避免 JNA。
默认推荐不采用。

### 9.2 实验性 UniFFI JNI 后端

主分支 `uniffi-bindgen-kotlin-jni` 使用 `jni_sys`，不依赖 JNA（`E-14`）。
此 backend 是实验性能力。它不是稳定发布承诺。
可以建立隔离试验。试验不得进入默认产品路径。
试验门槛如下。
1. 选择固定 commit 和固定 crate 版本。
2. 生成 Kotlin binding。
3. 验证 Windows x64 和 Android ABI。
4. 验证对象生命周期和 GC。
5. 验证取消、错误和异步调用。
6. 验证 panic containment。
7. 验证无 JNA 依赖。
8. 验证 ABI 升级策略。
9. 验证生成物可审计。
10. 验证失败后可以删除试验。

### 9.3 推荐结论

首版使用自定义 JNI。
UniFFI 只做受控试验。
如果实验性 JNI backend 达到稳定发布、可审计和可回滚条件，再建立新 ADR。
在 ADR 更新前，不把 UniFFI 写成首版运行时依赖。

## 10. 共享设计合同

### 10.1 共享内容

1. 设计令牌：颜色、间距、圆角、描边、动效和状态。
2. 文案：英文和简体中文。
3. 语义：角色、标签、状态和提示。
4. 测试 ID：Compose 与 SwiftUI 自动化共用稳定 ID。
5. 交互状态：正常、hover、pressed、focus、disabled 和 error。
6. 平台覆盖：字体、材质、窗口控件和系统权限。

### 10.2 不共享内容

1. SwiftUI 视图树和 Compose composable 不互相导入。
2. AppKit 和 Win32 窗口实现不共享。
3. 系统 share sheet、文件选择器和通知 UI 不共享。
4. Apple Liquid Glass 与 Windows 材质不承诺逐像素相同。
5. 业务状态机不进入设计合同。

### 10.3 平台字体映射

| 平台 | 字体 | 来源 | 约束 |
| --- | --- | --- | --- |
| macOS | SF Pro | Apple 系统字体 | 不打包到 Windows |
| iOS | SF Pro | Apple 系统字体 | 不打包到 Windows |
| Windows | Segoe UI Variable | Windows 系统字体 | 使用系统回退 |
| Android | 系统 sans-serif | Android 系统 | 后续验证 |

SF Pro 只用于 Apple 平台。Windows 不使用 Apple 字体文件。
Windows 可以使用 Selawik 作为开放度量兼容回退。Selawik 不能冒充 SF Pro。
设计合同必须声明 `fontFamily` 的平台覆盖。`metadata.fonts` 不能继续写“所有页面使用 SF Pro”。

### 10.4 视觉对齐层级

| 层级 | 标准 | 验收 |
| --- | --- | --- |
| L1 令牌 | 值完全一致 | 自动生成和比较 |
| L2 布局 | 关键锚点误差不超过 `2 dp` | 截图和边界检查 |
| L3 文字 | 字号、字重、层级和换行可读 | 设计评审 |
| L4 材质 | 允许平台等价实现 | 设计合同记录差异 |
| L5 系统控件 | 使用平台原生控件 | 不伪造 Apple 控件 |
| L6 无障碍 | 角色、标签、状态和顺序一致 | JAWS、NVDA、Accessibility Inspector |

Compose 视觉验收不能只比较截图像素。字体渲染、抗锯齿和系统材质会产生合法差异。
Apple 设计是权威源。Windows 视觉必须保留 Apple 的层级、节奏、文案和状态。Windows 原生字体、窗口按钮和输入习惯必须保留。

### 10.5 生成器要求

1. 设计合同是唯一来源。
2. 生成 Swift 文案、Swift 令牌、Rust 动效、Kotlin 文案和 Kotlin 令牌。
3. 生成物带固定 header。禁止手改。
4. `--check` 覆盖全部生成物。
5. CI 拒绝过期生成物。
6. 合同新增 `semantics` 段。
7. 合同新增 `platformOverrides` 段。
8. 合同新增 `acceptanceIds` 段。
9. 合同新增 `knownDifferences` 记录。
10. 设计合同变更后重跑生成器。

### 10.6 视觉测试矩阵

1. 亮色和深色。
2. Windows 缩放 `100%`、`125%`、`150%`、`200%`。
3. 窗口最小尺寸、默认尺寸和最大尺寸。
4. 英文和简体中文。
5. 长文件名、长设备名和长错误消息。
6. 键盘焦点顺序。
7. 减少动效模式。
8. 高对比度和系统主题。
9. hover、pressed、focus、disabled 和 error 状态。
10. 至少六个代表页面：首页、文件、设备、配对、传输、设置。

截图基线按平台保存。Windows 基线与 Apple 参考图分开保存。
视觉差异必须记录为设计合同中的平台差异。未记录差异视为失败。

## 11. 平台能力模型

### 11.1 能力枚举

现有 `CapabilityKind` 需要新增以下值。
1. `ShareSheet`
2. `BackgroundTask`
3. `AppLifecycle`
4. `NotificationActivation`

### 11.2 内容租约

文件选择结果使用内容租约。内容租约不包含文件内容。
内容租约包含以下字段。
1. `leaseId`
2. `kind`：file、directory、stream
3. `displayName`
4. `size`
5. `readable`
6. `writable`
7. `expiresAt`
8. `platformToken`：只在平台 adapter 内使用

平台 adapter 打开文件。Rust 读取文件。UI 不读取原始路径。
Apple 平台维持 security-scoped access。Android 维持 content URI 权限。
Windows 使用文件对话框返回的路径或 Win32 句柄。Rust 验证句柄和权限。

### 11.3 Windows adapter

1. 文件选择器：Rust adapter 或 JVM adapter 调用 Win32 文件对话框。
2. Share Sheet：使用 `ComposeWindow.windowHandle` 取得 HWND，再调用 `IDataTransferManagerInterop`。
3. 通知：使用 Windows App SDK 或现有 toast adapter。unpackaged app 需要 AUMID 和 shortcut。
4. 后台任务：窗口隐藏时保持进程和 tray worker。进程退出后保存恢复日志。
5. 无障碍：启用 Java Access Bridge，打包 `jdk.accessibility`。
6. 单实例：使用命名 mutex 或现有 single-instance 能力。
7. 顶部边缘触发：由 Windows adapter 监控。UI 只接收显示或隐藏事件。

### 11.4 Apple adapter

1. 文件选择器：Swift 调用 document picker。Swift 维持 security scope。
2. Share Sheet：Swift 调用 `UIActivityViewController` 或 `ShareLink`。
3. 通知：Swift 调用 `UNUserNotificationCenter`。
4. 后台任务：Swift 报告 foreground 和 background。Rust 暂停新接收并保存恢复点。
5. 无障碍：SwiftUI 使用 accessibility label、trait 和 focus order。

### 11.5 Android adapter

1. 文件选择器：Kotlin 使用 Storage Access Framework。
2. Share Sheet：Kotlin 使用 Android Sharesheet。
3. 通知：Kotlin 使用 NotificationManager。
4. 后台任务：Kotlin 使用 WorkManager 或前台服务。首版 Android 后置。
5. JNI 库：放入 `jniLibs/<abi>/libcovio_ffi.so`。
6. 16 KB page size：构建后检查 LOAD 和 RELRO 对齐（`E-27`）。

## 12. 文件与传输边界

1. 文件内容不进入普通 JSON 控制消息。
2. 大文件使用内容租约、文件描述符或 Rust 流。
3. 文件夹使用目录清单和逐项租约。目录内容不一次性读入内存。
4. 传输事件只包含 offset、size、rate、state 和 error。
5. 进度事件按频率合并。建议每 `100 ms` 最多一次。
6. 校验和由 Rust 计算。UI 只显示状态。
7. 冲突策略由 Rust 决定。UI 只显示选项和结果。
8. 保留期限由 Rust 政策决定。UI 显示剩余时间。
9. 断点续传使用持久化恢复点。恢复点包含摘要、已完成区间和临时文件位置。
10. 写入采用临时文件、校验和原子 rename。
11. 失败保留临时文件和恢复元数据。用户可重试或删除。
12. 日志不写文件内容、完整路径或凭据值。

## 13. 移动端后台降级

### 13.1 进入后台

1. UI host 调用 `lifecycle.background`。
2. Rust 停止接受新的接收任务。
3. Rust 保存当前传输校验点。
4. Rust 关闭可重新建立的连接。
5. Rust 发送暂停状态或等待对端超时。
6. UI 显示“回到前台后继续”。

### 13.2 回到前台

1. UI host 调用 `lifecycle.foreground`。
2. Rust 重连已配对设备。
3. Rust 交换任务 ID 和已完成区间。
4. Rust 从最后校验点续传。
5. UI 重新读取 snapshot。
6. UI 显示恢复结果。

### 13.3 重连策略

参考 Paseo 的模式，但不复用 Paseo 协议。
1. 初始重连退避 `1.5 s`。
2. 指数退避。
3. 最大退避 `30 s`。
4. liveness 间隔 `10 s`。
5. liveness 超时 `15 s`。
6. 连续失败达到阈值后暂停自动重试。UI 显示手动重试。
7. 连接恢复后刷新 snapshot。
8. 连接恢复后执行待发送队列。

### 13.4 后台限制

1. iOS 不承诺后台持续接收。
2. Android 不承诺长期前台服务。
3. 应用被杀后只从持久化恢复点继续。
4. OS 拒绝后台能力时返回 `unsupported` 或 `permission_denied`。
5. UI 不把“已暂停”显示成“已完成”。

## 14. Windows 迁移计划

### Phase 0：基线与合同

1. 冻结 egui 构建。
2. 记录冷启动、内存、CPU、包大小和无障碍基线。
3. 记录当前页面清单。
4. 记录当前窗口、托盘、hotkey 和顶部边缘行为。
5. 更新设计合同研究项。
6. 建立 bridge fixture。

退出条件：
1. 基线数据完整。
2. 回滚包可安装。
3. 当前数据格式有 fixture。
4. 设计差异表可评审。

### Phase 1：最小 vertical slice

1. 建立 `ui/covio-compose`。
2. 建立 Windows desktop target。
3. 加载 Rust 动态库。
4. 调用 ABI info。
5. 打开 session。
6. 显示一个真实页面。
7. 读取一个 snapshot。
8. 关闭 session。

退出条件：
1. 干净 Windows 11 x64 机器可启动。
2. Rust DLL 自动加载。
3. 无 JNA。
4. 无手工 DLL 复制。
5. 关闭流程无挂起。

### Phase 2：bridge 一致性

1. 建立 C ABI fixture。
2. 建立 JNI fixture。
3. 验证同一请求产生同一响应。
4. 验证同一错误产生同一 code。
5. 验证取消。
6. 验证超时。
7. 验证 stale generation。
8. 验证 invalid handle。
9. 验证 panic containment。
10. 验证事件 sequence。
11. 验证 backpressure。

退出条件：
1. C ABI 与 JNI 通过同一套 fixture。
2. panic 不终止进程。
3. 取消后恢复点可读。
4. 旧 generation 被拒绝。
5. 事件无乱序。

### Phase 3：设计与页面

1. 生成 Kotlin 令牌和文案。
2. 建立 Compose 基础组件。
3. 建立六个代表页面。
4. 建立 semantics 和 test ID。
5. 建立亮色和深色主题。
6. 建立缩放矩阵。
7. 建立截图基线。
8. 建立减少动效模式。

退出条件：
1. 令牌与合同一致。
2. 文案与合同一致。
3. 关键布局误差不超过 `2 dp`。
4. 设计负责人批准平台差异。
5. 未记录差异为零。

### Phase 4：平台能力

1. 文件选择器。
2. Share Sheet。
3. 通知。
4. 托盘。
5. 全局热键。
6. 单实例。
7. 顶部边缘触发。
8. 后台隐藏和恢复。
9. 取消和恢复传输。
10. 文件写入与校验。

退出条件：
1. 所有能力有 typed status。
2. 用户取消不报内部错误。
3. 通知点击可回到正确页面。
4. 托盘和 hotkey 可用。
5. Share Sheet 可从 Compose 窗口打开。
6. 文件选择结果可被 Rust 读取。

### Phase 5：分发

1. 在 Windows CI 构建 MSI。
2. 构建便携 ZIP。
3. 生成 `.sha256`。
4. 创建 GitHub pre-release。
5. 上传 MSI、ZIP 和校验和。
6. 执行 clean install。
7. 执行 upgrade。
8. 执行 uninstall。
9. 执行 rollback 安装。

退出条件：
1. MSI 可在干净机器安装。
2. 安装后自动加载 Rust DLL。
3. ZIP 可运行。
4. 校验和可验证。
5. Release 资产小于 `2 GiB`。
6. 回滚包可用。

### Phase 6：Cutover

1. 连续两个内部版本通过验收。
2. 无 P0 和 P1 问题。
3. 文件传输无数据损坏。
4. 无障碍通过。
5. 视觉通过。
6. 性能通过。
7. 回滚演练通过。
8. 关闭 Compose feature flag 的默认值。
9. 保留 egui 构建一个内部版本周期。
10. 再决定删除 egui。

退出条件：
1. Compose 默认 UI 通过全部验收。
2. egui 回滚仍可用。
3. 用户数据兼容。
4. 发布说明写明内部测试状态。

## 15. 原型门槛

以下门槛是初始值。Phase 0 必须用 egui 实测基线校准。
未校准前，数值标记为假设。

| 门槛 | 初始值 | 状态 |
| --- | --- | --- |
| 冷启动 P95 | `<= 3.0 s` | 待校准 |
| 空闲工作集 | `<= 250 MiB` | 待校准 |
| UI 帧时间 P95 | `<= 16.7 ms` | 待校准 |
| 输入到画面 P95 | `<= 100 ms` | 待校准 |
| MSI 大小 | `<= 200 MiB` | 待校准 |
| 安装后大小 | `<= 400 MiB` | 待校准 |
| 30 分钟传输 soak | 无崩溃、无损坏 | 尚未执行 |
| 50 次窗口开合 | 无挂起、无泄漏增长 | 尚未执行 |
| 缩放 | `100%`、`125%`、`150%`、`200%` | 尚未执行 |
| 主题 | 亮色、深色、高对比度 | 尚未执行 |
| 无障碍 | JAWS 或 NVDA 可操作 | 尚未执行 |
| 视觉 | 设计负责人批准 | 尚未执行 |
| 发布 | clean install、upgrade、uninstall | 尚未执行 |

任一硬门槛失败，停止 cutover。

## 16. 风险

| 风险 | 影响 | 缓解 |
| --- | --- | --- |
| JVM 冷启动慢 | 用户感知差 | 基线测量；优化启动；保留回滚 |
| JVM 内存高 | 桌面常驻成本高 | 空闲内存门槛；模块裁剪 |
| MSI 体积大 | GitHub 下载慢 | `jlink`；压缩；资产测量 |
| JAB 无障碍回归 | 键盘和读屏用户受阻 | 打包 `jdk.accessibility`；真机验 |
| Compose 透明窗口异常 | 顶部边缘体验回归 | vertical slice 先验 |
| 任务栏隐藏不可用 | 窗口行为变化 | 改用 native window adapter |
| Share Sheet HWND 失效 | 分享面板不可用 | 窗口生命周期测试 |
| toast 点击激活失败 | 通知不可操作 | AUMID 和 shortcut 测试 |
| 设计合同字体冲突 | 法务和视觉风险 | 平台字体覆盖 |
| 视觉漂移 | 品牌不一致 | 生成令牌和截图验收 |
| XML 或配置损坏 | 数据损坏风险 | 原子写、备份、回滚 |
| JNI panic | 进程崩溃 | 全入口 `catch_unwind` |
| JNI 版本漂移 | 运行时加载失败 | 固定 ABI 和 CI smoke |
| Android 16 KB 对齐 | 新设备崩溃 | `.so` 检查 |
| GitHub Release 限制 | 发布失败 | 单资产小于 `2 GiB`；校验 |
| 未签名安装包 | SmartScreen 提示 | 内测说明；正式阶段签名 |

## 17. 回滚条件

出现任一条，停止 Compose cutover。
1. 发生数据损坏或不可恢复的传输失败。
2. MSI 在干净机器无法安装。
3. 安装后无法加载 Rust DLL。
4. Share Sheet 不可用。
5. 文件选择器不可用。
6. 托盘或隐藏窗口不可用。
7. JAWS 或 NVDA 出现阻断问题。
8. 冷启动超过基线两倍。
9. 空闲内存超过硬门槛两倍。
10. 视觉验收未通过。
11. Rust panic 穿过 FFI 边界。
12. Stale handle 导致崩溃。
13. 文件内容进入控制消息。
14. 用户数据格式不能向后读取。
15. 发布包大于 GitHub 资产限制。
16. 无法执行旧版本安装。

回滚步骤：
1. 停止上传新的 Compose 默认构建。
2. 恢复最后一个 egui 构建为默认。
3. 保留新数据文件。
4. 保留失败构建和日志。
5. 记录失败条件和证据。
6. 建立修复 Issue。
7. 重新执行 Phase 1 或 Phase 2。

## 18. 验收标准

### 18.1 Bridge 验收

1. C ABI header 可编译。
2. JNI 库可在 Windows 加载。
3. ABI major 和 protocol major 匹配。
4. stale generation 被拒绝。
5. invalid handle 被拒绝。
6. request ID 可取消。
7. deadline 可触发。
8. panic 返回 typed error。
9. 事件 sequence 单调。
10. 大文件不进入 JSON。
11. 错误消息不含敏感值。
12. C ABI 与 JNI fixture 一致。

### 18.2 UI 验收

1. 六个代表页面可用。
2. 设计令牌和文案一致。
3. 亮色和深色可用。
4. 缩放可用。
5. 键盘焦点顺序正确。
6. Share Sheet 可用。
7. 文件选择器可用。
8. 通知可操作。
9. 托盘和 hotkey 可用。
10. 顶部边缘触发可用。
11. 减少动效可用。
12. 无未记录平台差异。

### 18.3 性能验收

1. 冷启动和空闲内存达到校准门槛。
2. 帧时间和输入延迟达到校准门槛。
3. 10 GB 文件传输不崩溃。
4. 10000 个小文件传输不崩溃。
5. 30 分钟 soak 无崩溃。
6. 50 次开合无持续泄漏。

### 18.4 分发验收

1. MSI clean install 通过。
2. 便携 ZIP 启动通过。
3. upgrade 通过。
4. uninstall 通过。
5. rollback 安装通过。
6. SHA-256 通过。
7. GitHub Release pre-release 可下载。
8. 资产小于 `2 GiB`。
9. 内部测试说明完整。
10. 无正式更新器依赖。

## 19. 实施计划

| 阶段 | 工作 | 产出 |
| --- | --- | --- |
| 1 | 建立 bridge fixture 和 schema | 单一协议 |
| 2 | 新增 `covio-jni` | Kotlin 调用 Rust |
| 3 | 修订 C ABI | Apple 稳定边界 |
| 4 | 建立 Compose vertical slice | Windows 可启动 |
| 5 | 生成 Kotlin 设计令牌 | 视觉基础 |
| 6 | 建立代表页面 | UI 复用验证 |
| 7 | 接入 Windows 能力 | Share、通知、文件 |
| 8 | 建立安装包 | MSI 和 ZIP |
| 9 | 执行验证 | 证据和门槛 |
| 10 | 决定 cutover | 默认 UI |

## 20. 产品化条件

1. 设计合同完成平台字体和语义扩展。
2. Windows x64 原型通过门槛。
3. Android 目标另行建立 Feature。
4. iOS C ABI 另行建立 Task。
5. 正式签名另行建立 ADR。
6. 正式更新器另行建立 ADR。
7. 文件传输协议完成独立研究。
8. 凭据存储合同完成独立研究。
9. Windows Share Target 另行确认。
10. 未验证项全部关闭。

## 21. 关联文档

- [主题索引](README.md)
- [上下文](context.md)
- [调研分析](investigation.md)
- [结论](conclusion.md)
- [证据](evidence.md)
- [验证计划](validation/README.md)
- [案例](validation/case-windows-compose-jni.md)