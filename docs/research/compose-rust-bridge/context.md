# Compose Multiplatform UI 与 Rust bridge：上下文与边界

## 1. 文档状态

| 项目 | 内容 |
| --- | --- |
| 文档版本 | `1.0` |
| 状态 | 初稿，可评审 |
| 日期 | `2026-11-10` |
| 主题 | Windows Compose host、跨平台 UI 边界和 Rust bridge |
| 验证状态 | 尚未执行 |

本文件定义问题、范围、角色、系统模型和成功标准。
结论见 [conclusion.md](conclusion.md)。证据见 [evidence.md](evidence.md)。

## 2. 问题类别

问题类别是跨平台 UI 与原生核心的边界设计。问题涉及四个决策。
1. Windows 与 Android 可以共享哪些 Compose UI。
2. Kotlin/JVM 如何安全调用 Rust。
3. SwiftUI 与 Compose 如何共享设计合同。
4. Windows egui 如何迁移到 Compose Multiplatform。

## 3. 研究问题

1. Compose Multiplatform 是否正式支持 Windows desktop 与 Android。
2. Compose desktop 是否使用 JVM。Windows 分发如何打包 JVM。
3. Windows 安装包如何通过 GitHub Releases 分发。
4. C ABI、JNI 和 UniFFI 各自负责什么。
5. 默认 UniFFI Kotlin 绑定是否依赖 JNA。
6. 自定义 JNI 是否可替代默认 UniFFI Kotlin 绑定。
7. bridge 如何处理线程、取消、错误、panic、句柄和版本。
8. Compose 与 SwiftUI 可以共享哪些 UI 内容和语义。
9. Compose 如何对齐 Apple 设计，同时遵守 Windows 平台规则。
10. Windows egui 替换的阶段性门槛、风险和回滚条件是什么。

## 4. 问题定义

Covio 需要一套 UI 技术方案。macOS 与 iOS 保留 SwiftUI。Windows 与后续 Android 共享 Compose UI。
Rust 拥有业务状态、传输状态机、持久化、能力和错误语义。UI 只保存显示状态、输入状态和平台生命周期状态。
bridge 必须提供稳定协议。bridge 不允许复制业务规则。

## 5. 触发条件

以下任一条件出现时，本主题需要重新评审。
1. Compose Multiplatform 不再把 desktop 或 Android 标为 Stable。
2. Windows desktop 不再支持 JVM。
3. GitHub Releases 的资产限制变化。
4. JNI 或 C ABI 的版本合同变化。
5. UniFFI 默认 Kotlin 后端移除 JNA。
6. Apple 字体许可或系统字体规则变化。
7. Windows Share Sheet 或通知 API 改变身份要求。
8. egui 基线无法保持回滚。

## 6. 问题分类表

| 类别 | 问题 | 影响 |
| --- | --- | --- |
| UI 共享 | Compose commonMain 的边界 | Windows 与 Android 的复用率 |
| UI 原生 | SwiftUI 与 Compose 的差异 | Apple 体验和设计一致性 |
| 运行时 | Windows JVM 与打包 | 启动、内存、体积和安装 |
| bridge | C ABI、JNI、UniFFI 职责 | 稳定性、性能和可维护性 |
| 生命周期 | 后台、取消、恢复 | 传输可靠性 |
| 设计 | 字体、材质、语义 | 视觉与可访问性 |
| 分发 | GitHub Releases 与 MSI | 内部测试可达性 |
| 回滚 | egui 保留周期 | 交付风险 |

## 7. 适用范围

1. Windows Compose host 的技术可行性。
2. Windows 与 Android 的 Compose UI 共享边界。
3. macOS 与 iOS 的 C ABI 边界。
4. Kotlin/JVM 与 Android 的 JNI 边界。
5. UniFFI 的职责评估。
6. 设计合同的生成和视觉验收。
7. Windows egui 的分阶段迁移。
8. 内部测试包的 GitHub Releases 分发。

## 8. 范围外事项

1. 正式商店发布。
2. 正式更新器。
3. 正式代码签名和公证。
4. iOS 产品工程的完整实现。
5. Android 第一版交付。
6. 文件传输协议、加密握手和 relay 的完整设计。
7. Keychain、Credential Manager 和 Keystore 的完整合同。
8. 云账号和云内容存储。
9. 具体视觉稿的最终设计批准。

## 9. 受影响角色

| 角色 | 关注点 |
| --- | --- |
| 用户 | 启动、操作、视觉、可访问性和传输状态 |
| Windows UI 研发 | Compose、JVM、窗口、托盘和原生接入 |
| Apple UI 研发 | SwiftUI、C ABI、Apple 设计和无障碍 |
| Rust core 研发 | 状态机、持久化、取消、错误和能力模型 |
| 设计 | Apple 权威、Compose 对齐和平台差异 |
| 测试 | JNI、ABI、安装包、视觉、无障碍和回滚 |
| 安全 | FFI 边界、权限、凭据、日志和文件句柄 |
| 发布 | MSI、ZIP、GitHub Release 和校验和 |

