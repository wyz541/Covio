# Covio 0.0.1.7

Covio 0.0.1.7 是内测版。
此版本不用于公开分发。

## 系统要求

- macOS 26 或更高版本。
- Apple Silicon Mac（arm64）。

## 安装包

本版提供默认瘦身 DMG、事务安装 PKG 和 App ZIP。
默认包不包含模型权重。
模型在用户确认后下载、校验并登记。
本版不构建离线模型 DMG。

## 从 0.6.0 internal build 15 到 0.0.1.7 的变化

- 客户端版本改为纯数字四段格式。此版本显示为 `0.0.1.7`。
- 设置 > 通用 增加版本卡片。版本卡片显示渠道、构建号、Git 短 SHA 和 helper 协议。
- 产品版本 `0.6.0`、构建号 `17`、渠道、Git commit 和 helper 协议分别保存。
- 已安装 build 15 可以直接升级到 build 17。
- 事务安装会同时更新 app 和 helper。helper 协议升级到 `10`。
- 监控页的 Screen 卡片统一管理合盖系统策略、合盖显示模式、合盖时长上限和外接屏暂停。
- Power 卡片保留开盖状态下的空闲睡眠与安全护栏。
- 更新检查只接受稳定的四段纯数字版本。

## 验证

- `bash scripts/test-all.sh`：通过。
- Kotlin、设计合同、发布脚本和 macOS SwiftUI CI：通过。
- macOS XCTest：1004 个测试通过，3 个跳过。
- 亮色和深色真机截图：通过。
- build 15 旧 app、旧 helper 和 schema 1 安装记录迁移：通过。
- update checker 的四段版本排序和 internal tag 排除：通过。

## 安装

1. 打开 `Covio-0.0.1.7.dmg`。
2. 将 `Covio.app` 拖入 `Applications`。
3. 打开 `Covio.app`。
4. 打开 AI 功能并确认模型下载。

事务安装与升级使用 `Covio-0.0.1.7.pkg`。

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
