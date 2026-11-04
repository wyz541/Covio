# Covio 0.0.2.3

Covio 0.0.2.3 是内测版。
此版本修复应用菜单设置入口和首次 Updater 安装。
此版本包含风扇预设和 Liquid Glass 更新。
此版本不用于公开分发。

## 系统要求

- macOS 26 或更高版本。
- Apple Silicon Mac（arm64）。

## 安装包

本版提供默认瘦身 DMG、事务安装 PKG 和 App ZIP。
默认包不包含模型权重。
模型在用户确认后下载、校验并登记。
本版不构建离线模型 DMG。

从 0.0.1.8 升级时，请使用事务安装 PKG。
只安装 DMG 不会安装 root updater。
事务安装 PKG 最多请求 1 次管理员授权。

## 从 0.0.2.1 到 0.0.2.3 的变化

- `Covio > Settings…` 和 `⌘,` 打开工作台中的真实设置页。
- PKG 首次安装 Updater 时创建完整布局并启动服务。
- 安装事务清理上次失败遗留的 Updater 进程。
- Updater 不在 PKG 安装期间错误执行自动更新恢复。

## 验证

- `bash scripts/test-all.sh`：通过。Kotlin 477 个测试通过；macOS XCTest 1069 个测试中 3 个跳过、0 个失败。
- GitHub Actions 的 Kotlin、Contract and scripts 检查：通过。
- MacBookPro18,2、macOS 27.0.1：PKG 从 0.0.1.8 build 18 升级到 0.0.2.3 build 23。
- 真机确认 App、Helper、Updater engine 和 Launcher 的 release ID 一致。
- 真机确认 Updater Launcher 和 engine 正在运行，health release ID 与 current 指针一致。
- 真机确认 `Covio > Settings…` 打开真实工作台设置页。

## 安装

1. 下载 `Covio-0.0.2.3.pkg`。
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
