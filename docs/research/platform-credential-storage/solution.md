# 跨平台凭据存储推荐方案

推荐方案是“原生根密钥保护加 Rust 加密仓库”。该方案把平台差异限制在小型适配器中，把业务记录、迁移和错误统一到 Rust facade。

> 本文件定义推荐架构、Rust trait、类型、错误码、平台适配器、流程、安全、迁移、测试和实施条件。

## 1. 推荐架构

### 1.1 路径选择

路径分为四层。

1. 原生安全存储保护根密钥。
2. Rust 派生记录密钥并加密业务记录。
3. Rust facade 执行用途校验、能力校验和错误映射。
4. 平台 UI 只提供用户交互和认证窗口。

原生存储不保存业务记录集合。
业务层不直接调用 Keychain、Credential Manager 或 Keystore。
业务层不接收长期根密钥明文。
桥接层不提供通用 secret read。

### 1.2 组件职责

| 组件 | 职责 | 不拥有 |
| --- | --- | --- |
| CredentialFacade | 校验用途、策略、长度和调用者 | 平台 UI |
| RecordVault | AEAD 加密、原子写入、版本和回读校验 | 原生认证 |
| RootKeyProtector | 保存、打开、轮换和删除根密钥 | 业务记录 |
| DeviceKeyStore | 生成和使用非导出设备身份密钥 | 业务记录 |
| AuthBridge | 显示认证提示并返回结构化结果 | 密钥持久化 |
| Migrator | 读取旧后端并写入新后端 | 日常业务规则 |
| AuditSink | 记录非秘密操作元数据 | 秘密内容 |

### 1.3 根密钥和记录

根密钥是 32 字节随机值。
根密钥只在内存中短暂打开。
根密钥使用 Zeroizing 或等价类型。
根密钥不实现 Clone、Debug、Serialize 和 Display。
根密钥离开作用域后必须零化。

记录包含以下字段。

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| format_version | u16 | 记录格式版本 |
| alg_id | u16 | AEAD 或 KDF 套件编号 |
| vault_id | UUID | 仓库随机标识 |
| key_generation | u32 | 根密钥代际 |
| record_id | String | 用途受限的稳定标识 |
| record_kind | enum | 记录用途 |
| revision | u64 | 本地修订号 |
| nonce | bytes | 唯一 nonce |
| ciphertext | bytes | AEAD 密文和认证标签 |
| created_at | i64 | UTC 毫秒 |
| updated_at | i64 | UTC 毫秒 |

AAD 至少包含以下字段。
AAD 包含应用 ID、设备 ID、vault_id、key_generation、record_id、record_kind、format_version 和 revision。
设备 ID 是应用生成的本安装随机标识。
设备 ID 不使用硬件序列号。
AAD 不包含用户名、文件路径或二维码原文。

### 1.4 调用路径

macOS 和 iOS 路径：

SwiftUI 或 Rust core
  -> Rust CredentialFacade
  -> Rust RecordVault
  -> Rust RootKeyProtector
  -> Security.framework SecItem
  -> Keychain 或 Secure Enclave

Windows 路径：

Compose host 或 Rust core
  -> Rust CredentialFacade
  -> Rust RecordVault
  -> Rust RootKeyProtector
  -> Win32 Credential Manager
  -> 当前用户凭据集

Android 路径：

Compose host 或 Rust core
  -> Rust CredentialFacade
  -> Rust RecordVault
  -> JNI 或 UniFFI 回调
  -> Kotlin Keystore adapter
  -> Android Keystore
  -> no-backup 密文目录

### 1.5 建议文件位置

建议位置如下。
这些文件尚未创建。

| 位置 | 内容 |
| --- | --- |
| rust/crates/covio-core/src/credential/facade.rs | 用途校验、策略和调用路径 |
| rust/crates/covio-core/src/credential/record.rs | 记录类型和版本 |
| rust/crates/covio-core/src/credential/error.rs | 稳定错误码 |
| rust/crates/covio-core/src/credential/migrate.rs | 两阶段迁移 |
| rust/crates/covio-platform/src/credential/apple.rs | macOS 和 iOS 适配器 |
| rust/crates/covio-platform/src/credential/windows.rs | Windows 适配器 |
| rust/crates/covio-platform/src/credential/android.rs | Android JNI 合同 |
| rust/crates/covio-ffi/src/credential.rs | C ABI 或 UniFFI 边界 |
| rust/crates/covio-platform/tests/credential_contract.rs | 合同测试入口 |

文件拆分可以在实现 ADR 中调整。
不论拆分方式如何，职责和边界不能改变。

## 2. 接口契约

### 2.1 传输和 ABI

Rust 内部使用类型化 trait。
macOS 和 iOS 使用版本化 C ABI。UniFFI 只在验证后生成 Swift 绑定。
Windows Compose 和 Android Compose 使用 JNI。
默认 UniFFI Kotlin 后端依赖 JNA，不进入首版产品路径。
所有边界都必须保留稳定错误码和用户动作。

