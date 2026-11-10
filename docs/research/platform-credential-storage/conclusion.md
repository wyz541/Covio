# 凭据存储结论与限制

推荐采用“原生根密钥保护加 Rust 加密仓库”的合同。合同必须按能力查询，不能把平台接口压成一个布尔安全等级。

> 本文件给出结论、决策因素、决策表、反证、系统限制、产品限制和未决项。

## 1. 结论摘要

结论一：原生安全存储只保存一个随机根密钥。
结论二：业务凭据由 Rust 使用 AEAD 加密后保存。
结论三：根密钥、记录和设备身份必须分开建模。
结论四：设备绑定、硬件保护、用户在场和备份范围必须分开表达。
结论五：facade 先查询平台能力，再执行请求。
结论六：不满足请求策略时返回 credential_policy_unsupported。
结论七：UI 不读取通用秘密，只触发受限业务操作。
结论八：首发版本不提供云端密钥备份。
结论九：新设备恢复后重新配对，不复用旧设备根密钥。
结论十：Android 合同使用 Keystore 包装根密钥，不把 Keystore 当作任意 secret 容器。

推荐方案见 [solution.md](solution.md)。
证据链见 [evidence.md](evidence.md)。
验证计划见 [validation/README.md](validation/README.md)。

## 2. 根因或决策因素

### 2.1 主要因素

#### 2.1.1 原生安全存储的语义不同

事实：Apple 有 file-based 和 data protection 两种 macOS Keychain。
事实：iOS 只使用 data protection Keychain。
事实：Windows 通用凭据有 2560 字节上限。
事实：Windows ENTERPRISE 持久化可能漫游。
事实：Android Keystore 保存非导出密钥，不直接保存任意 secret。
推论：单一 key-value 接口不能表达真实能力。
结论：合同需要能力矩阵和平台适配器。
证据：E-06、E-08、E-14、E-15、E-20。

#### 2.1.2 当前实现与设备绑定目标冲突

事实：当前 macOS 适配器使用便利 Keychain API。
事实：当前 macOS 适配器未显式选择 data protection Keychain。
事实：当前 macOS 适配器未设置 accessibility、access control 和 synchronizable。
事实：当前 Windows 适配器依赖 keyring 3.6.3。
事实：keyring 3.6.3 的 Windows 后端写入 CRED_PERSIST_ENTERPRISE。
推论：当前实现不能直接证明设备绑定。
结论：设备绑定策略必须进入新适配器验收。
证据：E-03、E-04、E-15。

#### 2.1.3 C ABI 暴露面过大

事实：当前 C ABI 暴露任意 keychain read、write 和 delete。
事实：with_service 变体允许指定任意 Keychain service。
事实：读取函数把秘密复制到 CovioOwnedBytes。
事实：CovioOwnedBytes 的释放函数只 drop Vec，没有先零化。
推论：当前边界不满足最小权限。
推论：当前边界不能保证秘密生命周期。
结论：新合同删除通用 secret read。
证据：E-05、E-25。

#### 2.1.4 后台接收需要独立访问策略

事实：Apple AfterFirstUnlock 适合后台访问。
事实：Apple userPresence 和 biometryCurrentSet 会要求用户交互。
事实：Windows Credential Manager 使用当前用户令牌。
事实：Android 认证绑定密钥需要用户认证。
事实：Android setUnlockedDeviceRequired 会阻止锁屏使用。
推论：后台传输密钥不能同时满足所有用户在场要求。
结论：后台传输密钥和审批密钥必须分开配置。
证据：E-08、E-09、E-16、E-21。

#### 2.1.5 新设备恢复不能静默重建旧秘密

事实：Apple ThisDeviceOnly 项不迁移到另一台设备。
事实：Android Keystore 密钥不可导出。
事实：Windows LOCAL_MACHINE 凭据不在其他计算机可见。
事实：当前产品没有账号和云端密钥托管。
推论：新设备恢复后可能只有密文没有根密钥。
结论：恢复后要求重新配对。
结论：不自动生成新根密钥覆盖旧仓库。
证据：E-08、E-15、E-23。

