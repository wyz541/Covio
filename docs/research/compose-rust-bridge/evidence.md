# Compose Multiplatform UI 与 Rust bridge：证据附录

## 1. 文档状态

| 项目 | 内容 |
| --- | --- |
| 文档版本 | `1.0` |
| 状态 | 初稿，可评审 |
| 日期 | `2026-11-10` |
| 来源截止 | `2026-11-10` |
| 执行状态 | 只读调研完成；产品原型尚未执行 |

本文件记录来源、观察、推论、反证和限制。
结论见 [conclusion.md](conclusion.md)。验证计划见 [validation/README.md](validation/README.md)。

## 2. 问题类别和案例映射

问题类别是跨平台 UI 与原生核心的边界设计。
案例映射如下。

| 案例 | 目的 |
| --- | --- |
| `Case 1` | Windows Compose + JNI vertical slice |
| `E-01` 至 `E-12` | Compose、JVM、打包和分发事实 |
| `E-13` 至 `E-17` | JNI、UniFFI 和 FFI 安全事实 |
| `E-18` 至 `E-22` | 当前源码与设计合同事实 |
| `E-23` 至 `E-27` | 字体、Windows 能力和生命周期事实 |

## 3. 来源等级

| 等级 | 来源 | 用途 | 置信度 |
| --- | --- | --- | --- |
| A | 规范、官方接口定义、许可、语言规则 | 硬约束 | 高 |
| B | 当前仓库源码和配置 | 当前事实 | 高 |
| C | 官方项目文档、厂商文档 | 产品能力 | 中高 |
| D | 本机环境 | 当前环境事实 | 中 |
| E | 第三方文章 | 背景 | 低 |

本次关键决策使用 A、B 或 C 级来源。
本次没有使用 E 级来源支持关键决策。

## 4. 环境事实

| 项目 | 值 |
| --- | --- |
| 当前分支 | `docs/cross-platform-product-direction` |
| 当前基线 commit | `5a1f6c8dd9d2a66dd2cb6c7d0f68b08fc9b88297` |
| Rust | `rustc 1.99.1` |
| Cargo | `cargo 1.99.1` |
| Java | OpenJDK `17.0.19` LTS |
| Kotlin | 未安装 |
| Gradle | 未安装 |
| 设计合同 SHA-256 | `D4DB917D232C196228425FE382DF4FE5B4437C51F0F68B2A758B0F493565952E` |
| `covio-ffi/src/lib.rs` SHA-256 | `CBEA1F621640C0D80D4ED5C275BC716C8DD411D9A10C7DFFA15DC016094132EE` |
| Windows egui host SHA-256 | `0935512384D892CE1F8AF052FD5AFE302A50083736AB50FE7B87F2027D2B591B` |

工作树有既有未提交修改。本文档只记录只读观察。
未执行 Compose 构建、Windows 打包、JNI 加载或视觉测试。

## 5. 复现命令

```powershell
git rev-parse HEAD
git status --short
rustc --version
cargo --version
java -version
Get-FileHash docs/covio-design-contract.json -Algorithm SHA256
Get-FileHash rust/crates/covio-ffi/src/lib.rs -Algorithm SHA256
Get-FileHash rust/apps/covio-windows/src/windows_app.rs -Algorithm SHA256
```

```powershell
rg -n 'PROTOCOL_VERSION|deny_unknown_fields|Sequence|sequence' rust/crates/covio-bridge/src/lib.rs
rg -n 'ABI_VERSION|C-unwind|ffi_guard|CovioAppHandle|CovioEngineHandle' rust/crates/covio-ffi/src
rg -n 'CovioCapability|COVIO_CAPABILITY' rust/crates/covio-ffi/include/covio_ffi.h
rg -n 'CapabilityKind|FilePicker|Share|Background' rust/crates/covio-platform/src
rg -n 'with_decorations|with_transparent|with_taskbar|with_always_on_top|TrayController|GlobalHotKey|TopEdgeMonitor' rust/apps/covio-windows/src
rg -n 'SF Pro|egui|platform/system/materials|platform/system/accessibility' docs/covio-design-contract.json
rg -n 'COPY_OUT|TOKENS_OUT|RUST_MOTION_OUT|--check' scripts/generate-contract-constants.py
```

## 6. 证据索引

