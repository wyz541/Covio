# Covio 跨平台目标架构

- 状态：accepted target architecture
- 日期：2026-11-10
- 决策：[ADR-0035](../adr/adr-0035-cross-platform-product-scope.md)

## 1. 结论

Covio 是独立跨平台产品。
第一版支持 macOS、Windows 和 iOS。
Android 在第一版之后进入。
Rust core 拥有共享业务逻辑。
SwiftUI 与 Compose 只拥有平台 UI、输入和平台接入。

## 2. 平台矩阵

| 平台 | 当前状态 | 目标 UI | Rust bridge | 凭据存储 |
| --- | --- | --- | --- | --- |
| macOS | 已交付 | SwiftUI + AppKit | C ABI；UniFFI 可选 | Keychain |
| Windows | egui 基线 | Compose Multiplatform | JNI | Credential Manager |
| iOS | 第一版目标 | SwiftUI | C ABI；UniFFI 可选 | Keychain |
| Android | 后续目标 | Compose Multiplatform | JNI | Keystore |

Windows egui 继续作为运行基线。
Compose host 通过功能、视觉、性能和打包验收后才能替换 egui。

## 3. 所有权

| 层 | 拥有 | 不拥有 |
| --- | --- | --- |
| Rust core | 业务规则、状态机、持久化、传输、权限策略、能力模型和错误合同 | 窗口、绘制、系统 share sheet |
| Rust bridge | C ABI、JNI、UniFFI、句柄、取消、deadline、panic containment | UI 状态和平台界面 |
| SwiftUI host | Apple 界面、输入、可访问性和 app lifecycle | 业务状态副本 |
| Compose host | Windows 与 Android 界面、输入和 UI lifecycle | 业务状态副本 |
| Platform adapter | 文件选择、share sheet、通知、后台任务和 OS 权限 | 业务规则、持久化规则和传输状态机 |
| Design contract | Apple 权威视觉、交互、动效和平台覆盖 | 运行时业务数据 |

## 4. 文件共享流程

1. 发送方选择文件。
2. 发送方选择已配对设备。
3. 接收方收到请求。
4. 接收方接受或拒绝。
5. 双方看到传输状态。
6. 中断后保存任务状态。
7. 网络恢复后继续传输。
8. 接收方校验内容并原子写入收件区。

配对使用二维码。
二维码绑定设备身份和临时配对会话。
接收方确认是默认行为。
设备信息页只读展示系统、版本、在线状态和能力。

## 5. Rust 能力模型

Rust core 定义以下能力。

- 设备发现与身份。
- 二维码配对。
- 授权和撤销。
- 传输队列、分块、续传和取消。
- 内容校验和原子提交。
- 文件冲突策略。
- 后台暂停与前台恢复状态。
- 文件选择结果和 share target。
- 通知事件。
- 凭据访问合同。
- 设备信息快照。

平台 adapter 实现以下能力。

- 原生文件选择器。
- 原生 share sheet。
- 原生通知。
- 后台任务和前台恢复。
- Keychain、Credential Manager 和 Keystore。
- 网络接口和 OS 权限。

## 6. Bridge 边界

1. 每个请求带 protocol version、request ID、generation 和 deadline。
2. 每个异步任务支持 cancellation。
3. 每个 callback 有 payload limit。
4. 大文件通过句柄或流传输，不进入普通 JSON envelope。
5. Secret 不进入普通日志或 UI state snapshot。
6. Rust panic 在 bridge 边界转换为 typed error。
7. Swift、Kotlin 和 Rust 的合同由同一 schema 生成。
8. C header 与 JNI 声明进入生成和漂移检查。
9. 默认 UniFFI Kotlin/JNA 后端不进入首版产品路径。
10. Compose host 使用有界事件队列。JNI 不保存 `JNIEnv`，长任务不在 UI 线程执行。

## 7. 设计合同

macOS 与 iOS 的 Apple 设计是权威源。
SwiftUI 与 Compose 共享设计合同。
合同包含视觉令牌、交互状态、动效、平台字体、平台覆盖和验收 ID。
Windows 使用 Segoe UI Variable。Windows 不使用 SF Pro。
Compose 只能声明平台 API、字体或渲染能力差异。
Compose 不得独立修改共享视觉语义。

## 8. 迁移阶段

### Phase 1：协议与合同

1. 完成凭据合同研究。
2. 完成文件传输语义研究。
3. 完成 Paseo 参考分析。
4. 完成 Compose 与 Rust bridge 研究。

### Phase 2：Rust 能力层

1. 建立设备身份与二维码配对。
2. 建立 `iroh 1.4.1` 传输适配层和 Covio 文件协议。
3. 建立 1 MiB 分块、8 MiB 窗口、BLAKE3 校验、SQLite 检查点和原子落盘。
4. 建立原生根密钥保护与 Rust AEAD 凭据仓库。
5. 建立设备信息快照。

### Phase 3：平台接入

1. 建立 macOS 与 iOS SwiftUI host。
2. 建立 Windows Compose host 原型。
3. 建立 Android Compose 工程骨架。
4. 建立平台 adapter 合同。

### Phase 4：Cutover

1. Windows Compose host 通过功能验收。
2. Windows Compose host 通过视觉验收。
3. Windows Compose host 通过性能和打包验收。
4. 切换 GitHub Releases 产物。
5. 保留 egui 回滚路径，直到真机验收完成。

## 9. 暂缓事项

- App Store 发布。
- Google Play 发布。
- 正式更新器。
- 正式签名和公证流程。
- 账号体系和云端内容存储。
- Android 第一版交付。

## 10. 研究链接

- [跨平台凭据存储](../research/platform-credential-storage/README.md)
- [Rust 文件传输](../research/rust-file-transfer/README.md)
- [Compose 与 Rust bridge](../research/compose-rust-bridge/README.md)
- [跨设备内容读取](../research/cross-device-content-access/README.md)