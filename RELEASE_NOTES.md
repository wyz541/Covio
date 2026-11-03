# Covio 0.0.2.1

Covio 0.0.2.1 是内测版。
此版本更新风扇控制和 Liquid Glass 界面。
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

## 从 0.0.2.0 到 0.0.2.1 的变化

- 风扇控制改为系统、安静、编译、持续和自定义五档策略。
- 两台风扇共用一条温度到风量百分比曲线。
- 用户可以拖动、增加和删除曲线节点，也可以通过滑杆精确调节。
- 图表同时显示预设风量、当前温度和当前实际风量。
- 内置预设支持覆盖和恢复默认控制点。
- 自定义预设和控制点会保存，并兼容旧版 RPM 曲线。
- 风扇卡片、Popover、策略选择、进度条和节点工具使用分层 Liquid Glass。
- 降低透明度或增强对比度时，内容面板改用不透明表面。
- 修正工作台外壳高度。

## 验证

- `bash scripts/test-all.sh`：通过。Kotlin 477 个测试通过；macOS XCTest 1066 个测试中 3 个跳过、0 个失败。
- GitHub Actions 的 Kotlin、Contract and scripts 检查：通过。
- 风扇卡片和浮层的亮色、深色、中文和英文布局检查：通过。
- 风扇控制专项测试：67 个测试通过。
- release 脚本会再次校验 app、helper、updater、安装包、摘要和发布身份。

## 安装

1. 下载 `Covio-0.0.2.1.pkg`。
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
