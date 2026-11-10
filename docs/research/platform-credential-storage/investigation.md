# 凭据存储调研与技术分析

推荐路径是平台原生安全存储保护根密钥，Rust facade 统一管理加密记录。原生接口不能提供同一套访问控制语义。

> 本文件记录调研方法、来源、系统模型、平台能力、候选方案、源码分析、反证和已知缺口。

## 1. 调研方法

调研分四步执行。

1. 阅读 Covio 的研究规范、跨平台目标架构和现有 secret 实现。
2. 阅读 Apple、Microsoft 和 Android 的官方接口文档、安全说明和备份说明。
3. 对比原生安全存储、薄封装和 Rust 加密仓库。
4. 从现有源码识别合同缺口，并设计失败关闭的统一 facade。

本调研没有执行平台原生测试。
本调研没有验证 iOS 真机、Android 真机或 Windows Credential Manager 实验。
所有实际验证写在 [validation/README.md](validation/README.md)。
所有计划项保持“尚未执行”。

## 2. 来源范围

| 等级 | 来源 | 用途 |
| --- | --- | --- |
| A | Apple Security API 参考、Apple 技术说明 TN3137 | Keychain 行为和安全属性 |
| A | Microsoft Win32 Credential Manager API 参考 | Credential Manager 类型、限制和持久化 |
| A | Android Keystore API 参考 | 密钥生成、认证和失效语义 |
| A | UniFFI 用户指南 | 跨语言错误和 foreign trait 语义 |
| B | Covio 当前源码和 Cargo 锁文件 | 现有实现、依赖版本和边界 |
| C | Apple、Microsoft、Android 的安全指南和备份指南 | 产品能力和操作限制 |
| C | zeroize crate 文档 | 内存零化建议 |

官方 API 参考和官方技术说明优先。
厂商示例页面只用于解释接口，不替代 API 定义。
第三方库源码只用于说明当前实现，不替代平台规范。

## 3. 领域模型

### 3.1 数据分层

| 层 | 数据 | 保存位置 | 生命周期 |
| --- | --- | --- | --- |
| 根密钥层 | 32 字节随机根密钥 | 平台原生安全存储 | 设备绑定，直到轮换或重置 |
| 记录层 | 配对记录、传输组密钥、提供方密钥 | Rust 管理的密文仓库 | 按业务规则保留 |
| 元数据层 | 版本、记录 ID、用途、修订号 | Rust 管理的数据文件 | 与记录同步 |
| 设备身份层 | 非导出签名密钥或密钥句柄 | Apple Secure Enclave、Windows CNG、Android Keystore | 设备生命周期 |
| 审计层 | 操作类别、结果、耗时、关联 ID | 日志系统 | 按日志策略保留 |

根密钥不直接进入业务记录。
记录密钥由根密钥经 KDF 派生。
记录载荷使用 AEAD 加密。
AAD 绑定应用 ID、设备 ID、记录 ID、用途和格式版本。

### 3.2 术语

| 术语 | 含义 |
| --- | --- |
| 凭据 | Covio 管理的秘密数据 |
| 根密钥 | 保护记录仓库的随机密钥 |
| 记录 | 密文、元数据和用途标识 |
| 设备绑定 | 数据只在指定设备边界内可用 |
| 硬件保护 | 密钥操作由安全硬件执行 |
| 用户在场 | 操作系统要求用户完成认证 |
| 生物认证 | Touch ID、Face ID、Android BiometricPrompt 等生物识别 |
| 备份迁移 | 数据恢复到另一台设备 |
| 后端迁移 | 同一设备更换存储格式或适配器 |
| 失败关闭 | 无法证明安全条件时拒绝操作 |

### 3.3 能力维度

