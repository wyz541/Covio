# 跨平台凭据存储证据附录

证据支持推荐架构，但不足以宣布任何平台已通过真机验收。所有平台行为必须由后续验证回填。

## 文档状态

| 项目 | 内容 |
| --- | --- |
| 文档版本 | 1.0 |
| 状态 | 初稿，可复核 |
| 日期 | 2026-11-10 |
| 研究问题 | 跨平台凭据存储统一合同 |
| 主文 | [主题索引](README.md) |
| 验证目录 | [验证目录](validation/README.md) |
| 当前环境 | Windows 主机中的 WSL2，仓库 commit 5a1f6c8dd9d2a66dd2cb6c7d0f68b08fc9b88297 |

## 1. 来源等级

| 等级 | 来源 | 用途 | 置信度 |
| --- | --- | --- | --- |
| A | Apple Security 与 LocalAuthentication API 参考 | Apple 接口和平台语义 | 高 |
| A | Microsoft Win32 Credential Manager API 参考 | Windows 接口和持久化语义 | 高 |
| A | Android Keystore 与 BiometricPrompt API 参考 | Android 密钥和认证语义 | 高 |
| A | UniFFI 用户指南 | 跨语言错误和 foreign trait 语义 | 高 |
| B | Covio 当前源码和 Cargo 锁文件 | 当前实现和依赖版本 | 高 |
| C | Apple、Microsoft、Android 安全指南 | 平台建议和操作限制 | 中高 |
| C | zeroize crate 文档 | 内存零化建议 | 中高 |

## 2. 环境事实

| 项目 | 值 | 命令或来源 | 置信度 |
| --- | --- | --- | --- |
| 仓库分支 | docs/cross-platform-product-direction | git branch --show-current | 高 |
| 仓库 commit | 5a1f6c8dd9d2a66dd2cb6c7d0f68b08fc9b88297 | git rev-parse HEAD | 高 |
| 主机环境 | WSL2，Linux 内核 6.18.33.2 | uname -a | 高 |
| Rust 版本 | 1.85.0 | rustc --version | 高 |
| Cargo 版本 | 1.85.0 | cargo --version | 高 |
| 当前平台原生测试 | 未执行 | 本轮任务范围 | 高 |
| 当前 iOS 工程 | 不存在 | 仓库目录检查 | 中高 |
| 当前 Android 工程 | 不存在 | 仓库目录检查 | 中高 |

## 3. 证据索引

| 编号 | 主题 | 来源 | 结论 | 置信度 |
| --- | --- | --- | --- | --- |
| E-01 | 跨平台目标架构 | B | 首发平台是 macOS、Windows 和 iOS | 高 |
| E-02 | 当前 SecretStore 合同 | B | 只有 read、write 和 delete | 高 |
| E-03 | 当前 Apple 适配器 | B/A | 未显式使用 data protection Keychain | 中高 |
| E-04 | 当前 Windows 适配器 | B/A | keyring 3.6.3 使用 ENTERPRISE 持久化 | 高 |
| E-05 | 当前 C ABI 秘密边界 | B | 暴露任意 secret read，释放不零化 | 高 |
| E-06 | Apple Keychain 实现选择 | A/C | macOS 默认 file-based，建议 data protection | 高 |
| E-07 | Apple SecItem 行为 | A | 秘密数据加密，调用可能阻塞线程 | 高 |
| E-08 | Apple Keychain 可用性和备份 | A/C | ThisDeviceOnly 不迁移，AfterFirstUnlock 支持后台 | 高 |
| E-09 | Apple 访问控制和生物认证 | A | userPresence 和 biometryCurrentSet 可绑定 Keychain 项 | 高 |
| E-10 | Apple 同步和 access group | A | 同步与 ThisDeviceOnly 冲突，access group 可共享 | 高 |
| E-11 | Apple Secure Enclave | A | 非导出 P-256 密钥，不能导入旧密钥 | 高 |
| E-12 | Apple LocalAuthentication | A | 认证策略依设备和配置变化，用户可取消 | 高 |
| E-13 | Apple 结果码 | A | item-not-found、interaction-not-allowed、auth-failed、user-canceled 可区分 | 高 |
| E-14 | Windows 通用凭据结构和上限 | A | CRED_TYPE_GENERIC，blob 上限 2560 字节 | 高 |
| E-15 | Windows 持久化范围 | A | LOCAL_MACHINE 本机可见，ENTERPRISE 可能漫游 | 高 |
| E-16 | Windows Credential Manager 上下文 | A | 使用当前令牌和登录会话 | 高 |
| E-17 | Windows PasswordVault | A/C | 可漫游，每应用最多 20 条 | 高 |
| E-18 | Windows UserConsentVerifier | A/C | 独立用户确认，不是通用凭据项级 ACL | 中高 |
| E-19 | Windows Credential Guard | A/C | 保护域凭据，通用凭据覆盖范围需验证 | 中 |
| E-20 | Android Keystore 基本能力 | A/C | 非导出密钥，可绑定 TEE 或 StrongBox | 高 |
| E-21 | Android 认证和失效 | A | 认证绑定、生物登记和锁屏变化可使密钥失效 | 高 |
| E-22 | Android 异常和认证窗口 | A | 明确区分未认证、永久失效和 StrongBox 不可用 | 高 |
| E-23 | Android 备份和直传 | A/C | no-backup 目录始终排除，D2D 规则受版本影响 | 高 |
| E-24 | UniFFI 错误和 foreign trait | A | Result 映射异常，foreign trait 方法应返回 Result | 高 |
| E-25 | zeroize 语义 | C | 使用 volatile 写入和内存屏障，Zeroizing 自动零化 | 高 |
| E-26 | 当前测试覆盖 | B | 只有部分 Rust 和 Swift smoke，无 iOS、Android、备份和认证测试 | 高 |

