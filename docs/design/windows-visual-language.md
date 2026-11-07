# Windows egui visual language

Windows 使用 macOS 设计合同作为视觉基准。

egui 不复制 Liquid Glass 的底层材质。Windows 使用语义 surface、stroke、圆角、间距和阴影表达相同层级。

## 视觉令牌

| 概念 | Light | Dark |
| --- | --- | --- |
| Canvas | `#F2F2F7` | `#1C1C1E` |
| Chrome | `#F5F5F7` | `#2C2C2E` |
| Surface | `#FFFFFF` | `#2C2C2E` |
| Primary text | `#1D1D1F` | `#F5F5F7` |
| Secondary text | `#6E6E73` | `#AEAEB2` |
| Accent | `#007AFF` | `#0A84FF` |
| Separator | `#D1D1D6` | `#3A3A3C` |

这些值来自 `docs/covio-design-contract.json`。

## 字体

Windows 优先加载系统 `Segoe UI`。

`Segoe UI` 是 Windows 上最接近 macOS SF Pro 的系统字体。

如果字体不可用，egui 使用默认 proportional font。

## 形状和间距

- Card radius：16。
- Panel radius：22。
- Control radius：12。
- Page maximum width：1120。
- 标准外围留白：16。
- 标准 item spacing：8。

## 组件

- Toolbar 使用 chrome surface 和圆角 16。
- 卡片使用 surface、1 像素 separator stroke 和弱阴影。
- 主按钮使用 accent fill 和 white text。
- 次按钮使用 surface fill 和 separator stroke。
- 危险按钮使用 error text 和 error stroke。
- 未选导航保持透明。
- 选中导航使用 accent fill。
- 输入框使用 surface fill。

## 导航

- Home、Shelf、Clipboard、Workspace 和 Settings 使用同一导航模型。
- 每个导航项对应一个产品 surface。
- 选中态来自 `CovioTheme`。
- 键盘焦点使用 egui 的 focus stroke。

## 平台边界

- Windows 保留原生窗口行为和标题栏。
- Windows 不绘制 macOS traffic-light controls。
- Windows 不复制 Liquid Glass blur。
- Windows 不支持的能力继续显示 unavailable 状态。

## Home dashboard

Home 使用 Bento 卡片网格。

- 宽度大于等于 720 时使用 3 列。
- 宽度大于等于 480 时使用 2 列。
- 更窄窗口使用 1 列。
- Now、Battery、Transfer、Monitor、Recent screenshots 和 Quick actions 各有一张卡。
- Windows 不支持的数据显示 unavailable。Windows 不伪造 macOS 数据。
- 计数文案区分单数和复数。