# Case 1：只读能力探针

## 文档状态

| 项目 | 内容 |
| --- | --- |
| 案例编号 | Case 1 |
| 状态 | 部分通过 |
| 覆盖测试 | V01 至 V06 |
| 日期 | `2026-10-24` |
| 执行人 | agent |
| 复核人 | 待填写 |

探针只读取 SDK、工具帮助和当前会话状态。
探针没有修改 Focus、应用或电源设置。

## 1. 验证目标

1. 确认 Focus 状态接口存在。
2. 确认 SDK 没有公开 Focus setter。
3. 确认 Shortcuts CLI 可用。
4. 确认 `Set Focus` 动作存在。
5. 确认应用和电源公开接口存在。

## 2. 预检记录

| 项目 | 值 |
| --- | --- |
| 系统 | macOS 27.0.1 |
| 构建 | 26A434 |
| Xcode | 27.1 |
| SDK | MacOSX27.0 |
| 当前用户 Shortcut 数量 | 0 |
| 活动会话 | 普通用户会话 |

## 3. 测试前采集

| 项目 | 值 | 命令 |
| --- | --- | --- |
| Focus 授权 | `0`，未决定 | Swift 探针 |
| Focus 布尔状态 | `false` | Swift 探针 |
| Shortcut 列表 | 空，退出码 `0` | `shortcuts list` |

## 4. V01：SDK 提供 Focus 状态读取

前置：已安装 Xcode 27.1。

命令：

```sh
SDK=$(xcrun --sdk macosx --show-sdk-path)
sed -n '1,120p' "$SDK/System/Library/Frameworks/Intents.framework/Versions/A/Headers/INFocusStatusCenter.h"
```

预期结果：存在状态中心和授权方法。

实际结果：

```text
INFocusStatusCenter
INFocusStatusCenter.focusStatus
INFocusStatusCenter.requestAuthorization
INFocusStatus.isFocused
```

结论：公开接口可以读取 Focus 状态。
授权状态不影响接口存在。
错误码：无。
状态：通过。

## 5. V02：SDK 不提供公开 Focus 写入

前置：已安装 Xcode 27.1。

命令：

```sh
SDK=$(xcrun --sdk macosx --show-sdk-path)
grep -RInE 'setFocus|enableFocus|disableFocus' \
  "$SDK/System/Library/Frameworks/Intents.framework/Versions/A/Headers"
```

预期结果：没有公开 Focus setter。

实际结果：

```text
无匹配
```

结论：本次头文件检索没有发现公开 Focus 写入方法。
限制：私有接口不在公开 SDK 中。
错误码：无。
状态：通过。

## 6. V03：Shortcuts CLI 可运行

前置：Shortcuts 已安装。

命令：

```sh
shortcuts help
shortcuts help run
shortcuts list >/dev/null 2>&1
printf 'exit=%s\n' "$?"
```

预期结果：命令存在，列表命令返回成功。

实际结果：

```text
Subcommands: run, list, view, sign
shortcuts run <shortcut-name-or-identifier>
exit=0
stdout_line_count=0
```

结论：CLI 可用。
当前用户没有 Shortcut。
错误码：无。
状态：通过。

## 7. V04：Focus 状态授权和布尔结果

前置：用户未授予 Covio 或探针 Focus 状态权限。

命令：

```sh
xcrun swift -e 'import Intents; let c = INFocusStatusCenter.default; print("status=\(c.authorizationStatus.rawValue), focused=\(String(describing: c.focusStatus.isFocused))")'
```

预期结果：读取授权状态。未授权时不能依赖布尔值。

实际结果：

```text
status=0, focused=Optional(false)
```

结论：接口可调用。
结论：`false` 不能单独证明没有 Focus。
错误码：无。
状态：部分通过。

## 8. V05：`Set Focus` 动作存在

前置：Shortcuts 10.0 已安装。

命令：

```sh
plutil -convert xml1 -o - \
  /System/Library/PrivateFrameworks/WorkflowKit.framework/Versions/A/Resources/Localizable.loctable \
  | grep -i -C 1 -E 'Set Focus \(Action Name\)|Turn On|Turn Off|Returns the currently active Focus'
```

预期结果：动作名称和开关值存在。

实际结果：

```text
Set Focus (Action Name)
Turn On
Turn Off
Returns the currently active Focus.
```

结论：Shortcuts 可承载 Focus 开关。
错误码：无。
状态：通过。

## 9. V06：应用和电源公开接口存在

前置：已安装 Xcode 27.1。

命令：

```sh
SDK=$(xcrun --sdk macosx --show-sdk-path)
grep -nE 'openApplicationAtURL|setDesktopImageURL' \
  "$SDK/System/Library/Frameworks/AppKit.framework/Versions/C/Headers/NSWorkspace.h"
grep -nE 'hide;|unhide;|terminate;|forceTerminate;' \
  "$SDK/System/Library/Frameworks/AppKit.framework/Versions/C/Headers/NSRunningApplication.h"
grep -nE 'IOPMAssertionCreateWithName' \
  "$SDK/System/Library/Frameworks/IOKit.framework/Versions/A/Headers/pwr_mgt/IOPMLib.h"
```

预期结果：应用和电源接口存在。

实际结果：

```text
openApplicationAtURL
setDesktopImageURL
hide
unhide
terminate
forceTerminate
IOPMAssertionCreateWithName
```

结论：首版所需的应用和电源接口均为公开接口。
错误码：无。
状态：通过。

## 10. 结果汇总

| 测试 | 结果 |
| --- | --- |
| V01 | 通过 |
| V02 | 通过 |
| V03 | 通过 |
| V04 | 部分通过 |
| V05 | 通过 |
| V06 | 通过 |

只读能力边界已确认。
Focus 写入仍需真实 Shortcut 验证。

## 11. 清理记录

本案例没有系统写入。
没有创建 Shortcut。
没有创建 Focus。
没有残留探针进程。

## 12. 更新规则

1. Focus 授权变化时更新 V04。
2. Shortcut 数量变化时更新 V03。
3. SDK 升级后重跑 V01、V02 和 V06。
4. 结果变化时同步更新 [验证计划](README.md)。
5. 结论变化时同步更新 [证据附录](../evidence.md)。

## 13. 关联文档

- [主题索引](../README.md)
- [证据附录](../evidence.md)
- [验证目录](README.md)
- [Case 2](case-focus-profile-apply.md)
