# Covio 0.6.0-internal.32

Covio 0.6.0-internal.32 是内测版。
本版重写 macOS 设置界面。
本版增加 Dock 图标和聚焦入口。
Windows 和 macOS 继续使用 Rust core 与平台原生 UI。
macOS 使用 SwiftUI 和 AppKit。
Windows 使用 egui。
本版不用于公开分发。

## 系统要求

- macOS 26 或更高版本。
- Apple Silicon Mac（arm64）。
- Windows 11 x64。

## 安装包

本版同时提供 macOS 包和 Windows 安装包。
macOS 包含默认瘦身 DMG、事务安装 PKG 和 App ZIP。
Windows 包含当前用户安装的 x64 安装包。
默认包不包含模型权重。
模型在用户确认后下载、校验并登记。
本版不构建离线模型 DMG。

从 0.0.2.3 或更早版本升级时，请使用事务安装 PKG。
`0.6.0-internal.26` 和 `.27` 的更新服务可能一直显示忙碌。
如果你当前运行 `.26` 或 `.27`，请手动安装 `.32` PKG 一次。
运行 `.28` 到 `.31` 时，可以使用自动更新升级到 `.32`。
事务安装 PKG 最多请求 1 次管理员授权。

## 从 0.6.0-internal.31 到 0.6.0-internal.32 的变化

- 设置改为独立的 SwiftUI `Settings` 窗口（#655）。
- 设置窗口使用 macOS 原生工具栏、固定窗格和系统搜索框（#655）。
- 概览、电池、闲置、剪贴板和通用页面改为分组 `Form` 布局（#655）。
- Liquid Glass 只用于系统工具栏和系统控件，设置内容使用标准分组表面（#655）。
- Covio 显示 Dock 图标（#655）。
- 点击 Dock 图标会聚焦设置窗口或恢复工作台（#655）。
- 关闭设置窗口不会退出 Covio（#655）。

## 验证

- `bash scripts/test-all.sh`：通过。
- macOS XCTest：执行 1,086 个测试，3 个跳过，0 个失败。
- macOS 真机：macOS 27.0.1，arm64。
- #655 完成独立设置窗口、原生工具栏、搜索、Dock 聚焦和明暗模式截图验收。
- Windows CI 覆盖 Windows 11 ARM64、Windows 11 x64 和 x64 安装包流程。

## 安装

### macOS

1. 下载 `Covio-0.6.0-internal.32.pkg`。
2. 打开 PKG 并完成 1 次管理员授权。
3. PKG 完成 app、helper 和 updater 的事务安装。
4. 打开 `Covio.app`。
5. 打开设置，确认独立设置窗口和 Dock 图标。

### Windows

1. 下载 `Covio-0.6.0-internal.32-windows-x64-setup.exe`。
2. 运行安装包。
3. 安装到当前用户目录。
4. 从开始菜单启动 Covio。
5. 打开设置，确认自动更新状态和手动检查入口。

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