### 2.2 次要因素

#### 2.2.1 错误类别不足

事实：当前平台错误只有四类。
事实：Apple 区分 item-not-found、interaction-not-allowed、auth-failed 和 user-canceled。
事实：Android 区分 auth-required、key-invalidated 和 StrongBox-unavailable。
推论：现有错误类别无法驱动正确 UI。
结论：引入稳定凭据错误码和用户动作。
证据：E-02、E-13、E-22。

#### 2.2.2 生物认证不能对齐为同一保证

事实：Apple SecAccessControl 可以把用户在场绑定到 Keychain 项。
事实：Android Keystore 可以把认证要求绑定到密钥。
事实：Windows Credential Manager 的通用凭据结构没有同等项级 ACL 证据。
事实：Windows UserConsentVerifier 是独立确认接口。
推论：Windows 的首发实现只能把确认提示标为用户界面确认。
结论：合同必须返回有效认证类型，不能只返回“有生物认证”。
证据：E-09、E-18、E-21。

#### 2.2.3 备份规则依赖平台

事实：Apple ThisDeviceOnly 项可以恢复到原设备，但不迁移到新设备。
事实：Android Auto Backup 默认包含多数应用数据。
事实：Android getNoBackupFilesDir 始终排除备份。
事实：Windows Credential Manager 的本地持久化只在本机可见。
推论：备份策略需要平台适配器和产品政策同时约束。
结论：首发版本不备份根密钥和密文仓库。
证据：E-08、E-15、E-23。

#### 2.2.4 迁移必须可回滚

事实：当前 macOS 可能已有 file-based Keychain 项。
事实：当前 Windows 可能已有 ENTERPRISE 凭据。
事实：新合同改变存储位置、持久化和记录格式。
推论：迁移需要两阶段写入和回滚。
结论：旧值删除前必须完成新值回读和仓库校验。
证据：E-03、E-04、E-15。

## 3. 决策表

| 决策 | 选择 | 原因 | 备选路径 |
| --- | --- | --- | --- |
| 总体架构 | 原生安全存储保存根密钥，Rust 保存加密记录 | 解决平台限制并统一记录语义 | 薄 keyring 抽象 |
| macOS 后端 | SecItem 加 data protection Keychain | 与 iOS 一致，支持现代 ACL | file-based Keychain |
| macOS 可用性 | 后台密钥使用 AfterFirstUnlockThisDeviceOnly | 后台任务可在首次解锁后运行 | WhenUnlockedThisDeviceOnly |
| macOS 同步 | kSecAttrSynchronizable 为 false | 禁止 iCloud 代际迁移 | 允许同步 |
| iOS 后端 | SecItem 加 data protection Keychain | iOS 的系统默认实现 | 其他存储 |
| Windows 后端 | Win32 CRED_TYPE_GENERIC | 小型本地秘密，接口明确 | PasswordVault |
| Windows 持久化 | CRED_PERSIST_LOCAL_MACHINE | 限定本机同一用户 | CRED_PERSIST_ENTERPRISE |
| Windows 生物认证 | 首发只声明用户界面确认 | Credential Manager 没有同等项级 ACL 证据 | Windows Hello 独立密钥 |
| Android 后端 | Keystore 包装根密钥 | 密钥不可导出，密文可放应用私有目录 | Keystore 直接存 secret |
| Android 后台密钥 | 不要求用户认证和 unlocked-device | 支持锁屏接收 | 认证绑定密钥 |
| Android 审批密钥 | 可以要求用户认证 | 保护配对和撤销操作 | 所有密钥统一认证 |
| 根密钥长度 | 32 字节随机值 | 常用对称密钥长度 | 可变长度 |
| 记录保护 | AEAD 加 AAD | 提供机密性和完整性 | 仅原生 ACL |
| AAD 绑定 | 应用、设备、记录、用途和版本 | 防止跨设备或跨用途替换 | 只绑定记录 ID |
| 设备身份密钥 | 平台非导出密钥，优先硬件保护 | 支持设备身份和认证 | 软件密钥 |
| 新设备恢复 | 重新配对 | 根密钥不可导出 | 云端密钥托管 |
| 错误合同 | 稳定 code、retryable 和 user_action | UI 可正确处理 | 原生错误直传 |
| 秘密读取边界 | 不给 UI 通用读接口 | 最小权限 | 现有 keychain read |
| 秘密释放 | 零化后释放 | 降低内存残留 | 普通 Vec drop |
| 日志 | 只记录非秘密元数据 | 防止泄漏 | 记录完整错误上下文 |

