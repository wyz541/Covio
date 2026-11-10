# 证据附录

## 文档状态

| 项目 | 内容 |
| --- | --- |
| 文档版本 | `1.0` |
| 状态 | 审计记录，可复核 |
| 日期 | `2026-11-10` |
| 主文 | [主题索引](README.md) |
| 验证目录 | [验证目录](validation/README.md) |
| 传输案例 | [传输案例](validation/case-transfer-metadata.md) |
| 移动端案例 | [移动端案例](validation/case-mobile-lifecycle.md) |

本文保存可复核证据。
本文不保存凭据。
本文不保存文件内容。
本文不保存设备序列号。
本文不保存本机绝对路径。

## 1. 来源等级

| 等级 | 来源 | 用途 | 置信度 |
| --- | --- | --- | --- |
| A | IETF RFC、NIST 标准 | 协议和安全约束 | 高 |
| B | 固定 commit 源码、固定版本项目源码 | 实现边界和可验证行为 | 高 |
| C | 官方项目文档、crates.io 元数据 | 能力、版本和维护状态 | 中高 |
| D | 当前仓库命令检查 | 当前环境事实 | 高，但范围小 |
| E | 第三方文章 | 本文件不使用 | 低 |

高影响结论使用 A 或 B 证据。
C 证据用于版本和项目能力。
D 证据只代表当前环境。
E 证据不能单独支持关键决策。

## 2. 环境事实

| 项目 | 值 | 命令 | 置信度 |
| --- | --- | --- | --- |
| 调研日期 | `2026-11-10` | 用户要求 | 高 |
| 当前分支 | `docs/cross-platform-product-direction` | `git status --short --branch` | 高 |
| 当前 HEAD | `5a1f6c8dd9d2a66dd2cb6c7d0f68b08fc9b88297` | `git rev-parse HEAD` | 高 |
| Paseo commit | `2e1747a145cd11c2f6ba7ef9fd8745a1a5b4455b` | `gh api repos/getpaseo/paseo/commits/<sha>` | 高 |
| Paseo commit 时间 | `2026-11-10T02:49:11Z` | 同一 API 输出 | 高 |
| Paseo 分析范围 | `packages/relay`、`packages/server`、`packages/app`、connectivity 文档 | 文件树和源码 | 高 |
| Covio 传输测试 | 尚未执行 | 本任务没有运行原型 | 高 |
| iOS 真机测试 | 尚未执行 | 本任务没有 iOS 设备测试 | 高 |

仓库存在本任务之外的未提交改动。
本任务没有修改这些改动。
本任务只修改 `docs/research/rust-file-transfer/`。

## 3. 证据索引

| 编号 | 主题 | 来源 | 结论 | 置信度 |
| --- | --- | --- | --- | --- |
| E-01 | Paseo 固定快照 | GitHub commit 和文件树 | 可以按固定 commit 复核 | 高 |
| E-02 | Paseo 二维码配对 | `pairing-offer.ts`、`connection-offer.ts`、`pair-scan-model.ts` | 二维码分发公钥和 relay 地址 | 高 |
| E-03 | Paseo relay 安全 | `relay-endpoint-security.md`、`secure-channel.ts` | Relay 不可信，protected 模式有重放保护 | 高 |
| E-04 | Paseo 移动端恢复 | `daemon-client.ts`、`host-runtime.ts`、architecture 文档 | 前台验活，失败后立即重连 | 高 |
| E-05 | Paseo 文件传输 | `file-transfer.ts`、e2e 测试、architecture 文档 | 有界分块和有界发送窗口 | 高 |
| E-06 | QUIC 传输语义 | RFC 9000 | 多流、流控和连接迁移 | 高 |
| E-07 | QUIC 安全与丢包 | RFC 9001、RFC 9002 | TLS 1.3 保护和包级恢复 | 高 |
| E-08 | quinn 能力 | quinn README `0.11.12` | 纯 Rust QUIC，macOS 和 Windows 已测试 | 高 |
| E-09 | iroh 能力 | iroh README `1.4.1`、iroh-relay README | 公钥寻址、打洞、relay 回退、QUIC | 高 |
| E-10 | mDNS 能力 | RFC 6762、RFC 6763、mdns-sd README | 发现可用，信任不可用 | 高 |
| E-11 | 散列选择 | crates.io 元数据、BLAKE3 规格、NIST 标准 | BLAKE3 主校验，SHA-256 兼容字段 | 中高 |
| E-12 | 原子写入工具 | crates.io 元数据 | 需要同卷暂存和平台测试 | 中 |
| E-13 | 目录遍历工具 | crates.io 元数据 | 首版使用一次快照，不做实时同步 | 中 |
| E-14 | FFI 和持久化工具 | crates.io 元数据 | UniFFI、JNI、SQLite 和 TLS 工具存在 | 中高 |
| E-15 | Paseo 文件语义缺口 | Paseo 源码范围 | Paseo 不是完整文件同步协议 | 高 |
| E-16 | 当前验证状态 | 当前仓库和任务记录 | 典型传输和移动端测试尚未执行 | 高 |

