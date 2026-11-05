# Covio 0.6.0-internal.26

Covio 0.6.0-internal.26 是内测版。
本版把 Windows 和 macOS 产品切到 Rust core 与平台原生 UI。
macOS 继续使用 SwiftUI 和 AppKit。
Windows 使用 egui。
本版不用于公开分发。

## 系统要求

- macOS 26 或更高版本。
- Apple Silicon Mac（arm64）。

## 安装包

本版提供默认瘦身 DMG、事务安装 PKG 和 App ZIP。
默认包不包含模型权重。
模型在用户确认后下载、校验并登记。
本版不构建离线模型 DMG。

从 0.0.2.3 或更早版本升级时，请使用事务安装 PKG。
首个 0.6.0 SemVer 内测版需要手动安装。
旧客户端不能解析新的 SemVer tag。
安装后，自动更新恢复。
事务安装 PKG 最多请求 1 次管理员授权。

## 从 0.0.2.3 到 0.6.0-internal.26 的变化

- macOS 产品改用 Rust core。窗口、菜单和可访问性继续使用 SwiftUI / AppKit。
- macOS 的配置、晾衣线、剪贴板、工作区、电源、helper 和更新规则使用 Rust。
- macOS 通过 C ABI 使用 Rust core。产品不再加载 KMP framework。
- Windows 产品改用 Rust core 和 egui。
- Windows 产品路径不包含 JVM、Kotlin、Compose 或 JNA。
- Windows 使用 Windows Credential Manager。macOS 使用 Keychain。
- 项目版本改用 Semantic Versioning。本版是 `0.6.0-internal.26`。
- 构建号与产品版本分开保存。
- 安装包和更新包增加 KMP、JVM、Kotlin、Compose 和 JNA 边界检查。
- macOS 和 Windows 的最终产品边界完成验收。

## 验证

- `bash scripts/test-all.sh`：通过。
- macOS 全量测试和最终包：[run 41861580963](https://github.com/wyz541/kmp-Covio/actions/runs/41861580963)。
- macOS 真机验收：MacBook Pro M1 Max，macOS 27.0.1。
- macOS Keychain、睡眠、helper 和重启恢复通过。
- macOS artifact boundary：57 个 app 文件，8 个 Mach-O 文件，无 KMP fallback。
- Windows CI 和最终 installer：[run 41861581262](https://github.com/wyz541/kmp-Covio/actions/runs/41861581262)。
- Windows installer：clean install、upgrade、rollback、uninstall、crash recovery 和 DPI 1.5 通过。
- Windows 多显示器：[run 41870873498](https://github.com/wyz541/kmp-Covio/actions/runs/41870873498)。

## 安装

1. 下载 `Covio-0.6.0-internal.26.pkg`。
2. 打开 PKG 并完成 1 次管理员授权。
3. PKG 完成 app、helper 和 updater 的事务安装。
4. 打开 `Covio.app`。
5. 打开设置，确认自动更新状态和手动检查入口。

**警告：** 此构建使用本地签名。
macOS Gatekeeper 可能阻止此构建。
请到“隐私与安全性”允许应用，或清除隔离属性：

```sh
xattr -dr com.apple.quarantine /Applications/Covio.app
```

## 内测说明

- 使用测试 Mac。
- 风扇控制会写入 SMC 值，并需要全局特权 helper。
- 首次打开风扇控制后检查 Liquid Glass、预设切换和节点拖动。
- 合盖保持会增加电池消耗。
- 自动更新仅使用 internal 渠道。
- 更新私钥不随 app、Release 或安装包分发。

## 本版不包含

- 离线模型 DMG。
- Developer ID 签名。
- Apple 公证。
- 公开分发。
- Intel 或 Universal 2 构建。
- App Store 构建。
