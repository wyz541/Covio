# Monitor 屏幕卡片

## 文档状态

| 项目 | 内容 |
| --- | --- |
| 文档版本 | `1.5` |
| 状态 | 已实现；#523 真机视觉验收通过 |
| 日期 | `2026-11-01` |
| Issue | #441、#523 |
| 上游决策 | ADR-0024 |

## 目标

`Monitor` 页签提供独立的屏幕 card。
用户可以先查看内建屏状态、亮度和显示功耗，再从第三段 popover 管理合盖屏幕行为。

Power card 继续管理电池、适配器、热状态、低电量模式、安全阈值和历史。
屏幕 card 不再把电源规则和显示行为混在同一个设置入口。

## 三段结构

| 段 | 内容 |
| --- | --- |
| 第一段 | 屏幕状态、亮度、显示功耗 |
| 第二段 | 外接屏数量、分辨率、刷新率 |
| 第三段 | “详情与设置”入口和 popover |

### 卡片视觉

屏幕卡片与其它 Monitor 卡片共用 `MonitorCardShell`。
第一段左侧使用亮度环。
第一段右侧显示屏幕状态和显示功耗。
摘要区复用 `MonitorDetailRows`。
卡片内部不使用带边框的亮度预览。
卡片内部不使用胶囊形指标块。
卡片内部不增加第二层内容卡。

## 数据口径

| 数据 | 来源 | 缺失行为 |
| --- | --- | --- |
| 屏幕状态 | `CoreGraphics` | 显示“未知” |
| 亮度 | 已验证的 `DisplayServices` 路径 | 显示“不可用” |
| 外接屏数量 | `ExternalDisplayReader` | 显示“不可用” |
| 分辨率与刷新率 | `CGDisplayMode` | 显示“不可用” |
| 显示功耗 | 可靠的单屏功耗源 | 显示“不可用” |

当前没有可靠的公开显示功耗瓦数来源。
屏幕 card 不显示系统总功耗。
屏幕 card 不使用背光电流估算瓦数。

## Popover

popover 只承载第一段和第二段之外的动作与设置。
popover 不重复屏幕状态、亮度、显示功耗、外接屏数量、分辨率和刷新率。

### 屏幕操作

- 立即关闭显示器。
- 打开 macOS 显示器设置。

### 合盖行为

合盖行为使用一个互斥菜单。

| 选项 | 行为 |
| --- | --- |
| 合盖时睡眠 | 不持有合盖租约，由 macOS 执行合盖睡眠 |
| 接通电源时保持运行 | 只在接通电源时持有合盖租约 |
| 使用电池时保持运行 | 只在使用电池时持有合盖租约 |
| 始终保持运行 | 任意已知电源状态都持有合盖租约 |

- 合盖时的屏幕使用一个互斥菜单。
- 有外接屏时暂停合盖保持唤醒使用一个开关。
- 合盖 Helper 显示安装、审批和修复状态。
- 零亮度失败时就地显示错误和公开关屏回退说明。
- `Settings > Lid` 不再保留重复开关。
- 选中电池路径时，卡片显示耗电警告。

### Popover 材质

- popover 外壳使用系统原生 regular Liquid Glass。
- 内容卡使用标准 thin material，不使用 Liquid Glass。
- 屏幕操作使用原生 GlassButtonStyle。
- 减少透明度或增强对比时，内容卡回退为不透明 surface。
- 多个操作按钮放入 `GlassEffectContainer`，保持系统合并与交互反馈。

| 模式 | 行为 |
| --- | --- |
| 关闭显示器 | 保持系统运行，显示器进入关闭状态 |
| 黑屏并保持显示链路 | 面板亮度为零；Covio 同时保持系统与显示器唤醒 |

黑屏模式在合盖后持有两个租约：合盖租约和系统加显示唤醒租约。
因此内建屏保持在线、活动、未睡眠。
Covio 不依赖 `caffeinate`、Sunshine 或其它外部工具保持显示器唤醒。
两个租约都受 `closedLidTimeCapMinutes` 限制。
开盖、策略切换、外接屏暂停、Helper 丢失或安全护栏会释放显示唤醒租约。
关闭显示器模式不额外阻止显示器睡眠。

## 持久化

屏幕设置保存在独立、版本化的 `DisplayConfig`。

| 字段 | 默认值 |
| --- | --- |
| `closedLidPowerPolicy` | 由旧合盖开关和电源条件迁移；默认为接通电源时保持运行 |
| `keepAwakeWhenLidClosed` | 兼容镜像；由 `closedLidPowerPolicy` 计算 |
| `closedLidDisplayMode` | 由旧 `PowerConfig.closedLidZeroBrightness` 迁移 |
| `pauseWhenExternalDisplayConnected` | 由旧 `PowerConfig.pauseClosedLidWithExternalDisplay` 迁移 |

`closedLidPowerPolicy` 是合盖保持条件的唯一持久化来源。
`PowerConfig` 和旧 `disableLidSleep*` 字段只保存兼容镜像。
`lidSleepImmediateOnClose` 固定为开启，不再提供独立开关。
屏幕 card 修改设置时，两处同步写入同一个配置事务。
旧配置缺少 `display` 键时，从 `power` 推导并保持当前行为。

## 交互与无障碍

- 点击 card 或第三段入口打开 popover。
- 按 Enter 或 Space 打开或关闭 popover。
- 合盖策略按电源状态自动申请和释放租约。
- 合盖策略被安全护栏否决时，界面显示原因。
- popover 打开期间，Hub 保持展开。
- 屏幕操作使用原生 `.glass` 按钮样式。
- 屏幕操作按钮至少有 44 点命中高度。
- 状态同时使用文字和图标。
- 减少透明度或增强对比时，内容卡使用不透明表面。
- macOS 继续负责主动锁屏、Wake 后的身份验证和密码策略。
- 黑屏合盖租约生效时，Covio 阻止空闲显示睡眠和自动空闲锁屏。
- Covio 不绕过密码。

## 异常

| 情况 | 行为 |
| --- | --- |
| 亮度读取失败 | 显示“不可用”，其它字段继续刷新 |
| 无内建屏 | 状态显示“离线” |
| 显示功耗无可靠来源 | 显示“不可用”和原因 |
| Helper 缺失 | 禁止申请合盖租约，显示安装入口 |
| Helper 待审批 | 显示打开系统设置入口 |
| 外接屏存在且暂停规则开启 | 合盖策略不能获得特权租约 |
| 零亮度失败 | 恢复原亮度，回退公开关屏，显示错误 |

## 视觉验收

### #523 当前视觉

屏幕卡片现在复用 Monitor 卡片的主数值环和摘要行。

| 亮色 | 深色 |
| --- | --- |
| ![Screen card light after](previews/523-monitor-screen-card-light-after-1.png) | ![Screen card dark after](previews/523-monitor-screen-card-dark-after-1.png) |

英文：

![Screen card English after](previews/523-monitor-screen-card-english-after-1.png)

### #441 历史证据

亮色：

![Screen card policy light](previews/441-screen-card-policy-light-after-5.png)

深色：

![Screen card policy dark](previews/441-screen-card-policy-dark-after-5.png)

英文：

![Screen card policy English](previews/441-screen-card-policy-english-after-5.png)

## 设计依据

- [Apple HIG: Materials](https://developer.apple.com/design/human-interface-guidelines/materials)：Liquid Glass 用于控制与导航层，内容层使用标准材质。
- [Apple HIG: Popovers](https://developer.apple.com/design/human-interface-guidelines/popovers)：popover 只承载少量相关任务，尺寸按内容收紧。