## 4. 证据详情

### E-01：Paseo 固定快照

来源等级：B
环境：公开仓库 `getpaseo/paseo`，commit `2e1747a145cd11c2f6ba7ef9fd8745a1a5b4455b`
命令或来源：

- `gh api repos/getpaseo/paseo/commits/2e1747a145cd11c2f6ba7ef9fd8745a1a5b4455b`
- `https://github.com/getpaseo/paseo/tree/2e1747a145cd11c2f6ba7ef9fd8745a1a5b4455b`

关键输出：

```text
sha = 2e1747a145cd11c2f6ba7ef9fd8745a1a5b4455b
date = 2026-11-10T02:49:11Z
```

观察：固定 commit 包含 `packages/relay`、`packages/server`、`packages/app` 和 connectivity 文档。
推论：本文的 Paseo 结论可以按同一 commit 复核。
反证：没有执行 Paseo 运行时测试。
限制：结论只覆盖源码和文档。结论不覆盖当前分支之后的代码。
置信度：高
关联：`E-02`、`E-03`、`E-04`、`E-05`、`E-15`

### E-02：Paseo 二维码配对

来源等级：B
环境：Paseo commit `2e1747a145cd11c2f6ba7ef9fd8745a1a5b4455b`
命令或来源：

- `https://github.com/getpaseo/paseo/blob/2e1747a145cd11c2f6ba7ef9fd8745a1a5b4455b/packages/server/src/server/pairing-offer.ts`
- `https://github.com/getpaseo/paseo/blob/2e1747a145cd11c2f6ba7ef9fd8745a1a5b4455b/packages/server/src/server/connection-offer.ts`
- `https://github.com/getpaseo/paseo/blob/2e1747a145cd11c2f6ba7ef9fd8745a1a5b4455b/packages/app/src/hosts/add-host/internal/pair-scan-model.ts`
- `https://github.com/getpaseo/paseo/blob/2e1747a145cd11c2f6ba7ef9fd8745a1a5b4455b/packages/app/src/runtime/host-runtime.ts`

关键输出：

```text
ConnectionOfferV2Schema:
  v, serverId, daemonPublicKeyB64, relay, minimumSecurityMode

encodeOfferToFragmentUrl:
  appBaseUrl + "#offer=" + base64url(JSON)

pair scan accepts:
  "#offer=", "#connect=", "relay://"
```

观察：二维码报价包含 daemon 公钥和 relay 地址。
观察：客户端在新增主机或改变主机身份时要求确认。
观察：配对流程支持认证凭据。
推论：二维码是身份和地址提示。二维码不是长期信任本身。
推论：公钥固定和用户确认必须共同使用。
反证：本次没有验证二维码被拍照后的实际攻击路径。
限制：报价不包含 Covio 接收方所需的双向文件确认语义。
置信度：高
关联：`E-03`、`E-04`

### E-03：Paseo relay 安全

来源等级：B
环境：Paseo commit `2e1747a145cd11c2f6ba7ef9fd8745a1a5b4455b`
命令或来源：

- `https://github.com/getpaseo/paseo/blob/2e1747a145cd11c2f6ba7ef9fd8745a1a5b4455b/docs/relay-endpoint-security.md`
- `https://github.com/getpaseo/paseo/blob/2e1747a145cd11c2f6ba7ef9fd8745a1a5b4455b/packages/relay/src/secure-channel.ts`
- `https://github.com/getpaseo/paseo/blob/2e1747a145cd11c2f6ba7ef9fd8745a1a5b4455b/packages/server/src/server/daemon-keypair.ts`

