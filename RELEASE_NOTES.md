# Covio 0.6.0（内测 build 15）

Covio 0.6.0 是内测版。
此版本不用于公开分发。

## 系统要求

- macOS 26 或更高版本。
- Apple Silicon Mac（arm64）。

## 安装包

本版提供默认瘦身 DMG、事务安装 PKG 和 App ZIP。
默认包不包含模型权重。
模型在用户确认后下载、校验并登记。
本版不构建离线模型 DMG。

## 从 build 14 到 build 15 的变化

### 风扇控制

- 电池温度控制点的百分比滑杆松手后保留新值。
- 滑杆、数字输入和每台风扇目标 RPM 保持同步。
- 风扇百分比按每台风扇的最高 RPM 计算。
- 风扇卡片采用 Monitor 卡片的数值环、趋势和摘要样式。
- 高级设置默认展开。

### Monitor 与工作台

- 屏幕卡片采用 Monitor 卡片的统一样式。
- 工作台导航使用原生 Liquid Glass 表面。
- 导航切换时页签栏不再位移。
- 删除重复的工作台页标题。

## 验证

- Kotlin 共享测试在 JVM 和 macOS Arm64 上通过。
- macOS XCTest：`994` 项通过，`3` 项跳过，`0` 项失败。
- `bash scripts/test-all.sh` 通过。
- GitHub Actions：Contract and scripts、Kotlin、macOS SwiftUI 全部通过。
- 电池温度滑杆在真机亮色和深色界面完成 Before/After 验证。
- 事务 PKG 在本机安装成功。
- `/Applications/Covio.app` 与 helper 的 release identity 一致。
- 本机正式 App 启动成功。

## 安装

1. 打开 `Covio-0.6.0.dmg`。
2. 将 `Covio.app` 拖入 `Applications`。
3. 打开 `Covio.app`。
4. 打开 AI 功能并确认模型下载。

事务安装与升级使用 `Covio-0.6.0.pkg`。

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