合同必须分别表达四项能力。
四项能力是设备绑定、硬件保护、用户在场和备份范围。
四项能力不能合并成一个布尔值。
一个平台可以为设备绑定，但不为硬件保护。
一个平台可以要求认证，但不把认证绑定到存储项。
一个平台可以禁止迁移，但允许同设备恢复。
UI 必须展示有效能力。
UI 不能把平台的 UI 确认提示显示为加密 ACL。

## 4. 约束模型

### 4.1 Apple 约束

| 约束 | 影响 | 证据 |
| --- | --- | --- |
| macOS 有 file-based 和 data protection 两种 Keychain | 必须显式选择 data protection 实现 | E-06 |
| iOS 只提供 data protection Keychain | iOS 和 macOS 可以共享 SecItem 语义 | E-06 |
| SecItem 可能阻塞调用线程 | 调用必须离开 UI 主线程 | E-07 |
| ThisDeviceOnly 不迁移到另一台设备 | 新设备恢复不能依赖旧 Keychain 项 | E-08 |
| AfterFirstUnlock 可供后台应用使用 | 后台传输密钥可以选择此可用性 | E-08 |
| 用户在场和生物认证由 SecAccessControl 表达 | 不能只设置比较字符串 | E-09 |
| iCloud 同步与 ThisDeviceOnly 冲突 | 设备绑定项必须禁止同步 | E-10 |
| Secure Enclave 只支持 P-256 且不能导入旧密钥 | 设备身份密钥必须现场生成 | E-11 |
| data protection Keychain 只在用户上下文可用 | launchd daemon 不能读取长期根密钥 | E-06 |

### 4.2 Windows 约束

| 约束 | 影响 | 证据 |
| --- | --- | --- |
| 通用凭据的 blob 上限为 2560 字节 | 原生存储只保存根密钥或小包装 | E-14 |
| TargetName 和 Type 共同标识凭据 | 记录 ID 必须形成稳定、可审计的名称 | E-14 |
| LOCAL_MACHINE 只在本机同一用户的后续登录可见 | 设备绑定可选用此项 | E-15 |
| ENTERPRISE 可能随漫游配置到其他计算机 | 设备绑定禁用此持久化范围 | E-15 |
| Credential Manager 使用当前令牌的凭据集 | 后台进程必须运行在正确用户上下文 | E-16 |
| UserConsentVerifier 是独立确认接口 | 不能把它写成 Credential Manager 项级 ACL | E-18 |
| PasswordVault 会随 Microsoft 账户漫游 | 设备绑定秘密不使用 PasswordVault | E-17 |
| PasswordVault 每应用最多 20 条 | 不适合作为通用记录仓库 | E-17 |
| Credential Guard 的适用范围需要确认 | 不能默认宣称所有通用凭据都由 VBS 保护 | E-19 |

### 4.3 Android 约束

| 约束 | 影响 | 证据 |
| --- | --- | --- |
| Keystore 保存非导出密钥，不保存任意大块秘密 | 根密钥必须用 Keystore 密钥包装，密文另存 | E-20 |
| 密钥可以绑定 TEE 或 StrongBox | 能力必须查询，不能假定有硬件保护 | E-20 |
| 用户认证要求可由 Keystore 执行 | 每个密钥独立配置认证要求 | E-21 |
| 锁屏被移除或重置会永久失效认证绑定密钥 | 适配器必须返回失效错误 | E-21 |
| 生物登记变化默认使生物专用密钥失效 | 产品必须选择失效或允许策略 | E-21 |
| setUnlockedDeviceRequired 在旧系统有已知缺陷 | 只在 Android 15 及以上作为强制策略 | E-21 |
| StrongBox 不可用时可回退普通 Keystore | 回退必须符合预先声明的策略 | E-20、E-22 |
| Auto Backup 默认包含多数应用数据 | 密文目录必须排除 | E-23 |
| Android 12 起 allowBackup=false 不保证停止所有 D2D 转移 | 必须使用备份规则和 no-backup 目录 | E-23 |

## 5. 控制路径

### 5.1 创建根密钥