C ABI 规则如下。

1. 枚举使用 repr(u32) 或等价固定宽度类型。
2. 每个句柄有显式打开和释放。
3. 每个输入有长度上限。
4. 每个输出有长度和容量字段。
5. 释放秘密缓冲区前先零化。
6. panic 在边界转换为 credential_internal。
7. 长期根密钥不进入 C ABI 返回值。
8. 通用 secret read 不出现在产品 ABI。

UniFFI 规则如下。

1. UniFFI 只用于验证后的 Swift 绑定或隔离试验。
2. 错误类型实现 Result 的 Err 类型。
3. Swift 捕获结构化错误。
4. foreign trait 方法全部返回 Result。
5. foreign trait 不允许形成 Rust 与 foreign 语言的循环引用。
6. 回调不携带长期根密钥。
7. 错误消息不包含秘密或完整本机路径。

JNI 规则如下。

1. JNI 方法只接收用途和受限字节。
2. JNI 方法只返回状态、句柄或非秘密元数据。
3. Keystore 密钥生成和认证在 Kotlin 适配器中完成。
4. Rust 不在 JNI 边界保存 jobject 长期引用。
5. Android Activity 只通过显式认证上下文传入。
6. 未声明的方法全部拒绝。

### 2.2 Rust 类型

以下类型是推荐合同。
最终字段名可以在 schema 评审后调整。

```rust
use zeroize::{Zeroize, ZeroizeOnDrop};

pub struct CredentialId(String);
pub struct DeviceId(String);
pub struct VaultId([u8; 16]);
pub struct KeyGeneration(u32);

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RecordKind {
    Pairing,
    TransportGroupKey,
    ProviderApiKey,
    UpdateSecret,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Availability {
    WhenUnlocked,
    AfterFirstUnlock,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum UserPresence {
    None,
    UserPresence,
    BiometricCurrentSet,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HardwareBacking {
    Required,
    Preferred,
    NotRequired,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BackupPolicy {
    DeviceBound,
    Recoverable,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Enforcement {
    Cryptographic,
    OsUiOnly,
    None,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Support {
    Supported,
    Unsupported,
    Unknown,
}

pub struct ProtectionRequest {
    pub purpose: RecordKind,
    pub availability: Availability,
    pub user_presence: UserPresence,
    pub hardware_backing: HardwareBacking,
    pub backup_policy: BackupPolicy,
}

pub struct BackendCapabilities {
    pub max_wrapped_key_bytes: Option<usize>,
    pub device_bound: Support,
    pub backup_scope: Support,
    pub hardware_backing: Support,
    pub user_presence: Support,
    pub biometric_only: Support,
    pub after_first_unlock: Support,
    pub authentication_enforcement: Enforcement,
    pub supports_rotation: bool,
    pub supports_attestation: Support,
}

#[derive(Zeroize, ZeroizeOnDrop)]
pub struct RootKey([u8; 32]);

pub struct KeyHandle {
    pub vault_id: VaultId,
    pub generation: KeyGeneration,
    pub backend_ref: String,
}

pub struct AuthContext {
    pub request_id: String,
    pub reason: String,
    pub timeout_ms: u32,
}

pub struct CredentialRecord {
    pub format_version: u16,
    pub alg_id: u16,
    pub vault_id: VaultId,
    pub key_generation: KeyGeneration,
    pub record_id: CredentialId,
    pub record_kind: RecordKind,
    pub revision: u64,
    pub nonce: Vec<u8>,
    pub ciphertext: Vec<u8>,
    pub created_at: i64,
    pub updated_at: i64,
}
```

RootKey 不提供公开字节访问。
RootKey 只在 RecordVault 的受限闭包内使用。
AuthContext 的 reason 使用本地化 UI 文案标识。
AuthContext 不包含秘密。
backend_ref 是平台引用，不是秘密。
backend_ref 不进入普通 UI snapshot。

### 2.3 Rust trait

```rust
pub trait RootKeyProtector: Send + Sync {
    fn capabilities(&self) -> Result<BackendCapabilities, CredentialError>;

    fn provision(
        &self,
        request: &ProtectionRequest,
    ) -> Result<KeyHandle, CredentialError>;

    fn open(
        &self,
        handle: &KeyHandle,
        auth: &AuthContext,
    ) -> Result<RootKey, CredentialError>;

    fn rotate(
        &self,
        old: &KeyHandle,
        request: &ProtectionRequest,
    ) -> Result<KeyHandle, CredentialError>;

    fn delete(&self, handle: &KeyHandle) -> Result<(), CredentialError>;

    fn inspect(&self, handle: &KeyHandle) -> Result<KeyStatus, CredentialError>;
}

pub struct KeyStatus {
    pub present: bool,
    pub device_bound: Support,
    pub hardware_backing: Support,
    pub authentication_enforcement: Enforcement,
    pub invalidated: bool,
}
```