## 10. 系统模型

```text
SwiftUI macOS / iOS
  -> C ABI
  -> Rust bridge
  -> Rust core
  -> platform adapters
  -> OS APIs

Compose Windows / Android
  -> JNI
  -> Rust bridge
  -> Rust core
  -> platform adapters
  -> OS APIs

Apple UI + Compose UI
  -> shared design contract
  -> generated tokens, copy, semantics and test IDs
```

Rust bridge 是跨语言边界。Rust core 是业务状态所有者。
UI host 拥有窗口、绘制、输入和 UI 生命周期。平台 adapter 拥有文件选择、share sheet、通知、后台授权和 OS 权限。
设计合同拥有视觉令牌、文案、语义、状态和平台覆盖。

## 11. 状态矩阵

| 状态 | 触发 | UI 行为 | Rust 行为 | 恢复条件 |
| --- | --- | --- | --- | --- |
| `ready` | 启动完成 | 显示快照 | 接收请求 | 无 |
| `request_pending` | 提交请求 | 显示进行中 | 跟踪 request ID | 收到响应或事件 |
| `cancelled` | 用户取消 | 显示已取消 | 释放任务资源 | 用户重试 |
| `deadline_exceeded` | 超时 | 显示超时原因 | 返回 typed error | 用户重试或改设置 |
| `background_paused` | 移动端进入后台 | 显示暂停 | 保存恢复点 | 回到前台 |
| `foreground_resume` | 移动端回到前台 | 显示恢复中 | 重连并续传 | 网络可用 |
| `stale_generation` | 旧 UI 会话调用 | 要求刷新快照 | 拒绝请求 | 新建 generation |
| `invalid_handle` | 旧句柄调用 | 关闭旧 UI 状态 | 拒绝请求 | 重新打开 session |
| `version_mismatch` | ABI 或协议不兼容 | 显示升级提示 | 拒绝 session | 使用匹配版本 |
| `panic_contained` | Rust panic | 显示内部错误 | 返回 `internal_panic` | 重建 session |
| `shutting_down` | 应用关闭 | 显示关闭中 | 停止接收新任务 | 进程退出 |
| `degraded` | 能力不可用 | 显示能力限制 | 返回 `unsupported` 或 `permission_denied` | 修复权限或环境 |

## 12. 场景定义

### 场景 A：Windows Compose 启动

1. 用户启动安装后的 Covio。
2. Java 启动器加载 Compose UI。
3. Kotlin adapter 加载 Rust 动态库。
4. bridge 返回 ABI 信息和 session 句柄。
5. UI 读取初始快照。
6. UI 在专用线程读取事件。

### 场景 B：文件选择

1. 用户在 Compose UI 选择文件。
2. 平台 adapter 打开 Windows 文件选择器。
3. adapter 返回内容句柄和权限状态。
4. Rust 建立传输源。
5. 文件内容不进入普通 bridge JSON。

### 场景 C：分享面板

1. UI 把 Compose 窗口句柄传给 Windows adapter。
2. adapter 调用 `IDataTransferManagerInterop`。
3. adapter 显示 Windows Share Sheet。
4. adapter 返回成功、取消或权限错误。

### 场景 D：移动端进入后台

1. UI host 发送前台状态变化。
2. Rust 把接收任务改为暂停状态。
3. Rust 保存校验点和恢复信息。
4. 对端收到暂停语义或超时。
5. UI 回到前台后请求恢复。
6. Rust 重连并从校验点续传。

### 场景 E：Windows 回滚

1. Compose 构建未通过门槛。
2. 发布者保留 egui 构建。
3. 用户安装 egui 构建。
4. 两种构建读取相同数据格式。
5. 回滚不删除新文件。

## 13. 成功标准

1. Windows Compose host 可以加载 Rust 动态库。
2. Kotlin 不依赖 JNA 调用 Rust core。
3. C ABI 与 JNI 使用同一协议版本。
4. 句柄、取消、deadline、错误和 panic 行为可测试。
5. 文件内容不通过控制消息传输。
6. Compose 与 SwiftUI 使用同一设计合同。
7. Windows 使用平台允许的字体。
8. Share Sheet、文件选择、通知和托盘流程可用。
9. Windows 安装包可从 GitHub Releases 安装。
10. egui 回滚路径可执行。
11. 未验证项明确标记。
12. 验证失败时停止切换默认 UI。

## 14. 关键假设

1. 第一版 Windows 目标为 x64。arm64 另行确认。
2. Windows 内部测试接受 JVM 运行时。
3. 用户接受未签名安装包的 SmartScreen 提示。
4. 第一版不要求 Windows Share Target。
5. Android 复用 Compose UI，不复用 Rust 业务状态副本。
6. 设计合同可以增加平台字体覆盖。
7. iOS 后台接收仍遵守暂停与前台恢复模型。

## 15. 关联文档

- [主题索引](README.md)
- [调研分析](investigation.md)
- [结论](conclusion.md)
- [方案](solution.md)
- [证据](evidence.md)
- [验证计划](validation/README.md)