1. Rust 生成随机根密钥。
2. Rust 创建仓库元数据。
3. Rust 调用平台适配器保存根密钥。
4. 平台适配器返回根密钥句柄和有效能力。
5. Rust 立即执行一次读取验证。
6. 验证失败时删除新根密钥并返回错误。
7. 验证成功后提交仓库状态。

### 5.2 存储记录

1. UI 或 Rust core 提交记录用途和秘密值。
2. facade 检查调用者、用途和长度。
3. facade 从平台适配器打开根密钥。
4. facade 派生记录密钥。
5. facade 生成随机 nonce 并执行 AEAD 加密。
6. facade 原子写入记录和元数据。
7. facade 回读并校验记录。
8. 回读失败时保留旧记录或回滚。

### 5.3 读取记录

1. facade 检查记录用途和调用者。
2. facade 打开根密钥。
3. facade 读取元数据和密文。
4. facade 校验格式版本和 AAD。
5. facade 执行 AEAD 解密。
6. facade 在受限闭包中使用秘密。
7. 闭包结束后立即零化秘密缓冲区。

### 5.4 轮换

1. 生成新根密钥。
2. 使用旧根密钥读取所有需要迁移的记录。
3. 使用新根密钥重新加密记录。
4. 原子写入新仓库版本。
5. 回读全部记录并校验。
6. 切换活动仓库指针。
7. 删除旧根密钥。
8. 删除失败时保留旧根密钥句柄和回滚标记。

### 5.5 失败关闭

以下条件必须失败关闭。

1. 平台能力不满足请求策略。
2. 平台存储不可用。
3. 根密钥不存在但密文存在。
4. 记录版本高于当前支持版本。
5. AEAD 校验失败。
6. 设备 ID 与 AAD 不匹配。
7. 轮换未完成验证。
8. 迁移未完成全部回读。

失败关闭不自动生成新根密钥。
自动生成新根密钥会让旧记录不可恢复。
自动生成新根密钥还会掩盖备份恢复或密钥失效。

## 6. 信任边界

### 6.1 主应用边界

主应用拥有用户交互上下文。
主应用可以请求 Keychain、Credential Manager 和 Keystore。
主应用不得把根密钥写入日志、崩溃报告或 UI snapshot。
主应用只通过 facade 使用根密钥。

### 6.2 后台任务边界

后台任务可以请求传输组密钥。
后台任务不能请求审批密钥或导出根密钥。
后台任务不能修改平台访问策略。
后台任务遇到认证要求时返回可恢复状态。
后台任务不能自动降低用户在场要求。

### 6.3 Helper 和 daemon 边界

macOS launchd daemon 不能使用 data protection Keychain。
Windows SYSTEM 服务不能读取当前用户的 Credential Manager 凭据。
因此长期根密钥只由用户上下文进程读取。
后台 daemon 只接收短生命周期会话密钥。
短生命周期会话密钥由认证 IPC 或内存句柄传递。
会话密钥不写入 daemon 日志和配置文件。

### 6.4 对端设备边界

对端设备持有自己的根密钥和设备身份密钥。
对端设备不持有本机的根密钥。
配对记录只包含信任关系和组密钥。
撤销设备后删除对应记录。
撤销设备后轮换受影响的组密钥。

## 7. 现有能力矩阵

| 平台 | 原生接口 | 可保存内容 | 设备绑定 | 备份与同步 | 用户在场 | 生物认证绑定 | 主要限制 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| macOS | Security.framework SecItem | 通用密码和密钥项 | 可用 ThisDeviceOnly | 可关闭同步 | 可用 SecAccessControl | 可用 Face ID 或 Touch ID | 必须显式选择 data protection Keychain |
| iOS | Security.framework SecItem | 通用密码和密钥项 | 可用 ThisDeviceOnly | 可关闭同步 | 可用 SecAccessControl | 可用 Face ID 或 Touch ID | 后台可用性受设备锁定和会话限制 |
| Windows | Win32 Credential Manager | 通用凭据小 blob | LOCAL_MACHINE 可用 | ENTERPRISE 可能漫游 | 独立 UserConsentVerifier | 没有通用项级 ACL 证据 | blob 上限 2560 字节 |
| Android | Android Keystore | 非导出加密密钥 | 密钥绑定应用和设备 | 密文需应用排除备份 | 可用 Keystore 认证要求 | 可用 BiometricPrompt 和 CryptoObject | 旧版本 unlocked 策略有已知缺陷 |