| 编号 | 主题 | 来源等级 | 结论 | 置信度 |
| --- | --- | --- | --- | --- |
| E-01 | Compose 平台支持 | C | Android、iOS、desktop JVM 为 Stable | 高 |
| E-02 | Compose release | C | 当前稳定 release 为 `1.12.2` | 高 |
| E-03 | Compose 与 Jetpack | C | 共享 compiler 和 runtime 原则 | 高 |
| E-04 | Android-only 与 IO | C | 权限、设备和 IO 不在 common API | 高 |
| E-05 | Native distribution | C | Windows 支持 MSI 和 EXE。桌面包自包含 JVM | 高 |
| E-06 | Windows package version | C | 使用 `MAJOR.MINOR.BUILD` | 高 |
| E-07 | jpackage | A | 目标平台构建。需要 WiX。bundled runtime | 高 |
| E-08 | Compose window | C | Windows `windowHandle` 返回 HWND | 高 |
| E-09 | Desktop accessibility | C | Windows 使用 Java Access Bridge | 高 |
| E-10 | Compose test API | C | 跨平台 UI test API 为 Experimental | 高 |
| E-11 | GitHub Release 限制 | A | 单资产小于 `2 GiB`。最多 `1000` 个资产 | 高 |
| E-12 | Immutable release | A | 发布后 tag 和资产不可修改 | 高 |
| E-13 | UniFFI JNA | A | 默认 Kotlin 后端要求 JNA `5.12.0+` | 高 |
| E-14 | UniFFI JNI backend | C | 主分支实验性 JNI backend 使用 `jni_sys` | 中高 |
| E-15 | JNI 线程模型 | A | `JNIEnv` 不能跨线程 | 高 |
| E-16 | Android JNI | A | 避免 UI 线程长调用。使用 `JavaVM` attach | 高 |
| E-17 | Rust unwind | A | panic 不穿过非 unwinding ABI | 高 |
| E-18 | 当前 C ABI | B | ABI `1`、原始指针、`C-unwind` callback | 高 |
| E-19 | Header 漂移 | B | 手写 header 能力枚举少于 Rust | 高 |
| E-20 | 当前 bridge 协议 | B | request、response、event、cancel 已有初版 | 高 |
| E-21 | Windows egui host | B | 透明置顶、托盘、hotkey、单实例和顶部触发 | 高 |
| E-22 | 设计合同 | B | SF Pro、egui 映射、无 Kotlin 生成 | 高 |
| E-23 | Apple 字体许可 | A | SF Pro 只许可 Apple OS 应用 | 高 |
| E-24 | Windows 字体 | C | Segoe UI Variable。Selawik 可作回退 | 高 |
| E-25 | Windows Share 与通知 | C | 发送 Share Sheet 支持 unpackaged。toast 需注册 | 中高 |
| E-26 | Paseo 生命周期 | C | 可见性、退避、liveness、queue restore | 中高 |
| E-27 | Android 16 KB | A | 共享库需要 16 KB 对齐 | 高 |

## 7. 证据详情

### E-01：Compose 平台支持

来源等级：C
环境：JetBrains Kotlin Multiplatform 文档，访问日期 `2026-11-10`
命令或来源：`https://www.jetbrains.com/help/kotlin-multiplatform-dev/supported-platforms.html`
关键输出：

```text
Android: Stable
iOS: Stable
Desktop (JVM): Stable
```

观察：Compose Multiplatform UI framework 把 Android、iOS 和 desktop JVM 标为 Stable。
推论：Windows desktop 和 Android 可以作为目标 UI 平台。
反证：Stable 不覆盖 Covio 的安装、性能、视觉和无障碍要求。
限制：官方项目文档是产品能力声明。它不是本机实验。
置信度：高
关联：`E-02`、`E-03`、`Case 1`

### E-02：Compose release

来源等级：C
环境：Compose Multiplatform GitHub release，访问日期 `2026-11-10`
命令或来源：`https://github.com/JetBrains/compose-multiplatform/releases/tag/v1.12.2`
关键输出：

```text
tag: v1.12.2
published: 2026-10-15
UI: 1.12.2
Runtime: 1.12.2
Material3: 1.12.0-alpha03
```

观察：`1.12.2` 是当前稳定 release。
观察：Material3 制品为 alpha。
推论：首版需要固定 Compose 版本。关键页面不应无审查地依赖 alpha Material3 行为。
反证：Compose UI、Foundation 和 Runtime 的版本仍为稳定组合。
限制：release 页面是官方制品信息。它不证明 Covio 产品可用。
置信度：高
关联：`E-03`、`E-10`

### E-03：Compose 与 Jetpack

来源等级：C
环境：JetBrains 文档，访问日期 `2026-11-10`
命令或来源：`https://www.jetbrains.com/help/kotlin-multiplatform-dev/compose-multiplatform-and-jetpack-compose.html`
关键输出：

```text
Compose Multiplatform extends Jetpack Compose.
Android uses Google Jetpack Compose artifacts.
Other targets use JetBrains multiplatform artifacts.
Platform-specific APIs remain platform-specific.
```