trait 规则如下。

1. 所有方法必须返回 Result。
2. 适配器不得把平台错误直接透传。
3. 适配器不得在错误中写秘密。
4. 适配器不得回退到明文文件。
5. 适配器不得自动降低 ProtectionRequest。
6. 适配器不得在 UI 线程执行阻塞调用。
7. 适配器必须回报有效能力。
8. 适配器必须把未知能力标为 Unknown。
9. 适配器必须在失败时保持旧状态。
10. 适配器必须支持删除缺失项的空操作。

### 2.4 facade 操作

| 操作 | 参数 | 返回 | 可见调用者 |
| --- | --- | --- | --- |
| credential.capabilities | 无 | BackendCapabilities | Rust core、UI |
| credential.bootstrap | ProtectionRequest | VaultStatus | Rust core |
| credential.status | VaultId | VaultStatus | UI |
| credential.unlock | AuthContext | OpaqueSession | Rust core |
| credential.store | OpaqueSession、CredentialId、RecordKind、SecretInput | RecordMetadata | Rust core、UI |
| credential.exists | VaultId、CredentialId | bool | UI |
| credential.delete | OpaqueSession、CredentialId | Ok | Rust core、UI |
| credential.rotate | OpaqueSession、ProtectionRequest | KeyGeneration | Rust core |
| credential.migrate | MigrationRequest | MigrationStatus | Rust core |
| credential.revoke_peer | OpaqueSession、DeviceId | RevokeResult | Rust core、UI |
| credential.reset_local | ResetRequest | ResetResult | UI |
| credential.health | 无 | HealthReport | UI 和测试 |

credential.store 可以接收用户输入。
通用 credential.get 不出现在产品接口。
Rust core 通过内部受限方法读取记录。
内部方法不跨 C ABI、UniFFI 或 JNI 返回明文。

### 2.5 请求示例

```json
{
  "request_id": "req-credential-001",
  "protocol_version": 1,
  "op": "credential.store",
  "args": {
    "record_id": "pairing/peer-001/psk",
    "record_kind": "pairing",
    "protection_profile": "device-bound-background",
    "secret_ref": "input-001"
  }
}
```

secret_ref 指向受限输入句柄。
普通 JSON 不携带 secret 字节。
句柄在请求结束后释放并零化。

### 2.6 响应示例

```json
{
  "request_id": "req-credential-001",
  "ok": true,
  "data": {
    "record_id": "pairing/peer-001/psk",
    "revision": 1,
    "key_generation": 1
  },
  "error": null
}
```

失败响应示例：

```json
{
  "request_id": "req-credential-001",
  "ok": false,
  "data": null,
  "error": {
    "code": "credential_auth_required",
    "retryable": true,
    "user_action": "authenticate",
    "correlation_id": "corr-001"
  }
}
```

### 2.7 错误码

| 数值 | 错误码 | 触发条件 | 默认可重试 | 用户动作 |
| --- | --- | --- | --- | --- |
| 1001 | credential_not_found | 记录或根密钥不存在 | 否 | 重新配对 |
| 1002 | credential_already_exists | 创建请求遇到已有仓库 | 否 | 使用已有仓库 |
| 1003 | credential_invalid_argument | ID、长度或字段无效 | 否 | 修正输入 |
| 1004 | credential_capacity_exceeded | 超出平台或产品上限 | 是 | 释放空间 |
| 1005 | credential_backend_unavailable | 原生存储不可用 | 按原因 | 重试 |
| 1006 | credential_policy_unsupported | 平台不能执行请求策略 | 否 | 选择可用策略 |
| 1007 | credential_access_denied | 操作系统拒绝访问 | 否 | 检查权限 |
| 1008 | credential_auth_required | 需要用户认证 | 是 | authenticate |
| 1009 | credential_auth_failed | 用户认证失败 | 是 | 重试认证 |
| 1010 | credential_user_cancelled | 用户取消认证 | 是 | 重试 |
| 1011 | credential_device_locked | 设备锁定禁止读取 | 是 | unlock_device |
| 1012 | credential_key_invalidated | 平台密钥永久失效 | 否 | 重新配对 |
| 1013 | credential_integrity_failed | AEAD 或 AAD 校验失败 | 否 | 隔离记录并重新配对 |
| 1014 | credential_record_corrupt | 记录头或元数据损坏 | 否 | 隔离记录 |
| 1015 | credential_version_unsupported | 版本高于当前支持范围 | 否 | 升级应用 |
| 1016 | credential_busy | 平台或适配器忙 | 是 | 重试 |
| 1017 | credential_timeout | 操作超时 | 是 | 重试 |
| 1018 | credential_cancelled | 调用方取消 | 否 | 无 |
| 1019 | credential_migration_required | 需要执行迁移 | 否 | migrate |
| 1020 | credential_recovery_required | 根密钥缺失或恢复不完整 | 否 | re_pair |
| 1021 | credential_internal | 未分类内部错误 | 否 | contact_support |