“没有通用项级 ACL 证据”是推论。
它表示公开通用凭据结构和 UserConsentVerifier 文档没有提供等同 ACL 的接口。
它不表示 Windows 没有其他安全机制。

## 8. 平台能力分析

### 8.1 Apple Keychain

Apple 所有平台都提供 Keychain。
iOS、tvOS 和 watchOS 只使用 SecItem 和 data protection Keychain。
macOS 同时存在 file-based Keychain 和 data protection Keychain。
Apple 技术说明建议新代码优先使用 data protection Keychain。
macOS 的 SecItem 默认仍指向 file-based Keychain。
要使用 data protection Keychain，必须显式设置 kSecUseDataProtectionKeychain。
macOS 的 data protection Keychain 与 iOS 行为接近。
macOS 的 file-based Keychain 使用不同的访问控制模型。
本主题要求 Apple 适配器使用 data protection Keychain。

Keychain 项可以设置可用性。
WhenUnlocked 只在设备解锁时可读。
WhenUnlockedThisDeviceOnly 还禁止迁移到另一台设备。
AfterFirstUnlock 适合后台应用，解锁一次后到下次重启前可读。
AfterFirstUnlockThisDeviceOnly 同时禁止迁移。
WhenPasscodeSetThisDeviceOnly 要求设备有密码。
设备移除密码时，该类的项会被删除。
ThisDeviceOnly 项可以恢复到原设备，但不迁移到新设备。

SecAccessControl 可以要求用户在场。
userPresence 允许生物认证或设备密码。
biometryCurrentSet 要求当前登记的生物集合。
新增或移除 Touch ID 手指会使 biometryCurrentSet 项失效。
Face ID 重新登记也会使该项失效。
SecItem 调用可能阻塞线程。
Apple 文档要求把可能显示提示的操作移出主线程。
因此 facade 不得在 SwiftUI 主 actor 上同步调用原生 Keychain。

kSecAttrSynchronizable 为 true 时，Keychain 项通过 iCloud 同步。
ThisDeviceOnly 与同步不兼容。
设备绑定项必须明确设置 kSecAttrSynchronizable 为 false。
kSecAttrAccessGroup 控制应用和扩展共享。
默认 access group 是应用 ID。
只有在 App Extension 确实需要读取时才增加共享 access group。
主应用单独使用的根密钥不应扩大 access group。

Secure Enclave 提供硬件密钥管理器。
Secure Enclave 只支持 P-256 密钥。
Secure Enclave 不能导入既有私钥。
Secure Enclave 私钥不能导出。
macOS 需要受支持的硬件。
iOS 需要 A7 或更新处理器。
设备身份密钥可以使用 Secure Enclave。
长期根密钥仍可以用 Keychain 保存。

### 8.2 Windows Credential Manager

Win32 Credential Manager 使用 CREDENTIALW 描述凭据。
CRED_TYPE_GENERIC 表示通用凭据。
通用凭据不绑定任何认证包。
TargetName 和 Type 唯一标识一条通用凭据。
TargetName 大小写不敏感。
通用凭据 blob 最大为 5 × 512 字节。
最大值为 2560 字节。
TargetName 最大长度为 32767 个字符。
Microsoft 建议 TargetName 使用公司前缀。
CredentialBlob 的字节序和对齐由应用定义。
Credential Manager 负责安全保存通用凭据。
公开说明没有给通用凭据提供额外认证特征。