观察：Windows 和 Android 可以共享 Compose API 和 common Kotlin 代码。
观察：Android target 仍使用 Google 制品。
推论：共享发生在源码层。Windows JVM 与 Android ART 使用不同运行时。
推论：窗口、权限、设备和 IO 必须放入平台 source set 或 adapter。
限制：文档不证明每个 UI 库都支持所有平台。
置信度：高
关联：`E-01`、`E-04`

### E-04：Android-only 与 IO

来源等级：C
环境：JetBrains 文档，访问日期 `2026-11-10`
命令或来源：`https://www.jetbrains.com/help/kotlin-multiplatform-dev/compose-android-only-components.html`
关键输出：

```text
Android Context, Activity and LocalContext are Android-only.
Permissions, devices and IO are out of Compose Multiplatform scope.
```

观察：`Context`、`Activity` 和部分 Android API 不能进入 `commonMain`。
观察：权限、设备、文件和 IO 不在 Compose common API 范围。
推论：平台 adapter 是必需边界。不能把 Android API 放入 Compose common UI。
限制：第三方库可以补充部分能力。第三方库不在本次关键决策中。
置信度：高
关联：`E-03`、`E-16`、`E-21`

### E-05：Native distribution

来源等级：C
环境：JetBrains Compose native distribution 文档，访问日期 `2026-11-10`
命令或来源：`https://www.jetbrains.com/help/kotlin-multiplatform-dev/compose-native-distribution.html`
关键输出：

```text
Windows formats: .exe and .msi
The plugin packages applications with jpackage.
Distributions include the necessary Java runtime.
jlink minimizes bundled modules.
Cross-compilation is not supported.
```

观察：Windows 可以生成 MSI 和 EXE。
观察：应用包包含 Java runtime。
观察：Windows 包必须在 Windows 构建。
推论：目标用户不需要安装 JDK。构建机需要 JDK 和打包工具。
推论：Windows GitHub Actions runner 必须执行 native package task。
限制：文档不提供 Covio 包大小和启动时间。
置信度：高
关联：`E-06`、`E-07`、`E-11`

### E-06：Windows package version

来源等级：C
环境：JetBrains Compose native distribution 文档，访问日期 `2026-11-10`
命令或来源：`https://www.jetbrains.com/help/kotlin-multiplatform-dev/compose-native-distribution.html#package-version`
关键输出：

```text
msi/exe version format: MAJOR.MINOR.BUILD
MAJOR <= 255
MINOR <= 255
BUILD <= 65535
```

观察：Windows package version 必须是三字段数字版本。
观察：Windows package version 不支持 SemVer pre-release 后缀。
推论：内部 SemVer 需要映射为数字 package version。
推论：Git tag 和文件名可以包含 `-internal.N`。MSI 版本不能包含该后缀。
限制：适用范围是当前 Compose Gradle plugin。
置信度：高
关联：`E-05`、`E-11`、`validation/README.md`

### E-07：jpackage

来源等级：A
环境：Oracle JDK 21 `jpackage` 文档，访问日期 `2026-11-10`
命令或来源：`https://docs.oracle.com/en/java/javase/21/jpackage/packaging-overview.html`
关键输出：

```text
Packages must be built on the target platform.
Windows exe/msi: WiX 3.0 or later is required.
A runtime image is packaged with the application.
jlink creates the runtime when no runtime image is supplied.
```

观察：`jpackage` 自带 runtime 生成。
观察：Windows MSI 或 EXE 需要 WiX。
观察：Windows 包必须在 Windows 构建。
推论：Compose Windows 发布需要 JVM 运行时。不能只分发 JAR。
推论：构建机必须固定 JDK 和 WiX 版本。
限制：Compose plugin 可能封装部分参数。实际 CI 仍需验证。
置信度：高
关联：`E-05`、`E-11`

### E-08：Compose window

来源等级：C
环境：Compose Multiplatform Core commit `c1d032e2a53819949c972f13f837025f1927f037`，访问日期 `2026-11-10`
命令或来源：`https://github.com/JetBrains/compose-multiplatform-core/blob/c1d032e2a53819949c972f13f837025f1927f037/compose/ui/ui/src/desktopMain/kotlin/androidx/compose/ui/awt/ComposeWindow.desktop.kt`
关键输出：

```text
class ComposeWindow : JFrame
val windowHandle: Long
Windows: HWND
X11: Window
macOS: NSWindow
```

观察：Compose `Window` 提供透明、无边框、`alwaysOnTop` 和 `focusable` 参数。
观察：`FrameWindowScope.window` 暴露 `ComposeWindow`。
观察：`windowHandle` 在 Windows 返回 HWND。
推论：Windows Share Sheet adapter 可以取得 Compose 窗口的 HWND。
推论：透明和置顶窗口具备技术路径。
反证：文档未直接证明 `taskbar=false` 与顶部边缘触发体验等价。
限制：固定源码观察不等于产品原型。
置信度：高
关联：`E-21`、`E-25`、`Case 1`