## 4. 证据详情

### E-01：跨平台目标架构

来源等级：B

环境：仓库 commit 5a1f6c8dd9d2a66dd2cb6c7d0f68b08fc9b88297。

命令或来源：docs/design/cross-platform-product.md。

关键观察：

- 首发平台是 macOS、Windows 和 iOS。
- Android 在后继阶段进入。
- Rust core 拥有共享业务逻辑。
- macOS 和 iOS 目标 UI 是 SwiftUI。
- Windows 目标 UI 是 Compose Multiplatform。
- 凭据列分别写 Keychain、Credential Manager 和 Keystore。

观察：目标架构已经列出四个平台的凭据后端。

推论：凭据合同必须覆盖三个首发平台，并预留 Android。

反证：该文件是目标架构，不是已实现代码。

限制：目标可能继续变更。

置信度：高

关联：V01、V04、V05

### E-02：当前 SecretStore 合同

来源等级：B

环境：仓库 commit 5a1f6c8dd9d2a66dd2cb6c7d0f68b08fc9b88297。

命令或来源：rust/crates/covio-platform/src/secret.rs；rust/crates/covio-platform/src/lib.rs。

关键观察：

- SecretStore 只有 read、write 和 delete。
- 缺失 key 的读取返回 Ok(None)。
- 缺失 key 的删除是成功空操作。
- SecretValue 的 Debug 输出固定为 redacted。
- SecretValue 的 Drop 手工覆盖字节。
- PlatformErrorCode 只有 Unavailable、InvalidArgument、PermissionDenied 和 Io。

观察：当前合同没有能力查询、访问策略、认证上下文、轮换、备份或迁移字段。

推论：当前接口不能表达平台安全差异。

反证：调用方可在外层补充策略，但无法证明平台实际执行策略。

限制：只分析当前源码。

置信度：高

关联：V01、V18、V19

### E-03：当前 Apple 适配器

来源等级：B、A

环境：Covio commit 5a1f6c8dd9d2a66dd2cb6c7d0f68b08fc9b88297；security-framework 3.7.0。

命令或来源：rust/crates/covio-platform/src/macos_secret.rs；security-framework 3.7.0 的 src/passwords.rs 和 src/passwords_options.rs；Apple TN3137。

关键观察：

- 当前适配器调用 get_generic_password、set_generic_password 和 delete_generic_password。
- 当前适配器没有调用 use_protected_keychain。
- 当前适配器没有设置 kSecAttrAccessible。
- 当前适配器没有设置 kSecAttrAccessControl。
- 当前适配器没有设置 kSecAttrSynchronizable。
- 当前适配器只匹配 errSecItemNotFound 和 errSecAuthFailed。
- 便利 API 的目标平台是 iOS 和 macOS。
- 当前模块只在 target_os = macos 编译。

观察：当前实现没有显式选择 Apple Keychain 实现。

推论：在 macOS 上，当前实现很可能使用 file-based Keychain。

反证：产品其他位置可能设置全局默认，但当前插件代码没有该设置。

限制：没有在真实 macOS 运行并检查 Keychain 项属性。

置信度：中高

关联：V01、V02、V06、V07

### E-04：当前 Windows 适配器

来源等级：B、A

环境：Covio commit 5a1f6c8dd9d2a66dd2cb6c7d0f68b08fc9b88297；keyring 3.6.3。

命令或来源：rust/crates/covio-platform/src/windows_credentials.rs；rust/Cargo.lock；keyring 3.6.3 的 src/windows.rs。