关键输出：

```text
relay is untrusted
protected = Noise_NK_25519_ChaChaPoly_SHA256
prologue = paseo-relay-e2ee/1
fresh daemon ephemeral per channel
counter-based replay protection
client pins daemon public key
```

观察：Paseo 把 relay 作为不可信转发通道。
观察：Paseo 在 protected 模式中使用新的临时密钥和记录计数器。
观察：Paseo 的客户端可以按 daemon 公钥建立最低安全模式。
推论：Covio 应使用端到端加密和公钥固定。
推论：Relay 可以负责转发。Relay 不能获得文件明文。
反证：Paseo 仍支持兼容模式。旧模式没有重放保护。
限制：Paseo 的 Noise 线协议不能直接复制到 QUIC。
置信度：高
关联：`E-02`、`E-06`、`E-07`

### E-04：Paseo 移动端恢复

来源等级：B
环境：Paseo commit `2e1747a145cd11c2f6ba7ef9fd8745a1a5b4455b`
命令或来源：

- `https://github.com/getpaseo/paseo/blob/2e1747a145cd11c2f6ba7ef9fd8745a1a5b4455b/docs/architecture.md`
- `https://github.com/getpaseo/paseo/blob/2e1747a145cd11c2f6ba7ef9fd8745a1a5b4455b/packages/client/src/daemon-client.ts`
- `https://github.com/getpaseo/paseo/blob/2e1747a145cd11c2f6ba7ef9fd8745a1a5b4455b/packages/app/src/runtime/host-runtime.ts`
- `https://github.com/getpaseo/paseo/blob/2e1747a145cd11c2f6ba7ef9fd8745a1a5b4455b/packages/app/src/navigation/host-runtime-bootstrap.ts`

关键输出：

```text
heartbeat interval = 10 s
ordinary timeout = 15 s
failure threshold = 2
foreground window = 5 s
foreground windows = 2
reconnect base = 1500 ms
reconnect max = 30000 ms
```

观察：应用可见性变化绑定到 `setAppVisible`。
观察：前台进入验证周期。验证失败后立即重连。
观察：后台只保持正常重连。Paseo 不保证系统继续执行。
推论：Covio 需要应用级前台验活。
推论：Covio 不能依赖旧 socket 或旧心跳结果。
推论：Covio 应把后台状态建模为暂停。
反证：本次没有 iOS 真机数据。
限制：Paseo 是 React Native 客户端。时序不能直接推导到 SwiftUI 和 Rust。
置信度：高
关联：`E-01`、`E-05`

### E-05：Paseo 文件传输和背压

来源等级：B
环境：Paseo commit `2e1747a145cd11c2f6ba7ef9fd8745a1a5b4455b`
命令或来源：

- `https://github.com/getpaseo/paseo/blob/2e1747a145cd11c2f6ba7ef9fd8745a1a5b4455b/packages/protocol/src/binary-frames/file-transfer.ts`
- `https://github.com/getpaseo/paseo/blob/2e1747a145cd11c2f6ba7ef9fd8745a1a5b4455b/packages/server/src/server/websocket-server.file-transfer.e2e.test.ts`
- `https://github.com/getpaseo/paseo/blob/2e1747a145cd11c2f6ba7ef9fd8745a1a5b4455b/docs/architecture.md`
- `https://github.com/getpaseo/paseo/blob/2e1747a145cd11c2f6ba7ef9fd8745a1a5b4455b/docs/connected-hosts.md`

关键输出：

```text
FileBegin = 0x10
FileChunk = 0x11
FileEnd = 0x12
chunk size = 256 KiB
outbound high-water = 8 MiB
routed message limit = 100 MiB
```

观察：文件下载使用稳定文件句柄。
观察：每个分块等待物理发送完成。
观察：传输按来源 socket 隔离。
观察：Paseo 的文件帧没有目录清单、冲突和原子提交。
推论：Covio 需要自建文件语义。
推论：有界分块和背压可以复用。
反证：Paseo 的测试没有覆盖断点续传和目录。
限制：Paseo 的文件帧不是 Covio 的协议合同。
置信度：高
关联：`E-04`、`E-06`、`E-07`、`E-15`

