# Covio 凭据仓库

- 状态：accepted
- 日期：2026-11-10
- 决策：[ADR-0035](../adr/adr-0035-cross-platform-product-scope.md)
- 研究：[跨平台凭据存储](../research/platform-credential-storage/README.md)

## 1. 结论

原生安全存储只保存 32 字节根密钥。
Rust 使用 XChaCha20-Poly1305 和 HKDF-SHA256 保存加密记录。
业务 bridge 不提供通用 secret read。
Agent token 使用单独的用途限定 ABI。

## 2. 存储分层

| 层 | 保存内容 | Owner |
| --- | --- | --- |
| macOS/iOS Keychain | 根密钥 | 平台 adapter |
| Windows Credential Manager | 根密钥 | 平台 adapter |
| Rust vault 文件 | 元数据、nonce、密文和修订号 | `covio-core` |
| Agent token | 一个受限业务 token | `covio-agent-token` ABI |

根密钥不进入普通 JSON、snapshot、event 或日志。
明文记录只在受限闭包中存在。
秘密类型在离开作用域前零化。

## 3. 文件格式

Vault 文件是 `credential-vault.json`。
每个文件只对应一个 vault。
`VaultMetadata` 包含以下字段。

- `format_version`
- `alg_id`
- `vault_id`
- `device_id`
- `key_generation`

`EncryptedRecord` 包含以下字段。

- `record_id`
- `record_kind`
- `revision`
- `nonce`
- `ciphertext`
- `created_at`
- `updated_at`

AAD 绑定应用、设备、vault、generation、record ID、record kind、格式版本和 revision。
AAD 不包含秘密、用户名、文件路径或二维码原文。

## 4. 根密钥

根密钥是 32 字节随机值。
根密钥使用 `ZeroizeOnDrop`。
记录密钥使用 HKDF-SHA256。
HKDF salt 是 `vault_id`。
XChaCha20-Poly1305 nonce 是 24 字节随机值。

## 5. 平台 adapter

macOS 和 iOS 使用 data protection Keychain。
macOS 设置 `kSecUseDataProtectionKeychain`，并禁用 iCloud 同步。
Windows 使用 `CRED_TYPE_GENERIC` 和 `CRED_PERSIST_LOCAL_MACHINE`。
Windows TargetName 必须位于 `Covio.CredentialVault.v1` 命名空间。
Android 后续使用 Keystore 包装根密钥。

## 6. 写入和读取

写入顺序如下。

1. 校验记录 ID 和长度。
2. 打开根密钥。
3. 派生记录密钥。
4. 生成 nonce。
5. 构造 AAD。
6. 加密记录。
7. 原子写入 vault 文件。
8. 返回修订元数据。

读取顺序如下。

1. 查找加密记录。
2. 打开根密钥。
3. 重建 AAD。
4. 解密并校验完整性。
5. 在受限闭包中提供明文。
6. 闭包结束后零化明文。

## 7. 轮换

轮换创建新 generation。
轮换重加密全部记录。
轮换写入新根密钥并回读验证。
轮换成功后删除旧根密钥。
轮换失败时保留旧 vault 和旧根密钥。

## 8. 错误

稳定错误码如下。

| Code | 含义 |
| --- | --- |
| 1001 | 记录或根密钥缺失 |
| 1002 | vault 已存在 |
| 1003 | 输入无效 |
| 1004 | 原生后端不可用 |
| 1005 | 需要认证 |
| 1006 | 设备锁定 |
| 1007 | 用户取消 |
| 1008 | 密钥失效 |
| 1009 | AEAD 或 AAD 校验失败 |
| 1010 | vault 或记录损坏 |
| 1011 | 版本不支持 |
| 1012 | 需要重新配对或恢复 |
| 1013 | 内部错误 |

错误对象不包含秘密、密文、完整路径或原生错误原文。

## 9. Agent token ABI

旧通用 Keychain C ABI 已删除。
Agent token 只允许以下入口。

- `covio_agent_token_read`
- `covio_agent_token_write`
- `covio_agent_token_delete`
- `covio_agent_token_reset`

入口接收 Application Support 根目录。
Rust 在该目录的 `credentials/` 子目录保存加密 vault。
Keychain 只保存 vault 根密钥。

Service 必须以 `com.wyz.covio.agent.` 开头。
Account 必须是 `mcp-bearer-token`。
其他 namespace 返回 `COVIO_STATUS_INVALID_ARGUMENT`。

## 10. 测试

测试覆盖以下场景。

- 创建、写入、重新打开和删除。
- 根密钥缺失。
- 设备锁定。
- 用户取消。
- 密文损坏。
- 根密钥轮换。
- Agent token namespace 限制。
- 秘密缓冲区零化释放路径。

## 11. 未决事项

- 旧 macOS file-based Keychain 项的产品迁移。
- 旧 Windows ENTERPRISE 凭据的产品迁移。
- iOS Keychain 真机验证。
- Android Keystore adapter。
- UserPresence、BiometricCurrentSet 和硬件保护能力。