## 4. 逻辑证据链

### 4.1 观察一：Apple 需要显式选择实现

观察：macOS SecItem 默认使用 file-based Keychain。
观察：Apple 建议新代码使用 data protection Keychain。
推论：当前 macOS 适配器不能证明使用现代实现。
决策：显式设置 kSecUseDataProtectionKeychain。
置信度：中高。
证据：E-03、E-06。

### 4.2 观察二：Windows 当前持久化可能漫游

观察：keyring 3.6.3 写入 CRED_PERSIST_ENTERPRISE。
观察：ENTERPRISE 可以在同一用户的其他计算机可见。
推论：当前 Windows 实现不满足设备绑定。
决策：改为 CRED_PERSIST_LOCAL_MACHINE。
置信度：高。
证据：E-04、E-15。

### 4.3 观察三：原生存储不适合保存全部记录

观察：Windows 通用凭据上限为 2560 字节。
观察：Android Keystore 操作密钥，不直接保存任意 secret。
推论：逐条保存会让合同受平台限制。
决策：原生存储只保存根密钥，Rust 保存记录。
置信度：高。
证据：E-14、E-20。

### 4.4 观察四：平台认证保证不同

观察：Apple 和 Android 可以提供密钥级认证要求。
观察：Windows UserConsentVerifier 与 Credential Manager 分离。
推论：统一合同不能只写“需要生物认证”。
决策：返回有效认证类型和执行位置。
置信度：中高。
证据：E-09、E-18、E-21。

### 4.5 观察五：新设备恢复没有共同秘密

观察：ThisDeviceOnly 项不迁移到新设备。
观察：Android Keystore 密钥不可导出。
观察：Windows LOCAL_MACHINE 项不在其他计算机可见。
推论：新设备不能解密旧仓库。
决策：重新配对。
置信度：高。
证据：E-08、E-15、E-20。

### 4.6 观察六：当前 C ABI 泄漏面过大

观察：当前 C ABI 提供任意 Keychain 读取。
观察：读取结果复制到调用方内存。
观察：释放函数没有先零化。
推论：UI 或调用方可以获得长期秘密。
决策：删除通用读取，改为用途受限 facade。
置信度：高。
证据：E-05、E-25。

## 5. 不采用方案

### 5.1 继续直接使用 keyring 抽象

原因：当前 Windows 持久化不满足设备绑定。
风险：凭据可能随漫游配置进入其他计算机。
风险：macOS 后端可能继续使用 file-based Keychain。
风险：错误和能力模型不足。
结论：不采用为最终合同。

### 5.2 使用 PasswordVault 保存根密钥

原因：PasswordVault 会随 Microsoft 账户漫游。
风险：设备绑定承诺失效。
风险：每应用最多 20 条。
风险：非 AppContainer 桌面应用可以访问所有用户 locker。
结论：不采用。

### 5.3 每个凭据直接写入 Windows Credential Manager

原因：通用凭据 blob 上限为 2560 字节。
风险：大 secret 无法保存。
风险：记录迁移需要逐项操作。
风险：平台 ACL 差异进入业务层。
结论：不采用为首要方案。

### 5.4 用 UserConsentVerifier 冒充加密 ACL

原因：UserConsentVerifier 是独立确认接口。
风险：确认不等于凭据项访问控制。
风险：同一用户进程仍可能访问凭据。
结论：不采用。
如需要强绑定，必须单独立项验证 Windows Hello、CNG 或 TPM。