### E-06：QUIC 传输语义

来源等级：A
环境：RFC 9000
命令或来源：

- `https://www.rfc-editor.org/rfc/rfc9000.html`
- 本地复核：`rfc9000.txt`

关键输出：

```text
Section 3: Streams
Section 4: Flow Control
Section 9: Connection Migration
Stream multiplexing avoids head-of-line blocking
```

观察：QUIC 支持多流传输。
观察：QUIC 提供按流和按连接的流控。
观察：连接可以在地址变化后迁移。
推论：控制流和文件流可以隔离。
推论：大文件可以使用多个有界流。
反证：QUIC 不保存应用级文件检查点。
限制：需要 UDP 可达或 relay。
置信度：高
关联：`E-07`、`E-08`、`E-09`

### E-07：QUIC 安全与丢包恢复

来源等级：A
环境：RFC 9001 和 RFC 9002
命令或来源：

- `https://www.rfc-editor.org/rfc/rfc9001.html`
- `https://www.rfc-editor.org/rfc/rfc9002.html`
- 本地复核：`rfc9001.txt`、`rfc9002.txt`

关键输出：

```text
RFC 9001: TLS provides authentication, confidentiality and integrity
RFC 9002: per-packet-number-space loss detection
RFC 9002: Probe Timeout (PTO)
```

观察：QUIC 使用 TLS 1.3 保护传输。
观察：QUIC 在包级执行丢失检测和探测超时。
推论：应用不应重复实现包级重传。
推论：应用仍需要文件和检查点恢复。
反证：0-RTT 有重放风险。变更操作不应使用 0-RTT。
限制：传输层完整性不等于文件语义完整性。
置信度：高
关联：`E-05`、`E-06`、`E-08`

### E-08：quinn 能力

来源等级：B
环境：quinn `0.11.12`，commit tag `quinn-0.11.12`
命令或来源：

- `https://github.com/quinn-rs/quinn/blob/quinn-0.11.12/README.md`
- `https://docs.rs/quinn/0.11.12/quinn/`

关键输出：

```text
pure-Rust QUIC
async-compatible
ordered and unordered stream reads
tested on Linux, macOS and Windows
rustls and ring
```

观察：quinn 提供纯 Rust QUIC。
观察：quinn 的 README 列出 macOS 和 Windows 测试。
观察：quinn 不提供 P2P 发现、打洞和 relay。
推论：quinn 适合自有传输实现。
推论：首版使用 quinn 会增加网络工程范围。
反证：README 没有明确列出 iOS。
限制：需要单独验证 iOS 构建和移动网络行为。
置信度：高
关联：`E-06`、`E-07`、`E-09`

### E-09：iroh 能力

来源等级：B
环境：iroh `1.4.1`，iroh-relay `1.4.1`
命令或来源：

- `https://github.com/n0-computer/iroh/blob/v1.4.1/README.md`
- `https://github.com/n0-computer/iroh/blob/v1.4.1/iroh-relay/README.md`
- `https://github.com/n0-computer/iroh/blob/v1.4.1/iroh/docs/relays.md`

关键输出：

```text
dial by public key
hole punching
relay fallback
built on QUIC
concurrent streams
relay can be self-hosted
relay supports allowlist, denylist and shared access control
```

观察：iroh 自动寻找直连路径。
观察：iroh 在直连失败后使用 relay。
观察：iroh-relay 提供自建和访问控制。
推论：iroh 覆盖首版 P2P 的主要网络需求。
推论：Covio 仍需定义文件协议和接收确认。
反证：iroh 版本较新。公共 relay 有外部依赖。
限制：本次没有 iOS 构建和真机测试。
置信度：高
关联：`E-06`、`E-07`、`E-08`

### E-10：mDNS 能力

来源等级：A 和 B
环境：RFC 6762、RFC 6763、mdns-sd `0.21.7`
命令或来源：

- `https://www.rfc-editor.org/rfc/rfc6762.html`
- `https://www.rfc-editor.org/rfc/rfc6763.html`
- `https://github.com/keepsimple1/mdns-sd/blob/v0.21.7/README.md`

关键输出：

