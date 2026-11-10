# Covio Rust 跨平台文件传输研究

## 文档状态

| 项目 | 内容 |
| --- | --- |
| 文档版本 | `1.0` |
| 状态 | 初稿，可评审 |
| 日期 | `2026-11-10` |
| 适用对象 | Covio Rust、macOS、Windows、iOS、安全和测试人员 |
| 当前验证环境 | macOS、Windows、iOS 尚未执行传输验证 |
| 当前结论 | 推荐 iroh 作为首版传输底座。Covio 自建文件协议。 |
| 验证状态 | 尚未执行 |

## 前因

Covio 第一版只支持 macOS、Windows 和 iOS。
Covio 需要提供类似 AirDrop 的文件共享。
发送方与接收方必须先配对。
接收方必须先看到文件摘要，再明确接受。
配对入口使用二维码。
移动端进入后台后不能保证持续传输。
移动端回到前台后必须恢复接收或续传。
研究问题、边界和成功标准见 [context.md](context.md)。
证据链见 [evidence.md](evidence.md)。

## 背景

文件传输同时涉及发现、身份、传输、恢复和落盘。
局域网不能作为信任边界。
互联网 relay 也不能作为信任边界。
Paseo 的固定 commit 使用二维码分发 daemon 公钥。
Paseo 的 relay 只转发端到端密文。
Paseo 的客户端在前台执行连接复核。
Rust 生态同时提供 QUIC、P2P、mDNS、散列和原子写入能力。
技术分析和候选方案见 [investigation.md](investigation.md)。
当前源码观察和来源限制见 [evidence.md](evidence.md)。

## 过程

调研截至 `2026-11-10`。
Paseo 证据来自 commit `2e1747a145cd11c2f6ba7ef9fd8745a1a5b4455b`。
重点查看 `packages/relay`、`packages/server`、`packages/app` 和 connectivity 文档。
Rust 证据来自 RFC、固定版本源码仓库和 crates 元数据。
没有复制 Paseo 产品代码。
没有执行真实传输测试。
没有执行 iOS 真机后台测试。
调研方法、来源和方案矩阵见 [investigation.md](investigation.md)。
源码、命令和限制见 [evidence.md](evidence.md)。
验证计划见 [validation/README.md](validation/README.md)。

## 结果

推荐 iroh `1.4.1` 作为首版传输底座。
iroh 支持公钥寻址、直连打洞、relay 回退和 QUIC 连接。
Covio 必须在 iroh 之上定义文件清单、分块、确认、续传和原子落盘协议。
纯 quinn 方案需要自行建设 relay、地址发现和 NAT 穿透。
mDNS 只用于局域网发现提示。mDNS 不建立信任。
文件完整性主校验使用 BLAKE3。
SHA-256 作为外部兼容字段，不作为首版主路径。
首版使用固定 `1 MiB` 分块和 `8 MiB` 发送窗口。
接收端按持久检查点恢复。检查点只记录已同步数据和已验证范围。
接收端先写入同一文件系统的临时文件。校验通过后再原子提交。
iOS 进入后台后暂停主动传输。
iOS 回到前台后先验证连接，再从检查点恢复。
具体限制和未决项见 [conclusion.md](conclusion.md)。
证据索引和逻辑链见 [evidence.md](evidence.md)。

## 预期

首版支持 macOS、Windows 和 iOS。
首版支持单文件和目录快照。
目录快照不表示实时同步。
首版支持发送方发起、接收方可见确认。
首版支持配对设备重连、暂停、取消和断点续传。
首版支持冲突策略 `keep_both`、`replace` 和 `skip`。
首版不允许跟随符号链接。
首版只保留可执行位和只读属性。
首版不保证 iOS 后台持续接收。
验收标准和首版范围见 [solution.md](solution.md)。
验证目标、矩阵和风险见 [validation/README.md](validation/README.md)。
证据链见 [evidence.md](evidence.md)。

## 实现预期的手段

推荐使用 `iroh` 传输层和自有 `covio-transfer-protocol`。
控制流承载 CBOR 信封。数据流承载长度前缀分块。
每个分块携带 BLAKE3 校验和。
每个文件携带最终 BLAKE3 校验和。
传输状态持久化到 SQLite。
发送窗口按持久确认字节推进。
接收端使用 `.covio/staging` 和同卷原子重命名。
文件系统能力通过平台适配层封装。
Swift 通过 C ABI 调用。UniFFI 只做可选绑定试验。
Windows Compose 通过 JNI 调用。
Android 后续通过 JNI 调用。
推荐架构、接口、状态机、错误码和完整语义见 [solution.md](solution.md)。
验证计划见 [validation/README.md](validation/README.md)。
证据和缺口见 [evidence.md](evidence.md)。

## 子文档

| 文件 | 内容 |
| --- | --- |
| [context.md](context.md) | 问题边界、场景、系统模型和成功标准 |
| [investigation.md](investigation.md) | Paseo 分析、Rust 方案矩阵、反证和缺口 |
| [conclusion.md](conclusion.md) | 推荐决策、不采用方案、限制和未决项 |
| [solution.md](solution.md) | 架构、接口、状态机、文件语义和实施计划 |
| [evidence.md](evidence.md) | 固定来源、观察、推论和证据缺口 |
| [validation/README.md](validation/README.md) | 验证目标、范围和测试矩阵 |
| [validation/case-transfer-metadata.md](validation/case-transfer-metadata.md) | 传输、校验和元数据案例 |
| [validation/case-mobile-lifecycle.md](validation/case-mobile-lifecycle.md) | iOS 前后台和续传案例 |

## 证据链

1. 从 [context.md](context.md) 阅读问题边界。
2. 从 [investigation.md](investigation.md) 阅读技术分析。
3. 从 [evidence.md](evidence.md) 阅读来源和观察。
4. 从 [conclusion.md](conclusion.md) 阅读推荐决策。
5. 从 [solution.md](solution.md) 阅读协议和文件语义。
6. 从 [validation/README.md](validation/README.md) 阅读验证矩阵。
7. 从 [validation/case-transfer-metadata.md](validation/case-transfer-metadata.md) 阅读传输案例计划。
8. 从 [validation/case-mobile-lifecycle.md](validation/case-mobile-lifecycle.md) 阅读移动端案例计划。

## 更新规则

执行验证后更新案例状态。
执行验证后更新验证矩阵。
执行验证后更新结论和限制。
执行验证后更新证据缺口。
执行验证后更新本索引。
修改推荐协议时更新接口版本。
新增平台时更新验收矩阵。
