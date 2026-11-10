# Covio 的 Compose Multiplatform UI 与 Rust bridge 研究

## 文档状态

| 项目 | 内容 |
| --- | --- |
| 文档版本 | `1.0` |
| 状态 | 初稿，可评审 |
| 调研日期 | `2026-11-10` |
| 当前结论 | Windows 使用 Compose Multiplatform；Kotlin 首版使用自定义 JNI；Apple 使用版本化 C ABI |
| 验证状态 | 尚未执行 |

Covio 可以把 Compose Multiplatform 用于 Windows 和后续 Android 的 UI。Covio 不应把默认 UniFFI Kotlin 后端作为 Windows 首版 bridge。
证据和限制见 [evidence.md](evidence.md)。

## 前因

Covio 决定成为独立跨平台产品。第一版支持 macOS、Windows 和 iOS。
当前 Windows 使用 Rust 与 egui。目标 Windows UI 使用 Compose Multiplatform。
目标 macOS 与 iOS UI 使用 SwiftUI。
Android 在第一版之后使用 Compose Multiplatform。
问题定义和范围见 [context.md](context.md)。
产品范围见 [ADR-0035](../../adr/adr-0035-cross-platform-product-scope.md)。

## 背景

Compose Multiplatform 把 Compose API 提供给 common Kotlin 代码。Android 使用 Google Jetpack Compose 制品。桌面使用 JetBrains 多平台制品。
Windows desktop 使用 JVM。安装包通过 `jpackage` 和 `jlink` 打包运行时。
默认 UniFFI Kotlin 绑定依赖 JNA。UniFFI 主分支另有实验性 JNI 后端。
当前 `covio-ffi` 使用 C ABI、原始指针句柄和回调。当前 bridge 还缺少 Windows JNI、事件顺序和大文件句柄合同。
当前设计合同仍要求 SF Pro。Apple 字体许可不允许在非 Apple OS 使用 SF Pro。
专业分析见 [investigation.md](investigation.md)。当前源码和官方来源见 [evidence.md](evidence.md)。

## 过程

研究只使用一手资料和当前仓库源码。
资料范围包括 JetBrains、Compose Multiplatform release、Oracle JNI 与 `jpackage`、Rust Reference、UniFFI、GitHub Releases、Microsoft Learn、Apple 字体许可和 Paseo 源码。
研究检查了 `covio-bridge`、`covio-ffi`、`covio-platform`、Windows egui host 和设计合同。
研究没有执行 Windows Compose 原型。
调研方法、方案矩阵和反证见 [investigation.md](investigation.md)。
证据编号、命令和限制见 [evidence.md](evidence.md)。

## 结果

C ABI 是 Apple 平台的稳定边界。JNI 是 Kotlin/JVM 与 Android 的低开销边界。
默认 UniFFI Kotlin 后端依赖 JNA。因此默认 UniFFI Kotlin 后端不进入 Windows 首版产品路径。
实验性 `uniffi-bindgen-kotlin-jni` 可避免 JNA。此后端尚未证明为稳定发布能力。
Windows 与 Android 可以共享 Compose `commonMain` UI、设计令牌、语义和显示状态。Rust 仍拥有业务状态。
Windows 替换 egui 必须分阶段完成。egui 保持默认路径，直到原型门槛通过。
结论、决策表和不采用方案见 [conclusion.md](conclusion.md)。证据链见 [evidence.md](evidence.md)。

## 预期

1. Windows Compose host 使用同一份 Rust 业务状态。
2. Kotlin 与 Swift 使用同一版 bridge 协议。
3. UI 线程不阻塞。后台任务可取消。错误可分类。panic 不越过 FFI 边界。
4. Compose 与 SwiftUI 共享设计合同、文案、语义、动效和验收编号。
5. Windows 安装包可从 GitHub Releases 下载，并附校验和。
6. egui 可在未通过验收时回滚。
接口、迁移门槛和回滚条件见 [solution.md](solution.md)。测试矩阵见 [validation/README.md](validation/README.md)。证据缺口见 [evidence.md](evidence.md)。

## 实现预期的手段

1. 新增 Compose UI 模块，只保存 UI、设计系统、显示状态和平台接入接口。
2. 保留 `covio-bridge` 作为唯一协议定义。大文件内容不进入普通控制消息。
3. 为 Apple 保留 C ABI。为 Kotlin/JVM 和 Android 新增 JNI adapter。
4. C ABI 与 JNI 共用请求、事件、错误、取消、deadline 和版本规则。
5. 事件通过有界队列交付。UI 在专用线程读取事件。Rust 不默认回调 Java 或 Swift。
6. 设计合同增加平台字体、语义、角色、焦点顺序和平台差异。
7. Windows 使用 MSI 加便携 ZIP。GitHub Release 标记为 pre-release，并附 SHA-256。
推荐架构、接口字段和迁移阶段见 [solution.md](solution.md)。验证目录见 [validation/README.md](validation/README.md)。证据和已知缺口见 [evidence.md](evidence.md)。

## 子文档

| 文件 | 内容 |
| --- | --- |
| [context.md](context.md) | 问题、范围、角色、系统模型、状态矩阵和成功标准 |
| [investigation.md](investigation.md) | 调研方法、能力矩阵、方案对比、源码分析和反证 |
| [conclusion.md](conclusion.md) | 结论、决策表、不采用方案、限制和未决项 |
| [solution.md](solution.md) | 推荐 bridge、接口契约、设计合同、迁移门槛和回滚 |
| [evidence.md](evidence.md) | 来源、证据编号、观察、推论、限制和缺口 |
| [validation/README.md](validation/README.md) | 验证目标、矩阵、风险和清理要求 |
| [validation/case-windows-compose-jni.md](validation/case-windows-compose-jni.md) | Windows Compose 与 JNI vertical slice 案例 |

## 证据链阅读顺序

1. 阅读 [context.md](context.md) 的约束和状态矩阵。
2. 阅读 [investigation.md](investigation.md) 的能力矩阵和反证。
3. 阅读 [evidence.md](evidence.md) 的 `E-01` 至 `E-27`。
4. 阅读 [conclusion.md](conclusion.md) 的决策表。
5. 阅读 [solution.md](solution.md) 的接口和迁移门槛。
6. 按 [validation/README.md](validation/README.md) 执行验证。

## 更新规则

1. 新来源先写入 [evidence.md](evidence.md)。
2. 新源码观察先记录 commit 或文件哈希。
3. 结论变化时同步更新 [conclusion.md](conclusion.md)。
4. 接口变化时同步更新 [solution.md](solution.md)。
5. 测试状态变化时同步更新 [validation/README.md](validation/README.md) 和案例文件。
6. 结论变化时同步更新 `docs/research/README.md` 的主题索引。