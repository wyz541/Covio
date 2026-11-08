# Windows Hub triggers

Windows egui host 使用 Rust host 事件循环处理触发入口。

## 触发方式

- `Ctrl+Alt+T` 在应用失焦时打开或收起主窗口。
- 鼠标进入任一显示器顶部 2 像素区域后，应用可打开 Workbench。
- 托盘图标左键打开或收起主窗口。
- 托盘图标右键打开菜单。
- 菜单项 `Show screenshots` 打开 Shelf。
- 菜单项 `Settings` 打开 Settings。
- 菜单项 `Quit Covio` 退出应用。
- 窗口有焦点时，`Ctrl+,` 打开 Settings，`Escape` 隐藏窗口。

## 顶部边缘触发

- 开关位于 Settings > Triggers。
- 开关默认关闭。
- 开关状态保存在 `%LOCALAPPDATA%\Covio\windows-ui.json`。
- 鼠标在任一显示器顶部 2 像素区域停留 180 ms 后触发。
- 触发显示 Workbench 时保留上次页面。
- 窗口已经显示时，顶部悬停不切换窗口。
- 显示后必须先离开顶部区域，才能再次触发。
- 触发后 700 ms 内禁止再次触发。
- 全局鼠标轮询间隔为 50 ms。
- 实现不安装低级鼠标钩子。

## 触发表现

- 显示窗口时发送 `Visible(true)` 和 `Focus`。
- 隐藏窗口时发送 `Visible(false)`。
- 隐藏后 core、托盘和全局快捷键继续运行。
- 窗口内容由 egui 绘制。Windows 不绘制 macOS 挂帘外壳。
- 快捷键冲突时应用继续运行。Settings 显示冲突原因。
- `--window-smoke` 验证快捷键冲突不阻止应用启动。

## 隐藏窗口轮询

Windows 隐藏窗口后，egui 不接收绘制更新。

因此，后台线程独立轮询全局鼠标位置。

后台线程命中顶部边缘后执行两个动作：

1. 显示原生窗口。
2. 唤醒 egui 更新。

UI 线程随后更新 HostModel。此顺序保证页面状态只在 UI 线程修改。

本机启动也使用同一路径。`--background` 在第一帧隐藏原生窗口，避免登录启动显示空窗口。

## 平台差异

macOS 的 `Option` + 双指下滑入口依赖 macOS 触摸板和系统手势事件。

Windows `winit` 和 egui 不提供等价的全局触摸板手势。

因此 Windows 使用以下主入口：

- `Ctrl+Alt+T`。
- 托盘图标。
- 可选的顶部边缘触发。

## 范围

本实现不包含以下能力：

- Windows 睡眠和合盖控制。
- 剪贴板 paste stack 全局快捷键。
- selected-text capture 全局快捷键。