Persist 字段有三个常用值。
CRED_PERSIST_SESSION 只在当前登录会话存在。
CRED_PERSIST_LOCAL_MACHINE 只在本机同一用户的后续登录存在。
CRED_PERSIST_ENTERPRISE 可以在同一用户的其他计算机登录可见。
ENTERPRISE 是否漫游取决于用户配置。
本主题选择 CRED_PERSIST_LOCAL_MACHINE。
本主题不选择 CRED_PERSIST_ENTERPRISE。

CredRead、CredWrite 和 CredDelete 使用当前令牌的凭据集。
当前令牌不能禁用用户 SID。
网络登录会话没有关联凭据集。
后台服务必须运行在目标用户上下文中。
SYSTEM 服务不能假设可以读取用户的 Credential Manager 项。

PasswordVault 是另一套 Credential Locker 接口。
PasswordVault 可以随 Microsoft 账户漫游到其他设备。
每个应用最多保存 20 条 PasswordVault 凭据。
非 AppContainer 桌面应用可以访问当前用户的所有 locker。
PasswordVault 不适合设备绑定根密钥。

UserConsentVerifier 可以请求 Windows Hello 或指纹确认。
桌面应用需要使用面向窗口的 interop 接口。
结果包括 Verified、Canceled、RetriesExhausted 和 NotConfiguredForUser。
UserConsentVerifier 是用户确认接口。
公开通用凭据结构没有引用 UserConsentVerifier 的项级 ACL。
因此合同不能把 UserConsentVerifier 写成 Credential Manager 的加密访问控制。
更强绑定需要 Windows Hello 密钥、CNG 或 TPM 方案。
这些方案需要单独验证。

Credential Guard 使用 VBS 保护域凭据。
Microsoft 文档列出的保护对象包括 Credential Manager 凭据。
默认启用条件和域账户相关。
通用凭据是否全部受相同保护没有足够证据。
本主题不宣称所有通用凭据由 Credential Guard 保护。

### 8.3 Android Keystore

Android Keystore 保存加密密钥。
Keystore 密钥不可导出。
应用执行加密操作时，密钥材料不进入应用进程。
密钥可以绑定 TEE 或 StrongBox。
应用可以用 KeyInfo 查询安全级别。
StrongBox 的设备支持、算法和性能不同。
StrongBox 不可用时，平台可能抛出 StrongBoxUnavailableException。
回退到普通 Keystore 必须由产品策略明确允许。
本主题把 Android 合同设计为 Keystore 包装根密钥。

KeyGenParameterSpec 支持用户认证要求。
setUserAuthenticationRequired 要求安全锁屏。
setUserAuthenticationParameters 可以设置认证有效期和认证类型。
认证类型可以包含生物认证和设备凭证。
要求生物专用密钥时，新增生物登记默认使密钥失效。
移除全部生物登记也会使密钥失效。
锁屏被禁用或强制重置会使认证绑定密钥永久失效。
这些情况需要映射为 credential_key_invalidated。

setUnlockedDeviceRequired 要求设备处于解锁状态。
它和 setUserAuthenticationRequired 不是同一个条件。
Android 12 到 14 存在已知缺陷。
本主题建议把强制 unlocked 策略限制到 Android 15 及以上。
后台接收若需要在锁屏时继续，不能使用该策略。
后台密钥与审批密钥应使用不同别名和不同认证要求。

Android Auto Backup 默认包含多数应用数据。
getNoBackupFilesDir 返回的目录始终不进入备份。
android:allowBackup=false 在 Android 12 及以上不一定阻止所有设备直传。
因此密文目录必须放在 no-backup 目录或使用明确的备份排除规则。
Keystore 密钥和密文恢复语义必须分别验证。
本主题不把 Android Keystore 密钥当作可备份密钥。

### 8.4 Rust 桥接

