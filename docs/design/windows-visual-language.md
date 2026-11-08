# Windows egui visual language

Windows 以当前 macOS SwiftUI 实现作为唯一视觉基准。

取值来源是 `macosApp/src/Design/` 和对应 SwiftUI 组件。Windows 不使用第二份设计合同。

egui 不复制 Liquid Glass 的底层模糊。Windows 使用语义色、圆角、间距、描边和阴影表达相同层级。

## 颜色

| 概念 | Light | Dark |
| --- | --- | --- |
| Canvas | `#F2F2F7` | `#1C1C1E` |
| Surface | `#FFFFFF` | `#2C2C2E` |
| Material thin | `#FFFFFFB2` | `#1C1C1E7A` |
| Elevated | `#F7F7F9` | `#3A3A3C` |
| Primary text | `#1D1D1F` | `#F5F5F7` |
| Secondary text | `#6E6E73` | `#AEAEB2` |
| Accent | `#007AFF` | `#0A84FF` |
| Divider | `#D1D1D6` | `#3A3A3C` |

这些值与 `macosApp/src/Design/ContractTokens.swift` 相同。

## 字体和控件

- Windows 使用 `Segoe UI`。
- 正文字号为 13。
- 按钮和页签字号为 12。
- 辅助文字字号为 11。
- 控件圆角为 8。
- 卡片圆角为 16。
- 面板圆角为 22。

## Workbench 几何

- 窗口内容基准尺寸为 `960 × 880`。
- 面板内边距为 24。
- 内容列宽度为 912。
- 顶部栏高度为 46。
- 搜索框为 `190 × 30`。
- Home 按钮为 `52 × 30`。
- 每个工作区页签为 `72 × 30`。
- 页签间距为 4。
- 右侧动作宽度为 52。
- Bento 网格使用 4 列。
- 每行高度为 96。
- 网格间距为 12。
- 卡片内边距为 14。

默认 Bento 布局与 macOS 默认组件一致：

| 卡片 | 列跨度 | 行跨度 |
| --- | --- | --- |
| Now | 2 | 1 |
| Battery | 1 | 1 |
| Transfer | 2 | 1 |
| Quick actions | 1 | 2 |
| Recent screenshots | 2 | 2 |
| Monitor | 1 | 1 |

## Workbench 顶部栏

- 搜索框位于左端。
- Home 入口紧随搜索框。
- Shelf、Clipboard 和 Workspace 使用固定宽度页签。
- Settings 是对齐右侧的页面动作。
- Windows 不显示 `Covio` 品牌文字。
- Windows 不使用 `Hide` 文字按钮。原生窗口关闭按钮和 `Escape` 保持隐藏行为。
- 选中页签使用 Accent 胶囊。
- 未选中页签使用透明背景和次要文字色。

## Settings 几何

- 窗口内容基准尺寸为 `900 × 640`。
- 顶部工具栏高度为 54。
- 内容列最大宽度为 620。
- 分组圆角为 16。
- 设置行高度为 44。
- 开关大小为 `38 × 22`。
- 内容使用 macOS grouped form 结构。
- 分页使用图标和短标题。
- 搜索框位于工具栏右端。
- Windows 保留一个返回箭头。原因是 Windows 用同一窗口显示 Workbench 和 Settings。
- 设置项修改后自动保存。Windows 不显示 macOS 样式中不存在的 `Save changes` 按钮。

## 平台边界

- Windows 保留原生标题栏和窗口行为。
- Windows 不绘制 macOS traffic-light controls。
- Windows 不复制 Liquid Glass blur。
- Windows 不支持的能力显示 unavailable。
- Windows 不伪造 Battery、Transfer 或 Monitor 数据。

## 证据

- 视觉预览位于 `docs/design/previews/700-windows-macos-parity/`。
- UI 测试覆盖 Bento 尺寸、卡片跨度和 Settings 搜索。