错误对象只包含 code、retryable、user_action 和 correlation_id。
错误对象不包含秘密、密钥、密文、完整路径或二维码原文。
原生 OSStatus 和 Win32 code 只进入受控诊断日志。
诊断日志必须脱敏。

### 2.8 用户动作

| 动作 | 含义 |
| --- | --- |
| none | 无用户动作 |
| unlock_device | 解锁设备 |
| authenticate | 完成平台认证 |
| retry | 稍后重试 |
| free_space | 释放本地空间 |
| re_pair | 重新完成二维码配对 |
| reset_vault | 清除本地仓库 |
| migrate | 执行数据迁移 |
| contact_support | 联系支持 |

## 3. 平台适配器

### 3.1 通用选择

根密钥按用途分开保存。
后台传输密钥用于接收和续传。
审批密钥用于配对、撤销、导出和重置。
提供方 API 密钥使用独立记录用途。
设备身份密钥使用独立 DeviceKeyStore。
不同用途使用不同 key ID 和不同 access policy。
删除一个用途的密钥不能删除其他用途的密钥。

### 3.2 macOS 适配器

服务名使用 com.wyz.covio.credentials。
账户名使用 vault/<vault_id>/<purpose>/<generation>。
Keychain class 使用 kSecClassGenericPassword。
所有操作显式设置 kSecUseDataProtectionKeychain 为 true。
所有设备绑定项设置 kSecAttrSynchronizable 为 false。
后台传输密钥使用 kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly。
审批密钥使用 kSecAttrAccessibleWhenUnlockedThisDeviceOnly。
审批密钥可以使用 SecAccessControl。
普通用户在场使用 kSecAccessControlUserPresence。
只允许当前生物集合时使用 kSecAccessControlBiometryCurrentSet。
主应用默认使用私有 access group。
只有 App Extension 需要读取同一项时才增加共享 access group。
适配器把 SecItem 调用放到后台 worker。
适配器把用户取消、锁定、认证失败和缺失项映射为稳定错误码。
适配器不得使用当前便利 set_generic_password 路径写入产品根密钥。

### 3.3 iOS 适配器

iOS 使用同一 SecItem 语义。
Keychain 实现固定为 data protection Keychain。
后台传输密钥使用 kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly。
审批密钥使用 kSecAttrAccessibleWhenUnlockedThisDeviceOnly。
审批密钥可以使用 kSecAccessControlUserPresence。
可选的严格策略使用 kSecAccessControlBiometryCurrentSet。
后台任务不申请用户在场提示。
后台任务读取失败时返回 credential_device_locked 或 credential_auth_required。
主应用默认使用应用私有 access group。
分享扩展不保存长期根密钥。
分享扩展只写入 App Group 临时内容。
主应用负责后续摘要、传输和记录写入。

### 3.4 Windows 适配器

原生接口使用 CredWriteW、CredReadW 和 CredDeleteW。
凭据类型使用 CRED_TYPE_GENERIC。
持久化使用 CRED_PERSIST_LOCAL_MACHINE。
TargetName 使用 Covio.CredentialVault.v1.<vault_id>.<purpose>.<generation>。
TargetName 使用固定公司前缀。
TargetName 和 Type 作为唯一项标识。
CredentialBlob 只保存版本化根密钥包装。
CredentialBlob 最大值为 2560 字节。
当前 v1 包装建议小于 256 字节。
适配器不保存业务记录到 Credential Manager。
适配器不枚举用户的其他凭据。
适配器不删除不匹配前缀的凭据。
适配器串行化同一 target 的写操作。
适配器把 ERROR_NOT_FOUND 映射为 credential_not_found。
适配器把 ERROR_NO_SUCH_LOGON_SESSION 映射为 credential_backend_unavailable 或 credential_access_denied。
适配器把 ERROR_INVALID_PARAMETER 映射为 credential_invalid_argument。
认证确认使用 UserConsentVerifierInterop。
认证确认只标记为 OsUiOnly。
认证确认不能提升 BackendCapabilities.authentication_enforcement 到 Cryptographic。
如需要密码学绑定的 Windows 策略，使用独立 Windows Hello 或 CNG 方案。
该方案尚未验证。

### 3.5 Android 适配器

Android 使用 Keystore AES-256-GCM 密钥包装根密钥。
后台传输别名使用 covio.vault.background.<vault_id>.<generation>。
审批别名使用 covio.vault.approval.<vault_id>.<generation>。
后台别名不要求用户认证。
后台别名不启用 setUnlockedDeviceRequired。
审批别名可以要求用户认证。
审批别名使用 BiometricPrompt CryptoObject。
只有 Android 15 及以上才把 setUnlockedDeviceRequired 作为强制策略。
StrongBox 优先使用 setIsStrongBoxBacked(true)。
StrongBox 不可用时执行以下规则。
如 HardwareBacking 为 Required，返回 credential_policy_unsupported。
如 HardwareBacking 为 Preferred，回退普通 Keystore 并在能力中报告。
如 HardwareBacking 为 NotRequired，回退普通 Keystore。
密文保存在 no-backup 目录。
密文不进入 Auto Backup。
密文不进入 D2D 转移。
密钥失效时返回 credential_key_invalidated。
认证窗口只接受当前 Activity 的显式上下文。
JNI 只导出 provision、open、rotate、delete 和 inspect。
JNI 不导出任意 Java 类和方法调用。

