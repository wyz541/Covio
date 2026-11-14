# 结论与限制

> 结论：全局最优方案是“Focus Filter 事件桥 + 单个生成式 helper Shortcut + 可选 Full Disk Access + 安全降级”。

## 1. 结论摘要

1. 提供 video、game、coding、work、study 五个内置模板。
2. 每个模板显式绑定一个 macOS Focus。
3. macOS Focus 是系统状态的唯一来源。
4. Covio 用 `SetFocusFilterIntent` 接收 Focus 激活、停用和切换。
5. Covio 用单个生成式 helper 从应用内切换 Focus。
6. helper 按 Focus ID 运行开启或关闭分支。
7. Covio 只运行自己生成并记录的 helper ID。
8. Full Disk Access 是可选权限，只用于模式发现和精确回读。
9. 用户拒绝 Full Disk Access 时仍可配置 Focus Filter。
10. 缺少 helper 时阻止 Covio 主动切换，不阻止系统 Focus 驱动。
11. 应用动作默认使用隐藏。
12. 请求退出是逐应用显式开关。
13. Covio 禁止强制退出应用。
14. 保持屏幕唤醒使用时限租约。
15. 首版不修改音量、亮度、网络、蓝牙、风扇和窗口布局。
16. 会话开始前写恢复日志。
17. 会话退出时按逆序恢复。
18. 恢复失败时保留日志并显示恢复入口。
19. 首版不申请 Accessibility 或 Screen Recording 权限。
20. GPL 和 AGPL 参考项目只采用架构，不复制代码。

## 2. 决策因素

### 2.1 主要因素

#### 2.1.1 Focus 写入边界

macOS SDK 公开读取 Focus 状态。
macOS SDK 不公开写入 Focus。
Shortcuts 提供 `Set Focus` 动作。
单个 helper 可以为全部 Focus 写入开关分支。

因此 Focus 写入交给 Shortcuts。
Covio 不模拟 Control Center。
Covio 不调用私有 Focus 写入框架。

证据链见 E-02 至 E-08、E-21、E-22。

#### 2.1.2 Focus 事件入口

`SetFocusFilterIntent` 是公开 AppIntent。
用户可以把系统 Focus 映射到应用配置。
Thaw、Home Assistant 和 Outer Spaces 使用该路径。
该路径覆盖手动、计划和系统触发的 Focus 变化。

因此 Covio 使用 Focus Filter 作为事件入口。
Covio 不持续轮询私有数据库。

证据链见 E-23、E-24、E-25、E-29、E-30。

#### 2.1.3 数据丢失风险

退出应用会影响未保存数据。
隐藏应用不会关闭文档。
请求退出仍可能触发保存提示。
强制退出会跳过保存提示。

因此默认动作使用隐藏。
请求退出需要逐应用开启。
强制退出不提供。

证据链见 E-09、E-10。

#### 2.1.4 可恢复性

系统动作必须能撤销或明确标为外部动作。
Covio 能恢复睡眠断言、应用隐藏和本会话 Focus。
Covio 不能保证恢复用户 Shortcut 的任意副作用。

因此恢复日志必须在动作前写入。
外部动作必须在 UI 中说明。
退出时只在系统 Focus 仍属于本会话时恢复原 Focus。

证据链见 E-04、E-11、E-18。

### 2.2 次要因素

1. 单个 helper 比每个模式两个 Shortcut 更易用。
2. Focus Filter 让系统 Focus 成为单一事实来源。
3. 可选 Full Disk Access 能换取自动发现和精确回读。
4. 无 Full Disk Access 的降级路径能保护隐私选择。
5. 限时会话能降低电池和热风险。
6. 按当前电源策略增加租约，避免覆盖已有唤醒请求。

## 3. 参考仓库结论

完整比较见 [github-references.md](github-references.md)。

| 仓库 | 可借鉴部分 | 不采用部分 |
| --- | --- | --- |
| Raycast Focus Modes | 单个 helper、ID 信任、状态回读 | 强制 Full Disk Access、持续轮询 |
| Thaw | Focus Filter 到配置档案的事件桥 | GPL 代码、产品专属菜单栏逻辑 |
| Home Assistant | Focus Filter 映射精确名称 | 只靠布尔状态判断 |
| Outer Spaces | Filter 直接应用用户预设 | GPL 代码、高权限系统动作 |
| Sapphire | 可选只读数据库发现 | 强制 FDA、持续私有库监视 |
| Hammerspoon | Shortcuts 与应用能力分层 | Lua 运行时 |
| 已归档 DND 工具 | 历史参考 | 旧 DND 私有偏好路径 |