```text
mDNS uses multicast UDP port 5353
DNS-SD describes service instances
mdns-sd supports macOS, Linux and Windows
mdns-sd README marks the implementation beta
RFC 6762 security section assumes cooperating participants
```

观察：mDNS 提供局域网名称和服务发现。
观察：mDNS 实现可能阻断或不可用。
观察：mDNS 记录没有强身份认证。
推论：mDNS 只能生成候选地址。
推论：Covio 必须使用二维码或固定公钥建立信任。
反证：mdns-sd 支持基本 macOS、Linux 和 Windows。
限制：README 没有明确列出 iOS。
置信度：高
关联：`E-02`、`E-09`

### E-11：散列选择

来源等级：C
环境：BLAKE3 crate `1.8.7`，sha2 crate `0.11.1`
命令或来源：

- `https://crates.io/crates/blake3`
- `https://crates.io/crates/sha2`
- `https://github.com/BLAKE3-team/BLAKE3`
- `https://csrc.nist.gov/pubs/fips/180-4/upd1/final`

关键输出：

```text
BLAKE3 = 256-bit hash
SHA-256 = 256-bit hash
crate versions checked on 2026-11-10
```

观察：BLAKE3 和 SHA-256 都提供 256 位输出。
观察：BLAKE3 适合树形并行散列。SHA-256 有广泛标准兼容性。
推论：首版使用 BLAKE3 作为主校验。
推论：SHA-256 在外部清单或合规需求出现后加入。
反证：BLAKE3 的 FIPS 合规性未评估。
限制：本次没有下载规格正文。
限制：本次没有执行三平台吞吐基准。
置信度：中高
关联：`E-05`、`E-12`

### E-12：原子写入工具

来源等级：C
环境：tempfile `3.27.0`，atomic-write-file `0.3.1`
命令或来源：

- `https://crates.io/crates/tempfile`
- `https://crates.io/crates/atomic-write-file`
- `https://docs.rs/tempfile/3.27.0/tempfile/`
- `https://docs.rs/atomic-write-file/0.3.1/atomic_write_file/`

关键输出：

```text
tempfile = temporary files and directories
atomic-write-file = atomic file writes
versions checked on 2026-11-10
```

观察：两个 crate 提供临时文件和原子写入相关能力。
推论：Covio 需要同卷暂存、同步和平台提交适配。
推论：不能只依赖 crate 名称证明跨平台原子性。
反证：Windows 替换和跨卷行为未测试。
限制：本次没有阅读两个 crate 的完整源代码。
置信度：中
关联：`E-05`、`E-11`

### E-13：目录遍历工具

来源等级：C
环境：walkdir `2.5.0`，jwalk `0.9.0`
命令或来源：

- `https://crates.io/crates/walkdir`
- `https://crates.io/crates/jwalk`

关键输出：

```text
walkdir = recursive directory iterator
jwalk = parallel directory walker, crate note recommends another project
versions checked on 2026-11-10
```

观察：Rust 生态提供目录遍历 crate。
观察：jwalk 元数据建议使用其他项目。
推论：首版使用简单的一次目录快照。
推论：实时目录同步不应进入首版。
反证：本次没有执行目录压力测试。
限制：没有比较全部目录遍历 crate。
置信度：中
关联：`E-05`、`E-12`

### E-14：FFI 和持久化工具

来源等级：C
环境：uniffi `0.32.2`、jni `0.22.4`、rusqlite `0.41.1`、rustls `0.23.46`、rcgen `0.14.10`、x509-parser `0.18.1`
命令或来源：

- `https://crates.io/crates/uniffi`
- `https://crates.io/crates/jni`
- `https://crates.io/crates/rusqlite`
- `https://crates.io/crates/rustls`
- `https://crates.io/crates/rcgen`
- `https://crates.io/crates/x509-parser`

关键输出：

```text
UniFFI, JNI, SQLite, rustls and certificate utilities are available
versions checked on 2026-11-10
```

观察：Rust 生态具备桥接、持久化和 TLS 工具。
推论：Covio 可以建立 Rust 核心和平台 UI 的稳定边界。
反证：没有执行 Swift、C ABI 或 JNI 集成测试。
限制：版本更新和移动端打包需要单独验证。
置信度：中高
关联：`E-08`、`E-09`、`E-12`