## 4. 密钥生命周期

### 4.1 状态

| 状态 | 含义 | 允许操作 |
| --- | --- | --- |
| Absent | 无根密钥 | bootstrap |
| Provisioning | 正在创建根密钥 | cancel |
| Active | 根密钥可用 | store、open、rotate |
| Locked | 当前不可读 | unlock、status |
| AuthRequired | 需要用户认证 | authenticate |
| Invalidated | 平台密钥永久失效 | reset、re_pair |
| Orphaned | 密文存在但根密钥不存在 | re_pair、reset |
| Rotating | 正在生成或切换根密钥 | resume、rollback |
| Retired | 旧代际已停用 | delete |
| Deleting | 正在删除 | resume |

### 4.2 转换

正常转换：

Absent -> Provisioning -> Active
Active -> Rotating -> Active
Locked -> AuthRequired -> Active
Active -> Retired -> Deleting -> Absent

异常转换：

Provisioning -> Absent
Rotating -> Active
Rotating -> Retired
Active -> Invalidated
Active -> Orphaned
AuthRequired -> Locked
Deleting -> Retired

异常转换必须保留可恢复状态。
异常转换不能覆盖密文。
用户确认重置后才能删除全部记录。

### 4.3 轮换

触发条件如下。

1. 用户主动轮换。
2. 设备撤销后需要轮换组密钥。
3. 根密钥策略升级。
4. 旧算法停止使用。
5. 怀疑根密钥泄露。
6. 后端迁移需要新代际。

轮换步骤见第 5.4 节。
每次轮换递增 key_generation。
旧代际只保留到迁移验证完成。
旧代际删除失败时保留删除标记。

## 5. 关键流程

### 5.1 首次创建

1. 检查平台能力。
2. 检查请求策略是否可满足。
3. 生成 32 字节根密钥。
4. 创建随机 vault_id。
5. 写入原生根密钥。
6. 执行根密钥回读。
7. 创建仓库元数据。
8. 写入空记录索引。
9. 返回 VaultStatus。

任何一步失败都清除本步骤创建的内容。
根密钥回读失败时不得创建密文。

### 5.2 记录写入

1. 校验 CredentialId 和 RecordKind。
2. 校验秘密长度不超过 16 KiB。
3. 打开根密钥。
4. 派生记录密钥。
5. 生成随机 nonce。
6. 构造 AAD。
7. 执行 AEAD 加密。
8. 原子写入记录。
9. 回读并解密验证。
10. 提交修订号。
11. 零化根密钥和秘密缓冲区。

### 5.3 记录读取

1. 校验调用者和 RecordKind。
2. 打开根密钥。
3. 读取记录头和密文。
4. 检查格式版本。
5. 重建 AAD。
6. 执行 AEAD 解密。
7. 在受限闭包中使用秘密。
8. 零化临时缓冲区。
9. 不把秘密写入返回值。

读取失败分为三类。
记录头损坏返回 credential_record_corrupt。
AAD 或标签失败返回 credential_integrity_failed。
根密钥无法打开返回 credential_auth_required、credential_device_locked、credential_key_invalidated 或 credential_recovery_required。

### 5.4 根密钥轮换

1. 生成新根密钥。
2. 把新根密钥写入新 generation。
3. 验证新根密钥可读。
4. 使用旧根密钥读取记录。
5. 使用新根密钥重新加密记录。
6. 写入新仓库快照。
7. 回读全部新记录。
8. 原子切换活动指针。
9. 标记旧 generation 为 Retired。
10. 删除旧根密钥。
11. 清理旧快照。

第 8 步前失败时保留旧仓库。
第 8 步后失败时保留新仓库和回滚标记。

### 5.5 配对写入

1. 接收端扫描二维码。
2. 双方验证临时会话。
3. 双方显示相同确认码。
4. 用户确认。
5. Rust core 构造 PairingRecord。
6. 使用审批密钥授权写入。
7. 保存对端设备标识和组密钥。
8. 返回配对结果。

二维码不携带长期根密钥。
二维码不携带提供方 API 密钥。
二维码原文不写入日志。
配对记录不写入 UI snapshot。

### 5.6 设备撤销

1. 用户选择撤销设备。
2. 打开审批密钥。
3. 删除对端 PairingRecord。
4. 生成新的组密钥。
5. 重新加密受影响的传输记录。
6. 保存撤销标记。
7. 记录非秘密审计事件。
8. 通知其他在线设备。