### E-09：Desktop accessibility

来源等级：C
环境：JetBrains desktop accessibility 文档，访问日期 `2026-11-10`
命令或来源：`https://www.jetbrains.com/help/kotlin-multiplatform-dev/compose-desktop-accessibility.html`
关键输出：

```text
Windows accessibility: Supported via Java Access Bridge.
Java Access Bridge is disabled by default.
Add jdk.accessibility module for native distributions.
Test with JAWS or NVDA.
```

观察：Windows Compose 无障碍依赖 Java Access Bridge。
观察：发布包必须包含 `jdk.accessibility`。
推论：安装包和测试环境必须启用 JAB。
推论：当前 egui 到 Compose 的迁移可能产生无障碍回归。
反证：Compose 提供 semantics。semantics 存在不等于读屏器可操作。
限制：实际 JAWS 和 NVDA 行为未测试。
置信度：高
关联：`E-10`、`Case 1`

### E-10：Compose test API

来源等级：C
环境：JetBrains Compose test 文档，访问日期 `2026-11-10`
命令或来源：`https://www.jetbrains.com/help/kotlin-multiplatform-dev/compose-test.html`
关键输出：

```text
The common Compose Multiplatform UI test API is Experimental.
Desktop JUnit-based test API is available.
```

观察：common UI test API 仍标记 Experimental。
观察：desktop 提供 JUnit-based API。
推论：验证计划需要把自动化和人工验收分开。
推论：视觉回归不能只依赖 experimental API。
限制：文档没有给出完整稳定性时间表。
置信度：高
关联：`E-09`、`validation/README.md`

### E-11：GitHub Release 限制

来源等级：A
环境：GitHub Docs，访问日期 `2026-11-10`
命令或来源：`https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases`
关键输出：

```text
Up to 1000 release assets per release.
Each file must be under 2 GiB.
No total release size limit.
No bandwidth limit.
```

观察：单资产上限为 `2 GiB`。
观察：单 release 最多 `1000` 个资产。
推论：MSI、ZIP 和校验和可以放在一个 release。
推论：超过 `2 GiB` 的包必须拆分或改用其他存储。首版不应采用此方案。
反证：当前包大小未知。限制只说明上限。
限制：平台限制可能变化。发布前需要复查。
置信度：高
关联：`E-05`、`E-06`、`E-12`

### E-12：Immutable release

来源等级：A
环境：GitHub Docs，访问日期 `2026-11-10`
命令或来源：`https://docs.github.com/en/code-security/concepts/supply-chain-security/immutable-releases`
关键输出：

```text
Immutable releases lock the tag, assets, and release contents after publication.
Create a draft, attach assets, then publish.
```

观察：immutable release 锁定 tag 和资产。
观察：官方建议先建 draft，再附加资产，再发布。
推论：内部发布应先建 draft。全部资产完成后再发布 pre-release。
推论：发布后不能替换资产。失败时使用新版本号。
限制：仓库是否启用 immutable releases 需要单独确认。
置信度：高
关联：`E-11`、`validation/README.md`

### E-13：UniFFI JNA

来源等级：A
环境：UniFFI `0.32` Kotlin 文档，访问日期 `2026-11-10`
命令或来源：`https://mozilla.github.io/uniffi-rs/0.32/kotlin/gradle.html`
关键输出：

```text
UniFFI relies on JNA for native calls.
JNA 5.12.0 or greater is required.
UniFFI relies on kotlinx coroutines for futures and async support.
```

观察：默认 Kotlin binding 依赖 JNA。
观察：默认 Kotlin binding 的 async 支持依赖 `kotlinx-coroutines-core`。
推论：默认 Kotlin binding 多一层 JNA。
推论：Windows 打包必须处理 JNA 原生库查找。
推论：默认 backend 与“首版 Kotlin 无 JNA”目标冲突。
反证：JNA 可以降低手写 JNI 的成本。
限制：该文档描述默认 Kotlin backend。它不描述实验性 JNI backend。
置信度：高
关联：`E-14`、`E-18`、`conclusion.md` 第 7.1 节

### E-14：UniFFI JNI backend

来源等级：C
环境：UniFFI main commit `2124d553b73444890fd913b90d8fdd98620def1d`，日期 `2026-11-09`
命令或来源：`https://github.com/mozilla/uniffi-rs/tree/main/uniffi-bindgen-kotlin-jni`
关键输出：

```text
This is an experimental crate for generating JNI-based Kotlin bindings.
The runtime uses jni-sys.
It uses JNI rather than JNA.
```