关键观察：

- 当前适配器使用 keyring 3.6.3 的 windows-native 功能。
- 适配器显式限制 secret 为 2560 字节。
- keyring 使用 CRED_TYPE_GENERIC。
- keyring 写入 CRED_PERSIST_ENTERPRISE。
- 当前适配器用进程内 Mutex 串行化操作。

观察：当前 Windows 持久化范围不是设备本地范围。

推论：使用漫游配置时，当前凭据可能在其他计算机可见。

反证：CRED_PERSIST_ENTERPRISE 是否真正漫游取决于用户配置。

限制：没有在 Windows 域账户或漫游配置中验证。

置信度：高

关联：V03、V12、V13、V18

### E-05：当前 C ABI 秘密边界

来源等级：B

环境：仓库 commit 5a1f6c8dd9d2a66dd2cb6c7d0f68b08fc9b88297。

命令或来源：rust/crates/covio-ffi/src/lib.rs；rust/crates/covio-ffi/include/covio_ffi.h。

关键观察：

- C ABI 暴露 covio_keychain_read、covio_keychain_write 和 covio_keychain_delete。
- with_service 变体允许调用者指定任意 service。
- 读取操作返回 CovioOwnedBytes。
- 读取路径把秘密复制到 Vec。
- covio_owned_bytes_free 使用 Vec::from_raw_parts 后直接 drop。
- 释放函数没有先覆盖秘密字节。
- Swift smoke 测试会读取并检查秘密值。

观察：UI 或调用方可以取得长期秘密。

推论：当前边界不满足最小权限和秘密生命周期要求。

反证：该 ABI 可能只用于可信调用方，但它仍是产品边界。

限制：没有进行崩溃转储或内存转储验证。

置信度：高

关联：V18、V19、V23

### E-06：Apple Keychain 实现选择

来源等级：A、C

环境：Apple TN3137，访问日期 2026-11-10。

命令或来源：https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains

关键观察：

- 所有 Apple 平台都支持 Keychain。
- iOS、tvOS 和 watchOS 只支持 SecItem 和 data protection Keychain。
- macOS 有 file-based Keychain 和 data protection Keychain。
- macOS SecItem 默认指向 file-based Keychain。
- 设置 kSecUseDataProtectionKeychain 为 true 可使用 data protection Keychain。
- Apple 建议新代码优先使用 data protection Keychain。
- data protection Keychain 只在用户上下文可用。
- launchd daemon 不能使用 data protection Keychain。

观察：macOS 和 iOS 可以共享 SecItem 语义，但 macOS 需要显式选择。

推论：长期根密钥应由用户上下文主应用读取。

反证：旧 file-based Keychain 仍受支持，但不是新代码首选。

限制：Apple 文档随系统版本更新。

置信度：高

关联：V01、V02、V07

### E-07：Apple SecItem 行为

来源等级：A

环境：Apple Security API 参考，访问日期 2026-11-10。

命令或来源：https://developer.apple.com/documentation/security/secitemadd(_:_:)

关键观察：

- SecItemAdd 向 Keychain 添加一项或多项。
- Keychain 对密码类型和私钥类型的秘密数据执行加密。
- SecItemAdd 会阻塞调用线程。
- Apple 建议从后台队列或异步函数调用。

观察：Keychain 操作可能造成 UI 卡顿。

推论：facade 不能从 SwiftUI 主线程同步调用 Keychain。

反证：部分无交互读取可能很快，但接口没有保证。

限制：阻塞时长受平台和认证状态影响。

置信度：高

关联：V01、V04、V07

### E-08：Apple Keychain 可用性和备份

来源等级：A、C

环境：Apple Security API 参考与 Keychain 指南，访问日期 2026-11-10。

命令或来源：

- https://developer.apple.com/documentation/security/restricting-keychain-item-accessibility
- https://developer.apple.com/documentation/security/ksecattraccessibleafterfirstunlock
- https://developer.apple.com/documentation/security/ksecattraccessiblewhenunlockedthisdeviceonly
- https://developer.apple.com/documentation/security/ksecattraccessiblewhenpasscodesetthisdeviceonly

关键观察：

- WhenUnlocked 是未显式设置时的默认可用性。
- AfterFirstUnlock 适合后台应用。
- ThisDeviceOnly 项不迁移到另一台设备。
- ThisDeviceOnly 项可以恢复到创建备份的原设备。
- WhenPasscodeSetThisDeviceOnly 要求设备有密码。
- 移除设备密码时，该项会被删除。

观察：设备绑定和后台可用性可以通过不同 Keychain 属性表达。