### E-15：Paseo 文件语义缺口

来源等级：B
环境：Paseo commit `2e1747a145cd11c2f6ba7ef9fd8745a1a5b4455b`
命令或来源：

- `https://github.com/getpaseo/paseo/blob/2e1747a145cd11c2f6ba7ef9fd8745a1a5b4455b/packages/protocol/src/binary-frames/file-transfer.ts`
- `https://github.com/getpaseo/paseo/blob/2e1747a145cd11c2f6ba7ef9fd8745a1a5b4455b/docs/architecture.md`
- `https://github.com/getpaseo/paseo/blob/2e1747a145cd11c2f6ba7ef9fd8745a1a5b4455b/docs/connected-hosts.md`

关键输出：

```text
FileBegin: metadata, size, encoding, modifiedAt, revision
FileChunk: payload
FileEnd: empty payload
```

观察：Paseo 的文件帧适合文件流式读取。
观察：Paseo 文件帧没有目录清单、冲突解决和原子提交字段。
推论：Covio 必须定义自己的文件清单和提交合同。
反证：Paseo 的其他模块可能有目录浏览能力。
限制：本任务没有证明 Paseo 不能扩展这些语义。
置信度：高
关联：`E-05`、`E-12`

### E-16：当前验证状态

来源等级：D
环境：当前仓库，日期 `2026-11-10`
命令或来源：

- `git status --short --branch`
- `git rev-parse HEAD`
- 本次任务执行记录

关键输出：

```text
branch = docs/cross-platform-product-direction
HEAD = 5a1f6c8dd9d2a66dd2cb6c7d0f68b08fc9b88297
Covio transfer tests = not run
iOS device tests = not run
```

观察：本任务只做了文档和源码研究。
观察：没有执行 Covio 传输原型。
观察：没有执行 iOS 真机验证。
推论：所有运行时结论都是设计推论。
反证：没有运行时反证样本。
限制：验证结果不能标记为通过。
置信度：高
关联：`validation/README.md`

## 5. 逻辑证据链

```text
身份需求
  -> Paseo 二维码携带公钥 (E-02)
  -> Paseo 固定公钥并确认身份 (E-02)
  -> Covio 使用设备公钥和双端确认
  -> 验证矩阵 V01 和 V02

Transport 需求
  -> QUIC 多流和流控 (E-06)
  -> QUIC TLS 和包级恢复 (E-07)
  -> iroh 提供 P2P 和 relay 回退 (E-09)
  -> Covio 自建文件协议
  -> 验证矩阵 V04、V05 和 V06

完整性需求
  -> Paseo 使用有界分块和背压 (E-05)
  -> BLAKE3 用于分块和文件校验 (E-11)
  -> 暂存文件校验后提交 (E-12)
  -> 验证矩阵 V07、V08 和 V09

移动端需求
  -> Paseo 前台验活和立即重连 (E-04)
  -> iOS 可以暂停应用
  -> Covio 使用后台暂停和前台恢复
  -> 验证矩阵 V10、V11 和 V12
```

## 6. 反证和限制

- Paseo 的 protected 模式有兼容旧模式。旧模式有重放风险。
- Paseo 的 relay 仍有连接元数据可见。
- Paseo 的文件帧没有完整文件同步语义。
- quinn 的 README 没有明确列出 iOS。
- iroh 的公共 relay 不是私有基础设施。
- iroh-ffi 的高层 blob 协议不在稳定范围。
- mDNS 在部分网络不可用。
- BLAKE3 的性能和合规性没有实测。
- SHA-256 的兼容需求没有确认。
- Windows 原子替换没有实测。
- iOS 后台恢复没有实测。
- 目录压力和 10 GiB 文件测试没有执行。

## 7. 已知缺口

