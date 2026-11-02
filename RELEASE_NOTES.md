# Covio 0.0.1.8

Covio 0.0.1.8 是内测版。
此版本不用于公开分发。

## 系统要求

- macOS 26 或更高版本。
- Apple Silicon Mac（arm64）。

## 安装包

本版提供默认瘦身 DMG、事务安装 PKG 和 App ZIP。
默认包不包含模型权重。
模型在用户确认后下载、校验并登记。
本版不构建离线模型 DMG。

## 从 0.0.1.7 到 0.0.1.8 的变化

- 工作台顶栏把搜索框移到首页入口左侧。
- 工作台导航不再显示助手和设置页签。
- 用户从菜单栏状态项打开设置。
- 助手成为设置分节。对话、本地模型和外部 Agent 服务使用同一入口。
- 发现新版本时，工作台右下角显示带版本号的更新入口。
- 用户点击更新入口后，Covio 执行手动检查。
- 旧工作台配置继续保留隐藏的助手和设置记录，升级不删除用户数据。

## 验证

- `bash scripts/test-all.sh`：通过。
- Kotlin：970 个测试通过。
- macOS XCTest：1012 个测试通过，3 个跳过。
- 发布脚本和设计合同校验：通过。
- GitHub Actions 的 Contract、Kotlin 和 macOS SwiftUI：通过。
- 亮色和深色真机截图：通过。
- 真机检查：搜索框在首页左侧，导航栏无助手和设置。
- 真机检查：设置包含助手分节。
- 真机检查：更新入口在工作台右下角，点击后执行更新检查。
- Release 资产验证和事务安装 PKG 安装验收：通过。

## 安装

1. 打开 `Covio-0.0.1.8.dmg`。
2. 将 `Covio.app` 拖入 `Applications`。
3. 打开 `Covio.app`。
4. 打开 AI 功能并确认模型下载。

事务安装与升级使用 `Covio-0.0.1.8.pkg`。

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
