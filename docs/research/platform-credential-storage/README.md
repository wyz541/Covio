# 跨平台凭据存储合同

推荐方案分两层。平台原生安全存储保护根密钥。Rust 统一 facade 管理加密记录、生命周期、错误和迁移。

## 文档状态

| 项目 | 内容 |
| --- | --- |
| 文档版本 | 1.0 |
| 状态 | 初稿，可评审 |
| 日期 | 2026-11-10 |
| 适用对象 | Covio 产品、Rust、SwiftUI、Compose、测试和安全人员 |
| 当前环境 | 官方文档与仓库 commit 5a1f6c8dd9d2a66dd2cb6c7d0f68b08fc9b88297 |
| 当前结论 | 原生根密钥保护加 Rust 加密仓库 |
| 验证状态 | 尚未执行 |
| 首发平台 | macOS、Windows、iOS |
| 后继平台 | Android |

## 前因

Covio 需要保存设备身份、二维码配对记录、传输密钥和提供方 API 密钥。
三个首发平台没有相同的原生安全存储语义。
macOS 和 iOS 需要 Keychain。
Windows 需要 Credential Manager。
Android 后续需要 Keystore。
统一合同必须先表达平台能力，再执行安全策略。

研究问题、范围、系统模型、状态矩阵和成功标准见 [context.md](context.md)。
现有实现和当前边界见 [evidence.md](evidence.md)。

## 背景

macOS 有 file-based Keychain 和 data protection Keychain。
iOS 只提供 data protection Keychain。
Windows 通用凭据有 2560 字节上限和不同持久化范围。
Android Keystore 保存非导出密钥，不保存任意大秘密。
因此不能把三个平台压成一个 key-value 布尔接口。
必须区分设备绑定、硬件保护、用户在场和备份范围。

技术分析、平台矩阵、候选方案和源码分析见 [investigation.md](investigation.md)。
来源、观察、推论和限制见 [evidence.md](evidence.md)。

## 过程

调研先读取 Covio 的研究规范和跨平台目标架构。
调研再读取 Apple、Microsoft、Android 的官方接口和备份说明。
调研随后检查当前 SecretStore、平台适配器和 C ABI。
调研最后比较薄封装、逐项原生存储、Rust 加密仓库、软件 vault 和云 KMS。
本轮没有执行平台真机测试。
所有验证计划保持“尚未执行”。

调研方法和候选方案见 [investigation.md](investigation.md)。
证据和复核方法见 [evidence.md](evidence.md)。
验证矩阵见 [validation/README.md](validation/README.md)。

## 结果

结论一：原生存储只保存 32 字节根密钥或小型根密钥包装。
结论二：业务记录使用 Rust AEAD 加密。
结论三：AAD 绑定应用、设备、仓库、用途和版本。
结论四：设备绑定、硬件保护、用户在场和备份范围必须分开表达。
结论五：平台不能执行请求策略时必须失败关闭。
结论六：UI 不读取通用秘密。
结论七：新设备恢复后重新配对。
结论八：Android 使用 Keystore 包装根密钥。

关键实现风险如下。

1. 当前 macOS 适配器没有显式选择 data protection Keychain。
2. 当前 Windows 适配器使用 ENTERPRISE 持久化。
3. 当前 C ABI 暴露任意 Keychain 读接口。
4. 当前 C ABI 释放秘密缓冲区前没有零化。
5. 当前错误模型不能区分锁定、取消和密钥失效。

结论、决策表、不采用方案和限制见 [conclusion.md](conclusion.md)。
证据链和缺口见 [evidence.md](evidence.md)。

## 预期

目标合同应满足以下条件。

1. 三个首发平台使用同一 Rust facade。
2. 平台适配器返回真实能力。
3. 不支持的策略返回稳定错误码。
4. 根密钥不跨 C ABI、UniFFI 或 JNI 返回。
5. 配对记录和传输密钥设备绑定。
6. 后台传输密钥和审批密钥分开配置。
7. 根密钥丢失时不自动覆盖密文。
8. 迁移失败时可以回滚。
9. 日志不包含秘密或个人内容。
10. Android 可以在后续接入 Keystore。