加权评分最高的是“helper + Focus Filter + 降级”。
评分表见 [github-references.md](github-references.md) 第 10 节。

## 4. 根因证据链

```text
问题：需要切换多种专注配置
  -> Apple Help：Focus 支持 Work、Gaming 和 Custom
  -> SDK：Focus 状态可读，写入未公开
  -> AppIntents：SetFocusFilterIntent 可接收系统 Focus 变化
  -> Shortcuts：提供 Set Focus 动作和 CLI
  -> Raycast：单个生成 helper 可覆盖全部 Focus
  -> Thaw：Focus Filter 可映射到配置档案
  -> Covio：已有 HoldLeaseManager 可管理多来源租约
  -> 决策：Focus Filter 管事件，helper 管切换，公开接口管动作
```

## 5. 决策表

| 决策 | 选择 | 原因 | 备选路径 |
| --- | --- | --- | --- |
| 模式集合 | video、game、coding、work、study | 覆盖用户示例和常见场景 | 允许复制为自定义模板 |
| 模板来源 | 内置模板可编辑 | 避免硬编码个人应用 | 固定不可改模板 |
| 系统状态来源 | macOS Focus | 避免 Covio 复制系统状态 | 只用应用内部模式 |
| 系统 Focus 事件 | `SetFocusFilterIntent` | 公开、事件驱动、可映射 | 轮询私有数据库 |
| Covio 主动切换 | 单个 helper Shortcut | 覆盖全部 Focus 且设置一次 | 每模式两个 Shortcut |
| helper 信任 | 只信任 Covio 生成的 ID | 防止运行同名替换项 | 按名称运行 |
| helper 状态回读 | 等待 Focus Filter 或数据库 | 避免假成功 | 只看退出码 |
| 模式发现 | 可选 Full Disk Access | 自动列出自定义 Focus | 手工逐个映射 |
| FDA 被拒绝 | Focus Filter 加降级运行 | 保留主要能力 | 完全禁用功能 |
| Focus 名称 | Focus Filter 映射 | `INFocusStatusCenter` 没有名称 | 私有数据库轮询 |
| Focus 状态 | Filter 事件为主，布尔值为辅 | 事件有序且可映射 | 每秒轮询 |
| 原 Focus 恢复 | 仅在目标 Focus 仍活动时恢复 | 避免覆盖用户后来的切换 | 无条件恢复 |
| 应用关闭 | 默认隐藏 | 降低数据丢失风险 | 直接请求退出 |
| 请求退出 | 逐应用显式开启 | 用户知道哪些应用可退出 | 全模板统一退出 |
| 强制退出 | 禁止 | 数据丢失风险高 | 无 |
| 保持唤醒 | 限时租约 | 降低电池和热风险 | 永久断言 |
| 唤醒所有者 | `HoldLeaseManager` 新来源 | 不覆盖已有规则 | 直接调用单断言端口 |
| 默认会话时长 | 2 小时 | 覆盖多数专注时段 | 用户修改 |
| 最大会话时长 | 8 小时 | 限制失控风险 | 用户延长 |
| 音量 | 不改 | 会影响视频和游戏播放 | 用户 Shortcut |
| 亮度 | 不改 | 公开接口不足 | 私有接口 |
| Wi-Fi | 不改 | 会中断网络和远程会话 | 用户 Shortcut |
| 蓝牙 | 不改 | 没有稳定公开写入接口 | 用户 Shortcut |
| 壁纸 | 后期可选 | 有公开接口，但恢复复杂 | 首版不做 |
| 窗口布局 | 不做 | 需要辅助功能权限且不稳定 | 用户 Shortcut |
| 恢复日志 | 动作前原子写入 | 支持崩溃恢复 | 只在内存记录 |
| 参考项目许可证 | 只复制 MIT 或 Apache-2.0 兼容代码 | Covio 使用 MIT | GPL 和 AGPL 仅参考 |

## 6. 不采用方案

