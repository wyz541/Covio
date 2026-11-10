# Windows Credential Manager 合同验证记录

本案例尚未执行。测试重点是本机持久化、2560 字节上限、用户边界和 ENTERPRISE 迁移。

## 文档状态

| 项目 | 内容 |
| --- | --- |
| 状态 | 尚未执行 |
| 执行人 | 待填写 |
| 复核人 | 待填写 |
| 环境 | Windows 11 测试机 |
| 版本 | 待填写 |
| 主方案 | [主题索引](../README.md) |
| 证据附录 | [证据附录](../evidence.md) |
| 目录说明 | [验证目录](README.md) |

## 1. 验证目标

1. 验证 CRED_TYPE_GENERIC 往返。
2. 验证 CRED_PERSIST_LOCAL_MACHINE。
3. 验证 2560 字节边界。
4. 验证不同 Windows 用户之间的隔离。
5. 验证其他计算机不可读取凭据。
6. 验证登录会话缺失的错误映射。
7. 验证 UserConsentVerifier 只作为用户界面确认。
8. 验证 ENTERPRISE 到 LOCAL_MACHINE 的迁移。

## 2. 预检记录

| 项目 | 值 | 状态 |
| --- | --- | --- |
| Windows 版本 | 待填写 | 尚未执行 |
| Windows Build | 待填写 | 尚未执行 |
| 应用 commit | 待填写 | 尚未执行 |
| 测试用户 A | 待填写 | 尚未执行 |
| 测试用户 B | 待填写 | 尚未执行 |
| 测试机 B | 待填写 | 尚未执行 |
| Compose host | 未切换 | 尚未执行 |
| Credential Manager 测试入口 | 待实现 | 尚未执行 |
| Windows Hello 配置 | 待填写 | 尚未执行 |

## 3. 测试前采集

powershell -NoProfile -Command "Get-ComputerInfo | Select-Object WindowsProductName,WindowsVersion,OsBuildNumber"

git rev-parse HEAD

记录字段：

WindowsVersion:

WindowsBuild:

Commit:

UserA:

UserB:

TestMachineB:

UserConsentAvailable:

PersistDefault:

## 4. 验证步骤

### V12：Windows 通用凭据基础往返

前置：测试入口可用。使用唯一 TargetName，前缀为 Covio.Test。

请求：op credential.store 和 op credential.exists。

记录：

Start time:

End time:

TargetName:

Write result:

Read result:

Error code:

Result: PENDING

通过条件：写入、读取、替换和删除全部成功。

### V13：Windows LOCAL_MACHINE 持久化

前置：V12 通过。

请求：创建 LOCAL_MACHINE 测试凭据，注销并重新登录，再读取。

记录：

Start time:

End time:

Persist field:

Before logout:

After login:

Error code:

Result: PENDING

通过条件：注销后仍可读取，CredRead 返回 LOCAL_MACHINE。

### V14：Windows 2560 字节边界

前置：V12 通过。

请求：分别写入 2559、2560 和 2561 字节的合成秘密。

记录：

Start time:

End time:

2559 result:

2560 result:

2561 result:

Error code:

Result: PENDING

通过条件：2559 和 2560 成功，2561 返回 credential_capacity_exceeded 或 credential_invalid_argument。

### V15：Windows 用户隔离和跨机边界

前置：用户 A 和用户 B 存在，测试机 B 可用。

请求：用户 A 创建凭据。用户 B 和测试机 B 尝试读取。

记录：

Start time:

End time:

User B result:

Machine B result:

Observed error:

Error code:

Result: PENDING

通过条件：用户 B 和测试机 B 无法读取用户 A 的测试凭据。

### V16：Windows 登录会话不可用

前置：测试入口可以模拟无凭据集或网络登录会话。

请求：在无当前用户凭据集的会话中执行读取。

记录：

Start time:

End time:

Session type:

Native code:

Mapped code:

Result: PENDING

通过条件：返回 credential_backend_unavailable 或 credential_access_denied，不崩溃。

### V17：Windows UserConsentVerifier 映射

前置：Windows Hello 可用，测试窗口可显示。

请求：分别执行成功确认、用户取消和重试耗尽。

记录：

Start time:

End time:

Verified result:

Canceled result:

RetriesExhausted result:

Capability enforcement:

Error code:

Result: PENDING

通过条件：成功确认返回 Verified。取消和重试耗尽映射为用户动作。能力保持 OsUiOnly。

### V18：Windows ENTERPRISE 到 LOCAL_MACHINE 迁移

前置：测试入口可以创建 ENTERPRISE 测试项。

请求：执行两阶段迁移，并在删除旧项时模拟失败。

记录：

Start time:

End time:

Old Persist:

New Persist:

Readback:

Cleanup marker:

Error code:

Result: PENDING

通过条件：新项为 LOCAL_MACHINE，旧项删除失败时保留清理任务，回滚可读。

## 5. 结果汇总

当前无实际结果。等待 Windows 11 测试机和测试入口。

## 6. 清理记录

1. 删除所有 Covio.Test 前缀的测试凭据。
2. 确认用户 A 和用户 B 没有测试项残留。
3. 删除测试机 B 的迁移副本。
4. 清除测试日志中的诊断信息。
5. 确认没有测试根密钥残留。
6. 记录 cmdkey 或测试工具的清理结果。

清理结果：PENDING

## 7. 更新规则

执行测试后填写实际结果。
执行测试后更新 [验证目录](README.md)。
执行测试后更新 [证据附录](../evidence.md)。
结论变化时更新 [结论](../conclusion.md)。
接口变化时更新 [推荐方案](../solution.md)。

## 8. 关联文档

- [主题索引](../README.md)
- [证据附录](../evidence.md)
- [验证目录](README.md)
- [推荐方案](../solution.md)
