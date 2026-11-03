# Covio 0.0.1.9

Covio 0.0.1.9 是内测版。
此版本不用于公开分发。

## 系统要求

- macOS 26 或更高版本。
- Apple Silicon Mac（arm64）。

## 安装包

本版提供默认瘦身 DMG、事务安装 PKG 和 App ZIP。
默认包不包含模型权重。
模型在用户确认后下载、校验并登记。
本版不构建离线模型 DMG。

## 从 0.0.1.8 到 0.0.1.9 的变化

<!-- TODO(release): 按用户可见的变化重写本节，然后删除本注释。 -->

- Add atomic updater installation pipeline（#573）
- Simplify the issue workflow（#572）
- Add automatic update controls to Settings（#570）
- Install the updater with the migration package（#569）
- Add the updater service and launcher（#568）
- Add signed update manifests（#567）
- Clarify the updater boundary（#566）
- Add the passwordless update ADR（#554）

## 验证

<!-- TODO(release): 填写本版的测试结果与真机验收，然后删除本注释。 -->

## 安装

1. 打开 `Covio-0.0.1.9.dmg`。
2. 将 `Covio.app` 拖入 `Applications`。
3. 打开 `Covio.app`。
4. 打开 AI 功能并确认模型下载。

事务安装与升级使用 `Covio-0.0.1.9.pkg`。

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
- 更新检查读取 GitHub Releases 页面。
- 更新检查忽略 pre-release。

## 本版不包含

- 离线模型 DMG。
- Developer ID 签名。
- Apple 公证。
- 公开分发。
- 自动安装更新。
- Intel 或 Universal 2 构建。
- App Store 构建。
