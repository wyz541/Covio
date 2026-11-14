# GitHub 参考实现与全局选型

> 结论：全局最优方案是“Focus Filter 事件桥 + 单个生成式 helper Shortcut + 可选 Full Disk Access + 安全降级”。

## 文档状态

| 项目 | 内容 |
| --- | --- |
| 文档版本 | `1.0` |
| 状态 | 可评审 |
| 日期 | `2026-10-24` |
| 关联 issue | [#342](https://github.com/wyz541/kmp-Covio/issues/342) |
| 关联 PR | [#344](https://github.com/wyz541/kmp-Covio/pull/344) |
| 许可证边界 | Covio 使用 MIT。GPL 和 AGPL 代码只能参考架构，不能复制。 |

## 1. 筛选方法

GitHub 候选项目按七项事实筛选。

1. 与 macOS Focus 或桌面配置直接相关。
2. 最近 12 个月有提交。
3. 有明确许可证。
4. 有发布记录或位于成熟仓库。
5. 源码可核验。
6. 不依赖失效的 DND 私有偏好。
7. 行为能映射到 Covio 的安全边界。

星标数只作辅助信号。
星标数不作为唯一成熟度标准。
仓库级成熟度不等于子项目成熟度。

## 2. 候选仓库

| 仓库 | 星标 | 许可证 | 最近发布或提交 | 直接价值 | 成熟度判断 |
| --- | --- | --- | --- | --- | --- |
| `raycast/extensions`：`focus-modes` | 仓库 7,805 | MIT | Focus 扩展首次提交 2026-10-09 | 生成单个 helper Shortcut 控制全部 Focus | 仓库成熟；扩展较新 |
| `thaw-app/Thaw` | 12,267 | GPL-3.0 | 2.1.0，2026-10-14 | Focus Filter 映射配置档案并通知主应用 | 高 |
| `home-assistant/iOS` | 2,385 | Apache-2.0 | 2026.10.1，2026-10-10 | Focus Filter 上报 Focus 名称；状态接口只返回布尔值 | 高 |
| `Lospi/OuterSpaces` | 98 | GPL-3.0 | 2.1.0，2026-05-25 | 公共 `SetFocusFilterIntent` 直接应用空间和 Stage Manager 配置 | 中 |
| `cshariq/Sapphire` | 368 | AGPL-3.0 | 3.5，2026-10-15 | 读取 DND 私有数据库并监控变更 | 中高 |
| `Hammerspoon/hammerspoon` | 16,323 | MIT | 1.1.1，2026-02-26 | 成熟的 Shortcuts 与应用自动化模块 | 高 |
| `sindresorhus/do-not-disturb` | 223 | MIT | 已归档；最后版本 2022 | 旧版 DND 控制 | 不采用 |

## 3. Raycast Focus Modes

### 3.1 核验版本

- 仓库：`raycast/extensions`
- 固定提交：`1a0ef1d91a7d2b1ce55ee8cd2323d98bcfb1f5ac`
- 目录：[focus-modes](https://github.com/raycast/extensions/tree/1a0ef1d91a7d2b1ce55ee8cd2323d98bcfb1f5ac/extensions/focus-modes)
- 许可证：[MIT](https://github.com/raycast/extensions/blob/1a0ef1d91a7d2b1ce55ee8cd2323d98bcfb1f5ac/LICENSE)
- 首次提交：2026-10-09

### 3.2 方案

Raycast 使用单个生成式 helper Shortcut。
Covio 可复用这个核心结构。

1. 应用从 Focus 数据库读取 Focus ID、名称、图标和状态。
2. 应用按全部 Focus 生成一个 helper Shortcut。
3. helper 输入是 Focus ID，或 `off:<Focus ID>`。
4. 当前 `Set Focus` 动作不能接收变量，因此 helper 为每个 Focus 写入开关分支。
5. helper 签名后打开 Shortcuts。
6. 用户点击一次“Add Shortcut”。
7. 应用只记录并运行自己生成的 helper ID。
8. helper 更新后先运行新副本；旧副本只作兼容回退。
9. 应用等待 Focus 状态回读后才显示成功。

关键源码：

- [focus-state.ts](https://github.com/raycast/extensions/blob/1a0ef1d91a7d2b1ce55ee8cd2323d98bcfb1f5ac/extensions/focus-modes/src/focus-state.ts)
- [helper-shortcut.ts](https://github.com/raycast/extensions/blob/1a0ef1d91a7d2b1ce55ee8cd2323d98bcfb1f5ac/extensions/focus-modes/src/helper-shortcut.ts)
- [focus.ts](https://github.com/raycast/extensions/blob/1a0ef1d91a7d2b1ce55ee8cd2323d98bcfb1f5ac/extensions/focus-modes/src/focus.ts)
- [tests](https://github.com/raycast/extensions/tree/1a0ef1d91a7d2b1ce55ee8cd2323d98bcfb1f5ac/extensions/focus-modes/tests)

### 3.3 优点

1. 用户只需安装一个 helper。
2. 自定义 Focus 也能覆盖。
3. helper 按 ID 运行，名称变化不会误触发。
4. 只信任应用自己记录的 helper。
5. 有单元测试覆盖分支生成、ID 解析和回读逻辑。
6. 状态回读避免“命令成功但 Focus 未变”。

### 3.4 限制

1. 需要 Full Disk Access 才能读取 Focus 数据库。
2. Focus 数据库格式没有公开兼容承诺。
3. helper 的 Shortcut 文件结构不是公开 API。
4. 每次新增 Focus 后需要重新导入 helper。
5. helper 签名依赖 Apple 服务。
6. Focus 扩展只上线 15 天，长期稳定性未知。
7. 数据库读取需要处理计划 Focus 和失效记录。

### 3.5 采用内容

1. 单个 helper Shortcut。
2. 按 Focus ID 开关。
3. 只信任 Covio 生成的 helper ID。
4. 运行后回读状态。
5. 数据库解析采用纯函数和固定 fixture 测试。
6. Full Disk Access 作为可选路径，不作为核心运行前置条件。

### 3.6 不采用内容

1. 不持续轮询私有数据库。
2. 不把 Full Disk Access 设为强制权限。
3. 不把数据库内容上传或写入日志。
4. 不复制未公开的 helper JSON 版本号。实现时按目标系统生成并验证。

## 4. Thaw

### 4.1 核验版本

- 仓库：`thaw-app/Thaw`
- 固定提交：`3e4347939fed1bd847d5e4baab6220b6102228ee`
- 许可证：GPL-3.0
- 最新版本：2.1.0，2026-10-14
- 星标：12,267

### 4.2 方案

Thaw 是成熟的菜单栏管理工具。
Thaw 用 Focus Filter 把 macOS Focus 映射到自身配置档案。

1. 应用提供 `SetFocusFilterIntent`。
2. 用户在系统 Focus 设置中选择 Thaw 档案。
3. Focus 开启时，Filter 写入档案 ID。
4. Filter 发布分布式通知。
5. 主应用接收通知并应用档案。
6. Focus 结束或切换时，Filter 清空档案 ID。
7. Focus Filter 和设备、Space、快捷键触发共用同一档案系统。
8. 档案通过 schema 默认值兼容旧版本。
9. 档案应用有测试覆盖和防重复机制。

关键源码：

- [FocusFilterIntent.swift](https://github.com/thaw-app/Thaw/blob/3e4347939fed1bd847d5e4baab6220b6102228ee/Thaw/Settings/Models/FocusFilterIntent.swift)
- [ProfileManager.swift](https://github.com/thaw-app/Thaw/blob/3e4347939fed1bd847d5e4baab6220b6102228ee/Thaw/Settings/Models/ProfileManager.swift)
- [Profile.swift](https://github.com/thaw-app/Thaw/blob/3e4347939fed1bd847d5e4baab6220b6102228ee/Thaw/Settings/Models/Profile.swift)
- [FocusFilterIntentTests.swift](https://github.com/thaw-app/Thaw/blob/3e4347939fed1bd847d5e4baab6220b6102228ee/ThawTests/Settings/Models/FocusFilterIntentTests.swift)

### 4.3 优点

1. 使用公开 `SetFocusFilterIntent`。
2. Focus 变化由系统推送，不需要轮询。
3. 用户可把任一系统 Focus 映射到任一 Covio 配置。
4. 配置档案包含持久化和版本兼容策略。
5. 通知事件和档案应用有测试。
6. 支持手动、Focus、设备等多种触发来源。

### 4.4 限制

1. GPL-3.0 代码不能复制进 MIT Covio。
2. 主应用必须能接收并应用事件。
3. Focus Filter 的后台执行行为需要 macOS 真机验证。
4. Filter 本身不负责启动 macOS Focus。
5. 多个触发源需要优先级和冲突处理。

### 4.5 采用内容

1. 公共 `SetFocusFilterIntent` 事件桥。
2. 系统 Focus 到 Covio 配置的显式映射。
3. 配置 schema 向后兼容。
4. 事件幂等和防重复应用。
5. 档案应用采用“捕获、应用、恢复、测试”的工程方法。

### 4.6 不采用内容

1. 不复制 GPL 代码。
2. 不把菜单栏布局这种产品专属逻辑带入 Covio。
3. 不让多个触发源无优先级地并发应用。

## 5. Home Assistant iOS

### 5.1 核验版本

- 仓库：`home-assistant/iOS`
- 固定提交：`772973042cafcad921c57f5759d2ae171836c904`
- 许可证：Apache-2.0
- 最新稳定版：2026.10.1，2026-10-10
- 星标：2,385

### 5.2 方案

Home Assistant 用 Focus Filter 上报用户选择的 Focus 名称。
应用同时保存最近一次开始和结束时间。

关键源码：

- [FocusNameFocusFilterAppIntent.swift](https://github.com/home-assistant/iOS/blob/772973042cafcad921c57f5759d2ae171836c904/Sources/App/Settings/Focus/FocusNameFocusFilterAppIntent.swift)
- [FocusStatusWrapper.swift](https://github.com/home-assistant/iOS/blob/772973042cafcad921c57f5759d2ae171836c904/Sources/Shared/Environment/FocusStatusWrapper.swift)

### 5.3 结论

1. `INFocusStatusCenter` 只提供布尔状态。
2. 精确 Focus 名称来自 Focus Filter 映射。
3. 非授权状态可能返回 `false`，不能当作“没有 Focus”的可靠证据。
4. iOS 端需要额外后台执行能力，Focus Filter 才能可靠运行。
5. macOS 的后台行为必须单独验证。

### 5.4 采用内容

1. Focus Filter 作为名称映射来源。
2. `INFocusStatusCenter` 只作辅助状态。
3. 保存开始和结束时间，处理乱序事件。

## 6. Outer Spaces

### 6.1 核验版本

- 仓库：`Lospi/OuterSpaces`
- 固定提交：`7edb63d0d86233e861a62385d8e80a7bf2da2774`
- 许可证：GPL-3.0
- 最新版本：2.1.0，2026-05-25
- 星标：98

### 6.2 方案

Outer Spaces 在 `SetFocusFilterIntent.perform()` 中直接应用 Space 和 Stage Manager 配置。
用户先在系统中把 Focus Filter 指向一个预设。

关键源码：

- [FocusFilter.swift](https://github.com/Lospi/OuterSpaces/blob/7edb63d0d86233e861a62385d8e80a7bf2da2774/Outer%20Spaces/System/Focus/FocusFilter.swift)
- [FocusStatusViewModel.swift](https://github.com/Lospi/OuterSpaces/blob/7edb63d0d86233e861a62385d8e80a7bf2da2774/Outer%20Spaces/ViewModel/FocusStatusViewModel.swift)

### 6.3 结论

1. Focus Filter 可以直接调用应用能力。
2. Focus Filter 可以映射预设，而不需要知道系统 Focus 名称。
3. 该项目需要 Accessibility 和 Automation 权限。
4. 项目规模较小，不能单独证明长期稳定性。
5. Focus Filter 的值可以是可选值；结束时需要安全处理空值。

### 6.4 采用内容

1. Focus Filter 映射到配置 ID。
2. `perform()` 必须用可选参数处理结束事件。
3. 事件处理失败不能破坏现有配置。

## 7. Sapphire

### 7.1 核验版本

- 仓库：`cshariq/Sapphire`
- 固定提交：`792f9b4ea3d556d7566fbc38592fe54e88d89dc0`
- 许可证：AGPL-3.0
- 最新版本：3.5，2026-10-15
- 星标：368

### 7.2 方案

Sapphire 读取 `Library/DoNotDisturb/DB`。
应用需要 Full Disk Access。
应用监听数据库目录变化并刷新当前 Focus。

关键源码：

- [FocusModeManager.swift](https://github.com/cshariq/Sapphire/blob/792f9b4ea3d556d7566fbc38592fe54e88d89dc0/Sapphire/Services/Miscellaneous/FocusModeManager.swift)
- [PermissionsManager.swift](https://github.com/cshariq/Sapphire/blob/792f9b4ea3d556d7566fbc38592fe54e88d89dc0/Sapphire/App/PermissionsManager.swift)

### 7.3 结论

1. 私有数据库能提供 Focus 名称和当前状态。
2. Full Disk Access 是读取数据库的必要权限。
3. 目录监听比定时轮询更省资源。
4. 私有 schema 和权限成本不适合作为首版核心。
5. AGPL 代码不能复制进 MIT Covio。

### 7.4 采用内容

1. 只读一次数据库用于首次模式发现。
2. 数据库变更时采用低频、显式刷新。
3. 文件不存在、权限被拒绝和 JSON 损坏分别返回错误。

### 7.5 不采用内容

1. 不用数据库作为唯一运行状态来源。
2. 不要求所有用户授予 Full Disk Access。
3. 不持续读取私有数据库。

## 8. Hammerspoon

### 8.1 核验版本

- 仓库：`Hammerspoon/hammerspoon`
- 固定提交：`23e387e2805a9890066366e0ac96c71b27f0cfd5`
- 许可证：MIT
- 最新版本：1.1.1，2026-02-26
- 星标：16,323

### 8.2 方案

Hammerspoon 将 Shortcuts 和应用控制拆成独立扩展模块。
核心只提供稳定原语，配置决定组合方式。

关键源码：

- [hs.shortcuts](https://github.com/Hammerspoon/hammerspoon/tree/23e387e2805a9890066366e0ac96c71b27f0cfd5/extensions/shortcuts)
- [hs.application](https://github.com/Hammerspoon/hammerspoon/tree/23e387e2805a9890066366e0ac96c71b27f0cfd5/extensions/application)

### 8.3 结论

1. Shortcuts 与应用控制应解耦。
2. 应用控制需要明确的 Bundle ID、启动等待和失败结果。
3. 配置层不应直接处理系统 API 细节。
4. Hammerspoon 是通用框架，不是 Focus 产品模板。
5. Covio 应采用能力分层，不引入 Lua 运行时。

## 9. 已归档项目

`sindresorhus/do-not-disturb` 有 223 星，许可证为 MIT。
仓库已归档，最后版本为 2022 年。
该方案只覆盖旧版 DND 开关。
该方案没有自定义 Focus、计划 Focus 和恢复模型。

结论：不采用。
链接：[sindresorhus/do-not-disturb](https://github.com/sindresorhus/do-not-disturb)。

## 10. 加权选型

### 10.1 评分规则

每个维度按 1 至 5 分评分。
加权分只用于工程比较，不是运行指标。

| 维度 | 权重 | 含义 |
| --- | --- | --- |
| 用户结果 | 30% | 是否覆盖五个模式和双向 Focus 同步 |
| 安全恢复 | 20% | 是否可回滚且不丢数据 |
| 权限隐私 | 15% | 权限范围和私有数据读取 |
| 兼容维护 | 15% | 公开接口、测试和系统升级风险 |
| 设置成本 | 10% | 用户完成配置的步骤 |
| 证据成熟度 | 10% | 仓库、测试和发布记录 |

### 10.2 候选方案

| 方案 | 用户结果 | 安全恢复 | 权限隐私 | 兼容维护 | 设置成本 | 证据成熟度 | 加权分 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 每个模式手工绑定 Shortcut | 3 | 5 | 5 | 4 | 2 | 3 | 3.75 |
| Raycast 式单个 helper | 4 | 4 | 2 | 3 | 5 | 4 | 3.65 |
| 只用 Focus Filter | 3 | 5 | 5 | 5 | 3 | 5 | 4.20 |
| helper + Focus Filter + 降级 | 5 | 5 | 3.5 | 4 | 4.5 | 4.5 | 4.53 |
| 私有 Focus 直接写入 | 5 | 2.5 | 2 | 1 | 5 | 1.5 | 3.10 |
| Control Center GUI 自动化 | 4 | 2 | 1 | 1 | 3 | 1.5 | 2.35 |

### 10.3 结论

最高分是“helper + Focus Filter + 降级”。

该方案同时覆盖两条路径。

1. 用户从 Covio 切换：生成式 helper 设置系统 Focus。
2. 用户从系统切换：Focus Filter 通知 Covio 应用对应配置。
3. 用户拒绝 Full Disk Access：保留 Focus Filter 映射和降级运行。
4. 用户授予 Full Disk Access：提供自动模式发现、单个 helper 安装和精确回读。

该方案成本最高。
但该方案覆盖最完整。
该方案把不可写系统能力留在 Shortcuts。
该方案把事件映射留在公开 AppIntents。
该方案把私有数据库限制为可选只读能力。

## 11. 最终取舍

### 11.1 采用

1. 单个生成式 `Covio Focus Router` Shortcut。
2. 公共 `Covio Focus Filter`。
3. Focus 到 Covio 配置的显式映射。
4. 可选 Full Disk Access。
5. 只读、缓存、低频的 Focus 模式发现。
6. Focus ID 白名单和 helper ID 信任列表。
7. 状态回读、幂等处理和恢复日志。
8. 无 Full Disk Access 时的明确降级路径。

### 11.2 不采用

1. 每模式手工创建两个 Shortcut。
2. 只用 Focus Filter 而无法从 Covio 发起切换。
3. 只用私有数据库轮询。
4. 直接写入私有 Focus 接口。
5. Control Center GUI 自动化。
6. 已归档 DND 工具的实现路径。
7. 复制 GPL 或 AGPL 项目代码。

## 12. 许可证和实现约束

1. Raycast 仓库和 Hammerspoon 使用 MIT，可参考并复用兼容代码。
2. Home Assistant 使用 Apache-2.0，复制代码时需保留许可和变更说明。
3. Thaw 和 Outer Spaces 使用 GPL-3.0，只能参考架构。
4. Sapphire 使用 AGPL-3.0，只能参考架构。
5. 已归档项目只能作为历史参考。
6. Covio 若复制 MIT 或 Apache-2.0 代码，必须记录来源和许可证。
7. 任何参考实现都必须按 Covio 的测试和恢复标准重新实现。

## 13. 关联文档

- [主题索引](README.md)
- [问题边界](context.md)
- [调研分析](investigation.md)
- [结论与限制](conclusion.md)
- [推荐方案](solution.md)
- [证据附录](evidence.md)
- [验证计划](validation/README.md)
