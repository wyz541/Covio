# 跨平台凭据存储验证目录

验证尚未执行。本目录只定义验证目标、矩阵、前置条件和清理要求。

## 文档状态

| 项目 | 内容 |
| --- | --- |
| 状态 | 尚未执行 |
| 日期 | 2026-11-10 |
| 目标环境 | macOS、iOS、Windows 11、Android 后继环境 |
| 问题类别 | 跨平台秘密数据保护、设备绑定、备份和迁移 |
| 主方案 | [主题索引](../README.md) |
| 证据附录 | [证据附录](../evidence.md) |
| 当前事实 | 官方文档审核完成，真机测试未执行 |

## 1. 案例索引

| 编号 | 案例 | 状态 | 记录 |
| --- | --- | --- | --- |
| Case 1 | Apple Keychain 合同 | 尚未执行 | [case-apple-keychain.md](case-apple-keychain.md) |
| Case 2 | Windows Credential Manager 合同 | 尚未执行 | [case-windows-credential-manager.md](case-windows-credential-manager.md) |
| Case 3 | Rust vault 合同 | 尚未执行 | [case-rust-vault-contract.md](case-rust-vault-contract.md) |
| Case 4 | Android Keystore 合同 | 尚未执行 | [case-android-keystore-contract.md](case-android-keystore-contract.md) |

## 2. 目标

1. 验证根密钥设备绑定。
2. 验证平台能力报告与真实行为一致。
3. 验证锁定、取消、认证失败和密钥失效的错误映射。
4. 验证备份恢复不迁移长期根密钥。
5. 验证迁移失败可以回滚。
6. 验证秘密不进入日志、snapshot 和普通 JSON。
7. 验证 FFI 释放路径执行零化。
8. 验证 Android Keystore 只作为密钥包装器。
9. 验证后台接收的降级路径。
10. 为正式合同提供可复核证据。

## 3. 范围

### 3.1 范围内

1. macOS Keychain。
2. iOS Keychain。
3. Windows Credential Manager。
4. Rust facade 和记录仓库。
5. C ABI、UniFFI 和 JNI 语义。
6. Android Keystore 合同。
7. 根密钥轮换和迁移。
8. 访问控制、认证、备份和日志。
9. 测试清理和残留检查。

### 3.2 范围外

1. 正式发布验收。
2. 云端密钥托管。
3. 账号恢复。
4. Windows Hello 完整实现。
5. Android 第一版交付。
6. 密码学算法认证。
7. 硬件安全认证。
8. 生产用户数据测试。
9. 公网服务测试。
10. GitHub Discussion 更新。

## 4. 当前事实

1. 当前仓库没有 iOS 工程。
2. 当前仓库没有 Android 工程。
3. 当前 Windows Compose host 尚未替换 egui。
4. 当前 macOS 适配器没有显式 data protection Keychain。
5. 当前 Windows 适配器使用 ENTERPRISE 持久化。
6. 当前 C ABI 暴露通用 secret read。
7. 当前 C ABI 释放秘密缓冲区前没有零化。
8. 当前错误类别不足以表达锁定、取消和失效。
9. macOS 已有基础 Keychain 往返测试。
10. Windows 有目标平台条件测试，但本轮未运行。

## 5. 成功标准

1. 不支持的策略都返回 credential_policy_unsupported。
2. 认证取消返回 credential_user_cancelled。
3. 设备锁定返回 credential_device_locked。
4. 平台密钥失效返回 credential_key_invalidated。
5. AEAD 校验失败返回 credential_integrity_failed。
6. 根密钥缺失返回 credential_recovery_required。
7. 新设备不能解密旧仓库。
8. Windows 只写入 LOCAL_MACHINE。
9. Apple 设备绑定项不进入 iCloud 同步。
10. Android 密文不进入 Auto Backup 或 D2D。
11. 迁移失败可以读回旧数据。
12. 秘密日志泄漏为 0。
13. 测试项清理成功率为 100%。
14. 每个案例都有时间、环境、版本和实际结果。

## 6. 前置条件

1. 使用合成秘密。
2. 使用唯一测试名称。
3. 记录目标系统版本。
4. 记录应用 commit 和构建号。
5. 记录设备型号。
6. 记录认证配置。
7. 记录备份配置。
8. 记录测试账号类型。
9. 准备清理命令。
10. 准备旧版本回滚路径。
11. 准备测试数据备份。
12. 准备无生产秘密的测试环境。

## 7. 风险

| 风险 | 影响 | 缓解 |
| --- | --- | --- |
| 使用生产秘密 | 秘密泄漏 | 只用合成秘密 |
| 测试项残留 | 下一次测试污染 | 唯一名称和清理检查 |
| 恢复真实设备备份 | 用户数据丢失 | 只用测试设备 |
| 删除错误 Keychain 项 | 其他应用受影响 | 固定 service 和 access group |
| 删除错误 Credential Manager 项 | 用户登录凭据受影响 | 固定 Covio 前缀 |
| Android 清除测试数据 | 本地测试状态丢失 | 只清测试包和测试别名 |
| 生物登记变化 | 原密钥永久失效 | 使用专用测试设备或明确回滚 |
| 日志包含秘密 | 隐私泄漏 | 合成秘密和脱敏检查 |
| 迁移中断 | 双写状态不一致 | 两阶段迁移和回滚 |
| 正式设备配置变化 | 结果不可复现 | 记录完整环境 |

