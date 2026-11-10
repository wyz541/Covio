# Apple Keychain 合同验证记录

本案例尚未执行。当前仓库没有 iOS 工程，iOS 步骤处于阻塞状态。

## 文档状态

| 项目 | 内容 |
| --- | --- |
| 状态 | 尚未执行 |
| 执行人 | 待填写 |
| 复核人 | 待填写 |
| 环境 | macOS 和 iOS 测试设备 |
| 版本 | 待填写 |
| 主方案 | [主题索引](../README.md) |
| 证据附录 | [证据附录](../evidence.md) |
| 目录说明 | [验证目录](README.md) |

## 1. 验证目标

1. 验证 macOS 使用 data protection Keychain。
2. 验证设备绑定项不进入 iCloud 同步。
3. 验证锁定、取消和认证失败的错误映射。
4. 验证 ThisDeviceOnly 在新设备恢复后不可用。
5. 验证 biometryCurrentSet 失效行为。
6. 验证 iOS 后台接收的可用性。
7. 验证扩展 access group 的最小权限。

## 2. 预检记录

| 项目 | 值 | 状态 |
| --- | --- | --- |
| macOS 版本 | 待填写 | 尚未执行 |
| iOS 版本 | 待填写 | 尚未执行 |
| Mac 型号 | 待填写 | 尚未执行 |
| iPhone 型号 | 待填写 | 尚未执行 |
| 应用 commit | 待填写 | 尚未执行 |
| macOS Keychain 测试入口 | 待实现 | 尚未执行 |
| iOS 测试目标 | 不存在 | 阻塞 |
| 生物认证配置 | 待填写 | 尚未执行 |
| 加密备份配置 | 待填写 | 尚未执行 |

## 3. 测试前采集

执行以下命令并记录结果。

sw_vers

uname -m

xcodebuild -version

git rev-parse HEAD

记录字段：

MacOSVersion:

BuildVersion:

XcodeVersion:

Commit:

DeviceModel:

BiometricType:

PasscodeEnabled:

BackupEncryptionEnabled:

## 4. 验证步骤

### V01：macOS Keychain 基础往返

前置：macOS 测试入口可用。使用唯一服务名和 account。

请求：

JSON 请求使用 op credential.store，vault_id 为合成值，record_kind 为 pairing。

记录：

Start time:

End time:

Response:

Error code:

Result: PENDING

通过条件：写入成功，回读成功，记录 revision 为 1。

### V02：macOS 显式 data protection Keychain

前置：V01 通过。

请求：读取测试项的 Keychain 属性并确认 kSecUseDataProtectionKeychain 语义。

记录：

Start time:

End time:

Observed class:

Observed accessibility:

Observed synchronizable:

Response:

Error code:

Result: PENDING

通过条件：测试项位于 data protection Keychain，且 synchronizable 为 false。

### V03：macOS 可用性、同步和 access group

前置：V02 通过。准备后台密钥和审批密钥两组测试项。

请求：分别创建 AfterFirstUnlockThisDeviceOnly 和 WhenUnlockedThisDeviceOnly 项。

记录：

Start time:

End time:

Background accessible:

Approval accessible:

Access group:

Response:

Error code:

Result: PENDING

通过条件：后台项和审批项使用不同策略，默认 access group 不扩大。

### V04：macOS 锁定、取消和认证失败

前置：测试设备已设置密码和可用认证方式。

请求：锁定设备后读取审批项，再取消认证，再输入错误认证。

记录：

Start time:

End time:

Locked error:

Cancel error:

Auth failed error:

Response:

Result: PENDING

通过条件：分别得到 credential_device_locked、credential_user_cancelled 和 credential_auth_failed。

### V05：macOS 备份恢复和新设备迁移

**警告：** 只在测试设备上执行。先备份测试设备并保存恢复路径。不要使用生产数据。

前置：准备加密备份和另一台测试 Mac。

请求：创建 ThisDeviceOnly 测试项，备份，恢复到原测试机，再恢复到新测试机。

记录：

Start time:

End time:

Same device result:

New device result:

Observed key presence:

Error code:

Result: PENDING

通过条件：原设备恢复可用，新设备不能解密旧根密钥。

### V06：macOS 旧 file-based 项迁移

前置：准备旧适配器创建的测试项。

请求：执行两阶段迁移，模拟旧项删除失败。

记录：

Start time:

End time:

New item read:

Old item read:

Migration marker:

Error code:

Result: PENDING

通过条件：新项回读成功，旧项删除失败时保留清理任务，回滚可读。

### V07：iOS Keychain 基础往返

前置：iOS 工程存在，测试入口可用。

当前状态：阻塞，仓库没有 iOS 工程。

请求：在测试 App 中执行 credential.store 和 credential.exists。

记录：

Start time:

End time:

Response:

Error code:

Result: PENDING

通过条件：写入和存在检查成功，秘密不进入 UI snapshot。

### V08：iOS 后台 AfterFirstUnlock 读取

前置：V07 通过，后台任务使用 AfterFirstUnlockThisDeviceOnly。

请求：重启设备，首次解锁，锁定屏幕，然后触发后台测试任务。

记录：

Start time:

End time:

After first unlock readable:

Locked readable:

Background task state:

Error code:

Result: PENDING

通过条件：后台任务得到预期可读状态或可恢复暂停状态。

### V09：iOS biometryCurrentSet 失效

前置：V07 通过，测试设备有生物认证。

请求：创建 biometryCurrentSet 测试项，增加或移除测试生物登记。

记录：

Start time:

End time:

Before change:

After change:

Error code:

Result: PENDING

通过条件：测试项失效返回 credential_key_invalidated 或明确的不确定结果。

### V10：iOS 新设备恢复和重新配对

**警告：** 使用测试设备和合成数据。恢复操作前保存测试设备备份。

前置：准备两台测试 iPhone 和一台加密备份设备。

请求：备份设备 A，恢复到设备 B，再执行测试配对。

记录：

Start time:

End time:

Key presence:

Decrypt result:

Re-pair result:

Error code:

Result: PENDING

通过条件：设备 B 不能解密旧仓库，重新配对后可以建立新仓库。

### V11：iOS 分享扩展 access group 边界

前置：iOS 工程含分享扩展。分享扩展只写入 App Group 临时内容。

请求：检查分享扩展的 Keychain access group 和读取权限。

记录：

Start time:

End time:

App group:

Keychain access group:

Extension secret read:

Response:

Result: PENDING

通过条件：扩展不保存长期根密钥，主应用完成后续写入。

## 5. 结果汇总

当前无实际结果。所有步骤等待测试入口和真机环境。

## 6. 清理记录

1. 删除 macOS 测试 service 和 account。
2. 删除 macOS 测试 access group 项。
3. 删除 iOS 测试 App 数据。
4. 删除测试 Keychain 项。
5. 删除测试备份中的合成秘密。
6. 确认没有测试根密钥残留。
7. 记录清理命令和结果。

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
