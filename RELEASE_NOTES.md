# Covio 0.6.0-internal.33

Covio 0.6.0-internal.33 是内测版。
本版改进 macOS 启动路径、空闲资源和 Hub 首次打开速度。
本版缩小 macOS 发布包，并增加可重复的跨平台性能门禁。
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
如果你当前运行 `.26` 或 `.27`，请手动安装 `.33` PKG 一次。
运行 `.28` 到 `.32` 时，可以使用自动更新升级到 `.33`。
事务安装 PKG 最多请求 1 次管理员授权。

## 从 0.6.0-internal.32 到 0.6.0-internal.33 的变化

- 菜单栏入口先出现，再启动唤醒日志扫描（#669）。
- 唤醒日志流式进入 Rust parser，减少启动等待和内存峰值（#671）。
- macOS 启动和空闲资源开销降低（#675）。
- macOS Hub 首次打开不再承担视图首次构建成本（#679）。
- macOS Release 包移除本地符号，保留单独 dSYM（#673）。
- 性能门禁覆盖 macOS 双版本对比和 Windows x64 单产品测量（#672、#677）。

在 #678 的 10 轮 macOS 门禁中，Hub 窗口可见时间比 KMP 基线快 `1.49%`。同一门禁中，warm launch 快 `4.22%`，进程树 RSS 低 `53.01%`，私有足迹低 `78.05%`，idle CPU 低 `32.09%`。

## 验证

- `bash scripts/test-all.sh`：通过。
- macOS XCTest：执行 1,093 个测试，3 个跳过，0 个失败。
- macOS 真机：`MacBookPro18,2`、macOS `27.0.1 (26A434)`、arm64、AC 电源。
- #678 交互和资源门禁：两个产品均为 `10/10` 样本，门禁通过。
- Windows x64 CI：构建当前用户安装包，并验证 clean install、upgrade、crash recovery、rollback 和 uninstall。

## 安装

### macOS

1. 下载 `Covio-0.6.0-internal.33.pkg`。
2. 打开 PKG 并完成 1 次管理员授权。
3. PKG 完成 app、helper 和 updater 的事务安装。
4. 打开 `Covio.app`。
5. 打开设置，确认独立设置窗口和 Dock 图标。

### Windows

1. 下载 `Covio-0.6.0-internal.33-windows-x64-setup.exe`。
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