UniFFI 把 Rust Result 的 Err 映射为 Swift 或 Kotlin 异常。
UniFFI 错误类型必须是 enum 或兼容的错误接口。
UniFFI foreign trait 允许 Swift 或 Kotlin 实现 Rust trait。
foreign trait 方法应返回 Result。
foreign trait 不保证无环。
C ABI 需要稳定枚举、repr、长度和释放函数。
JNI 需要明确线程、局部引用和对象生命周期。
本主题建议统一语义层放在 Rust。
平台 UI 只提供认证窗口和用户输入。
JNI 只调用 Android Keystore 和 BiometricPrompt。
C ABI 和 UniFFI 不返回长期根密钥明文。

### 8.5 内存和日志

秘密在内存中应使用不可打印类型。
Debug 输出必须固定为 redacted。
秘密缓冲区离开作用域后必须零化。
zeroize 使用 volatile 写入和内存屏障。
普通 Vec drop 不保证覆盖字节。
当前 C ABI 的 owned bytes 释放路径只 drop Vec。
当前读取路径会把秘密复制到 Swift 可见缓冲区。
本主题建议删除通用 secret read。
如必须保留读接口，释放函数必须先零化再释放。

## 9. 目标产品源码分析

分析基线：Covio 仓库快照。
分支：docs/cross-platform-product-direction。
commit：5a1f6c8dd9d2a66dd2cb6c7d0f68b08fc9b88297。
环境：Windows 主机中的 WSL2。
Rust 版本：1.85.0。
Cargo 版本：1.85.0。

### 9.1 当前 SecretStore

当前 SecretStore 只有三个操作。
三个操作是 read、write 和 delete。
读缺失 key 返回 Ok(None)。
删除缺失 key 是成功空操作。
接口没有能力查询。
接口没有访问策略。
接口没有用户认证上下文。
接口没有设备绑定字段。
接口没有备份策略。
接口没有轮换操作。
接口没有状态检查。
接口没有迁移版本。
平台错误只有 Unavailable、InvalidArgument、PermissionDenied 和 Io。
这些类别不足以表达锁定、取消、认证失败和密钥失效。

### 9.2 当前 macOS 适配器

当前 macOS 适配器使用 security-framework 3.7.0。
适配器调用 set_generic_password、get_generic_password 和 delete_generic_password。
便利函数只使用 service 和 account。
适配器没有调用 use_protected_keychain。
适配器没有设置 kSecAttrAccessible。
适配器没有设置 kSecAttrAccessControl。
适配器没有设置 kSecAttrSynchronizable。
适配器只匹配 errSecItemNotFound 和 errSecAuthFailed。
其他 OSStatus 都映射为 Io。
适配器只在 target_os = macos 编译。
当前代码不能直接用于 iOS。
根据 TN3137，macOS 的 SecItem 默认使用 file-based Keychain。
因此当前 macOS 实现有迁移风险。

### 9.3 当前 Windows 适配器

当前 Windows 适配器使用 keyring 3.6.3。
功能选择为 windows-native。
适配器把 service 和 account 传给 keyring Entry。
适配器限制 secret 为 2560 字节。
keyring 3.6.3 的 Windows 实现使用 CRED_TYPE_GENERIC。
keyring 3.6.3 写入 CRED_PERSIST_ENTERPRISE。
ENTERPRISE 可能随漫游状态进入其他计算机。
这与设备绑定策略冲突。
适配器用自己的 Mutex 串行化操作。
串行化是本产品行为，不是平台保证。
当前错误映射只区分 NoStorageAccess、TooLong、Invalid、NoEntry 和 IO。
当前实现不能区分 Credential Manager 的登录会话错误、锁定和认证取消。

### 9.4 当前 C ABI

