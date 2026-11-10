# ADR-0034：删除仓库中的 KMP shared module

- Status：accepted
- Kind：architecture
- Date：2026-11-05
- Updated：2026-11-10
- Supersedes：none
- Implements：#611
- 相关：[ADR-0030](adr-0030-rust-core-platform-native-ui.md)、[ADR-0035](adr-0035-cross-platform-product-scope.md)、[迁移计划](../design/rust-core-migration.md)

> 2026-11-10：ADR-0035 更新本 ADR 的平台范围与 UI runtime 约束。KMP shared module 继续删除。Rust core 继续拥有业务逻辑。Windows 和 Android 可以使用 Kotlin/Compose/JVM UI host。本 ADR 中禁止 UI host 使用 Kotlin、Compose 或 JVM 的条款不再适用。

## 背景

ADR-0030 决定 Windows 和 macOS 使用 Rust core 与平台原生 UI。
Windows 和 macOS 的产品 cutover 已完成。
两个产品都不再加载 KMP framework、JVM、Compose 或 JNA。

仓库仍保留 Kotlin Multiplatform（KMP）shared module、旧 Compose helper、Amper 构建文件、Kotlin release identity 和 Kotlin 测试门禁。
这些内容不属于 Windows 或 macOS 产品路径。
这些内容还会增加构建、测试和发布边界。

Android、iOS 和 Web 不在本次迁移范围。
当前仓库没有 Android UI、Android build 或 JNI 产品实现。
本 ADR 不决定未来 Android 的 UI、JNI、Keystore 或发布边界。

## 决策

1. Windows 和 macOS 是本次决策覆盖的产品边界。
2. Rust core 是两个平台唯一的共享业务逻辑来源。
3. 删除旧 Kotlin `app` module。
4. 删除 KMP shared module。
5. 删除 Amper project、Kotlin wrapper、Kotlin version catalog 和 Kotlin framework 构建脚本。
6. 删除 CI、全量测试和 release cache 中的旧 Kotlin JVM、Compose 与 KMP shared module 步骤。ADR-0035 可以重新引入 Kotlin/Compose UI host 的构建任务。
7. Release identity 只生成 Swift constant 和 Xcode xcconfig。
8. 设计合同删除 `composeMapping` 与 Kotlin interface inventory。
9. 跨语言 wire fixture 移到 Rust core test fixture，继续由 Rust 与 Swift 测试读取。
10. 历史 ADR、research 和发布记录保留原文。历史文本不等于活动产品路径。
11. 增加仓库与 build graph 检查。检查拒绝 KMP shared module、KMP framework 和 Kotlin 非 UI 产品路径。ADR-0035 允许 Kotlin/Compose/JVM UI host。
12. Android、iOS 和 Web 的产品工程不在本 ADR 内。ADR-0035 设定 iOS 第一版目标和 Android 后续目标。具体产品工程必须建立独立 Feature。

## 后果

### 正面

- 仓库的构建图与产品边界一致。
- Rust、Swift 和 Windows build 不再维护 Kotlin 非 UI 路径。
- CI 和本地全量测试不再安装 JDK 或运行 Amper。
- Release identity 只有一个 shared source，即 `release/release-manifest.json`。
- 设计合同不再声明不存在的 Compose 落点。

### 负面

- 仓库失去 KMP parity 测试。
- 历史 Kotlin 实现不能再作为可执行参考。
- Rust core fixture 必须承担跨语言兼容证据。

### 风险

- 风险：删除 fixture 会降低 wire compatibility 证据。缓解：把 fixture 移入 Rust test fixture，并保留 Rust 与 Swift 两端测试。
- 风险：release identity 可能留下旧 Kotlin 生成物。缓解：检查生成目录和漂移测试。
- 风险：CI 可能仍调用 Kotlin。缓解：工作流校验禁止 Kotlin 命令和 JDK setup。
- 风险：未来 Android 工作需要重做共享层。缓解：Android 进入迁移时建立独立 ADR 和 Feature。

## 备选方案

### 备选 1：保留 KMP 作为未使用模块

该方案保留旧代码和历史参考。
该方案仍维护 Amper、Kotlin、Compose 和 JDK 门禁。
该方案不满足仓库级删除目标。
未采纳。

### 备选 2：只删除 CI 中的 Kotlin 测试

该方案缩短 CI。
该方案仍保留死代码和失效构建入口。
该方案无法证明仓库构建图已删除 KMP。
未采纳。

### 备选 3：把 Android 纳入同一次迁移

该方案可以一次决定 Android 共享层。
当前仓库没有 Android product target。
该方案会虚构未实现范围，并扩大 #611 的工期。
未采纳。

## 未决事项

| 项目 | 状态 | 确认方法 |
| --- | --- | --- |
| Android 产品实现 | out of scope | 需要独立 ADR 和独立 Feature |
| iOS 产品实现 | out of scope | 需要独立 ADR 和独立 Feature |
| Web 产品实现 | out of scope | 需要独立 ADR 和独立 Feature |

## 参考

- [ADR-0030：Windows 与 macOS 使用 Rust core 和原生 UI](adr-0030-rust-core-platform-native-ui.md)
- [Rust core 迁移计划](../design/rust-core-migration.md)
- [Issue #611](https://github.com/wyz541/kmp-Covio/issues/611)
