# Covio 0.6.0-internal.36

Covio 0.6.0-internal.36 是内测版。
本版建立 macOS、Windows 和 iOS 共用的内部测试 Release 身份。
本版增加 macOS 和 iOS 的二维码配对、发送、接收和设备信息入口。
本版增加 Rust iroh 单文件传输和目录快照传输。
本版将 Windows Compose host 的版本改为读取发布清单。
三个平台继续使用 Rust core 与平台原生 UI。
macOS 使用 SwiftUI 和 AppKit。
Windows 使用 Compose Multiplatform。
iOS 使用 SwiftUI。
本版不用于公开分发。

## 系统要求

- macOS 26 或更高版本。
- Apple Silicon Mac（arm64）。
- Windows 11 x64。
- iOS 17 或更高版本。
- 已登记到 Apple 开发团队的 iPhone。

## 安装包

本版同时提供 macOS、Windows 和 iOS 制品。
macOS 包含默认瘦身 DMG、事务安装 PKG 和 App ZIP。
Windows 包含 Compose 便携 ZIP 和 MSI。
iOS 包含已签名的 arm64 IPA。
三个平台使用同一个 `clientVersion`、`buildNumber` 和 Git commit。
默认包不包含模型权重。
模型在用户确认后下载、校验并登记。
本版不构建离线模型 DMG。

从 0.0.2.3 或更早版本升级时，请使用事务安装 PKG。
`0.6.0-internal.32` 和 `.33` 的更新器使用旧仓库路径。
运行 `.32` 或 `.33` 时，请手动安装 `.34` PKG 一次。
从 `.34` 起，更新器使用当前仓库路径并兼容旧签名清单。
事务安装 PKG 最多请求 1 次管理员授权。

## 从 0.6.0-internal.35 到 0.6.0-internal.36 的变化

- macOS 文件页增加 Devices 栏。用户可以配对设备、发送文件、启动接收并查看设备信息。
- iOS 宿主提供 Pair、Send、Receive 和 Devices 页面。
- Windows Compose host 从 `release/release-manifest.json` 读取版本。Devices 页面显示同一 `clientVersion`。
- 配对使用二维码和两端确认码。设备身份保存在 Keychain 或 Credential Manager 支持的凭据仓库。
- 单文件传输提供中断、暂停、恢复、取消、校验和续传状态。
- 目录传输处理冲突、损坏清单、原子提交和路径安全。
- 统一 Release 同时校验 macOS、Windows 和 iOS 制品。任一端版本或 commit 不一致时，发布失败。
- 传输错误显示稳定错误码。存储不足、损坏分块、冲突目录和续传点错误有明确消息。

## 验证

- `bash scripts/test-all.sh`：通过。
- macOS XCTest：1113 个通过，3 个跳过，0 个失败。
- iOS Simulator XCTest：4 个通过，0 个失败。
- Rust core、Windows host、Windows Compose、安装事务和发布脚本：通过。
- macOS C ABI 启动和二维码生成：通过。
- Windows ↔ iOS、macOS ↔ Windows、macOS ↔ iOS 真机矩阵：发布前执行并补录。

## 安装

### macOS

1. 下载 `Covio-0.6.0-internal.36.pkg`。
2. 打开 PKG 并完成 1 次管理员授权。
3. PKG 完成 app、helper 和 updater 的事务安装。
4. 打开 `Covio.app`。
5. 打开设置，确认独立设置窗口和 Dock 图标。

### Windows

1. 下载 `Covio-0.6.0-internal.36-windows-x64-portable.zip` 或 `Covio-0.6.0-internal.36-windows-x64.msi`。
2. 解压 ZIP 后运行 `Covio.exe`，或打开 MSI。
3. 启动 Covio。
4. 打开 Devices，确认版本为 `0.6.0-internal.36`。

### iOS

1. 下载 `Covio-0.6.0-internal.36-ios-arm64.ipa`。
2. 使用 Apple Configurator 或 Xcode 的 Devices 窗口安装到已登记 iPhone。
3. 打开 Covio。
4. 打开 Devices，确认版本为 `0.6.0-internal.36`。

**警告：** 此构建使用本地签名。
macOS Gatekeeper 可能阻止此构建。
请到“隐私与安全性”允许应用，或清除隔离属性：

```sh
xattr -dr com.apple.quarantine /Applications/Covio.app
```

## 内测说明

- 使用测试 Mac 或测试 Windows 11 设备。
- 风扇控制会写入 SMC 值，并需要全局特权 helper。
- 首次打开风扇控制后检查 Liquid Glass、预设切换和节点拖动。
- 合盖保持会增加电池消耗。
- 自动更新仅使用 internal 渠道。
- 更新私钥不随 app、Release 或安装包分发。

## 本版不包含

- 离线模型 DMG。
- Developer ID 签名。
- Windows Authenticode 签名。
- Apple 公证。
- 公开分发。
- Intel 或 Universal 2 构建。
- App Store 构建。