| 方案 | 风险 | 不采用原因 |
| --- | --- | --- |
| 每个模式两个手工 Shortcut | 设置步骤多，映射容易漂移 | 用户成本高 |
| 只用 Focus Filter | 无法从 Covio 发起 Focus 切换 | 不满足主动切换 |
| 只用私有数据库轮询 | FDA、私有 schema、持续读取 | 隐私和兼容成本高 |
| Control Center GUI 自动化 | Accessibility 授权、菜单变化、焦点依赖 | 不稳定且权限成本高 |
| 私有 Focus 直接写入 | 无兼容承诺，可能触发审核问题 | 不可维护 |
| 模拟通知开关 | 无法完整覆盖 Focus 过滤和允许列表 | 与系统行为冲突 |
| 直接退出所有非允许应用 | 未保存文件可能丢失 | 风险不可接受 |
| 强制退出应用 | 数据丢失 | 禁止 |
| 修改全局音量 | 视频和游戏会被静音 | 动作语义错误 |
| 修改 Wi-Fi 或 VPN | 消息、同步和远程会话会中断 | 副作用过高 |
| 用常驻无限睡眠断言 | 电池耗尽、热风险和意外过夜 | 改用限时租约 |
| 复制 GPL 或 AGPL 实现 | 与 MIT 许可证冲突 | 仅参考架构 |

## 7. 系统限制

1. macOS 没有公开的 Focus 创建接口。
2. macOS 没有公开的 Focus 名称读取接口。
3. `INFocusStatusCenter` 只返回布尔状态。
4. `INFocusStatusCenter` 读取需要用户授权。
5. Focus Filter 需要用户逐个配置。
6. Focus Filter 的后台启动行为未验证。
7. helper 的文件结构没有公开文档。
8. Focus 数据库读取需要 Full Disk Access。
9. Focus 数据库没有公开兼容承诺。
10. 应用隐藏状态可能被应用自身改变。
11. 请求退出可能被保存提示阻止。
12. 用户主动睡眠不受空闲断言阻止。
13. 私有亮度接口没有兼容承诺。
14. 蓝牙开关没有稳定的公开写入接口。

## 8. 产品限制

1. 首版要求用户创建或选择系统 Focus。
2. 首版要求用户配置 Focus Filter。
3. Full Disk Access 可选，但自动切换需要它。
4. 首版没有自动切换窗口布局。
5. 首版没有自动调整亮度和音量。
6. 首版没有跨设备同步。
7. 首版没有自动写入 macOS Focus。
8. 首版没有 Mac App Store 分发方案。
9. 外部 Shortcut 的副作用由用户负责。
10. 应用退出后不会自动重启已关闭的应用。

## 9. 未决项

| 项目 | 现状 | 下一步 |
| --- | --- | --- |
| Focus Filter 后台执行 | 未验证 | 测试主应用运行和未运行两种状态 |
| helper 新版 schema | 参考实现可用 | 用固定 fixture 和真机验证 |
| 数据库版本变化 | 私有格式 | 版本门控、fixture 和失败降级 |
| macOS 26 行为 | 未验证 | 增加一台 macOS 26 真机 |
| 当前 Focus 名称 | 无公开接口 | 只从 Filter 映射或数据库读取 |
| 已开启其他 Focus | 可读取时可记录 | 设计冲突和恢复文案 |
| 默认唤醒时长 | 建议 2 小时 | 产品评审确认 |
| 会话恢复 UI | 建议显示恢复入口 | 设计合同阶段确认 |
| 降级模式文案 | 建议明确说明通知未静音 | 设计合同阶段确认 |
| Raycast MIT 代码复用范围 | 未决定 | 编码实现前做许可证审计 |

## 10. 已决项

| 项目 | 结论 |
| --- | --- |
| 是否使用私有 Focus 写入接口 | 不采用 |
| 是否使用 Control Center 自动化 | 不采用 |
| 是否强制退出应用 | 禁止 |
| 是否修改全局音量 | 首版不修改 |
| 是否修改亮度 | 首版不修改 |
| 是否保持系统永久唤醒 | 禁止 |
| 是否要求 Accessibility 权限 | 首版不要求 |
| 是否支持五个示例模式 | 支持 |
| 是否支持系统 Focus 触发 Covio | 支持 |
| 是否支持从 Covio 切换 Focus | 支持，需 helper |
| 是否支持单个 helper | 支持 |
| 是否强制 Full Disk Access | 不强制 |
| 是否允许外部 Shortcut | 支持，需警告 |
| 是否复制 GPL 或 AGPL 代码 | 不复制 |

## 11. 后续动作

1. 评审本报告、GitHub 参考分析和五个模板的动作清单。
2. 评审通过后编写 ADR。
3. ADR 通过后创建 Feature issue。
4. 按验证计划运行 Focus Filter、helper、应用恢复和崩溃恢复测试。
5. 批准后拆分子 issue，并逐项交付。
