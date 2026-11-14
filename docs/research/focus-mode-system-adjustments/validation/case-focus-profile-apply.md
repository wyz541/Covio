# Case 2：Focus Filter、helper 与恢复

## 文档状态

| 项目 | 内容 |
| --- | --- |
| 案例编号 | Case 2 |
| 状态 | 尚未执行 |
| 覆盖测试 | V07 至 V14 |
| 日期 | `2026-10-24` |
| 执行人 | 待填写 |
| 复核人 | 待填写 |

案例会修改 Focus、应用可见性、Full Disk Access 和睡眠断言。
执行前必须先取得用户确认。
执行前必须备份个人 Focus 和 Shortcut 配置。

## 1. 验证目标

1. 验证 Focus Filter 激活、停用和去重。
2. 验证单个 helper 的安装、运行和更新。
3. 验证应用隐藏、退出和恢复。
4. 验证 Focus 唤醒租约和释放。
5. 验证崩溃恢复。
6. 验证 Full Disk Access 被拒绝后的降级。

## 2. 预检记录

| 项目 | 值 | 状态 |
| --- | --- | --- |
| 系统版本 | 待填写 | 待执行 |
| 电源状态 | 待填写 | 待执行 |
| 当前 Focus | 待填写 | 待执行 |
| Focus 数据库权限 | 待填写 | 待执行 |
| helper ID | 待填写 | 待执行 |
| 测试文档 | 待填写 | 待执行 |

## 3. 测试前采集

命令：

```sh
sw_vers
pmset -g assertions
shortcuts list --show-identifiers
test -r "$HOME/Library/DoNotDisturb/DB/ModeConfigurations.json"; echo "focus_db_read=$?"
```

记录字段：

```text
System:
Assertions:
Shortcut count:
Focus database readable:
Current Focus:
```

## 4. V07：Focus Filter 激活、停用和去重

前置：Covio 已实现 Focus Filter。

用户操作：

1. 打开“系统设置 > 专注模式”。
2. 新建自定义 Focus，名称为 `Covio Test Focus`。
3. 添加 Covio Focus Filter。
4. 将 Filter 映射到 `Covio Test Study` 模板。
5. 从 Control Center 开启 `Covio Test Focus`。
6. 从 Control Center 关闭 `Covio Test Focus`。

请求模板：

```json
{
  "request_id": "v07-filter",
  "event_id": "event-v07-001",
  "profile_id": "test-study",
  "source": "focus_filter",
  "allow_degraded": false
}
```

预期结果：

1. 激活事件启动一次会话。
2. 停用事件结束同一会话。
3. 重复事件返回 `focus_event_duplicate`。
4. 旧事件返回 `focus_event_stale`。
5. 应用运行和未运行两种状态都有明确结果。

记录：

```text
Start time:
End time:
Activation event:
Deactivation event:
Duplicate event:
Stale event:
App running:
App not running:
Error code:
Result: PENDING
```

通过条件：激活、停用和去重符合状态机。

## 5. V08：单个 helper 安装和按 ID 运行

前置：用户授予 Covio 读取 Focus 模式的权限。

用户操作：

1. 在 Covio 中建立测试 Focus 绑定。
2. 点击生成 helper。
3. 在 Shortcuts 中完成导入。
4. 返回 Covio 确认 helper ID。

命令：

```sh
shortcuts list --show-identifiers | grep -i 'Covio Test'
```

应用内步骤：

1. 从 Covio 运行 helper 的开启输入。
2. 从 Covio 运行 helper 的关闭输入。
3. 确认 Covio 使用 helper ID，不使用显示名称。
4. 把另一个 Shortcut 改成相同显示名称。
5. 再次运行并确认没有调用替换项。

预期结果：

1. helper 包含全部已绑定 Focus。
2. Covio 记录 helper ID。
3. helper 返回 `ok` 或 `unknown`。
4. 同名替换项不会被执行。

记录：

```text
Start time:
End time:
Trusted helper ID:
Install target:
On result:
Off result:
Name collision result:
Error code:
Result: PENDING
```

通过条件：helper 按 ID 运行，且覆盖全部绑定 Focus。

## 6. V09：应用隐藏、退出和恢复

前置：只使用可丢弃的 TextEdit 文档。

命令模板：

```sh
open -a TextEdit
```

应用动作：

1. 记录 TextEdit 的可见状态。
2. 启动测试配置。
3. 让配置隐藏 TextEdit。
4. 确认 TextEdit 隐藏。
5. 停止测试配置。
6. 确认 TextEdit 恢复可见。
7. 对未保存文档重复请求退出。
8. 确认出现保存提示。
9. 取消退出并确认应用继续运行。

预期结果：

1. 隐藏状态可恢复。
2. 原本隐藏的应用不被取消隐藏。
3. 取消退出不会触发强制退出。
4. 应用继续运行。

记录：

```text
Start time:
End time:
Before visibility:
During visibility:
After visibility:
Quit prompt:
Cancelled state:
Error code:
Result: PENDING
```

通过条件：应用可见状态和取消退出行为符合规则。

## 7. V10：Focus 唤醒租约和释放

前置：实现 Focus 租约来源。

请求模板：

```json
{
  "request_id": "v10-start",
  "op": "focus.session.start",
  "args": {
    "profile_id": "test-coding",
    "duration_seconds": 120,
    "dry_run": false,
    "allow_degraded": false
  }
}
```

预期结果：

1. 会话进入 `active`。
2. `pmset -g assertions` 显示 Covio 的保持唤醒断言。
3. 停止后断言消失。