推论：后台传输密钥应使用 AfterFirstUnlockThisDeviceOnly。

推论：审批密钥应使用更严格的可用性和用户在场策略。

反证：原设备恢复行为不等于跨设备恢复。

限制：具体恢复结果仍需真机验证。

置信度：高

关联：V01、V02、V04、V05、V07、V08、V10

### E-09：Apple 访问控制和生物认证

来源等级：A

环境：Apple Security API 参考，访问日期 2026-11-10。

命令或来源：

- https://developer.apple.com/documentation/security/secaccesscontrolcreatewithflags(_:_:_:_:)
- https://developer.apple.com/documentation/security/secaccesscontrolcreateflags/userpresence
- https://developer.apple.com/documentation/security/secaccesscontrolcreateflags/biometrycurrentset

关键观察：

- SecAccessControlCreateWithFlags 创建访问控制对象。
- userPresence 允许生物认证或设备密码。
- biometryCurrentSet 要求当前登记的生物集合。
- 新增或移除 Touch ID 手指会使 biometryCurrentSet 项失效。
- Face ID 重新登记也会使该项失效。
- 受访问控制保护的项可能阻塞主线程。

观察：Apple 可以把用户在场绑定到 Keychain 项。

推论：Apple 适配器可以报告 Cryptographic 用户在场执行。

反证：系统提示行为依设备和配置变化。

限制：必须验证用户取消和失效结果码。

置信度：高

关联：V01、V04、V09、V11

### E-10：Apple 同步和 access group

来源等级：A

环境：Apple Security API 参考，访问日期 2026-11-10。

命令或来源：

- https://developer.apple.com/documentation/security/ksecattrsynchronizable
- https://developer.apple.com/documentation/security/ksecattraccessgroup

关键观察：

- kSecAttrSynchronizable 为 true 时，Keychain 项通过 iCloud 同步。
- ThisDeviceOnly 与可同步项不兼容。
- 一个 Keychain 项只属于一个 access group。
- 应用可以访问自己的 access group。
- 多个应用可以通过 access group 共享 Keychain 项。
- macOS 只有使用 data protection Keychain 或同步属性时，access group 规则才接近 iOS。

观察：设备绑定项必须禁止同步。

推论：首发版本应使用 false 的 synchronizable，并限制 access group。

反证：如果产品未来需要跨设备同步，策略需要单独设计。

限制：iCloud 状态和团队签名配置会影响验证。

置信度：高

关联：V01、V02、V07

### E-11：Apple Secure Enclave

来源等级：A

环境：Apple Security 指南，访问日期 2026-11-10。

命令或来源：https://developer.apple.com/documentation/security/protecting-keys-with-the-secure-enclave

关键观察：

- Secure Enclave 是隔离的硬件密钥管理器。
- 私钥明文不进入应用内存。
- 支持设备包括 A7 或更新 iOS 设备和指定 Mac 硬件。
- Secure Enclave 只支持 P-256。
- Secure Enclave 不能导入已有密钥。
- Secure Enclave 私钥不能导出。
- 用途包括签名和 ECDH。

观察：设备身份密钥适合放入 Secure Enclave。

推论：设备身份密钥和 32 字节根密钥应分开建模。

反证：不是所有 Mac 和支持设备都有 Secure Enclave。

限制：需要能力查询和回退策略。

置信度：高

关联：V04、V19

### E-12：Apple LocalAuthentication

来源等级：A

环境：Apple LocalAuthentication API 参考，访问日期 2026-11-10。

命令或来源：https://developer.apple.com/documentation/localauthentication/lacontext/evaluatepolicy(_:localizedreason:reply:)

关键观察：

- evaluatePolicy 异步评估认证策略。
- 实际行为取决于策略、设备类型和配置描述文件。
- 用户取消或系统取消会导致失败。
- 一次成功不能保证下一次成功。

观察：认证结果不是永久状态。

推论：每次受限读取都必须重新检查认证结果。

反证：某些访问控制项可以在一次认证后短期复用。

限制：短期复用窗口由平台管理。

置信度：高

关联：V04、V07、V09

### E-13：Apple 结果码

来源等级：A

环境：Apple Security API 参考，访问日期 2026-11-10。

命令或来源：

- https://developer.apple.com/documentation/security/errsecitemnotfound
- https://developer.apple.com/documentation/security/errsecinteractionnotallowed
- https://developer.apple.com/documentation/security/errsecauthfailed
- https://developer.apple.com/documentation/security/errsecusercanceled
- https://developer.apple.com/documentation/localauthentication/laerror-swift.struct/biometrylockout

关键观察：