当前 C ABI 暴露任意 keychain read、write 和 delete。
with_service 变体允许调用者指定任意 Keychain service。
读取函数返回 CovioOwnedBytes。
CovioOwnedBytes 的释放函数执行 Vec drop。
释放函数没有先零化内容。
调用者可以在 Swift 侧取得秘密副本。
这违反最小权限边界。
新合同应只暴露用途受限的高层操作。
新合同不应提供通用 secret read。
写入输入可以在边界复制。
读取输出只允许内部 Rust 使用。
如果测试需要读取，应使用专用测试接口并在释放前零化。

### 9.5 当前测试

现有 Rust 测试覆盖内存后端和部分真实平台后端。
macOS 有真实 Keychain 往返测试。
Windows 有目标平台条件测试。
Swift smoke 覆盖 C ABI Keychain 往返。
当前没有 iOS 测试目标。
当前没有 Android 工程。
当前没有备份恢复测试。
当前没有生物认证测试。
当前没有跨进程访问边界测试。
当前没有 C ABI 秘密释放零化测试。

## 10. 候选方案分析

### 10.1 方案 A：继续使用薄 keyring 抽象

做法：直接把每个业务 secret 放入原生 keyring。
成本：低。
风险：高。
成熟度：依赖第三方库。
可维护性：表面简单，语义分散。

风险点如下。

1. Apple 和 Windows 的访问控制不统一。
2. Windows 2560 字节限制会进入业务层。
3. 当前 Windows 后端使用 ENTERPRISE。
4. 当前 macOS 后端未显式使用 data protection Keychain。
5. 备份和迁移语义不可统一。
6. 生物认证无法形成统一保证。
7. 每个平台要独立迁移。

结论：不采用为最终合同。
它可以作为临时过渡，但必须改正平台属性。

### 10.2 方案 B：每个逻辑凭据直接存入原生存储

做法：一个凭据对应一个 Keychain item 或 Credential Manager entry。
成本：中。
风险：中高。
成熟度：高。
可维护性：中。

风险点如下。

1. Windows 大小限制直接影响 API 密钥长度。
2. Android Keystore 不直接保存任意 secret。
3. 记录数量和迁移成本增加。
4. 不同平台的 item 语义不同。
5. 记录轮换需要逐项操作。
6. 备份恢复策略更难统一。

结论：不作为首要方案。
它适合短小、平台专用的系统凭据。

### 10.3 方案 C：原生存储保护根密钥加 Rust 加密仓库

做法：原生存储只保存一个 32 字节根密钥。Rust 保存加密记录。
成本：中。
风险：中。
成熟度：高。
可维护性：高。

优点如下。

1. Windows blob 上限不再约束业务凭据。
2. Android Keystore 可以用包装方式接入。
3. 记录格式和迁移由 Rust 控制。
4. 设备绑定可以写入 AAD。
5. 平台 ACL 差异可以由能力模型表达。
6. 业务记录可以整体轮换和审计。
7. UI 可以完全不读取记录秘密。

风险点如下。

1. Rust AEAD 和 KDF 实现必须正确。
2. 根密钥丢失会让全部记录不可读。
3. 备份策略必须明确排除密文。
4. 设备身份密钥仍需另一个平台适配器。
5. 需要两阶段迁移保护。

结论：推荐方案 C。

### 10.4 方案 D：Rust 软件 vault 加用户口令

做法：用口令派生密钥，Rust 保存全部密文。
成本：中。
风险：高。
成熟度：中。
可维护性：中。

风险点如下。

1. 需要新增口令 UX。
2. 口令强度和恢复流程成为产品责任。
3. 后台任务无法无提示读取。
4. 设备绑定依赖应用逻辑。
5. 与二维码配对的无口令目标冲突。

结论：不用于首发版本。
它可以作为未来的可恢复导出方式。

### 10.5 方案 E：云端密钥管理或账号同步

做法：使用云 KMS、账户密钥环或系统云同步。
成本：高。
风险：高。
成熟度：取决于服务。
可维护性：低。

风险点如下。

