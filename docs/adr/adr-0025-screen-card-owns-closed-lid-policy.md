# ADR-0025：由 Screen card 统一管理合盖策略

- Status：accepted
- Kind：architecture
- Date：2026-11-02
- Supersedes：none
- Implements：#542
- 相关：#539、#441、ADR-0024

## 背景

Monitor 同时提供 Power 和 Screen 两张卡片。
Power card 有开盖状态的保持唤醒设置。
Screen card 已经提供合盖系统策略和显示模式。

用户提出一个更清晰的责任边界：

- 开盖状态由 Power 管理。
- 合盖状态由 Screen 管理。

合盖后系统是否保持运行，与屏幕是否关闭或黑屏，属于同一个用户任务。
用户问“合上后会发生什么”时，应在一个位置得到完整答案。

## 决策

1. Screen card 是合盖策略的唯一用户入口。
2. Screen card 同时管理合盖后的系统运行和屏幕显示。
3. Screen card 管理合盖时长上限、供电条件、外接屏暂停和黑屏模式。
4. Power card 只管理开盖状态下的空闲睡眠与自动保持唤醒。
5. Power card 保留安全护栏配置和电源历史。
6. Power card 不提供合盖策略、合盖时长上限或合盖显示模式。
7. Power 的手动保持唤醒会话只提供开盖状态模式。
8. Screen card 显示安全护栏暂停合盖保持唤醒的原因。
9. `DisplayConfig.closedLidPowerPolicy` 继续是合盖策略的权威持久化字段。
10. `PowerConfig` 中的合盖字段继续作为运行时兼容镜像。
11. `PowerRuntime` 继续执行系统断言和 helper 租约。
12. 运行时分权不改变用户入口的归属。
13. 任何新增的合盖能力都先归入 Screen card。

## 后果

### 正面

- 用户不需要跨卡片推导合盖结果。
- 系统状态和显示状态不会产生互相矛盾的独立开关。
- Power card 的开盖语义更清楚。
- 安全护栏暂停时，原因出现在当前合盖策略旁边。
- Screen card 可以继续承载黑屏链路和外接屏规则。

### 负面

- Screen card 的设置和错误状态会增加。
- Power card 与 Screen card 都会显示系统状态，需要明确谁拥有动作。
- 现有调试入口仍可能直接创建旧的合盖会话。

### 风险

- 两个卡片可能重复显示状态。缓解：Power 只显示结果，Screen 显示合盖控制。
- 安全护栏可能让用户以为策略丢失。缓解：保留用户选择，并显示“已暂停”原因。
- 旧配置镜像可能漂移。缓解：继续由 `AppConfig.normalized()` 和 `applyClosedLidPolicy` 统一同步。

## 备选方案

### 备选 1：Power 管理全部系统睡眠

未采纳。用户会把合盖系统运行和合盖显示视为同一个任务。
拆到两个卡片会增加优先级推导。

### 备选 2：Screen 只管理显示

未采纳。合盖系统运行与黑屏模式存在无效组合。
独立的系统与显示开关会增加错误状态。

## 参考

- [Discussion #539](https://github.com/wyz541/kmp-Covio/discussions/539)
- [Issue #542](https://github.com/wyz541/kmp-Covio/issues/542)
- [ADR-0024：把显示行为从电源策略中拆开](adr-0024-split-display-behavior-from-power-policy.md)
