# Compose Multiplatform UI 与 Rust bridge：结论

## 1. 文档状态

| 项目 | 内容 |
| --- | --- |
| 文档版本 | `1.0` |
| 状态 | 初稿，可评审 |
| 日期 | `2026-11-10` |
| 验证状态 | 尚未执行 |

Covio 可以采用 Compose Multiplatform 作为 Windows 与后续 Android 的 UI 技术。Kotlin 首版 bridge 应使用自定义 JNI。默认 UniFFI Kotlin 后端不进入 Windows 产品路径。
证据见 [evidence.md](evidence.md)。

## 2. 结论摘要

1. Windows 使用 Compose Multiplatform desktop。运行时是 JVM。
2. Android 后续使用 Compose Multiplatform。Windows 与 Android 共享 `commonMain` UI、语义和设计令牌。
3. macOS 与 iOS 继续使用 SwiftUI。Apple UI 不复用 Compose 页面。
4. Rust core 继续拥有业务状态、传输状态机、持久化、能力模型和错误语义。
5. Apple 使用 C ABI。Kotlin/JVM 和 Android 使用 JNI。
6. C ABI 与 JNI 共用同一版协议、错误、取消、deadline 和版本规则。
7. 默认 UniFFI Kotlin binding 依赖 JNA。JNA 不进入首版 Windows 产品路径。
8. 实验性 UniFFI JNI backend 可以作为独立试验。此试验不能阻塞首版。
9. 控制消息只传小数据。文件内容使用内容句柄或流。
10. 设计合同必须先增加平台字体、文案、语义和验收编号。
11. Windows 使用 MSI 加便携 ZIP。发布位置是 GitHub Releases。
12. egui 保持默认路径，直到 Compose 原型通过阶段门槛。
13. Compose 替换 egui 必须包含功能和视觉验收。技术可编译不构成替换条件。
14. 所有未执行验证标记为 `尚未执行`。

## 3. 主要决策因素

### F1：Compose 支持目标平台

Compose Multiplatform 把 Android 和 desktop JVM 标为 Stable（`E-01`）。
Windows desktop 使用 JVM。Android 使用 Jetpack Compose 制品（`E-03`）。
因此 Windows 与 Android 可以共享 Kotlin Compose UI 源码。
共享不包含二进制 UI 产物。Windows 与 Android 仍使用不同运行时。

### F2：Kotlin bridge 不能默认使用 JNA

默认 UniFFI Kotlin 文档要求 JNA `5.12.0` 或更高版本（`E-13`）。
UniFFI 主分支的实验性 JNI backend 使用 `jni_sys`，不依赖 JNA（`E-14`）。
实验性 backend 还没有稳定发布保证。
因此首版选择自定义 JNI。自定义 JNI 的维护成本可接受。JNA 的运行时和打包成本不可接受。

### F3：C ABI 与 JNI 需要同一协议

Apple 使用 C ABI。Kotlin/JVM 使用 JNI（`E-18`、`E-15`）。
两套边界必须共用 request、event、error、cancel 和 version 合同。
否则 Swift、Kotlin 和 Rust 会产生行为漂移。
因此 `covio-bridge` 保持唯一语义定义。C header、Kotlin 声明和 Swift 包装器只做边界转换。

### F4：事件队列优于跨语言 callback

Rust callback Java 或 Swift 需要处理线程 attach、重入、异常和生命周期。
当前 C ABI 使用 `C-unwind` callback（`E-18`）。
Rust panic 不得穿过非 unwinding ABI 边界（`E-17`）。
因此默认 bridge 使用有界事件队列。
UI 在专用线程读取事件。Rust 不默认回调 UI。

### F5：设计合同当前不可直接用于 Windows

当前合同要求 SF Pro（`E-22`）。
Apple 字体许可禁止在非 Apple OS 使用 SF Pro（`E-23`）。
当前合同还有 egui 平台映射。生成器没有 Kotlin 输出。
因此设计合同迁移必须先于 Compose UI 实现。
Windows 字体应使用 Segoe UI Variable（`E-24`）。

### F6：Windows 迁移必须分阶段

当前 egui host 拥有透明置顶窗口、托盘、全局热键、单实例和顶部边缘触发（`E-21`）。
Compose desktop 支持透明、无边框和置顶窗口（`E-08`）。
Compose 的 Windows Share Sheet 发送路径支持 unpackaged app（`E-25`）。
产品性能、JAB 无障碍、MSI 加载和视觉对齐仍未验证。
因此迁移必须使用原型、门槛和回滚。

## 4. 次要决策因素

### F7：JVM 分发