记录：

```text
Start time:
End time:
Start response:
Assertion before stop:
Assertion after stop:
Error code:
Result: PENDING
```

通过条件：断言创建和释放都能回读。

## 8. V11：崩溃恢复

前置：测试配置已经启动。

步骤：

1. 启动测试配置。
2. 确认恢复日志存在。
3. 终止 Covio 进程。
4. 重新启动 Covio。
5. 检查残留会话提示。
6. 执行恢复。
7. 检查应用、Focus 和断言状态。

预期结果：

1. 重启后发现残留会话。
2. 用户能看到恢复入口。
3. 恢复后应用可见状态正确。
4. 恢复后没有 Focus 租约。
5. 恢复失败时日志保留。

记录：

```text
Start time:
End time:
Journal before restart:
Recovery prompt:
Recovery result:
Journal after recovery:
Error code:
Result: PENDING
```

通过条件：会话可被发现和恢复。

## 9. V12：Full Disk Access 模式发现

前置：用户明确同意读取 Focus 数据库。

步骤：

1. 撤销 Covio 的 Full Disk Access。
2. 运行模式发现。
3. 确认返回 `full_disk_access_denied`。
4. 授予 Covio Full Disk Access。
5. 重新运行模式发现。
6. 确认只读取允许字段。
7. 检查日志没有数据库原文。

预期结果：

1. 拒绝权限时返回明确错误。
2. 授予权限后能列出 Focus 名称和 ID。
3. 数据库缺失和 JSON 损坏有独立结果。
4. 日志不包含通知、消息或文档内容。

记录：

```text
Start time:
End time:
Before grant:
After grant:
Detected modes:
Database error:
Log check:
Error code:
Result: PENDING
```

通过条件：权限和错误路径均可复现。

## 10. V13：helper 新增 Focus 后更新

前置：现有 helper 不包含新 Focus。

步骤：

1. 记录当前 helper ID。
2. 新建 `Covio Test Focus 2`。
3. 让 Covio 检测 helper 覆盖缺口。
4. 生成新 helper。
5. 取消一次导入。
6. 确认旧 helper 仍在信任列表。
7. 再次生成并完成导入。
8. 运行新 Focus 的开启和关闭。

预期结果：

1. 覆盖缺口返回 `helper_update_required`。
2. 取消导入不删除旧 helper。
3. 新 helper 成功后才登记新 ID。
4. 新 Focus 可以开启和关闭。

记录：

```text
Start time:
End time:
Old helper ID:
Cancel result:
New helper ID:
New focus on:
New focus off:
Error code:
Result: PENDING
```

通过条件：helper 更新无损且可回滚。

## 11. V14：拒绝 Full Disk Access 的降级

前置：Covio 没有 Full Disk Access。

步骤：

1. 在系统 Focus 中配置 Covio Focus Filter。
2. 从 Control Center 开启测试 Focus。
3. 确认 Covio 应用模板动作。
4. 从 Covio 选择模板。
5. 确认界面说明无法主动切换 Focus。
6. 确认没有读取数据库。
7. 从 Control Center 关闭测试 Focus。

预期结果：

1. Focus Filter 路径仍可用。
2. Covio 主动切换返回 `full_disk_access_denied`。
3. UI 提供授予权限和降级入口。
4. 没有数据库读取和日志泄漏。

记录：

```text
Start time:
End time:
Filter-driven start:
Filter-driven stop:
Direct switch result:
UI message:
Database access:
Error code:
Result: PENDING
```

通过条件：隐私路径可用且边界清楚。

## 12. 错误码

| 错误码 | 记录位置 |
| --- | --- |
| `focus_event_duplicate` | V07 |
| `focus_event_stale` | V07 |
| `focus_filter_unavailable` | V07 |
| `helper_missing` | V08 |
| `helper_untrusted` | V08 |
| `helper_failed` | V08 |
| `helper_timeout` | V08 |
| `app_hide_failed` | V09 |
| `app_quit_cancelled` | V09 |
| `wake_lease_failed` | V10 |
| `restore_failed` | V11 |
| `journal_corrupt` | V11 |
| `full_disk_access_denied` | V12、V14 |
| `focus_database_changed` | V12 |
| `helper_update_required` | V13 |

## 13. 结果汇总

当前状态：尚未执行。

待验证项目：

1. Focus Filter。
2. helper。
3. 应用隐藏和退出。
4. Focus 租约。
5. 崩溃恢复。
6. Full Disk Access。
7. helper 更新。
8. 无 FDA 降级。

## 14. 清理记录

执行后填写。

1. 退出测试专注模式。
2. 删除 Covio Test Filter。
3. 删除生成的 helper。
4. 删除 `Covio Test Focus`。
5. 删除 `Covio Test Focus 2`。
6. 关闭测试文档，不保存。
7. 删除测试事件、配置和会话日志。
8. 撤销测试授予的 Full Disk Access。
9. 检查没有活动断言。

## 15. 更新规则

1. 每步完成后回填时间和实际结果。
2. 失败项写明错误码。
3. 结果变化时更新 [验证计划](README.md)。
4. 证据变化时更新 [证据附录](../evidence.md)。
5. 结论变化时更新 [结论与限制](../conclusion.md)。

## 16. 关联文档

- [主题索引](../README.md)
- [GitHub 参考实现](../github-references.md)
- [证据附录](../evidence.md)
- [验证目录](README.md)
- [Case 1](case-readonly-focus-probe.md)
