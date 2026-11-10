# Android Keystore 合同验证记录

本案例阻塞。当前仓库没有 Android 工程、测试包和真机环境。

## 文档状态

| 项目 | 内容 |
| --- | --- |
| 状态 | 阻塞 |
| 执行人 | 待填写 |
| 复核人 | 待填写 |
| 环境 | Android 后继测试环境 |
| 版本 | Android 目标版本待定 |
| 主方案 | [主题索引](../README.md) |
| 证据附录 | [证据附录](../evidence.md) |
| 目录说明 | [验证目录](README.md) |
| 阻塞条件 | 缺少 Android 工程和真机 |

## 1. 验证目标

1. 验证 Keystore 包装根密钥。
2. 验证认证绑定密钥。
3. 验证锁屏和生物登记导致的失效。
4. 验证 StrongBox 回退。
5. 验证 no-backup 和 D2D 排除。
6. 验证锁屏后台接收。
7. 验证 Android 15 的 unlocked-device 门槛。

## 2. 预检记录

| 项目 | 值 | 状态 |
| --- | --- | --- |
| Android 工程 | 不存在 | 阻塞 |
| Android 版本 | 待填写 | 阻塞 |
| 设备型号 | 待填写 | 阻塞 |
| 应用 commit | 待填写 | 阻塞 |
| StrongBox 支持 | 待填写 | 阻塞 |
| 生物认证配置 | 待填写 | 阻塞 |
| 测试包名 | 待填写 | 阻塞 |
| 测试别名 | 待填写 | 阻塞 |

## 3. 测试前采集

future Android test task: androidCredentialContractTest

记录字段：

AndroidVersion:

BuildFingerprint:

DeviceModel:

Commit:

StrongBoxSupported:

BiometricEnrolled:

SecureLockScreen:

## 4. 验证步骤

### V25：Android Keystore 包装往返

前置：Android 工程和测试包可用。

请求：生成后台 Keystore 密钥，包装根密钥，写入 no-backup 密文，再解包回读。

记录：

Start time:

End time:

Alias:

StrongBox result:

Wrap result:

Unwrap result:

Error code:

Result: PENDING

通过条件：包装和解包成功，明文根密钥不写入文件。

### V26：Android 认证和密钥失效

前置：测试设备有安全锁屏和生物认证。

请求：生成审批密钥，取消认证，错误认证，移除锁屏，再改变生物登记。

记录：

Start time:

End time:

Auth required:

User canceled:

Lock screen removed:

Biometric changed:

Error code:

Result: PENDING

通过条件：分别得到 credential_auth_required、credential_user_cancelled 和 credential_key_invalidated。

### V27：Android StrongBox 回退

前置：准备支持和不支持 StrongBox 的测试设备。

请求：HardwareBacking 分别为 Required、Preferred 和 NotRequired。

记录：

Start time:

End time:

Required on unsupported device:

Preferred on unsupported device:

NotRequired on unsupported device:

Error code:

Result: PENDING

通过条件：Required 返回 credential_policy_unsupported，Preferred 和 NotRequired 按策略回退并报告能力。

### V28：Android 备份和 D2D 排除

**警告：** 只用测试包和合成数据。恢复操作前备份测试设备。

前置：准备 Android 自动备份和设备直传测试环境。

请求：创建测试仓库，执行云备份、D2D 和恢复。

记录：

Start time:

End time:

Cloud backup excludes ciphertext:

D2D excludes ciphertext:

Restored key presence:

Restored decrypt result:

Error code:

Result: PENDING

通过条件：密文和根密钥都不迁移，恢复后返回 credential_recovery_required。

### V29：Android 锁屏后台接收

前置：后台密钥不要求认证，设备已设置锁屏。

请求：锁定设备，触发后台接收，再触发审批操作。

记录：

Start time:

End time:

Background key access:

Approval key access:

Task state:

Error code:

Result: PENDING

通过条件：后台接收继续或暂停，审批操作返回 credential_auth_required 或 credential_device_locked。

### V30：Android 15 unlocked-device 门槛

前置：准备 Android 14 和 Android 15 测试设备。

请求：在 Android 14 记录 setUnlockedDeviceRequired 行为，在 Android 15 重复测试。

记录：

Start time:

End time:

Android 14 result:

Android 15 result:

Policy selected:

Error code:

Result: PENDING

通过条件：Android 14 不启用强制策略，Android 15 只按显式策略启用。

## 5. 结果汇总

当前阻塞。没有 Android 工程和真机，未执行任何步骤。

## 6. 清理记录

1. 删除测试 Keystore 别名。
2. 删除 no-backup 测试目录。
3. 删除测试包数据。
4. 删除测试备份数据。
5. 确认没有测试根密钥和密文残留。
6. 记录清理结果。

清理结果：PENDING

## 7. 更新规则

Android 工程建立后解除阻塞。
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