撤销失败时保留撤销标记。
下一次启动继续完成密钥轮换。

### 5.7 后台接收降级

| 平台 | 锁定状态 | 后台处理 | UI 处理 |
| --- | --- | --- | --- |
| macOS | 设备锁定时 data protection Keychain 可能不可读 | 暂停任务 | 解锁后恢复 |
| iOS | 首次解锁后可读 AfterFirstUnlock 项 | 可继续可读任务 | 用户在场任务暂停 |
| Windows | 当前用户会话有效 | 可读取 LOCAL_MACHINE 项 | 认证确认按策略执行 |
| Android | 后台密钥不要求认证 | 可继续包装和解密 | 审批任务暂停 |

如果用户选择严格前台策略，后台接收暂停。
恢复时使用已保存的传输任务状态。
暂停不等于删除任务。
后台失败必须返回可恢复状态。

### 5.8 备份恢复

首发版本不提供产品级密钥备份。
备份策略如下。

1. 根密钥不导出。
2. 密文不进入云备份。
3. Android 密文进入 no-backup 目录。
4. Apple 根密钥使用 ThisDeviceOnly。
5. Windows 根密钥使用 LOCAL_MACHINE。
6. 新设备发现密文但无根密钥时返回 credential_recovery_required。
7. 用户重新二维码配对。
8. 旧密文隔离，不自动删除。

未来若提供可恢复导出，必须新增独立 ADR。
导出方案需要用户口令、恢复码或外部密钥托管。

## 6. 迁移

### 6.1 当前 macOS 到 data protection Keychain

1. 读取旧 file-based Keychain 项。
2. 写入新的 data protection Keychain 项。
3. 回读新项并比较摘要。
4. 创建新的根密钥仓库。
5. 把旧业务 secret 写入记录。
6. 逐项回读验证。
7. 全部成功后写入迁移完成标记。
8. 删除旧项。
9. 删除失败时保留下一次清理任务。

迁移期间旧适配器只读。
迁移期间新写入进入新仓库。
迁移失败时回滚到旧读取路径。

### 6.2 当前 Windows ENTERPRISE 到 LOCAL_MACHINE

1. 使用旧 TargetName 读取旧凭据。
2. 使用新 TargetName 写入 LOCAL_MACHINE 凭据。
3. 回读新凭据并检查 Persist。
4. 创建新的根密钥仓库。
5. 逐项迁移业务 secret。
6. 回读全部记录。
7. 写入迁移完成标记。
8. 删除旧 TargetName。

不要直接在旧 TargetName 上修改 Persist。
直接修改可能受现有字段约束。
新 TargetName 可以提供清晰回滚路径。

### 6.3 iOS 和 Android

iOS 当前没有产品凭据实现。
Android 当前没有产品凭据实现。
两个平台直接使用新合同。
它们不需要旧格式迁移。
它们仍需要祈祷的备份恢复测试，见第 9 节。

### 6.4 迁移状态

| 状态 | 含义 | 结束条件 |
| --- | --- | --- |
| NotStarted | 未开始 | 用户或升级流程触发 |
| ReadingLegacy | 读取旧值 | 全部旧值回读成功 |
| WritingNew | 写入新仓库 | 全部新值回读成功 |
| Verified | 新旧摘要一致 | 迁移完成标记写入 |
| CleanupPending | 等待删除旧值 | 旧值删除成功 |
| RolledBack | 已回退 | 旧路径恢复可用 |
| Failed | 迁移失败 | 保留错误和旧数据 |

## 7. 安全设计

### 7.1 设备绑定

设备绑定由三层组成。

1. 原生存储的设备限定。
2. AAD 中的随机设备 ID。
3. 根密钥不导出。

Apple 使用 ThisDeviceOnly。
Windows 使用 LOCAL_MACHINE。
Android 使用应用私有 Keystore 别名和 no-backup 密文。
设备 ID 不使用硬件序列号。
设备 ID 可以因重装而变化。
设备 ID 变化时旧仓库按恢复失败处理。

### 7.2 硬件保护

硬件保护是独立能力。
Apple Secure Enclave 可以保护设备身份密钥。
Android Keystore 可以绑定 TEE 或 StrongBox。
Windows Credential Manager 不提供通用硬件保护查询。
Windows 强绑定需要独立 CNG、TPM 或 Windows Hello 方案。
能力对象必须报告 Unknown 或 Unsupported。
产品不能把 Unknown 显示为硬件保护。

### 7.3 用户在场

Apple 使用 SecAccessControl。
Android 使用 Keystore 认证要求和 BiometricPrompt CryptoObject。
Windows 使用独立 UserConsentVerifier。
Windows 结果必须标记为 OsUiOnly。
后台传输密钥默认不要求用户在场。
审批密钥默认要求用户在场。
用户只能明确选择降级。
后台任务不能自动选择降级。

### 7.4 生物认证失效