- errSecItemNotFound 表示项不存在。
- errSecInteractionNotAllowed 表示不允许与 Security Server 交互。
- errSecAuthFailed 表示授权或认证失败。
- errSecUserCanceled 表示用户取消。
- biometryLockout 表示生物认证尝试次数过多。

观察：Apple 错误可以支持不同用户动作。

推论：当前只映射 auth-failed 的实现不足。

反证：部分错误需要上下文才能区分锁定和策略拒绝。

限制：不能把原始 OSStatus 直接暴露给 UI。

置信度：高

关联：V04、V21

### E-14：Windows 通用凭据结构和上限

来源等级：A

环境：Microsoft Learn，访问日期 2026-11-10。

命令或来源：https://learn.microsoft.com/en-us/windows/win32/api/wincred/ns-wincred-credentialw

关键观察：

- CREDENTIALW 描述单个凭据。
- CRED_TYPE_GENERIC 表示通用凭据。
- 通用凭据不会用于任何认证包。
- TargetName 和 Type 唯一标识通用凭据。
- TargetName 大小写不敏感。
- TargetName 最大长度为 32767 个字符。
- CredentialBlobSize 最大为 5 × 512 字节。
- 通用凭据由应用定义 blob 格式。

观察：通用凭据适合小型应用秘密。

推论：根密钥可以直接保存，业务记录不应逐项保存。

反证：应用可以拆分大秘密，但会增加迁移和事务复杂度。

限制：错误上下文和 ACL 仍需单独分析。

置信度：高

关联：V03、V12、V13

### E-15：Windows 持久化范围

来源等级：A

环境：Microsoft Learn，访问日期 2026-11-10。

命令或来源：https://learn.microsoft.com/en-us/windows/win32/api/wincred/ns-wincred-credentialw

关键观察：

- CRED_PERSIST_SESSION 只在当前登录会话存在。
- CRED_PERSIST_LOCAL_MACHINE 在本机同一用户的后续登录可见。
- CRED_PERSIST_ENTERPRISE 可以在同一用户的其他计算机登录可见。
- ENTERPRISE 是否漫游取决于用户配置。
- 无漫游配置时，ENTERPRISE 可以作为本地持久化。

观察：LOCAL_MACHINE 提供更窄的设备范围。

推论：设备绑定合同应使用 CRED_PERSIST_LOCAL_MACHINE。

反证：系统映像备份可能恢复整个本机状态，不在本文范围。

限制：需要真机验证 CredRead 返回的 Persist 字段。

置信度：高

关联：V03、V13、V15、V18

### E-16：Windows Credential Manager 上下文

来源等级：A

环境：Microsoft Learn，访问日期 2026-11-10。

命令或来源：

- https://learn.microsoft.com/en-us/windows/win32/api/wincred/nf-wincred-credreadw
- https://learn.microsoft.com/en-us/windows/win32/api/wincred/nf-wincred-credwritew

关键观察：

- CredRead 读取当前登录会话关联的凭据集。
- 当前令牌不能禁用用户 SID。
- 网络登录会话没有关联凭据集。
- CredWrite 创建或修改当前令牌的凭据。
- ERROR_NOT_FOUND 表示没有匹配凭据。
- ERROR_NO_SUCH_LOGON_SESSION 表示没有凭据集。
- ERROR_INVALID_PARAMETER 表示字段冲突或参数无效。

观察：Credential Manager 与用户登录上下文强绑定。

推论：SYSTEM 服务和后台 daemon 不能直接读取用户根密钥。

反证：服务可以通过用户代理或 IPC 获取短生命周期会话。

限制：具体服务模型需要在 Windows 真机验证。

置信度：高

关联：V03、V14、V16

### E-17：Windows PasswordVault

来源等级：A、C

环境：Microsoft Learn，访问日期 2026-11-10。

命令或来源：

- https://learn.microsoft.com/en-us/windows/apps/develop/security/credential-locker
- https://learn.microsoft.com/en-us/uwp/api/windows.security.credentials.passwordvault

关键观察：

- Credential Locker 可以随 Microsoft 账户漫游。
- 凭据不会因不活跃而自动过期。
- 每个应用最多保存 20 条凭据。
- 非 AppContainer 桌面应用可以访问当前用户的所有 locker。
- AppContainer 应用只能访问自己的 locker。

观察：PasswordVault 的范围和产品设备绑定目标不同。

推论：设备绑定根密钥不使用 PasswordVault。

反证：未来的账号级可恢复凭据可以使用另一套设计。

限制：当前 Windows Compose 打包方式尚未决定。

置信度：高

关联：V03、V15

### E-18：Windows UserConsentVerifier

来源等级：A、C

环境：Microsoft Learn，访问日期 2026-11-10。

