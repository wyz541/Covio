# Covio 0.0.1.9

Covio 0.0.1.9 是内测版。
此版本是自动更新的迁移桥。
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

## 从 0.0.1.8 到 0.0.1.9 的变化

- 设置新增自动更新开关、手动检查、安装和重启状态。
- 首次安装迁移 PKG 会安装独立 root updater。
- 后续 internal 更新由 updater 下载、验证并安装。
- 更新覆盖 app、helper、updater engine 和安装记录。
- 更新失败时事务恢复旧组件。
- 自动更新只接受固定 internal Release 和签名 manifest。
- 普通自动更新不替换不可变 launcher 和 LaunchDaemon。
- 工作流文档改为精简的 Issue 和 PR 流程。

## 验证

- 自动更新 manifest 的签名、摘要、渠道、版本和 URL 校验：通过。
- app、helper 和 updater 的原子事务、握手失败回滚和 launcher 保留：通过。
- 设置页亮色和深色 Before/After 真机截图：通过。
- GitHub Actions 的 Contract、Kotlin 和 macOS SwiftUI：通过。
- `bash scripts/test-all.sh`：通过。
- 本版从 0.0.1.8 到 0.0.1.9 的迁移安装验收记录在 #563。
- 0.0.1.9 到 0.0.2.0 的无管理员更新验收记录在 #563。

## 安装

1. 下载 `Covio-0.0.1.9.pkg`。
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