Compose desktop 使用 `jpackage` 和 `jlink`。安装包包含 Java runtime（`E-05`、`E-07`）。
目标用户不需要安装 JDK。构建机需要 JDK 和 WiX。Windows 安装包必须在 Windows 构建（`E-05`、`E-07`）。
Windows package version 必须使用 `MAJOR.MINOR.BUILD`（`E-06`）。
内部 SemVer 后缀只能出现在 Git tag、文件名和 app version。

### F8：GitHub Releases 约束

每个 release 资产必须小于 `2 GiB`。单个 release 最多 `1000` 个资产（`E-11`）。
内部测试应使用 pre-release。GitHub 的 latest 链接不应用于 pre-release 分发。
应为每个资产生成 SHA-256。
如果启用 immutable releases，应先创建 draft，再附加资产（`E-12`）。

### F9：Windows 无障碍

Compose desktop 在 Windows 通过 Java Access Bridge 提供无障碍（`E-09`）。
JAB 默认关闭。安装包需要 `jdk.accessibility`。
验收必须使用 JAWS 或 NVDA。
当前 egui 使用 AccessKit。迁移可能产生无障碍回归。

### F10：移动端后台

Paseo 使用 app visibility、重连退避、liveness 和发送队列（`E-26`）。
Covio 应采用相同模式。
移动端进入后台时保存恢复点。新接收任务暂停。回到前台后重连和续传。
Covio 不应承诺后台持续接收。

## 5. 根因和证据链

```text
研究问题
  -> Compose desktop 和 Android 为 Stable
  -> Windows 使用 JVM，Android 使用 ART
  -> 共享 UI 只能在源码层
  -> Kotlin 需要 JNI
  -> 默认 UniFFI Kotlin 需要 JNA
  -> 首版选择自定义 JNI
  -> C ABI 与 JNI 共用协议
  -> 事件队列、版本、句柄、取消和 panic 需要显式合同
  -> 原型验证后再替换 egui
```

证据编号如下。
- 平台支持：`E-01`、`E-02`、`E-03`。
- JVM 与打包：`E-05`、`E-06`、`E-07`。
- 窗口与无障碍：`E-08`、`E-09`。
- JNI 与 UniFFI：`E-13`、`E-14`、`E-15`、`E-16`。
- FFI 安全：`E-17`、`E-18`、`E-19`。
- 设计：`E-22`、`E-23`、`E-24`。
- Windows 原生能力：`E-25`。
- 生命周期参考：`E-26`。
- 发布：`E-11`、`E-12`。

## 6. 决策表

| 决策 | 选择 | 原因 | 证据 |
| --- | --- | --- | --- |
| Windows UI | Compose Multiplatform desktop | 支持 Stable，JVM 可打包 | `E-01`、`E-05` |
| Android UI | Compose Multiplatform | 与 Windows 共享 Kotlin UI | `E-01`、`E-03` |
| Apple UI | SwiftUI | 保留 Apple 原生体验 | `E-01`、`E-23` |
| Apple bridge | C ABI | Swift 可直接导入 C header | `E-18` |
| Kotlin bridge | 自定义 JNI | 避开默认 UniFFI 的 JNA | `E-13`、`E-14` |
| UniFFI | 只做受控试验 | 实验性 JNI backend 未稳定 | `E-14` |
| 协议 | `covio-bridge` 单一 schema | 防止三端漂移 | `E-20` |
| 句柄 | `u64` token 加 generation | 避免原始指针生命周期风险 | `E-18` |
| 事件 | 有界队列加阻塞读取 | 避免跨语言 callback 和线程 attach | `E-15`、`E-17` |
| 错误 | 稳定 code、retryable、user action | UI 可分类处理 | `E-20` |
| 取消 | request ID 加协作式取消 | 传输可保存恢复点 | `E-26` |
| panic | 所有导出函数捕获 | 防止越过 FFI 边界 | `E-17` |
| 版本 | ABI major/minor 加 protocol major/minor | 支持渐进升级 | `E-18`、`E-20` |
| 设计权威 | Apple 设计 | 产品要求 | `E-22` |
| Windows 字体 | Segoe UI Variable | Apple 字体许可限制 | `E-23`、`E-24` |
| 视觉验收 | 令牌、布局、无障碍和平台差异 | 不承诺像素相同 | `E-09`、`E-10` |
| 分发 | MSI 加 ZIP | Windows 内部测试 | `E-05`、`E-11` |
| 回滚 | 保留 egui 构建 | 保护已有用户 | `E-21` |

## 7. 不采用方案

### 7.1 默认 UniFFI Kotlin 加 JNA

风险：
1. Windows 产品多一个 JNA 运行时。
2. JNA 需要处理原生库查找。
3. JNA 回调线程需要 attach 和 detach。
4. 默认 Kotlin 后端与 Android 包结构绑定。
5. 与 ADR-0035 的 JNI 方向不一致。

结论：不采用。

### 7.2 实验性 UniFFI JNI 作为首版依赖

