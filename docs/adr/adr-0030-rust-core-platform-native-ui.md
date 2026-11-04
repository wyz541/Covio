# ADR-0030：Windows 与 macOS 使用 Rust core 和原生 UI

- Status：accepted
- Kind：architecture
- Date：2026-11-04
- Supersedes：ADR-0001 的 KMP shared-foundation 决策
- Superseded by：none
- Implements：#596
- 相关：[Feature #595](https://github.com/wyz541/kmp-Covio/issues/595)、[迁移计划](../design/rust-core-migration.md)

## 范围

本 ADR 只决定 Windows 和 macOS 的产品边界。
Android、iOS 和 Web 不在本次迁移范围内。
本 ADR 不决定这三个平台的 UI、bridge、secret storage 或发布时间。

| 平台 | 范围 | 最终 UI | Rust 接入 | Secret storage | 最终产品边界 |
| --- | --- | --- | --- | --- | --- |
| Windows | in scope | Rust + egui | 同一进程直接调用 | Windows Credential Manager | 不含 JVM、Kotlin、Compose 或 JNA |
| macOS | in scope | SwiftUI + AppKit | C ABI / cinterop | Keychain | 不含 Kotlin framework 或 KMP shared module |
| Android | out of scope | 本 ADR 不决定 | 本 ADR 不决定 | 本 ADR 不决定 | 需要独立 ADR |
| iOS | out of scope | 本 ADR 不决定 | 本 ADR 不决定 | 本 ADR 不决定 | 需要独立 ADR |
| Web | out of scope | 本 ADR 不决定 | 本 ADR 不决定 | 本 ADR 不决定 | 需要独立 ADR |

## 背景

当前 `main` 已让 macOS 产品使用 Rust core。
macOS SwiftUI / AppKit 宿主通过 C ABI 调用 Rust。
Windows 仍使用迁移期 Kotlin path。
旧版 ADR-0030 把 Android 写成第三个产品边界，这与当前决策不一致。

Windows 和 macOS 需要一套共享业务语义。
两个平台只保留自己的 UI、窗口、生命周期和 OS capability adapter。
Windows 最终产品不能保留 JVM、Kotlin、Compose 或 JNA。
macOS 最终产品不能保留 Kotlin framework 或 KMP shared module。

KMP shared module 的仓库级删除不在本 ADR 的决定范围内。
Android 的数据迁移、JNI、Keystore 和 Kotlin UI 也不在本 ADR 范围内。

## 决策

1. Rust 是 Windows 和 macOS 非 UI application core 的唯一长期 owner。
2. Rust 拥有业务规则、durable state、网络、存储、字典、媒体、搜索、阅读、平台策略、版本规则和 bridge contract。
3. Rust 拥有 secret 的读取、写入、替换、删除和 redaction 合同。
4. Windows 最终使用 Rust + egui。egui 只拥有窗口、输入、绘制、焦点、托盘和 ephemeral widget state。
5. Windows 在同一 Rust 进程内调用 Rust core。C ABI 和 JNA 不是 Windows 最终产品边界。
6. macOS 最终使用 SwiftUI + AppKit。平台 UI 通过 C ABI / cinterop 调用 Rust。
7. Bridge 只暴露 bounded commands、events、snapshots、opaque handles 和 typed errors。
8. Bridge 必须定义 payload limit、generation、cancellation、deadline、panic containment 和 shutdown。
9. Secret value、用户文件内容和本地路径不进入日志或普通 JSON control envelope。
10. 在 Windows 或 macOS 完成 cutover 前，该平台现有 path 仍是 authoritative path。
11. 每个平台保留旧 artifact 和 feature flag，直到真实 release acceptance 完成。
12. Windows 和 macOS 的最终 artifact 不得包含 KMP fallback、JVM 或平台禁止的 runtime。
13. Android、iOS 和 Web 不得被本 ADR 当作已承诺的迁移目标。
14. Android、iOS 或 Web 进入迁移时，必须建立独立 ADR 和独立 Feature。
15. ADR-0001 的 SwiftUI + AppKit UI 决策继续有效。本 ADR 只取代它的 KMP shared-foundation 决策。

## Rust ownership

| Crate 或 host | Ownership |
| --- | --- |
| `covio-core` | 业务规则、durable state、策略、状态机和 typed errors |
| `covio-bridge` | 版本化 command / event / snapshot envelope 和边界校验 |
| `covio-platform` | filesystem、process、secret、notification 和平台 capability port |
| `covio-ffi` | macOS C ABI、opaque handle、callback、cancellation 和 shutdown |
| `covio-windows` | Windows egui host 和同进程 composition root |

平台 adapter 只实现 OS capability 和 bounded boundary。
平台 adapter 不复制 Rust core 的业务状态机。

## 数据兼容

1. Windows 和 macOS 迁移必须读取本平台现有用户数据。
2. `config.json` 保留未知键和逐键类型回退。
3. `shelf.json`、剪贴板和 `index.json` 保留现有 schema。
4. 原子写入继续使用同目录临时文件与 rename。
5. 迁移不删除旧数据，直到新路径通过兼容验收。
6. 每个平台保存旧 artifact。回滚不能要求用户手工恢复数据。
7. 兼容差异必须有 fixture、明确分类和后续动作。

## Cutover 顺序

1. 合并本 ADR 与修正后的迁移计划。
2. 建立 Rust workspace 和 bridge。
3. 迁移配置、durable state、电源、helper、更新和设计合同规则。
4. 验证 Rust 与现有 KMP path 的行为和数据兼容。
5. 建立 macOS 和 Windows capability adapter。
6. 完成 macOS UI cutover 和真实设备验收。
7. 完成 Windows egui host、adapter 和产品 cutover。
8. 更新 Windows 和 macOS 的 CI、安装包和 artifact boundary checks。
9. 完成 Windows 和 macOS 真实产品验收。
10. 决定 KMP 仓库级删除。该决定不属于本 ADR。

## 后果

### 正面

- Windows 和 macOS 共享一套 Rust 业务语义。
- Windows 最终产品不再包含 JVM、Kotlin、Compose 或 JNA。
- macOS 最终产品不再包含 Kotlin framework。
- 两个平台的 UI 和 OS capability 边界更清楚。
- Secret storage 使用平台原生能力。
- Durable state 和数据迁移规则只有一份实现。

### 负面

- 需要维护 Rust core、macOS C ABI 和 Windows egui host。
- 迁移期需要同时维护现有 KMP path 与 Rust path。
- Rust 与平台 host 之间需要新的版本、取消、线程和关闭合同。
- Windows 与 macOS 发布流程需要分别重写。
- 旧测试需要迁移为 Rust tests、platform tests 和真实设备验收。

### 风险

- Bridge 可能出现 ABI 漂移。缓解：版本化 envelope、C header tests 和生成的 bindings。
- Callback 或 pointer 生命周期错误可能导致崩溃。缓解：opaque handle、generation、panic containment 和 shutdown tests。
- 数据迁移可能丢字段。缓解：共享 fixture、round-trip tests、未知键保留和回滚 artifact。
- 迁移期两套状态机可能漂移。缓解：先做 parity gate，再执行平台 cutover。
- Rust 和平台 UI 可能重复业务逻辑。缓解：code review 检查 ownership，adapter 只保留 capability。
- Secret 可能进入日志。缓解：redaction tests 和统一 typed error。
- Windows 缺少真实设备证据。缓解：Windows release gate 保持 open，直到设备验收完成。

## 备选方案

### 备选 1：继续使用 KMP，并在 KMP 后面新增 Rust

该方案迁移范围较小。
该方案仍保留 Kotlin framework、JVM 和 KMP 产品路径。
该方案不满足 Windows 和 macOS 的最终产品边界。

未采纳。

### 备选 2：Windows 最终通过 JNA 调用 Rust

该方案复用 JVM 依赖。
该方案保留 JNA、JVM 和额外 bridge 开销。
该方案与 Rust + egui 的目标冲突。

未采纳。

### 备选 3：Windows 和 macOS 分别重写业务逻辑

该方案不需要跨语言 bridge。
该方案会产生两套状态机、持久化和错误规则。
该方案无法保证两个平台语义一致。

未采纳。

### 备选 4：macOS 也使用 egui

该方案共享 UI 技术栈。
该方案会丢失现有 SwiftUI、AppKit、Liquid Glass 和 macOS 可访问性实现。
该方案需要重做已验证的 UI。

未采纳。

### 备选 5：把 Android 作为第三个平台纳入本 ADR

该方案扩大迁移承诺。
该方案需要同时决定 JNI、Keystore、Android UI 和 Android 发布边界。
当前决策不包含这些内容。

未采纳。

## 未决事项

| 项目 | 状态 | 确认方法 |
| --- | --- | --- |
| Windows 安装包格式 | proposed | Windows cutover Issue 以 MSI 或等价安装包完成 clean install 验收 |
| Android 迁移 | out of scope | 需要独立 ADR 和独立 Feature |
| iOS 迁移 | out of scope | 需要独立 ADR 和独立 Feature |
| Web 迁移 | out of scope | 需要独立 ADR 和独立 Feature |
| KMP 仓库级删除 | not decided | 单独 ADR，在 Windows 和 macOS cutover 后决定 |
| 性能收益 | not measured | 只有同设备、同 OS、同负载有读数后才能声明 |

## 参考

- [ADR-0001：macOS UI 使用 SwiftUI](adr-0001-macos-ui-swiftui.md)
- [ADR-0021：废弃 Compose Web 打样](adr-0021-deprecate-compose-web-preview.md)
- [Rust core 迁移计划](../design/rust-core-migration.md)
- [Feature #595](https://github.com/wyz541/kmp-Covio/issues/595)