### 5.5 把 Android Keystore 当作任意 secret 容器

原因：Keystore 保存非导出密钥，不提供任意大块值保存。
风险：把密文和密钥混为一谈。
风险：备份和恢复逻辑错误。
结论：不采用。
Android 适配器必须包装根密钥，密文放 no-backup 目录。

### 5.6 用用户口令作为首发唯一恢复方式

原因：首发目标是无账号配对和后台接收。
风险：后台任务需要用户输入。
风险：口令恢复流程增加产品复杂度。
结论：不采用。
可以作为未来的显式导出和恢复方案。

## 6. 系统限制

1. Apple data protection Keychain 只适用于有用户上下文的进程。
2. Apple Keychain 调用可能阻塞线程。
3. Apple ThisDeviceOnly 项不能迁移到另一台设备。
4. Windows 通用凭据 blob 最大为 2560 字节。
5. Windows Credential Manager 使用当前用户令牌。
6. Windows 通用凭据没有同等项级生物 ACL 证据。
7. Android Keystore 密钥不可导出。
8. Android 认证绑定密钥会因锁屏或生物登记变化失效。
9. Android StrongBox 不是所有设备都支持。
10. Android 备份和 D2D 规则受 Android 版本和厂商影响。
11. Rust AEAD 和 KDF 选型仍需独立评审。
12. 设备身份密钥的最终格式尚未决定。

## 7. 产品限制

1. 首发版本不支持账号恢复。
2. 首发版本不支持云端密钥备份。
3. 首发版本不承诺跨设备自动迁移。
4. 首发版本不承诺 Windows 生物认证等同 Apple 或 Android。
5. 首发版本不承诺所有平台都有硬件级根密钥。
6. 后台接收可能因设备锁定暂停。
7. 用户需要重新配对才能恢复新设备上的受保护关系。
8. 正式发布前必须完成平台真机验证。
9. 正式发布前必须完成秘密内存和日志审计。
10. 正式发布前必须完成迁移回滚演练。

## 8. 未决项

### 8.1 必须决策

1. 记录 AEAD 算法。
2. 根密钥 KDF 和记录密钥派生方式。
3. 设备身份密钥算法。
4. 配对记录的最小字段。
5. 后台传输密钥和审批密钥的最终策略。
6. 日志保留期限。
7. 迁移期的旧项保留时间。

### 8.2 必须验证

1. macOS data protection Keychain 和备份恢复。
2. iOS 后台锁定读取和生物认证失效。
3. Windows LOCAL_MACHINE 持久化和用户隔离。
4. Windows UserConsentVerifier 的实际提示行为。
5. Android Keystore 包装、认证和失效。
6. Android no-backup 和 D2D 行为。
7. C ABI、UniFFI 和 JNI 的错误映射。
8. 秘密零化在 FFI 释放路径上的效果。

### 8.3 当前置信度

| 结论 | 置信度 | 原因 |
| --- | --- | --- |
| 原生存储应只保存根密钥 | 高 | 平台限制清楚，候选方案可推导 |
| Apple 应使用 data protection Keychain | 高 | Apple 技术说明明确建议 |
| Windows 应使用 LOCAL_MACHINE | 高 | 持久化语义明确 |
| Windows 没有同等项级生物 ACL | 中高 | 基于公开 API 和文档的推论 |
| Android 应使用 Keystore 包装根密钥 | 高 | Keystore 能力明确 |
| 新设备恢复需要重新配对 | 高 | 三个平台都缺少共同根密钥 |
| Rust AEAD 具体算法 | 待定 | 尚未完成算法 ADR |
| Paseo 的凭据实现 | 未验证 | 未完成源码核验 |

## 9. 结论边界

本结论是架构和合同建议。
本结论不是正式安全认证。
本结论不表示平台原生存储已经通过真机验收。
本结论不表示 Windows 生物认证已经可以等同 Apple 或 Android。
本结论不表示 Android 第一版已经进入实现。
所有真实结果必须在验证案例中回填。