## 8. 测试矩阵

| 编号 | 场景 | 当前状态 | 结果文件 |
| --- | --- | --- | --- |
| V01 | macOS Keychain 基础往返 | 待执行 | case-apple-keychain.md |
| V02 | macOS 显式 data protection Keychain | 待执行 | case-apple-keychain.md |
| V03 | macOS 可用性、同步和 access group | 待执行 | case-apple-keychain.md |
| V04 | macOS 锁定、取消和认证失败 | 待执行 | case-apple-keychain.md |
| V05 | macOS 备份恢复和新设备迁移 | 待执行 | case-apple-keychain.md |
| V06 | macOS 旧 file-based 项迁移 | 待执行 | case-apple-keychain.md |
| V07 | iOS Keychain 基础往返 | 阻塞 | case-apple-keychain.md |
| V08 | iOS 后台 AfterFirstUnlock 读取 | 阻塞 | case-apple-keychain.md |
| V09 | iOS biometryCurrentSet 失效 | 阻塞 | case-apple-keychain.md |
| V10 | iOS 新设备恢复和重新配对 | 阻塞 | case-apple-keychain.md |
| V11 | iOS 分享扩展 access group 边界 | 阻塞 | case-apple-keychain.md |
| V12 | Windows 通用凭据基础往返 | 待执行 | case-windows-credential-manager.md |
| V13 | Windows LOCAL_MACHINE 持久化 | 待执行 | case-windows-credential-manager.md |
| V14 | Windows 2560 字节边界 | 待执行 | case-windows-credential-manager.md |
| V15 | Windows 用户隔离和跨机边界 | 待执行 | case-windows-credential-manager.md |
| V16 | Windows 登录会话不可用 | 待执行 | case-windows-credential-manager.md |
| V17 | Windows UserConsentVerifier 映射 | 待执行 | case-windows-credential-manager.md |
| V18 | Windows ENTERPRISE 到 LOCAL_MACHINE 迁移 | 待执行 | case-windows-credential-manager.md |
| V19 | 根密钥不跨 FFI 返回 | 阻塞 | case-rust-vault-contract.md |
| V20 | AEAD、AAD 和设备绑定 | 阻塞 | case-rust-vault-contract.md |
| V21 | 稳定错误码映射 | 阻塞 | case-rust-vault-contract.md |
| V22 | 轮换和迁移回滚 | 阻塞 | case-rust-vault-contract.md |
| V23 | 秘密零化和日志脱敏 | 阻塞 | case-rust-vault-contract.md |
| V24 | 记录损坏和根密钥缺失 | 阻塞 | case-rust-vault-contract.md |
| V25 | Android Keystore 包装往返 | 阻塞 | case-android-keystore-contract.md |
| V26 | Android 认证和密钥失效 | 阻塞 | case-android-keystore-contract.md |
| V27 | Android StrongBox 回退 | 阻塞 | case-android-keystore-contract.md |
| V28 | Android 备份和 D2D 排除 | 阻塞 | case-android-keystore-contract.md |
| V29 | Android 锁屏后台接收 | 阻塞 | case-android-keystore-contract.md |
| V30 | Android 15 unlocked-device 门槛 | 阻塞 | case-android-keystore-contract.md |

## 9. 证据要求

每个步骤记录以下字段。

1. 开始时间。
2. 结束时间。
3. 操作系统和版本。
4. 设备型号。
5. 应用 commit 和构建号。
6. 前置状态。
7. 请求或命令。
8. 预期结果。
9. 实际结果。
10. 错误码。
11. 是否可重试。
12. 用户动作。
13. 日志摘要。
14. 清理结果。
15. 证据文件位置。

证据不记录真实秘密。
证据不记录完整用户路径。
证据不记录设备序列号。
证据不记录二维码原文。
截图和日志必须脱敏。

## 10. 清理步骤

1. 删除唯一测试 Keychain service 或 account。
2. 删除唯一测试 Keychain access group 关联项。
3. 删除唯一 Covio 测试 Credential Manager TargetName。
4. 删除唯一测试 vault_id 文件。
5. 删除 Android 测试别名。
6. 删除 Android no-backup 测试密文。
7. 删除 WebAuthn 或生物登记测试产生的测试状态。
8. 清除测试日志中的临时诊断文件。
9. 确认没有测试根密钥残留。
10. 确认没有测试记录残留。
11. 确认迁移标记已清除或按计划保留。
12. 在案例文件中记录清理结果。

## 11. 关联文档

- [主题索引](../README.md)
- [证据附录](../evidence.md)
- [推荐方案](../solution.md)
- [结论](../conclusion.md)
- [Apple 案例](case-apple-keychain.md)
- [Windows 案例](case-windows-credential-manager.md)
- [Rust 合同案例](case-rust-vault-contract.md)
- [Android 合同案例](case-android-keystore-contract.md)