观察：UniFFI 主分支存在实验性 JNI backend。
观察：该 backend 使用 `jni_sys`，不依赖 JNA。
观察：该 backend 明确标记 experimental。
推论：未来可以用 UniFFI 生成无 JNA 的 Kotlin binding。
推论：当前不能用该 backend 作为稳定首版依赖。
反证：主分支还有新功能和版本漂移。主分支源码不等于稳定发布。
限制：该路径不在 `v0.32.2` 稳定 tag 中。需要发布评审。
置信度：中高
关联：`E-13`、`conclusion.md` 第 9 节

### E-15：JNI 线程模型

来源等级：A
环境：Oracle Java 21 JNI Specification，访问日期 `2026-11-10`
命令或来源：`https://docs.oracle.com/en/java/javase/21/docs/specs/jni/design.html`
关键输出：

```text
The JNI interface pointer is valid only in the current thread.
Native methods must not pass the interface pointer to another thread.
JNIEnv is thread-local.
System.loadLibrary loads platform-specific native libraries.
```

观察：`JNIEnv` 是线程局部值。
观察：JNI 库通过 `System.loadLibrary` 加载。
观察：native 方法需要处理 Java exception。
推论：Rust 不能保存 `JNIEnv`。
推论：Rust worker 需要 JavaVM attach 才能调用 Java。
推论：默认事件队列可以避免 Rust 主动 attach。
限制：不同 JVM 的 JNI 实现可能扩展行为。规范约束仍然适用。
置信度：高
关联：`E-16`、`E-18`

### E-16：Android JNI 实践

来源等级：A
环境：Android NDK JNI Tips，访问日期 `2026-11-10`
命令或来源：`https://developer.android.com/ndk/guides/jni-tips`
关键输出：

```text
JNIEnv is thread-local.
Use JavaVM and AttachCurrentThread when needed.
Minimize JNI calls on the UI thread.
Keep JNI interface code in a small number of locations.
```

观察：Android 使用 JNI 的方式与 JVM JNI 一致。
观察：官方建议减少 UI 线程上的 JNI 长调用。
观察：官方建议减少 JNI 代码位置。
推论：Windows 和 Android 应共用一个小型 JNI adapter。
推论：传输和文件 IO 不进入 JNI UI 调用。
限制：Android 版本差异仍需设备验证。
置信度：高
关联：`E-15`、`E-27`

### E-17：Rust unwind

来源等级：A
环境：Rust Reference，访问日期 `2026-11-10`
命令或来源：`https://doc.rust-lang.org/reference/items/functions.html#unwinding`
关键输出：

```text
panic=unwind + non-unwinding ABI = abort at the ABI boundary.
Native unwind across a non-unwinding ABI is undefined behavior.
C-unwind is the unwind-capable ABI.
```

观察：普通 `extern "C"` 不是 unwinding ABI。
观察：Rust panic 穿过普通 C ABI 会 abort 或产生未定义行为。
推论：每个 C ABI 和 JNI 导出函数必须捕获 panic。
推论：默认跨语言 callback 不应使用 panic-producing 路径。
限制：panic containment 不能修复已损坏的业务状态。UI 仍需要重建 session。
置信度：高
关联：`E-18`、`solution.md` 第 7.4 节

### E-18：当前 C ABI

来源等级：B
环境：当前工作树，commit `5a1f6c8dd9d2a66dd2cb6c7d0f68b08fc9b88297` 加未提交修改
命令或来源：`rust/crates/covio-ffi/src/lib.rs`、`rust/crates/covio-ffi/src/engine_api.rs`
关键输出：

```text
ABI_VERSION = 1
CovioEventCallback = extern "C-unwind" fn(...)
EngineCapabilityCallback = extern "C-unwind" fn(...)
ffi_guard uses catch_unwind
APIs return raw *mut CovioAppHandle or *mut CovioEngineHandle
```

观察：当前 ABI 有版本常量。
观察：当前 handle 是原始指针。
观察：当前 callback 使用 `C-unwind`。
观察：当前导出函数使用 `ffi_guard`。
推论：当前 ABI 可以支持 Apple C ABI 起始路径。
推论：当前 ABI 需要增加整数句柄、事件队列和版本信息。
推论：当前 callback 不应成为跨平台默认合同。
限制：当前工作树未构建。静态观察不代表运行行为。
置信度：高
关联：`E-17`、`E-19`、`solution.md` 第 6 节

### E-19：Header 漂移

来源等级：B
环境：当前工作树
命令或来源：`rust/crates/covio-ffi/include/covio_ffi.h`、`rust/crates/covio-platform/src/capabilities.rs`
关键输出：

```text
Header CovioCapability ends at SECURE_STORAGE.
Rust CapabilityKind includes Screenshot, Startup and FilePicker.
Header contains bool and size_t parameters.
Header is hand-maintained.
No cbindgen drift test was found.
```

