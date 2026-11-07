# Windows Hub triggers

Windows egui host 使用 Rust host 事件循环处理触发入口。

## 触发方式

- `Ctrl+Alt+T` 在应用失焦时打开或收起主窗口。
- 托盘图标左键打开或收起主窗口。
- 托盘图标右键打开菜单。
- 菜单项 `Show screenshots` 打开 Shelf。
- 菜单项 `Settings` 打开 Settings。
- 菜单项 `Quit Covio` 退出应用。
- 窗口有焦点时，`Ctrl+,` 打开 Settings，`Escape` 隐藏窗口。

## 触发表现

- 显示窗口时发送 `Visible(true)` 和 `Focus`。
- 隐藏窗口时发送 `Visible(false)`。
- 隐藏后 core、托盘和全局快捷键继续运行。
- 窗口内容由 egui 绘制。Windows 不绘制 macOS 挂帘外壳。
- 快捷键冲突时应用继续运行。Settings 显示冲突原因。
- `--window-smoke` 验证快捷键冲突不阻止应用启动。

## 平台差异

macOS 的双指下滑入口依赖 macOS 触摸板和系统手势事件。

Windows `winit` 和 egui 不提供等价的全局触摸板手势。

因此 Windows 使用 `Ctrl+Alt+T` 作为全局主入口。

## 范围

本实现不包含以下能力：

- Windows 睡眠和合盖控制。
- 剪贴板 paste stack 全局快捷键。
- selected-text capture 全局快捷键。