命令或来源：https://learn.microsoft.com/en-us/uwp/api/windows.security.credentials.ui.userconsentverifier

关键观察：

- UserConsentVerifier 检查 Windows Hello、PIN 或指纹的可用性。
- 桌面应用使用窗口 interop 接口。
- 结果包括 Verified、Canceled、RetriesExhausted、DeviceNotPresent、DisabledByPolicy 和 NotConfiguredForUser。
- API 用于请求用户确认。

观察：UserConsentVerifier 与 Credential Manager 项访问分开。

推论：它只能作为用户界面确认，不能自动证明通用凭据 ACL。

反证：Windows 可能通过其他机制实现绑定，但当前通用凭据 API 没有展示。

限制：强绑定方案需要 Windows Hello 或 CNG 独立验证。

置信度：中高

关联：V17

### E-19：Windows Credential Guard

来源等级：A、C

环境：Microsoft Learn，访问日期 2026-11-10。

命令或来源：https://learn.microsoft.com/en-us/windows/security/identity-protection/credential-guard/

关键观察：

- Credential Guard 使用 VBS 隔离秘密。
- 它保护 NTLM 哈希、Kerberos TGT 和域凭据。
- 文档列出 Credential Manager 会利用平台安全功能保护凭据。
- Windows 11 22H2 起，部分域加入设备默认启用。
- 启用条件依赖硬件和配置。

观察：Credential Guard 的保护范围与设备配置有关。

推论：不能把“Credential Guard 可用”写成所有通用凭据的保证。

反证：特定企业环境可能防护更强。

限制：通用凭据的实际覆盖范围需要专门验证。

置信度：中

关联：V14

### E-20：Android Keystore 基本能力

来源等级：A、C

环境：Android Developers，访问日期 2026-11-10。

命令或来源：

- https://developer.android.com/privacy-and-security/keystore
- https://developer.android.com/privacy-and-security/risks/backup-best-practices

关键观察：

- Keystore 保存非导出加密密钥。
- 密钥材料不进入应用进程。
- 密钥可以绑定 TEE 或 StrongBox。
- StrongBox 需要设备支持。
- StrongBox 不可用时可以返回 StrongBoxUnavailableException。
- 应用可以查询 KeyInfo 的安全级别。

观察：Keystore 提供密钥操作，不提供任意大 secret 容器。

推论：Android 适配器应生成 Keystore 密钥并包装根密钥。

反证：小 secret 可以作为一个 Keystore key 使用，但语义不适合多记录仓库。

限制：StrongBox 算法、性能和可用性因设备而异。

置信度：高

关联：V05、V25、V27

### E-21：Android 认证和失效

来源等级：A

环境：Android API 参考，访问日期 2026-11-10。

命令或来源：https://developer.android.com/reference/android/security/keystore/KeyGenParameterSpec.Builder

关键观察：

- setUserAuthenticationRequired 要求安全锁屏。
- setUserAuthenticationParameters 设置认证有效期和认证类型。
- 认证可以包含生物认证或设备凭证。
- 认证绑定密钥在锁屏禁用或强制重置后永久失效。
- 生物专用密钥在新生物登记或全部生物移除后失效。
- setUnlockedDeviceRequired 只要求设备解锁。
- Android 12 到 14 的 unlocked-device 策略有已知缺陷。
- Android 15 修复相关缺陷。

观察：后台访问、设备解锁和用户认证是三个不同条件。

推论：后台传输密钥和审批密钥必须使用不同密钥别名。

反证：某些设备可能额外限制后台 Keystore 访问。

限制：需要在目标 Android 版本验证。

置信度：高

关联：V25、V26、V29、V30

### E-22：Android 异常和认证窗口

来源等级：A

环境：Android API 参考，访问日期 2026-11-10。

命令或来源：

- https://developer.android.com/reference/android/security/keystore/UserNotAuthenticatedException
- https://developer.android.com/reference/android/security/keystore/KeyPermanentlyInvalidatedException
- https://developer.android.com/reference/android/security/keystore/StrongBoxUnavailableException
- https://developer.android.com/reference/android/hardware/biometrics/BiometricPrompt

关键观察：

- UserNotAuthenticatedException 表示认证不足，可以通过认证解决。
- KeyPermanentlyInvalidatedException 表示密钥永久失效。
- StrongBoxUnavailableException 表示请求的安全硬件不可用。
- BiometricPrompt 区分用户取消、锁定、永久锁定、超时和传感器不可用。

观察：Android 可以给出明确用户动作。

推论：适配器应把这些条件映射到不同凭据错误码。

反证：OEM 实现可能有额外错误。

限制：需要真机验证错误分布。

置信度：高