| 缺口 | 证据状态 | 影响 | 后续动作 |
| --- | --- | --- | --- |
| iroh iOS 构建 | 未执行 | 可能阻断首版 | Xcode 编译和真机连接 |
| quinn iOS 构建 | 未执行 | 备选方案不可确认 | 编译和网络测试 |
| 公共 relay 隐私 | 未评审 | 可能影响内测范围 | 制定 relay 数据政策 |
| 自建 relay | 未部署 | 发布范围不明 | 建立测试 relay |
| BLAKE3 吞吐 | 未测量 | 分块参数可能不优 | 三平台基准 |
| SHA-256 合规 | 未评审 | 外部兼容性不明 | 安全评审 |
| Windows 原子替换 | 未测量 | 可能无法原子覆盖 | 文件系统测试 |
| macOS Unicode 路径 | 未测量 | 冲突检测可能不完整 | 文件系统测试 |
| iOS 后台恢复 | 未测量 | 任务可能长时间暂停 | 真机生命周期测试 |
| 设备密钥硬件后备 | 未验证 | 长期身份保护不确定 | Keychain 和 Credential Manager 测试 |

## 8. 复核方法

1. 检出 Paseo 指定 commit。
2. 检查 `packages/relay/src/secure-channel.ts`。
3. 检查 `packages/server/src/server/pairing-offer.ts`。
4. 检查 `packages/client/src/daemon-client.ts`。
5. 检查 `packages/protocol/src/binary-frames/file-transfer.ts`。
6. 阅读 RFC 9000、RFC 9001 和 RFC 9002。
7. 阅读 quinn `quinn-0.11.12` README。
8. 阅读 iroh `v1.4.1` 和 iroh-relay `v1.4.1` README。
9. 阅读 mdns-sd `v0.21.7` README。
10. 核对 crates.io 版本元数据。
11. 执行验证矩阵后回填实际结果。
12. 使用 `git diff --check` 检查文档空白。

## 参考来源

- [Paseo commit](https://github.com/getpaseo/paseo/commit/2e1747a145cd11c2f6ba7ef9fd8745a1a5b4455b)
- [Paseo relay security](https://github.com/getpaseo/paseo/blob/2e1747a145cd11c2f6ba7ef9fd8745a1a5b4455b/docs/relay-endpoint-security.md)
- [Paseo architecture](https://github.com/getpaseo/paseo/blob/2e1747a145cd11c2f6ba7ef9fd8745a1a5b4455b/docs/architecture.md)
- [Paseo connected hosts](https://github.com/getpaseo/paseo/blob/2e1747a145cd11c2f6ba7ef9fd8745a1a5b4455b/docs/connected-hosts.md)
- [RFC 9000](https://www.rfc-editor.org/rfc/rfc9000.html)
- [RFC 9001](https://www.rfc-editor.org/rfc/rfc9001.html)
- [RFC 9002](https://www.rfc-editor.org/rfc/rfc9002.html)
- [RFC 6762](https://www.rfc-editor.org/rfc/rfc6762.html)
- [RFC 6763](https://www.rfc-editor.org/rfc/rfc6763.html)
- [quinn 0.11.12](https://github.com/quinn-rs/quinn/blob/quinn-0.11.12/README.md)
- [iroh 1.4.1](https://github.com/n0-computer/iroh/blob/v1.4.1/README.md)
- [iroh-relay 1.4.1](https://github.com/n0-computer/iroh/blob/v1.4.1/iroh-relay/README.md)
- [iroh-ffi 1.2.0](https://github.com/n0-computer/iroh-ffi/blob/v1.2.0/README.md)
- [mdns-sd 0.21.7](https://github.com/keepsimple1/mdns-sd/blob/v0.21.7/README.md)
- [BLAKE3](https://github.com/BLAKE3-team/BLAKE3)
- [NIST FIPS 180-4](https://csrc.nist.gov/pubs/fips/180-4/upd1/final)
- [tempfile 3.27.0](https://docs.rs/tempfile/3.27.0/tempfile/)
- [atomic-write-file 0.3.1](https://docs.rs/atomic-write-file/0.3.1/atomic_write_file/)
- [UniFFI 0.32.2](https://docs.rs/uniffi/0.32.2/uniffi/)
- [JNI 0.22.4](https://docs.rs/jni/0.22.4/jni/)
- [rusqlite 0.41.1](https://docs.rs/rusqlite/0.41.1/rusqlite/)

## 9. 关联文档

- [主题索引](README.md)
- [问题边界](context.md)
- [调研分析](investigation.md)
- [结论](conclusion.md)
- [推荐方案](solution.md)
- [验证目录](validation/README.md)
- [传输案例](validation/case-transfer-metadata.md)
- [移动端案例](validation/case-mobile-lifecycle.md)
