# #700 Windows Workbench and Settings parity

## 验证信息

- 日期：2026-11-08。
- 设备：Maxsun 台式机，Intel Core i5-14600KF。
- 系统：Windows 11 Enterprise `10.0.26200`，x64。
- 显示器：两块 HKC `V2719Q`。
- 截图参数：`--ui-scale 1.0`。
- Workbench 逻辑尺寸：`960 × 880`。
- Settings 逻辑尺寸：`900 × 640`。
- 实现 commit：`7eb9d00`、`11e5ac0`、`1ccfa85`。
- Before 来源：#689 和 #692 的历史视觉证据。

## macOS 基准

- Workbench：`605-hub-home-dark-current-1.png`。
- Settings：`654-settings-window-overview-light-after-2.png`。
- Workbench 几何：`macosApp/src/Design/HubMetrics.swift`。
- Settings 结构：`macosApp/src/App/CovioSettingsView.swift`。

## Workbench Before

| Light | Dark |
| --- | --- |
| ![Workbench before light](before-workbench-light.png) | ![Workbench before dark](before-workbench-dark.png) |

## Workbench After

| Light | Dark |
| --- | --- |
| ![Workbench after light](after-workbench-light.png) | ![Workbench after dark](after-workbench-dark.png) |

## Settings Before

| Light | Dark |
| --- | --- |
| ![Settings before light](before-settings-overview-light.png) | ![Settings before dark](before-settings-overview-dark.png) |

## Settings After

### Overview

| Light | Dark |
| --- | --- |
| ![Overview light](after-settings-overview-light.png) | ![Overview dark](after-settings-overview-dark.png) |

### Appearance

| Light | Dark |
| --- | --- |
| ![Appearance light](after-settings-appearance-light.png) | ![Appearance dark](after-settings-appearance-dark.png) |

### Triggers

| Light | Dark |
| --- | --- |
| ![Triggers light](after-settings-triggers-light.png) | ![Triggers dark](after-settings-triggers-dark.png) |

### Capabilities

| Light | Dark |
| --- | --- |
| ![Capabilities light](after-settings-capabilities-light.png) | ![Capabilities dark](after-settings-capabilities-dark.png) |

### Updates

| Light | Dark |
| --- | --- |
| ![Updates light](after-settings-updates-light.png) | ![Updates dark](after-settings-updates-dark.png) |

## 验收结果

- Workbench 使用 macOS 顶栏顺序。搜索框、Home、工作区页签和右侧动作对齐。
- Workbench 使用 4 列 Bento 网格。
- Bento 行高为 96，间距为 12，卡片圆角为 16。
- 默认卡片跨度匹配 macOS。
- Settings 使用图标分页栏、搜索框和 grouped form。
- Settings 行高为 44，内容列最大宽度为 620。
- Settings 使用 macOS 风格开关。
- Light 和 Dark 使用 macOS Swift 令牌。
- Windows 不绘制 traffic-light controls。
- egui 不复制 Liquid Glass blur。颜色、圆角、间距和层级已对齐。
- Windows 不伪造 Battery、Transfer 和 Monitor 数据。
## 验证结果

- `cargo test -p covio-platform -p covio-windows --all-targets` 通过。
- `cargo clippy -p covio-platform -p covio-windows --all-targets -- -D warnings` 通过。
- `scripts/test-windows-rust.sh` 通过。
- `Ctrl+Alt+T` 在本机被其他应用占用。该冲突不阻止应用启动。