风险：
1. 实验性 API 可能变化。
2. 主分支能力可能未进入稳定 release。
3. 生成器与 JNI 符号需要额外测试。
4. 首版不能把核心 bridge 建立在未稳定工具上。

结论：只做隔离试验。首版不依赖。

### 7.3 C ABI 加 JNA 作为 Kotlin 路径

风险：
1. 多一层 FFI。
2. 多一个 JNA 依赖。
3. 取消和事件仍需要额外设计。
4. 性能和维护成本高于自定义 JNI。

结论：不采用。

### 7.4 Rust 直接 callback Java 或 Swift

风险：
1. `JNIEnv` 不能跨线程。
2. Swift callback 不能安全传播 Rust panic。
3. callback 重入容易死锁。
4. 生命周期和对象引用难测试。

结论：不作为默认路径。

### 7.5 Compose 页面复用到 Apple

风险：
1. Apple 设计权威失效。
2. 失去现有 SwiftUI 和 AppKit 能力。
3. 平台控件和可访问性差异扩大。

结论：不采用。

### 7.6 像素级复制 Apple 视觉

风险：
1. SF Pro 不能用于 Windows。
2. Compose 和 Apple 的字体渲染不同。
3. Liquid Glass 没有跨平台等价 API。
4. Windows 原生窗口和输入习惯会被破坏。

结论：不采用。使用语义对齐和平台差异表。

### 7.7 直接切换默认 Windows UI

风险：
1. 文件、托盘、通知和无障碍可能同时回归。
2. 回滚路径容易失效。
3. 用户数据格式可能被迫变化。
4. 发布问题会与 UI 问题混在一起。

结论：不采用。先做 vertical slice。

## 8. 系统限制

1. Windows Compose 依赖 JVM。不能把桌面 Compose 说成无运行时。
2. Windows 与 Android 只共享源码和语义。不能共享同一个二进制 UI。
3. Apple 平台和 Windows 的字体、材质和窗口控件不同。
4. SF Pro 不能合法用于 Windows 产品。
5. `JNIEnv` 不能跨线程共享。
6. Rust panic 不能跨过非 unwinding ABI 边界。
7. C header 手写会漂移。当前已出现能力枚举漂移。
8. `jpackage` 只能在目标平台构建。
9. MSI 或 EXE 需要 WiX。
10. Windows 无障碍依赖 JAB 和 `jdk.accessibility`。
11. Windows Share Sheet 发送和接收是不同能力。
12. 移动端后台传输受 OS 限制。Covio 使用暂停和恢复模型。
13. GitHub Releases 有资产大小和数量限制。
14. 未签名安装包会触发 Windows 安全提示。

## 9. 产品限制

1. 首版只承诺 Windows x64 内部测试。
2. 首版不承诺 Windows Share Target。
3. 首版不承诺正式自动更新。
4. 首版不承诺正式签名和公证。
5. 首版不承诺 Android 交付。
6. 首版不承诺 iOS 后台持续接收。
7. 首版不承诺像素级跨平台一致。
8. 首版不承诺 Windows arm64。
9. 首版不承诺大于 `2 GiB` 的单资产发布。
10. 首版不承诺未通过验收的 Compose 默认 UI。

## 10. 未决项

| 项目 | 状态 | 确认方法 |
| --- | --- | --- |
| Windows x64 是否为首版唯一架构 | 待确认 | 产品范围评审 |
| Compose 透明窗口与顶部边缘触发 | 未验证 | Windows 原型 |
| Compose 任务栏隐藏和托盘 | 未验证 | Windows 原型 |
| Compose HWND 与 Share Sheet | 未验证 | Windows 原型 |
| unpackaged toast 点击激活 | 未验证 | Windows 原型 |
| Java Access Bridge 验收 | 未验证 | JAWS 或 NVDA 测试 |
| Windows 冷启动和内存 | 未验证 | 基线测量 |
| MSI 和 ZIP 体积 | 未验证 | 实际构建 |
| Rust DLL 加载路径 | 未验证 | 安装后启动 |
| 实验性 UniFFI JNI backend 是否发布 | 未验证 | release 评审 |
| 设计合同平台字体扩展 | 未完成 | 设计合同变更 |
| Kotlin 常量生成 | 未完成 | 生成器变更 |
| Android 16 KB 对齐 | 未验证 | `.so` 检查 |
| iOS C ABI 打包 | 未验证 | XCFramework 构建 |
| Windows 正式签名 | 暂缓 | 发布阶段评审 |
| ADR-0035 的 UniFFI 措辞 | 待更新 | 新 ADR 或修订 |

## 11. 关联文档

- [主题索引](README.md)
- [上下文](context.md)
- [调研分析](investigation.md)
- [方案](solution.md)
- [证据](evidence.md)
- [验证计划](validation/README.md)