Apple biometryCurrentSet 项在生物登记变化后失效。
Android 生物专用密钥在生物登记变化后失效。
适配器应映射为 credential_key_invalidated。
如果平台只返回 item-not-found，适配器必须报告不确定性。
产品不得把不确定结果写成认证失败。

### 7.5 备份和恢复

首发版本只支持设备绑定。
首发版本不支持跨设备密钥恢复。
密文可以存在，但根密钥不可恢复时不得解密。
恢复失败时不删除密文。
恢复失败时不覆盖设备身份密钥。
用户可以显式重置后重新配对。

### 7.6 最小权限

Apple 规则如下。

1. 主应用默认使用私有 access group。
2. 不为便利扩大共享 access group。
3. 扩展只获得完成任务所需的组。
4. 删除任意 service 的 C ABI。
5. helper 不读取根密钥。

Windows 规则如下。

1. 只访问 Covio 前缀的 TargetName。
2. 不枚举其他通用凭据。
3. 不使用 PasswordVault。
4. 不在 SYSTEM 服务读取用户根密钥。
5. 不把 UserConsentVerifier 当作 ACL。

Android 规则如下。

1. 不使用 sharedUserId。
2. 不导出 Keystore 回调服务。
3. 只暴露五个 JNI 方法。
4. 密文放 no-backup 目录。
5. 认证 Activity 使用显式上下文。
6. 不使用任意反射调用。

Rust 规则如下。

1. 不提供通用 secret read。
2. 不把根密钥放入普通 JSON。
3. 不把秘密放入 snapshot、event 或日志。
4. 只在受限闭包中使用秘密。
5. 释放秘密前先零化。
6. 迁移使用显式 allowlist。
7. 不根据文件名推断秘密类型。
8. 不自动升级安全策略。

### 7.7 日志脱敏

允许记录的字段如下。

1. operation。
2. backend。
3. result。
4. error_code。
5. retryable。
6. duration_ms。
7. key_generation。
8. record_kind。
9. correlation_id。
10. 能力布尔值或枚举值。

禁止记录的字段如下。

1. 根密钥。
2. 记录明文。
3. 记录密文。
4. 二维码原文。
5. 完整记录 ID。
6. 文件路径。
7. 用户名或账户名。
8. 设备序列号。
9. 完整原生错误文本。
10. 生物认证模板或认证材料。

记录 ID 如需关联日志，使用安装级随机 salt 的摘要。
salt 不写入仓库文件。
salt 不跨设备复制。
日志轮转和保留期限由独立隐私策略决定。

### 7.8 内存

秘密只使用不可打印类型。
秘密类型不实现 Clone、Debug、Serialize 和 Display。
秘密缓冲区使用 zeroize。
错误路径也必须执行零化。
C ABI、UniFFI 和 JNI 边界只传递受限输入或句柄。
FFI 释放函数先零化再释放。
内存锁定属于可选增强。
内存锁定不能替代 zeroize。

## 8. 可靠性设计

1. 记录写入使用原子替换。
2. 记录回读失败时保留旧版本。
3. 根密钥轮换使用两阶段提交。
4. 迁移逐项验证。
5. 旧值删除失败时保留清理任务。
6. 密钥失效时不自动生成替代根密钥。
7. 记录损坏时隔离单条记录。
8. 仓库损坏时保留备份和诊断摘要。
9. 并发写同一记录时返回 credential_busy 或串行化。
10. 后台恢复使用持久化任务状态。
11. 适配器操作有超时。
12. 超时后不重复执行非幂等写操作。

## 9. 测试矩阵

测试矩阵详见 [validation/README.md](validation/README.md)。
测试案例分为五组。
五组是 macOS、iOS、Windows、Rust 合同和 Android 合同。
所有测试使用合成秘密。
所有测试使用唯一测试名称。
所有测试执行清理。
所有真实结果在案例文件中回填。

### 9.1 合同测试

1. 能力查询。
2. 策略不支持时失败关闭。
3. 记录往返。
4. 记录篡改失败。
5. 设备 ID 不匹配失败。
6. 错误码映射。
7. 秘密零化。
8. 日志脱敏。
9. 轮换回滚。
10. 丢失根密钥恢复。

### 9.2 平台测试

1. macOS data protection Keychain 和锁定状态。
2. iOS 后台读取和生物认证失效。
3. Windows LOCAL_MACHINE 和用户隔离。
4. Windows UserConsentVerifier 的用户动作。
5. Android Keystore 包装和认证。
6. Android no-backup 和设备直传。
7. 新设备备份恢复。

### 9.3 验收阈值

以下阈值是建议值。
正式阈值在测试入口建立后评审。

1. 不含用户提示的根密钥读取 P95 小于 500 毫秒。
2. 不含用户提示的记录读写 P95 小于 100 毫秒。
3. 记录损坏检测率为 100%。
4. 根密钥缺失检测率为 100%。
5. 策略不支持检测率为 100%。
6. 秘密日志泄漏为 0。
7. 测试记录清理成功率为 100%。
8. 迁移回滚成功率为 100%。