观察：C header 的能力枚举少于 Rust 能力枚举。
观察：header 使用 `bool` 和 `size_t`。
观察：header 没有生成器或漂移测试。
推论：Swift 可能看不到新增能力。
推论：header 与 Rust 已成为不一致合同。
推论：在 CMP 迁移前必须修复 header 生成和检查。
限制：当前构建可能仍能编译旧 Swift smoke。旧 smoke 不能证明枚举完整。
置信度：高
关联：`E-18`、`solution.md` 第 6 节

### E-20：当前 bridge 协议

来源等级：B
环境：当前工作树
命令或来源：`rust/crates/covio-bridge/src/lib.rs`
关键输出：

```text
PROTOCOL_VERSION = 1
DEFAULT_MAX_CONTROL_BYTES = 1024 * 1024
RequestEnvelope: protocol_version, request_id, generation, deadline, command, payload
ResponseEnvelope: request_id, generation, revision, result
EventEnvelope: generation, revision, event, payload
Multiple envelopes use deny_unknown_fields
EventEnvelope has no sequence field
```

观察：当前协议已有 request、response、event、cancel 和 shutdown 初版。
观察：协议限制控制消息大小。
观察：可演进 envelope 不允许未知字段。
观察：事件没有 sequence。
推论：当前协议可作为新合同基础。
推论：新协议需要事件 sequence、相对超时和可选字段。
推论：不能在同一 major 版本中静默删除字段。
限制：协议源码未连接 Windows JNI。
置信度：高
关联：`E-18`、`solution.md` 第 6、8 节

### E-21：Windows egui host

来源等级：B
环境：当前工作树
命令或来源：`rust/apps/covio-windows/src/windows_app.rs`、`rust/apps/covio-windows/src/top_edge.rs`、`rust/apps/covio-windows/src/lib.rs`
关键输出：

```text
with_decorations(false)
with_transparent(true)
with_has_shadow(false)
with_taskbar(false)
with_always_on_top()
TrayController
GlobalHotKeyManager
SingleInstance
TopEdgeMonitor
Capability smoke: Credential Manager, clipboard, startup, file picker, notification, update handoff
```

观察：当前 egui host 有自定义窗口和常驻能力。
观察：当前 host 有 tray、global hotkey、single instance 和 top edge。
观察：当前 capability smoke 覆盖多个 Windows 原生能力。
推论：Compose host 必须保留这些能力。
推论：迁移不只是替换 UI 绘制。
推论：原型必须验证窗口行为、原生能力和安装后加载。
限制：当前 smoke 不等价于 Compose host smoke。
置信度：高
关联：`E-08`、`E-25`、`Case 1`

### E-22：设计合同

来源等级：B
环境：当前工作树
命令或来源：`docs/covio-design-contract.json`、`scripts/generate-contract-constants.py`
关键输出：

```text
schemaVersion: 1.4.0
metadata.fonts.family: SF Pro
metadata.fonts.usage: All Covio delivery pages
platform/system/materials.runtimeTarget: egui drawable surfaces
platform/system/accessibility.runtimeTarget: egui accessibility semantics
Generator outputs: Swift copy, Swift tokens, Rust motion
Generator check: --check
No Kotlin output
```

观察：设计合同仍要求 SF Pro。
观察：平台映射仍包含 egui。
观察：生成器只生成 Swift 和 Rust。
推论：Compose 无法从当前合同生成完整令牌。
推论：Windows 使用 SF Pro 与 Apple 许可冲突。
推论：设计合同更新是 Compose UI 实施前置条件。
限制：合同正在当前工作树修改。文件哈希只代表本次观察。
置信度：高
关联：`E-23`、`E-24`、`solution.md` 第 10 节

### E-23：Apple 字体许可

来源等级：A
环境：Apple Developer Fonts 页面，访问日期 `2026-11-10`
命令或来源：`https://developer.apple.com/fonts/`
关键输出：

```text
LICENSE AGREEMENT FOR THE APPLE SAN FRANCISCO FONT
For iOS, OS X and tvOS application uses only
You may not install, use or run the Apple Font for non-Apple operating system UI.
You may not embed the Apple Font in software programs.
```

观察：SF Pro 使用许可绑定 Apple OS。
观察：许可禁止在非 Apple OS 使用 Apple Font。
观察：许可禁止未授权嵌入。
推论：Windows Compose 不能打包或使用 SF Pro。
推论：设计合同必须提供平台字体覆盖。
推论：Windows 实际字体应使用 Segoe UI Variable。
限制：这是许可文本的直接观察。正式发布前仍应做法律复核。
置信度：高
关联：`E-22`、`E-24`

### E-24：Windows 字体

来源等级：C
环境：Microsoft Learn Windows typography，访问日期 `2026-11-10`
命令或来源：`https://learn.microsoft.com/en-us/windows/apps/design/style/typography`
关键输出：