1. 违反首发无账号假设。
2. 引入网络依赖。
3. 引入云端信任边界。
4. 需要账户恢复和合规设计。
5. 与设备绑定目标冲突。

结论：本主题不采用。

### 10.6 候选方案对比

| 方案 | 成本 | 风险 | 成熟度 | 可维护性 | 结论 |
| --- | --- | --- | --- | --- | --- |
| 薄 keyring 抽象 | 低 | 高 | 中 | 低 | 仅过渡 |
| 每个凭据直接存原生 | 中 | 中高 | 高 | 中 | 不作为主方案 |
| 原生根密钥加 Rust 仓库 | 中 | 中 | 高 | 高 | 推荐 |
| Rust 软件 vault 加口令 | 中 | 高 | 中 | 中 | 暂不采用 |
| 云 KMS 或账号同步 | 高 | 高 | 取决于服务 | 低 | 不采用 |

## 11. 参考实现分析

### 11.1 Apple 参考实现

Apple 的 Secure Enclave 示例把非导出私钥放入 Keychain。
示例使用访问控制和 protected keychain。
示例还强调用户认证可能阻塞线程。
本主题借鉴其分层方式。
设备身份私钥留在平台安全硬件中。
业务记录不直接复制私钥。

### 11.2 Windows 参考实现

Win32 Credential Manager 适合保存小型通用凭据。
PasswordVault 适合漫游的密码项。
两者都不是 Rust 加密仓库。
本主题借鉴 Credential Manager 的小 blob 和用户边界。
本主题不采用 PasswordVault 的漫游语义。

### 11.3 Android 参考实现

Android Keystore 适合生成和操作密钥。
应用应把包装后的二进制数据放在应用私有目录。
认证绑定密钥需要 BiometricPrompt CryptoObject。
密钥失效必须由用户在应用内重新配对或重建。
本主题借鉴其包装和失效模型。

### 11.4 Paseo 参考

当前任务没有 Paseo 源码证据。
本主题只继承产品背景中的二维码配对要求。
Paseo 的具体秘密保存实现未完成源码核验。
该缺口列入第 13 节。

## 12. 反证和限制

1. Apple 技术说明说明 data protection Keychain 推荐，但没有保证所有旧版本行为完全一致。
2. Windows 通用凭据文档说明存储安全，但没有给出统一的项级生物 ACL。
3. Android 不同设备的 StrongBox 和 Keymaster 实现不同。
4. 当前仓库没有 iOS 和 Android 工程，不能给出真机结论。
5. 当前验证只在 Linux/WSL2 文档环境完成。
6. 备份恢复测试涉及真实设备和生产数据风险，尚未执行。
7. 设备身份密钥的最终算法和格式尚未决定。
8. Rust AEAD 算法尚未决定。
9. 日志保留期限尚未决定。
10. Credential Guard 对通用凭据的覆盖范围尚未验证。

以上反证不会推翻推荐架构。
它们限制推荐架构的保证范围。
确定结论必须等待对应验证回填。

## 13. 已知缺口

1. Windows 通用凭据是否被 Credential Guard 完整保护。
2. Windows 通用凭据在卸载、系统还原和漫游配置中的清理行为。
3. Apple Keychain 项在应用卸载、同设备恢复和跨设备恢复中的具体残留。
4. Keychain  失效与 item-not-found 的映射。
5. iOS 后台任务在锁屏时能否读取 AfterFirstUnlock 项。
6. Android 各厂商的 StrongBox 可用性和失效事件。
7. Android Keystore 密钥在设备直传和恢复后的实际状态。
8. Windows Hello 独立密钥绑定方案的安全证明。
9. Paseo 的凭据保存和配对实现。
10. 正式达到“硬件绑定”承诺所需的认证和审计范围。
11. Rust AEAD、KDF 和 nonce 方案的最终决策。
12. 设备身份密钥的生命周期和撤销格式。