推荐架构、trait、错误码和实施计划见 [solution.md](solution.md)。
验证目标、测试矩阵和清理要求见 [validation/README.md](validation/README.md)。
证据链见 [evidence.md](evidence.md)。

## 实现预期的手段

第一阶段完成合同和错误码评审。
第二阶段实现 Rust facade 和测试后端。
第三阶段改造 macOS 并增加 iOS 目标。
第四阶段改造 Windows Credential Manager 适配器。
第五阶段建立 Android Keystore 合同。
第六阶段收口 C ABI、UniFFI 和 JNI 边界。

macOS 使用 data protection Keychain。
Windows 使用 CRED_TYPE_GENERIC 和 CRED_PERSIST_LOCAL_MACHINE。
Android 使用 Keystore 包装根密钥，密文放 no-backup 目录。
Apple 和 Android 可以执行密钥级用户认证。
Windows 首发只把 UserConsentVerifier 标为用户界面确认。

推荐方案和安全边界见 [solution.md](solution.md)。
实际验证记录见 [validation/README.md](validation/README.md)。
证据支持见 [evidence.md](evidence.md)。

## 子文档

| 文件 | 内容 |
| --- | --- |
| [context.md](context.md) | 研究问题、范围、系统模型、状态矩阵和成功标准 |
| [investigation.md](investigation.md) | 调研方法、平台能力、候选方案、源码分析和缺口 |
| [conclusion.md](conclusion.md) | 结论、决策表、不采用方案、限制和未决项 |
| [solution.md](solution.md) | 推荐架构、Rust trait、类型、错误码、adapter、流程和迁移 |
| [evidence.md](evidence.md) | 来源、观察、推论、反证、复核方法和参考链接 |
| [validation/README.md](validation/README.md) | 验证目标、测试矩阵、风险和清理要求 |
| [validation/case-apple-keychain.md](validation/case-apple-keychain.md) | macOS 和 iOS 的 Keychain 验证计划 |
| [validation/case-windows-credential-manager.md](validation/case-windows-credential-manager.md) | Windows Credential Manager 验证计划 |
| [validation/case-rust-vault-contract.md](validation/case-rust-vault-contract.md) | Rust facade、错误和内存边界验证计划 |
| [validation/case-android-keystore-contract.md](validation/case-android-keystore-contract.md) | Android Keystore 合同验证计划 |

## 证据链

1. 从 [context.md](context.md) 阅读问题边界和状态矩阵。
2. 从 [investigation.md](investigation.md) 阅读平台能力、源码分析和候选方案。
3. 从 [evidence.md](evidence.md) 阅读官方来源、观察、推论和限制。
4. 从 [conclusion.md](conclusion.md) 阅读决策、不采用方案和未决项。
5. 从 [solution.md](solution.md) 阅读推荐合同、trait、错误码和实施计划。
6. 从 [validation/README.md](validation/README.md) 阅读测试矩阵和清理要求。
7. 从 [validation/case-apple-keychain.md](validation/case-apple-keychain.md) 阅读 Apple 验证计划。
8. 从 [validation/case-windows-credential-manager.md](validation/case-windows-credential-manager.md) 阅读 Windows 验证计划。
9. 从 [validation/case-rust-vault-contract.md](validation/case-rust-vault-contract.md) 阅读 Rust 合同验证计划。
10. 从 [validation/case-android-keystore-contract.md](validation/case-android-keystore-contract.md) 阅读 Android 验证计划。

## 更新规则

执行验证后更新案例状态。
执行验证后更新验证矩阵。
执行验证后更新结论和限制。
执行验证后更新证据缺口。
执行验证后更新本索引。
平台 API 变化时更新证据和方案。
接口或错误码变化时更新 solution.md。
正式发布前完成真机证据和安全复核。