```text
Segoe UI Variable is the new system font for Windows.
Selawik is an open-source font metrically compatible with Segoe UI.
```

观察：Windows 11 系统字体是 Segoe UI Variable。
观察：Selawik 可作为开放度量兼容回退。
推论：Windows Compose 应优先使用系统 Segoe UI Variable。
推论：Selawik 可作为缺失系统字体时的回退。Selawik 不能替代 SF Pro 的品牌语义。
限制：字体渲染和换行仍需 Windows 原型验证。
置信度：高
关联：`E-22`、`E-23`

### E-25：Windows Share 与通知

来源等级：C
环境：Microsoft Learn Windows app integration，访问日期 `2026-11-10`
命令或来源：`https://learn.microsoft.com/en-us/windows/apps/develop/windows-integration/integrate-sharesheet-send`、`https://learn.microsoft.com/en-us/windows/apps/develop/notifications/app-notifications/toast-desktop-apps`
关键输出：

```text
Desktop apps use IDataTransferManagerInterop for per-window sharing.
The desktop Share path supports packaged and unpackaged apps.
Unpackaged Win32 apps can send toast notifications with extra activation steps.
```

观察：Windows Share Sheet 发送路径支持 packaged 和 unpackaged desktop app。
观察：Share Sheet 需要窗口句柄。
观察：unpackaged toast 需要 AUMID、shortcut 或 COM activation 配置。
推论：`ComposeWindow.windowHandle` 可以提供给 Share adapter。
推论：MSI 安装后需要验证 toast 点击激活。
反证：Windows Share Target 接收路径仍可能需要 package identity。该目标不在发送路径内。
限制：Compose 窗口 HWND 的实际调用未测试。
置信度：中高
关联：`E-08`、`E-21`、`Case 1`

### E-26：Paseo 生命周期

来源等级：C
环境：Paseo `v0.15.4` commit `1c00b365c9e0b74c1580eba33d905d693125ae21`，访问日期 `2026-11-10`
命令或来源：`packages/app/src/hooks/use-app-visible.ts`、`packages/app/src/utils/app-visibility.ts`、`packages/client/src/daemon-client.ts`
关键输出：

```text
AppState tracks active and background.
DEFAULT_RECONNECT_BASE_DELAY_MS = 1500
DEFAULT_RECONNECT_MAX_DELAY_MS = 30000
LIVENESS_HEARTBEAT_INTERVAL_MS = 10000
LIVENESS_HEARTBEAT_TIMEOUT_MS = 15000
On reconnect: restore server info, flush pending send queue.
```

观察：Paseo 使用前台可见性和连接状态。
观察：Paseo 使用指数退避和 liveness。
观察：Paseo 恢复连接后刷新状态并发送排队数据。
推论：Covio 应使用相同生命周期模式。
推论：移动端进入后台时保存恢复点。回到前台后重连。
推论：后台持续接收不能作为首版承诺。
限制：Paseo 使用 daemon 和 relay。Covio 首版是局域网直连。
置信度：中高
关联：`solution.md` 第 13 节

### E-27：Android 16 KB

来源等级：A
环境：Android Developers 16 KB page size 文档，访问日期 `2026-11-10`
命令或来源：`https://developer.android.com/guide/practices/page-sizes`
关键输出：

```text
Shared libraries must use 16 KB ELF alignment.
Check arm64-v8a and x86_64 shared libraries.
Check LOAD alignment and GNU_RELRO end alignment.
```

观察：Android 共享库需要 16 KB page-size 对齐。
观察：检查范围包括 `arm64-v8a` 和 `x86_64`。
观察：不对齐可能导致运行时崩溃。
推论：Android JNI 构建必须检查 Rust `.so`。
推论：该检查后续加入 Android 工程验收。
限制：Android 不在第一版范围。验证尚未执行。
置信度：高
关联：`E-16`、`validation/README.md`

## 8. 逻辑证据链

```text
E-01、E-03
  -> Compose desktop 和 Android 可共享 common UI 源码
  -> Windows 使用 JVM，Android 使用 ART
  -> E-05、E-06、E-07
  -> Windows 需要 jpackage、JVM runtime、WiX 和数字版本
  -> E-13、E-14、E-15、E-16
  -> 默认 UniFFI Kotlin 依赖 JNA
  -> 自定义 JNI 可避开 JNA
  -> E-17、E-18、E-19、E-20
  -> bridge 需要 panic containment、整数句柄、事件 sequence 和生成 header
  -> E-21、E-22、E-23、E-24
  -> Compose 迁移受窗口、设计合同和字体限制
  -> E-25、E-26
  -> Windows 原生能力需要 adapter。移动端后台需要暂停和恢复
  -> E-11、E-12
  -> GitHub Releases 可以承载内部测试。发布必须可复核
  -> Case 1
  -> 验证 Compose、JNI、MSI、Share、通知、无障碍和回滚
```

