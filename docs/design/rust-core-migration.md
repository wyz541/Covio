# Covio Rust core 与平台原生 UI 迁移计划

- 状态：accepted
- 日期：2026-11-04
- 决策：[ADR-0030](../adr/adr-0030-rust-core-platform-native-ui.md)
- Feature：[#595](https://github.com/wyz541/kmp-Covio/issues/595)

## 1. 结论

Covio 的最终产品使用 Rust core。
Windows 使用 Rust + egui。
macOS 使用 SwiftUI + AppKit。
Android 使用 Kotlin UI 和 JNI 调用壳。
最终产品删除 KMP shared module、Kotlin JVM 产品路径和 Windows Compose 路径。

迁移期间，现有 KMP path 继续服务当前产品。
每个平台只有通过数据兼容、行为 parity 和真实 artifact 验收后，才执行 cutover。

## 2. 当前状态与目标状态

| 项目 | 当前状态 | 目标状态 |
| --- | --- | --- |
| 业务规则 | `kmpDomain` Kotlin | `covio-core` Rust |
| Durable state | Kotlin + okio | Rust + platform filesystem adapter |
| macOS bridge | Kotlin framework | C ABI / cinterop |
| macOS UI | SwiftUI + AppKit | SwiftUI + AppKit |
| Windows UI | Compose Multiplatform 计划 | Rust + egui |
| Windows bridge | JVM / JNA 计划 | 同一 Rust 进程直接调用 |
| Android UI | 尚未建立正式产品路径 | Kotlin Android UI |
| Android bridge | 无 | JNI / NDK |
| Secrets | 目标未实现 | Keychain、Credential Manager、Keystore |
| 最终 artifact | 含 KMP | 不含 KMP |

## 3. Ownership

| 层 | 拥有 | 不拥有 |
| --- | --- | --- |
| Rust core | 业务规则、状态机、durable state、网络、存储策略、更新、版本、bridge contract | 窗口、绘制、输入、OS UI lifecycle |
| Windows egui | 窗口、输入、绘制、焦点、托盘、菜单、ephemeral widget state | 业务状态机、持久化、跨平台协议 |
| macOS SwiftUI / AppKit | 窗口、菜单、selection panel、accessibility、app lifecycle | 业务规则、durable state、secret 规则 |
| Android Kotlin UI | Activity、UI、input、accessibility、permission UI、Android build | shared KMP business logic |
| Platform adapters | OS capability 和 bounded boundary | 业务规则、状态副本、无关 OS 扩展 |

## 4. Rust workspace

```text
rust/
├── Cargo.toml
├── crates/
│   ├── covio-core/
│   ├── covio-bridge/
│   ├── covio-platform/
│   ├── covio-ffi/
│   └── covio-jni/
└── apps/
    └── covio-windows/
```

### 4.1 Crate responsibilities

| Crate | 责任 |
| --- | --- |
| `covio-core` | 领域模型、状态机、策略、持久化规则和 typed errors |
| `covio-bridge` | 版本化 envelope、payload bounds、generation、cancellation 和 shutdown |
| `covio-platform` | filesystem、process、secret、power、notification 和 update ports |
| `covio-ffi` | macOS C ABI、opaque handle、callback、panic containment |
| `covio-jni` | Android JNI / NDK 入口和 Java VM bridge |
| `covio-windows` | Windows egui composition root 和 OS adapter composition |

`covio-core` 不依赖 UI crate。
后续字典、媒体、搜索和阅读能力直接进入 Rust core。
本次迁移不实现这些能力的完整产品功能。
`covio-ffi` 和 `covio-jni` 只做边界转换。
`covio-ffi` 和 `covio-jni` 不复制业务规则。

## 5. Bridge 合同

### 5.1 共同规则

1. 每个请求带 protocol version、request id、generation 和 deadline。
2. 每个 snapshot 带 revision 和 generation。
3. 每个异步任务支持 cancel。
4. 每个 callback 有 payload limit。
5. 每个 handle 有显式 release。
6. Core panic 在 boundary 转换为 typed error。
7. Shutdown 等待或取消所有 active callback。
8. Stale generation 和 stale revision 返回明确错误。
9. Secret value 不进入普通 JSON control envelope。
10. 大文件或大媒体内容使用 opaque handle 或 bounded bytes。

### 5.2 平台入口

| 平台 | 入口 | 进程 | 线程模型 |
| --- | --- | --- | --- |
| Windows | Rust public API | 同一进程 | egui main thread + bounded worker pool |
| macOS | C ABI | 同一进程 | SwiftUI actor/main + core worker |
| Android | JNI / NDK | 同一进程 | UI thread + core worker + callback dispatch |

Windows 不通过 JNA 调用 Rust。
Windows 不启动 JVM。
macOS 不加载 KMP framework。
Android 不加载 shared KMP module。

## 6. Durable state 与数据兼容

### 6.1 不变的文件布局

| 数据 | 路径或规则 |
| --- | --- |
| 配置 | `~/Library/Application Support/com.wyz.covio/config.json` |
| 晾衣线 | `~/Library/Application Support/Covio/Screenshots/shelf.json` |
| 剪贴板 | `~/Library/Application Support/Covio/Clipboard/` |
| 工作区 | `~/Library/Application Support/Covio/Workspace/` |
| 工作区索引 | `Workspace/index.json` |
| 工作区内容 | `Workspace/objects/<sha256>` |
| 工作区临时内容 | `Workspace/incoming/<sha256>` |
| 删除标记 | `Workspace/tombstones.json` |

### 6.2 兼容规则

1. Rust reader 必须读取现有 Kotlin writer 的 fixture。
2. Rust writer 必须保留未知 JSON 键。
3. 单个字段损坏时，只回退该字段。
4. 原子写入使用同目录 `.tmp` 文件和 rename。
5. 写入失败返回 typed error。平台 adapter 不得吞掉失败。
6. 迁移不删除旧文件。
7. 新版本只能删除用户数据，当用户明确执行清理动作。
8. 每个平台保留旧 artifact，直到回滚验收通过。

### 6.3 兼容验收

| Fixture | 验收 |
| --- | --- |
| 默认配置 | 字段、顺序和默认值一致 |
| 未知配置键 | 保存后仍然存在 |
| 单键类型损坏 | 只有该键回退 |
| 旧 `shelf.json` | 条目、路径和顺序一致 |
| 损坏剪贴板 JSON | 回退空状态且不崩溃 |
| 工作区索引 | SHA-256、配额、tombstone 和错误码一致 |
| helper wire vectors | 请求与响应字节语义一致 |
| 设计合同 | token、copy 和 diagnostics 一致 |
| 版本规则 | 语义版本比较和更新窗口一致 |

## 7. Platform adapter 合同

| Adapter | macOS | Windows | Android |
| --- | --- | --- | --- |
| Secret | Keychain | Credential Manager | Keystore |
| Filesystem | Foundation / POSIX | Win32 / std | ContentResolver / std |
| Process | Foundation / POSIX | Win32 | Android process APIs |
| Notifications | UserNotifications | Win32 toast policy | Android notification API |
| Clipboard | NSPasteboard | Win32 clipboard | Android clipboard |
| Screenshots | native screenshot directory | Windows screenshot adapter | Android media adapter |
| Update handoff | app / updater XPC | updater process policy | Play or local installer policy |

平台 adapter 对不支持的能力返回 typed unavailable。
平台 adapter 不返回虚假成功。
平台 adapter 不在错误消息中写出 secret、文件内容或完整用户路径。

## 8. 执行顺序

| 阶段 | Issue | 结果 |
| --- | --- | --- |
| 决策 | #596 | ADR 与迁移计划 |
| Rust foundation | #597 | workspace 与 bridge |
| Core state | #598–#602 | 配置、数据、电源、helper、更新与合同规则 |
| Parity gate | #604 | Rust 与 KMP 行为及数据兼容证据 |
| macOS adapter | #603 | C ABI、Keychain 和 bounded boundary |
| macOS cutover | #605 | SwiftUI 产品切到 Rust |
| Windows host | #606–#608 | egui、Credential Manager 和产品 cutover |
| Android path | #609–#610 | JNI / Keystore 和 Kotlin UI |
| KMP removal | #611 | 删除 shared module 与旧产品路径 |
| Build and release | #612 | CI、安装包和 artifact checks |
| Final verification | #613 | 三平台真实产品边界 |

## 9. Cutover gates

### 9.1 Core gates

- 所有 core fixture 通过。
- Rust 与 KMP 的差异已解释或修复。
- Secret redaction 测试通过。
- Cancellation、stale generation、deadline 和 shutdown 测试通过。
- 大 payload 不进入普通 JSON control envelope。

### 9.2 Platform gates

| 平台 | 必须通过 |
| --- | --- |
| macOS | clean install、Keychain、睡眠、helper、升级和回滚 |
| Windows | clean install、Credential Manager、托盘、升级和卸载 |
| Android | clean install、Keystore、process death 和 JNI restart |

### 9.3 Artifact gates

- macOS app bundle 不含 Kotlin framework 或 KMP code。
- Windows artifact 不含 JVM、Kotlin、Compose 或 JNA。
- Android APK 不含 shared KMP business logic。
- Release workflow 只构建 Rust core 和平台 native UI。
- 仓库搜索、dependency graph 和 artifact scan 证明没有 KMP fallback。

## 10. 回滚

1. 每个平台保留 pre-cutover artifact。
2. Feature flag 选择旧 path 或 Rust path。
3. 数据文件保持向后可读。
4. 回滚不删除新文件。
5. 回滚后旧版本仍能读取迁移后的共享字段。
6. 回滚失败时停止 cutover，不继续删除 KMP。

## 11. 测试与证据

| 层 | 证据 |
| --- | --- |
| Rust unit / integration | `cargo fmt --check`、Clippy、workspace tests |
| Bridge | C header、JNI contract、round-trip、cancellation 和 payload tests |
| Data compatibility | Kotlin fixture 与 Rust output 对照 |
| macOS | Swift tests、Keychain、真机流程、artifact scan |
| Windows | egui tests、Credential Manager、Windows 11 artifact 验收 |
| Android | Android build、JNI tests、Keystore、process death 验收 |
| Release | clean install、upgrade、rollback、dependency graph 和 bundle scan |

仓库测试不等于真实产品验收。
真实设备结论必须记录日期、设备、OS、artifact、commit 和结果。

## 12. 文档更新

迁移期间需要同步更新以下文档。

| 文档 | 要求 |
| --- | --- |
| `README.md` | 区分当前 KMP path 和 Rust 目标 path |
| `AGENTS.md` | 迁移完成后删除 KMP 构建约束 |
| `docs/design/workbench-architecture.md` | UI 行为不变，只更新 host ownership 引用 |
| `docs/adr/adr-0030-rust-core-platform-native-ui.md` | 记录决策和 cutover 门槛 |
| `docs/design/rust-core-migration.md` | 更新阶段、完成状态和证据 |
| 平台发布文档 | 更新构建、签名、安装和回滚命令 |

## 13. 完成定义

Feature #595 只有满足以下条件才能关闭。

1. #596–#613 完成或有明确的 out-of-scope 决议。
2. Rust core 是三个平台的唯一业务逻辑来源。
3. 三个平台完成真实 artifact 验收。
4. Keychain、Credential Manager 和 Keystore 通过 secret 验收。
5. 现有用户数据无损迁移。
6. KMP module、Kotlin JVM / Compose 产品路径和 KMP build scripts 删除。
7. CI 和 release 只构建 Rust core 与平台 native UI。
8. README、ADR、迁移计划和发布文档与现实一致。