## 10. 失败模式

| 失败 | 错误码 | 处理 |
| --- | --- | --- |
| Keychain 项缺失 | credential_not_found | 检查备份或重新配对 |
| Keychain 需要交互 | credential_auth_required | 在用户上下文认证 |
| 设备锁定 | credential_device_locked | 解锁后重试 |
| 用户取消 | credential_user_cancelled | 保持旧状态 |
| Windows 登录会话不存在 | credential_backend_unavailable | 在用户上下文重试 |
| Windows 项缺失 | credential_not_found | 检查迁移或恢复 |
| Android 未认证 | credential_auth_required | 启动 BiometricPrompt |
| Android 密钥失效 | credential_key_invalidated | 重新配对或重置 |
| StrongBox 不可用 | credential_policy_unsupported | 按策略回退或拒绝 |
| 记录头损坏 | credential_record_corrupt | 隔离记录 |
| AEAD 校验失败 | credential_integrity_failed | 隔离记录并重新配对 |
| 根密钥丢失 | credential_recovery_required | 重新配对 |
| 用户取消轮换 | credential_cancelled | 保留旧根密钥 |
| 原生存储忙 | credential_busy | 延迟重试 |
| 原生存储超时 | credential_timeout | 检查状态后重试 |
| 迁移版本不支持 | credential_version_unsupported | 升级应用 |

## 11. 合规设计

1. 不建立账号体系。
2. 不建立云端内容存储。
3. 不收集硬件序列号。
4. 日志不记录秘密和个人内容。
5. 用户可显式清除本地仓库。
6. 用户可显式撤销已配对设备。
7. 首次使用说明本地网络和凭据用途。
8. 错误提示说明用户下一步。
9. 安全降级需要用户明确选择。
10. 正式发布前完成隐私说明和平台权限说明。

## 12. 实施计划

### 12.1 阶段一：合同

1. 评审错误码。
2. 评审能力模型。
3. 评审根密钥和记录格式。
4. 评审设备身份密钥格式。
5. 评审 AEAD 和 KDF 方案。

### 12.2 阶段二：Rust facade

1. 实现 CredentialId 和 RecordKind。
2. 实现 RecordVault。
3. 实现能力检查。
4. 实现错误映射。
5. 实现零化。
6. 实现测试后端。

### 12.3 阶段三：Apple

1. 改造 macOS 适配器。
2. 显式使用 data protection Keychain。
3. 增加 accessibility 和 access control。
4. 增加 iOS 目标。
5. 增加后台传输策略。
6. 增加锁定和认证测试。

### 12.4 阶段四：Windows

1. 移除 keyring ENTERPRISE 写入路径。
2. 实现 CredWriteW、CredReadW 和 CredDeleteW。
3. 使用 LOCAL_MACHINE。
4. 增加 TargetName 白名单。
5. 增加 UserConsentVerifier 的独立能力标记。
6. 增加迁移和用户隔离测试。

### 12.5 阶段五：Android

1. 建立 Android 工程。
2. 实现 Keystore 包装。
3. 实现 BiometricPrompt CryptoObject。
4. 实现 no-backup 目录。
5. 实现 JNI 白名单。
6. 实现设备直传和恢复测试。

### 12.6 阶段六：桥接

1. 删除通用 secret read。
2. 增加受限输入句柄。
3. 增加零化释放函数。
4. 增加 C ABI 错误码。
5. 增加 UniFFI 错误映射。
6. 增加 JNI 错误映射。
7. 增加 binding 漂移检查。

## 13. 回滚条件

出现以下任一条件时停止切换。

1. 根密钥回读失败。
2. 记录回读失败。
3. AEAD 校验失败率大于 0。
4. 设备绑定测试失败。
5. 备份恢复产生可解密旧记录。
6. Android 密钥失效未映射。
7. Windows 凭据写入非 LOCAL_MACHINE。
8. 秘密进入日志或 UI snapshot。
9. 通用 secret read 仍暴露在产品 ABI。
10. 迁移无法回滚到旧路径。

回滚时保留新密文。
回滚时保留旧根密钥。
回滚时禁止自动覆盖用户数据。
回滚完成后写入诊断摘要。

## 14. 产品化条件

满足以下条件后才能进入首发产品路径。

1. 三个首发平台的合同测试通过。
2. macOS 和 iOS 真机证据完整。
3. Windows 11 真机证据完整。
4. 根密钥不迁移到新设备的证据完整。
5. Android 合同和后续工程边界清楚。
6. 所有秘密日志检查通过。
7. FFI 释放路径零化测试通过。
8. 迁移回滚测试通过。
9. 用户错误提示通过产品评审。
10. 安全负责人完成合同复核。

正式发布前还要完成文档同步。
本主题不修改正式发布流程。
本主题不修改现有代码。
