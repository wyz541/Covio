# ADR-0030：Rust 拥有非 UI 核心，平台保持原生 UI

- Status：proposed
- Kind：architecture
- Date：2026-11-04
- Supersedes：ADR-0001 的 KMP shared-foundation 决策
- Superseded by：none
- Implements：#596
- 相关：[Feature #595](https://github.com/wyz541/kmp-Covio/issues/595)、[迁移计划](../design/rust-core-migration.md)

## 背景

Covio 当前使用 Kotlin Multiplatform 保存共享业务逻辑。
macOS SwiftUI 宿主通过 `kmpDomain.framework` 调用共享层。
Kotlin `app` 模块仍保留 Compose 与 helper 旧路径。
Windows 客户端仍采用 Compose Multiplatform 计划。
仓库没有 Rust workspace。

目标产品需要三个平台边界。

| 平台 | UI | Rust 接入 | Secret storage |
| --- | --- | --- | --- |
| Windows | Rust + egui | 同进程直接调用 | Windows Credential Manager |
| macOS | SwiftUI + AppKit | C ABI / cinterop | Keychain |
| Android | Kotlin Android UI | JNI / NDK | Android Keystore |

KMP shared module 无法提供这个最终边界。
Windows 的最终产品也不能保留 JVM、Kotlin、Compose 或 JNA。

## 决策

1. Rust 是 Covio 非 UI application core 的唯一长期 owner。
2. Rust 拥有业务规则、durable state、网络、存储、字典、媒体、搜索、阅读、平台策略、版本规则和 bridge contract。
3. Rust 拥有 secret 的读取、写入、替换、删除和 redaction 合同。
4. Windows 最终使用 Rust + egui。egui 只拥有窗口、输入、绘制和 ephemeral widget state。
5. macOS 最终使用 SwiftUI + AppKit。平台 UI 通过 C ABI / cinterop 调用 Rust。
6. Android 最终使用 Kotlin Android UI。Kotlin 只保留 UI、Android build 和 JNI 调用壳。
7. Android 通过 JNI / NDK 调用 Rust core。
8. Windows 在同一 Rust 进程内直接调用 Rust core。C ABI 和 JNA 不是 Windows 最终产品边界。
9. Bridge 只暴露 bounded commands、events、snapshots、opaque handles 和 typed errors。
10. Bridge 必须定义 payload limit、generation、cancellation、deadline、panic containment 和 shutdown。
11. Secret value、用户文件内容和本地路径不进入日志或普通 JSON control envelope。
12. 现有 KMP path 在每个平台完成 cutover 前仍是 authoritative path。
13. 每个平台保留旧 artifact 和 feature flag，直到 release acceptance 完成。
14. 所有平台完成 cutover 与兼容验收后，删除 `kmpDomain`、Kotlin JVM / Compose 产品入口和 KMP 构建路径。
15. ADR-0001 的 SwiftUI + AppKit UI 决策继续有效。本 ADR 只取代它的 KMP shared-foundation 决策。
16. 本次迁移范围为 Windows、macOS 和 Android。iOS 与 Web 需要新的 ADR 和独立 Issue。

## Rust ownership

| Crate 或 host | Ownership |
| --- | --- |
| `covio-core` | 业务规则、durable state、策略、状态机和 typed errors |
| `covio-bridge` | 版本化 command / event / snapshot envelope 和边界校验 |
| `covio-platform` | filesystem、process、secret、power、notification 等 capability port |
| `covio-ffi` | macOS C ABI、opaque handle、callback 和 shutdown |
| `covio-jni` | Android JNI / NDK adapter |
| `covio-windows` | Windows egui host 和同进程 composition root |

平台 adapter 只实现 OS capability 和 bounded boundary。
平台 adapter 不复制 Rust core 的业务状态机。

## 数据兼容

1. 迁移必须读取现有用户数据。
2. `config.json` 保留未知键和逐键类型回退。
3. `shelf.json`、剪贴板和 `index.json` 保留现有 schema。
4. 原子写入继续使用同目录临时文件与 rename。
5. 迁移不删除旧数据，直到新路径通过兼容验收。
6. 每个平台保存旧 artifact。回滚不能要求用户手工恢复数据。
7. 兼容差异必须有 fixture、明确分类和后续动作。

## Cutover 顺序

1. 合并本 ADR 与迁移计划。
2. 建立 Rust workspace 和 bridge。
3. 迁移配置、durable state、电源、helper、更新和设计合同规则。
4. 验证 Rust 与 KMP 的行为和数据兼容。
5. 建立 macOS、Windows 和 Android 平台 adapter。
6. 按平台完成 UI cutover。
7. 删除 KMP 产品路径。
8. 更新 CI、安装包和 artifact boundary checks。
9. 完成 macOS、Windows 和 Android 真实产品验收。
10. 关闭 Feature #595。

## 后果

### 正面

- 三个平台共享一套 Rust 业务语义。
- Windows 最终产品不再包含 JVM、Kotlin、Compose 或 JNA。
- macOS 最终产品不再包含 Kotlin framework。
- Android 只保留 UI、build 和 JNI 调用壳。
- 平台 adapter 的权限和生命周期边界更清楚。
- Secret storage 使用各平台原生能力。
- Durable state 和数据迁移规则只有一份实现。

### 负面

- 需要建立 Rust workspace、C ABI、JNI 和 Windows host。
- 迁移期需要同时维护 KMP 与 Rust path。
- Rust 与平台 host 之间需要新的版本、取消、线程和关闭合同。
- Android build 需要 NDK 与多 ABI native library。
- macOS 与 Windows 发布流程需要重写。
- 旧测试需要迁移为 Rust tests、platform tests 和真实设备验收。

### 风险

- Bridge 可能出现 ABI 漂移。缓解：版本化 envelope、C header tests 和生成的 bindings。
- Callback 或 pointer 生命周期错误可能导致崩溃。缓解：opaque handle、generation、panic containment 和 shutdown tests。
- 数据迁移可能丢字段。缓解：Kotlin fixture、round-trip tests、未知键保留和回滚 artifact。
- 迁移期两套状态机可能漂移。缓解：先做 parity gate，再执行平台 cutover。
- Rust 和平台 UI 可能重复业务逻辑。缓解：code review 检查 ownership，adapter 只保留 capability。
- Secret 可能进入日志。缓解：redaction tests 和统一 typed error。
- Windows 或 Android 缺少真实设备证据。缓解：Issue #613 保持 open，直到设备验收完成。

## 备选方案

### 备选 1：继续使用 KMP，并在 KMP 后面新增 Rust

该方案迁移范围较小。
该方案仍保留 Kotlin framework、JVM 和 KMP 产品路径。
该方案不满足最终产品边界。

未采纳。

### 备选 2：Windows 最终通过 JNA 调用 Rust

该方案复用 JVM 依赖。
该方案保留 JNA、JVM 和额外 bridge 开销。
该方案与 Rust + egui 的目标冲突。

未采纳。

### 备选 3：每个平台分别重写业务逻辑

该方案不需要跨语言 bridge。
该方案会产生三套状态机、持久化和错误规则。
该方案无法保证跨平台语义一致。

未采纳。

### 备选 4：macOS 也使用 egui

该方案共享 UI 技术栈。
该方案会丢失现有 SwiftUI、AppKit、Liquid Glass 和 macOS 可访问性实现。
该方案需要重做已验证的 UI。

未采纳。

## 未决事项

| 项目 | 状态 | 确认方法 |
| --- | --- | --- |
| Windows 安装包格式 | proposed | Issue #608 以 MSI 或等价安装包完成 clean install 验收 |
| Android UI 起始范围 | proposed | Issue #610 只交付当前产品能力的 Android shell |
| iOS 与 Web 迁移 | out of scope | 需要新 ADR |
| 性能收益 | not measured | 只有在同设备、同 OS、同负载有读数后才能声明 |

## 参考

- [ADR-0001：macOS UI 使用 SwiftUI](adr-0001-macos-ui-swiftui.md)
- [ADR-0021：废弃 Compose Web 打样](adr-0021-deprecate-compose-web-preview.md)
- [Rust core 迁移计划](../design/rust-core-migration.md)
- [Feature #595](https://github.com/wyz541/kmp-Covio/issues/595)