关联：V21、V25、V26、V27

### E-23：Android 备份和直传

来源等级：A、C

环境：Android Developers，访问日期 2026-11-10。

命令或来源：

- https://developer.android.com/identity/data/autobackup
- https://developer.android.com/privacy-and-security/risks/backup-best-practices

关键观察：

- Auto Backup 默认包含多数应用数据。
- getNoBackupFilesDir 中的文件始终排除。
- 缓存目录也排除。
- android:allowBackup=false 在 Android 12 及以上的部分设备上可能只禁用云备份。
- 部分厂商仍允许设备直传。
- 敏感数据建议排除备份或要求端到端加密。

观察：单纯依赖 allowBackup 不够。

推论：Android 密文必须放在 no-backup 目录并配置排除规则。

反证：Android 16 QPR2 增加跨平台传输配置，需要后续核对目标版本。

限制：设备厂商行为差异需要真机验证。

置信度：高

关联：V05、V28

### E-24：UniFFI 错误和 foreign trait

来源等级：A

环境：UniFFI 用户指南，访问日期 2026-11-10。

命令或来源：

- https://mozilla.github.io/uniffi-rs/latest/proc_macro/errors.html
- https://mozilla.github.io/uniffi-rs/latest/foreign_traits.html

关键观察：

- Result 的 Err 会在 Swift 或 Kotlin 中抛出。
- 错误类型需要可导出的 enum 或兼容类型。
- foreign trait 允许 Swift 或 Kotlin 实现 Rust trait。
- foreign trait 方法应返回 Result。
- foreign trait 可能形成跨语言循环引用。
- 未处理的 unexpected error 可能导致 panic。

观察：跨语言合同必须有明确错误类型。

推论：平台错误必须先映射到稳定凭据错误。

反证：C ABI 可以使用数字状态码，不需要 UniFFI。

限制：最终 bridge 选型尚未决定。

置信度：高

关联：V19、V21

### E-25：zeroize 语义

来源等级：C

环境：zeroize crate 文档，访问日期 2026-11-10。

命令或来源：https://docs.rs/zeroize/latest/zeroize/

关键观察：

- zeroize 使用 volatile 写入和原子内存屏障。
- 目标是不让编译器删除零化操作。
- Zeroizing 包装器在 Drop 时零化。
- Vec 的 Zeroize 实现覆盖整个 capacity。
- 内存零化不能替代更强的内存保护。

观察：普通 Vec drop 不保证覆盖秘密字节。

推论：秘密类型和 FFI 释放路径应使用 zeroize 或等价实现。

反证：zeroize 不能清除其他进程或崩溃转储中的副本。

限制：需要测试实际释放路径。

置信度：高

关联：V19、V23

### E-26：当前测试覆盖

来源等级：B

环境：仓库 commit 5a1f6c8dd9d2a66dd2cb6c7d0f68b08fc9b88297。

命令或来源：rust/crates/covio-platform/src；rust/crates/covio-ffi/src/lib.rs；rust/crates/covio-ffi/tests/swift_smoke.swift。

关键观察：

- Rust 单元测试覆盖内存后端。
- macOS 有真实 Keychain 往返测试。
- Windows 有目标平台条件测试。
- Swift smoke 测试覆盖 C ABI Keychain 往返。
- 当前没有 iOS 测试目标。
- 当前没有 Android 工程。
- 当前没有备份恢复测试。
- 当前没有生物认证测试。
- 当前没有跨进程访问边界测试。
- 当前没有 C ABI 秘密释放零化测试。

观察：当前证据只能证明基础往返。

推论：不能把现有测试当作跨平台安全验收。

反证：后续可能新增未提交测试，本文只覆盖当前快照。

限制：没有执行平台真机测试。

置信度：高

关联：V01 至 V30

## 5. 逻辑证据链

1. E-01 定义三个首发平台和 Android 后继范围。
2. E-02 到 E-05 识别当前实现的合同缺口。
3. E-06 到 E-13 说明 Apple 的可用性、ACL、备份和错误能力。
4. E-14 到 E-19 说明 Windows 的持久化、限制和认证边界。
5. E-20 到 E-23 说明 Android 的密钥包装、失效和备份边界。
6. E-24 到 E-25 支持跨语言错误和内存生命周期设计。
7. E-26 说明当前证据不足以宣布安全验收。
8. 上述证据支持“原生根密钥保护加 Rust 加密仓库”。
9. 上述证据也要求能力查询和失败关闭。
10. 真机结论必须由 [validation/README.md](validation/README.md) 回填。

## 6. 反证和限制

