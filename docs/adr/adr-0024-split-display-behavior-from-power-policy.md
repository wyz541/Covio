# ADR-0024：把显示行为从电源策略中拆开

- Status：accepted
- Kind：architecture
- Date：2026-10-28
- Supersedes：none
- Implements：#441
- 相关：#434、#542

## 背景

Power card 同时承载供电状态、睡眠租约、自动规则、合盖 Helper 和显示行为。
这种组织把“系统是否休眠”和“屏幕如何关闭”混在一个设置入口。
用户无法判断问题属于电源、屏幕还是合盖传感器。

现有 `PowerConfig` 已经保存三个显示相关字段：

1. `allowClosedLid`
2. `pauseClosedLidWithExternalDisplay`
3. `closedLidZeroBrightness`

直接删除这些字段会破坏旧配置兼容性。
因此需要独立持久化模型，同时保留运行时兼容镜像。

## 决策

1. `Monitor` 增加独立屏幕 card。
2. 屏幕 card 第一段显示状态、亮度和显示功耗。
3. 屏幕 card 第三段打开详情与持久化设置 popover。
4. 合盖屏幕行为由 `DisplayConfig` 保存。
5. `LidState` 只表示传感器输入，不保存用户意图。
6. `DisplayPolicy` 决定关屏、零亮度黑屏和显示链路行为。
7. `PowerRuntime` 执行系统睡眠断言、helper 租约和安全否决。
8. Power card 继续管理电池、温度、自动规则、合盖时长和历史。
9. 旧 `PowerConfig` 显示字段迁移到新 `DisplayConfig`。
10. `PowerConfig` 保留为运行时兼容镜像。
11. 新配置以 `DisplayConfig` 为权威来源。
12. 显示功耗只在存在可靠测量来源时显示。没有来源时显示“不可用”。
13. `DisplayConfig.closedLidPowerPolicy` 保存唯一的合盖电源条件。
14. 合盖策略只有睡眠、接通电源、使用电池和始终四种值。
15. 旧 `disableLidSleepInCharging`、`disableLidSleepOnBattery` 只作迁移输入和兼容镜像。
16. `lidSleepImmediateOnClose` 不再提供独立入口，并固定为开启。

## 后果

### 正面

- 用户能按结果选择电源或屏幕设置。
- 合盖屏幕设置不再占用 Power card 的视觉层级。
- 电源策略和显示策略可以独立测试。
- 旧配置可以无损读取。

### 负面

- 配置文件中同时存在新配置和兼容镜像。
- 写入显示设置时要同步两个模型。
- 屏幕 card 增加一个 Monitor 网格卡片。
- 自动合盖租约由 `PowerRuntime` 按当前电源状态申请或释放。

### 风险

- 两个配置模型可能漂移。缓解：写入集中到 `AppRuntime.applyClosedLidPolicy`，读取时以 `display` 为准。
- 策略字段与旧镜像可能漂移。缓解：`AppConfig.normalized()` 从策略重写全部旧镜像。
- 私有亮度接口可能失效。缓解：保留可用性检查、恢复记录和公开关屏回退。
- 显示器功耗没有可靠来源。缓解：显示“不可用”，不使用估算值。

## 备选方案

### 备选 1：继续全部放在 Power card

未采纳。屏幕行为和系统睡眠的职责不同。
用户难以从 Power card 找到显示设置。

### 备选 2：只移动 UI，不拆分配置

未采纳。UI 和持久化模型会继续混在一起。
后续难以独立演进显示行为。

### 备选 3：删除旧 PowerConfig 字段

未采纳。会破坏旧版本双向兼容。

## 未决事项

| 项目 | 状态 | 确认方法 |
| --- | --- | --- |
| 可靠的显示器功耗来源 | unknown | 如果找到稳定来源，再增加读数 |
| 外接屏 DDC 控制 | out of scope | 另开 issue |

## 参考

- [Issue #441](https://github.com/wyz541/kmp-Covio/issues/441)
- [ADR-0025：由 Screen card 统一管理合盖策略](adr-0025-screen-card-owns-closed-lid-policy.md)
- [Power card popover #434](https://github.com/wyz541/kmp-Covio/issues/434)
- [ADR-0011：用持久化意图与租约统一电源 Engine](adr-0011-power-engine-policy.md)
- [ADR-0022：默认开启实验性合盖黑屏](adr-0022-default-experimental-black-screen.md)