## 9. 反证和限制

1. Compose desktop 为 Stable。Covio 的 Windows 产品可行性仍未验证。
2. Compose 支持透明和置顶窗口。`taskbar=false` 和顶部边缘体验仍未验证。
3. Windows Share Sheet 支持 unpackaged app。Compose HWND 和 MSI 安装路径仍未验证。
4. Windows toast 支持 unpackaged app。点击激活仍未验证。
5. UniFFI 有实验性 JNI backend。实验性能力不能作为稳定发布承诺。
6. 当前 C ABI 有 panic guard。当前 callback 仍使用 `C-unwind`。
7. 当前 bridge 有 request、response 和 event。当前事件没有 sequence。
8. 当前设计合同有 `--check`。当前生成器没有 Kotlin 输出。
9. Apple 字体许可限制 SF Pro。正式法律结论仍应复核。
10. GitHub Releases 有资产限制。当前资产大小未知。
11. Paseo 有重连模式。Paseo 不是 Covio 的传输实现。
12. 本机有 Java 17。当前没有 Kotlin 和 Gradle。

## 10. 已知缺口

1. Windows Compose host 未构建。
2. Windows MSI 和便携 ZIP 未构建。
3. JNI 动态库未在 Windows 加载。
4. C ABI 和 JNI 未运行同一 fixture。
5. Compose `windowHandle` 未驱动 Share Sheet。
6. Compose 托盘和顶部边缘未验证。
7. JAB、JAWS 和 NVDA 未验证。
8. 冷启动、内存、帧时间和包大小未测量。
9. 设计合同未增加 Kotlin 输出。
10. 设计合同未增加平台字体和语义。
11. Apple 字体许可未进入正式设计审批。
12. GitHub Release 的 immutable 设置未确认。
13. Windows toast 激活未验证。
14. Android 16 KB 对齐未验证。
15. iOS C ABI 和 XCFramework 未验证。
16. 正式签名和公证未研究。
17. Windows Share Target 未研究。
18. 文件传输协议和加密握手未研究。
19. `docs/research/README.md` 主题索引已在本任务收口时更新。

## 11. 复核方法

1. 检查 commit 和文件哈希。
2. 重新打开本文档列出的官方 URL。
3. 对比 Compose release 版本。
4. 重新检查 UniFFI stable tag 和 main backend。
5. 运行 header 生成或漂移检查。
6. 用同一 fixture 测试 C ABI 和 JNI。
7. 执行 [validation/case-windows-compose-jni.md](validation/case-windows-compose-jni.md)。
8. 把新观察回填到 [evidence.md](evidence.md)。
9. 结论变化时更新 [conclusion.md](conclusion.md)。

## 12. 参考来源

1. JetBrains：`https://www.jetbrains.com/help/kotlin-multiplatform-dev/supported-platforms.html`
2. JetBrains：`https://www.jetbrains.com/help/kotlin-multiplatform-dev/compose-native-distribution.html`
3. JetBrains：`https://www.jetbrains.com/help/kotlin-multiplatform-dev/compose-desktop-accessibility.html`
4. Compose Multiplatform：`https://github.com/JetBrains/compose-multiplatform/releases/tag/v1.12.2`
5. Oracle：`https://docs.oracle.com/en/java/javase/21/jpackage/packaging-overview.html`
6. Oracle：`https://docs.oracle.com/en/java/javase/21/docs/specs/jni/design.html`
7. Rust：`https://doc.rust-lang.org/reference/items/functions.html#unwinding`
8. UniFFI：`https://mozilla.github.io/uniffi-rs/0.32/kotlin/gradle.html`
9. UniFFI：`https://github.com/mozilla/uniffi-rs/tree/main/uniffi-bindgen-kotlin-jni`
10. GitHub：`https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases`
11. Microsoft：`https://learn.microsoft.com/en-us/windows/apps/design/style/typography`
12. Microsoft：`https://learn.microsoft.com/en-us/windows/apps/develop/windows-integration/integrate-sharesheet-send`
13. Microsoft：`https://learn.microsoft.com/en-us/windows/apps/develop/notifications/app-notifications/toast-desktop-apps`
14. Apple：`https://developer.apple.com/fonts/`
15. Android：`https://developer.android.com/ndk/guides/jni-tips`
16. Android：`https://developer.android.com/guide/practices/page-sizes`
17. Paseo：`https://github.com/getpaseo/paseo`

## 13. 关联文档

- [主题索引](README.md)
- [上下文](context.md)
- [调研分析](investigation.md)
- [结论](conclusion.md)
- [方案](solution.md)
- [验证计划](validation/README.md)
- [案例](validation/case-windows-compose-jni.md)