1. 当前代码没有在 macOS 上验证实际 Keychain 实现类型。
2. keyring ENTERPRISE 的实际漫游取决于用户配置。
3. Windows 通用凭据可能有额外系统保护，公开 API 没有展示。
4. Credential Guard 对通用凭据的覆盖范围未验证。
5. PasswordVault 和 Win32 Credential Manager 不是同一接口。
6. Apple Keychain 的原设备恢复和跨设备恢复仍需真机验证。
7. Android StrongBox 行为和错误码因设备而异。
8. Android D2D 行为因版本和厂商而异。
9. 当前没有 iOS 和 Android 工程。
10. 当前没有实际认证窗口测试。
11. 当前没有实际备份恢复测试。
12. 当前没有 Paseo 源码证据。

## 7. 已知缺口

1. Windows 通用凭据是否受 Credential Guard 完整保护。
2. Windows 凭据在卸载、系统还原和漫游配置中的清理行为。
3. Apple Keychain 项在卸载、同设备恢复和跨设备恢复中的残留。
4. Apple biometryCurrentSet 失效的具体 OSStatus。
5. iOS 后台任务在锁屏时读取 AfterFirstUnlock 项的行为。
6. Android StrongBox 可用性和密钥失效事件。
7. Android Keystore 在设备直传后的实际状态。
8. Windows Hello、CNG 或 TPM 的强绑定方案。
9. Paseo 的凭据保存和配对实现。
10. Rust AEAD、KDF 和 nonce 方案。
11. 设备身份密钥格式和撤销协议。
12. 正式安全认证范围。

## 8. 复核方法

1. 重新读取本文引用的官方页面。
2. 在仓库当前 commit 检查源码路径和依赖版本。
3. 在 macOS 检查 Keychain 项的 class、accessibility、access control 和 synchronizable 属性。
4. 在 Windows 检查 CredRead 返回的 Persist 字段。
5. 在 Android 检查 KeyInfo 的安全级别和认证要求。
6. 按验证目录执行锁定、取消、失效、备份和恢复测试。
7. 用合成秘密检查日志和内存释放路径。
8. 将实际结果写回案例文件和本附录。
9. 结论变化时更新 [conclusion.md](conclusion.md)。
10. 接口变化时更新 [solution.md](solution.md)。

## 参考来源

- Apple TN3137：https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains
- Apple SecItemAdd：https://developer.apple.com/documentation/security/secitemadd(_:_:)
- Apple Keychain accessibility：https://developer.apple.com/documentation/security/restricting-keychain-item-accessibility
- Apple Secure Enclave：https://developer.apple.com/documentation/security/protecting-keys-with-the-secure-enclave
- Apple LocalAuthentication：https://developer.apple.com/documentation/localauthentication/lacontext/evaluatepolicy(_:localizedreason:reply:)
- Microsoft CREDENTIALW：https://learn.microsoft.com/en-us/windows/win32/api/wincred/ns-wincred-credentialw
- Microsoft CredRead：https://learn.microsoft.com/en-us/windows/win32/api/wincred/nf-wincred-credreadw
- Microsoft CredWrite：https://learn.microsoft.com/en-us/windows/win32/api/wincred/nf-wincred-credwritew
- Microsoft Credential Locker：https://learn.microsoft.com/en-us/windows/apps/develop/security/credential-locker
- Microsoft UserConsentVerifier：https://learn.microsoft.com/en-us/uwp/api/windows.security.credentials.ui.userconsentverifier
- Microsoft Credential Guard：https://learn.microsoft.com/en-us/windows/security/identity-protection/credential-guard/
- Android Keystore：https://developer.android.com/privacy-and-security/keystore
- Android KeyGenParameterSpec.Builder：https://developer.android.com/reference/android/security/keystore/KeyGenParameterSpec.Builder
- Android Auto Backup：https://developer.android.com/identity/data/autobackup
- Android backup best practices：https://developer.android.com/privacy-and-security/risks/backup-best-practices
- UniFFI errors：https://mozilla.github.io/uniffi-rs/latest/proc_macro/errors.html
- UniFFI foreign traits：https://mozilla.github.io/uniffi-rs/latest/foreign_traits.html
- zeroize：https://docs.rs/zeroize/latest/zeroize/

## 9. 关联文档

- [主题索引](README.md)
- [前因与边界](context.md)
- [调研分析](investigation.md)
- [结论](conclusion.md)
- [推荐方案](solution.md)
- [验证目录](validation/README.md)
- [Apple 案例](validation/case-apple-keychain.md)
- [Windows 案例](validation/case-windows-credential-manager.md)
- [Rust 合同案例](validation/case-rust-vault-contract.md)
- [Android 合同案例](validation/case-android-keystore-contract.md)
