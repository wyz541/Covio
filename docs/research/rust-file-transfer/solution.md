# 推荐架构、接口与实施计划

> 本文件给出首版实现合同。合同用于评审。合同不代表已实现。

## 1. 推荐架构

### 1.1 路径选择

[Covio 决策] 首版使用 `iroh 1.4.1`。
[Covio 决策] Covio 在 iroh 之上定义文件协议。
[Covio 决策] 首版不直接使用 iroh-blobs 作为文件语义。
[Covio 决策] Covio 保留 `quinn` 适配器边界。
[Covio 决策] mDNS 只提供局域网发现提示。
[Covio 决策] 首版先做二维码配对。
[Covio 决策] 首版先做直连和 iroh relay 回退。

选择理由见 [conclusion.md](conclusion.md) 和 [evidence.md](evidence.md)。

### 1.2 组件

| 组件 | 职责 | 环境 | 启动方式 |
| --- | --- | --- | --- |
| `covio-transfer-domain` | 类型、规则、状态机、错误码 | Rust 全平台 | 随应用启动 |
| `covio-transfer-protocol` | CBOR 信封、清单、帧、版本 | Rust 全平台 | 随运行时启动 |
| `covio-transfer-transport` | `Transport` 接口、iroh 适配器 | macOS、Windows、iOS | 任务需要时启动 |
| `covio-transfer-store` | SQLite、任务、检查点、迁移 | Rust 全平台 | 应用启动 |
| `covio-transfer-fs` | 枚举、路径校验、暂存、提交 | Rust 全平台 | 传输开始 |
| `covio-transfer-keys` | 设备密钥和平台安全存储适配 | 平台适配 | 首次启动 |
| `covio-transfer-runtime` | 编排、重试、事件、前后台策略 | Rust 全平台 | 应用启动 |
| `covio-transfer-ffi` | C ABI 与 JNI 边界；UniFFI 受控试验 | Swift、Compose、Android | 应用启动 |
| `covio-transfer-notify` | 通知和后台生命周期适配 | 平台实现 | 应用启动 |
| `covio-transfer-mdns` | 局域网发现提示 | 后续平台启用 | 后续版本 |

### 1.3 调用路径

```text
SwiftUI 或 Compose UI
  -> covio-transfer-ffi
    -> covio-transfer-runtime
      -> covio-transfer-domain
      -> covio-transfer-store
      -> covio-transfer-keys
      -> covio-transfer-fs
      -> covio-transfer-protocol
        -> covio-transfer-transport
          -> iroh QUIC
            -> direct path
            -> relay path
```

### 1.4 平台桥接

| 平台 | 桥接方式 | 主要理由 |
| --- | --- | --- |
| macOS SwiftUI | C ABI | 生成或维护版本化 C header |
| iOS SwiftUI | C ABI | 与 macOS 共用 Rust API |
| Windows Compose | JNI | 不进入默认 UniFFI JNA 路径 |
| Android Compose | JNI | 与 Windows 共用 Kotlin bridge 合同 |
| CLI 或测试 | Rust API | 直接测试核心 |

C ABI 只暴露不透明句柄、C 结构体和有界事件。
Rust 结构体不直接跨 C ABI。
C ABI 与 JNI 共享同一领域合同、错误码和版本规则。
JNI adapter 调用 Rust core 的公开导出。
UniFFI 只在验证后可生成 Apple 绑定。默认 UniFFI Kotlin 后端不进入首版产品路径。
所有桥接层返回稳定错误码。
Ffi 层不保存业务状态。业务状态放在 Rust 核心。

## 2. 文件位置

路径只写逻辑位置。文档不写本机绝对路径。

| 数据 | 逻辑位置 | 生命周期 |
| --- | --- | --- |
| 任务数据库 | `${APP_DATA}/transfer.db` | 应用安装周期 |
| 设备记录 | `${APP_DATA}/devices/` | 直到用户删除设备 |
| 清单缓存 | `${APP_CACHE}/manifests/` | 任务完成或过期后删除 |
| 暂存根目录 | `${DEST_ROOT}/.covio/staging/{task_id}/` | 任务完成或过期后删除 |
| 临时文件 | `${DEST_ROOT}/.covio/staging/{task_id}/{entry_id}.part` | 校验和提交前 |
| 已完成元数据 | `${APP_DATA}/transfer.db` | 默认 `30 d` |
| 日志 | `${APP_LOG}/transfer.log` | 默认 `7 d` |
| 设备私钥 | 平台安全存储 | 直到用户移除设备 |

暂存目录必须与目标文件位于同一卷。
暂存目录权限为仅当前用户可读写。
暂存文件权限为 `0600`。
暂存目录权限为 `0700`。

## 3. 接口合同

### 3.1 传输

| 项目 | 合同 |
| --- | --- |
| 传输底座 | iroh `1.4.1` 的 QUIC 端点 |
| 应用协议 | `covio-transfer/1` |
| ALPN | `covio/transfer/1` |
| 控制流 | 一条双向控制流 |
| 数据流 | 每个文件一条单向数据流 |
| 消息编码 | 长度前缀 CBOR |
| 消息前缀 | `u32_be` 字节长度 |
| 控制消息上限 | `1 MiB` |
| 数据分块 | `1 MiB` |
| 发送窗口 | `8 MiB` |
| 证据 | `E-06`、`E-07`、`E-08`、`E-09` |

首版一次只传一个文件数据流。
后续版本可以并行多个文件流。
控制流始终独立于文件数据流。
控制流不能携带文件内容。

### 3.2 权限

| 操作 | 所需条件 |
| --- | --- |
| 展示二维码 | 用户主动发起配对 |
| 扫描二维码 | 用户主动打开扫描界面 |
| 发送文件 | 已选择文件并完成接收确认 |
| 接收文件 | 接收方明确接受 |
| 替换文件 | 接收方选择 `replace` |
| 保存设备 | 双端配对确认通过 |
| 后台接收 | 系统能力和首版范围允许 |
| 读取设备信息 | 独立只读能力，不进入文件协议 |

### 3.3 请求信封

实际编码使用 CBOR。下面使用 JSON 展示字段。

```json
{
  "version": 1,
  "kind": "transfer.offer",
  "request_id": "req-0001",
  "transfer_id": "tr-0001",
  "sequence": 1,
  "sent_at_ms": 0,
  "body": {}
}
```

| 字段 | 类型 | 约束 |
| --- | --- | --- |
| `version` | `u16` | 首版固定为 `1` |
| `kind` | `string` | 稳定枚举 |
| `request_id` | `uuid` | 幂等键 |
| `transfer_id` | `uuid` 或空 | 传输任务标识 |
| `sequence` | `u64` | 会话内单调递增 |
| `sent_at_ms` | `i64` | Unix 毫秒 |
| `body` | CBOR map | 由 `kind` 决定 |

### 3.4 响应信封

```json
{
  "version": 1,
  "kind": "transfer.accept",
  "request_id": "req-0001",
  "transfer_id": "tr-0001",
  "sequence": 2,
  "ok": true,
  "data": {
    "accepted_entries": 120,
    "conflict_policy": "keep_both"
  },
  "error_code": null,
  "error_message": null
}
```

失败响应必须使用稳定错误码。
错误消息只用于调试。界面文案由平台本地化。
错误消息不能包含文件内容或配对密钥。

### 3.5 操作列表

| 操作 | 参数 | 返回 | 说明 |
| --- | --- | --- | --- |
| `pairing.begin` | 设备显示名、能力 | 二维码报价 | 生成短期配对 |
| `pairing.complete` | 报价、确认码 | 设备记录 | 完成双端确认 |
| `devices.list` | 无 | 设备列表 | 只读设备资料 |
| `transfer.offer` | 文件项摘要 | 接收确认 | 发送接收请求 |
| `transfer.accept` | 冲突策略 | 接受状态 | 接收方明确接受 |
| `transfer.reject` | 原因码 | 拒绝状态 | 接收方拒绝 |
| `transfer.start` | 任务标识 | 流状态 | 开始数据流 |
| `transfer.pause` | 任务标识 | 暂停状态 | 保存检查点 |
| `transfer.resume` | 任务标识 | 恢复状态 | 从检查点继续 |
| `transfer.cancel` | 任务标识、发起方 | 取消状态 | 停止任务 |
| `transfer.status` | 任务标识 | 快照 | 查询任务 |
| `transfer.history` | 过滤条件 | 记录列表 | 查询历史 |
| `retention.apply` | 策略 | 清理结果 | 应用保留期限 |

### 3.6 事件

| 事件 | 载荷 | 用途 |
| --- | --- | --- |
| `pairing.code_required` | 六位确认码、远端摘要 | 双端核对 |
| `pairing.completed` | 设备记录 | 配对完成 |
| `incoming.offer` | 文件数量、总字节、摘要 | 接收确认 |
| `conflict.required` | 冲突项、策略选项 | 冲突选择 |
| `transfer.progress` | 已确认字节、总字节、速度 | 进度显示 |
| `transfer.state` | 任务状态 | 状态同步 |
| `transfer.paused` | 原因、检查点 | 暂停显示 |
| `transfer.resumed` | 检查点 | 恢复显示 |
| `transfer.completed` | 最终路径、校验摘要 | 完成显示 |
| `transfer.failed` | 错误码、可重试标志 | 失败显示 |

### 3.7 清单

清单使用规范 CBOR 编码。
清单字段排序固定。
清单摘要使用 BLAKE3。
清单摘要进入 `transfer.offer`。

```json
{
  "manifest_version": 1,
  "root_name": "Project",
  "total_entries": 3,
  "total_bytes": 5242880,
  "chunk_size": 1048576,
  "entries": [
    {
      "entry_id": "e-0001",
      "relative_path": "Project/",
      "kind": "directory",
      "size": 0,
      "mode_hint": null,
      "mtime_ms": 0
    },
    {
      "entry_id": "e-0002",
      "relative_path": "Project/readme.txt",
      "kind": "file",
      "size": 1048576,
      "mode_hint": 420,
      "mtime_ms": 0,
      "blake3": "hex",
      "chunks": 1
    },
    {
      "entry_id": "e-0003",
      "relative_path": "Project/empty",
      "kind": "directory",
      "size": 0,
      "mode_hint": 493,
      "mtime_ms": 0
    }
  ]
}
```

清单限制如下。

- 路径使用 UTF-8。
- 路径使用 `/` 作为协议分隔符。
- 路径必须为相对路径。
- 路径不能包含 `.` 或 `..` 段。
- 路径不能包含 NUL。
- 首版最大深度为 `128`。
- 首版最大文件项为 `10,000`。
- 首版最大单文件为 `10 GiB`。
- 首版最大总字节为 `50 GiB`。
- 特殊文件拒绝。
- 符号链接首版拒绝。
- 硬链接首版按独立文件处理。
- 稀疏文件首版按普通逻辑字节处理。

### 3.8 数据帧

每个文件流以一个 `FileStreamHeader` 开始。

```text
kind=1 u16
version=1 u16
entry_id=16 bytes
total_size=u64
blake3=32 bytes
```

每个数据帧格式如下。

```text
offset=u64
length=u32
flags=u16
chunk_blake3=32 bytes
payload=length bytes
```

接收方只接受以下情况。

- `offset` 等于当前持久确认字节。
- `length` 等于 `chunk_size`，最后一帧除外。
- `length` 不超过 `1 MiB`。
- `chunk_blake3` 与载荷一致。
- `offset + length` 不超过文件总大小。

### 3.9 持久化记录

| 表 | 关键字段 | 用途 |
| --- | --- | --- |
| `devices` | `device_id`、`endpoint_id`、`public_key`、`last_seen`、`trust_state` | 设备身份 |
| `pairing_offers` | `offer_id`、`expires_at`、`state` | 短期配对 |
| `transfer_jobs` | `transfer_id`、`peer_id`、`direction`、`state`、`manifest_hash`、`expires_at` | 任务 |
| `transfer_entries` | `entry_id`、`relative_path`、`kind`、`size`、`chunk_count`、`durable_bytes`、`status` | 文件项 |
| `transfer_chunks` | `entry_id`、`chunk_index`、`blake3`、`durable` | 分块状态 |
| `transfer_events` | `event_id`、`task_id`、`event_type`、`created_at` | 审计和恢复 |
| `retention_rules` | `resource_kind`、`ttl_seconds` | 保留策略 |

数据库使用 SQLite。
数据库使用 WAL 模式。
普通检查点使用事务。
最终提交前执行 `sync_data` 或平台同步等价操作。
数据库迁移必须可回滚。
数据库不保存设备私钥。
数据库不保存配对一次性密钥。

## 4. 状态机

### 4.1 任务状态

```text
idle
  -> pairing
  -> ready
  -> offer_waiting
  -> awaiting_acceptance
  -> preparing
  -> transferring
  -> verifying
  -> committing
  -> completed

transferring
  -> paused
  -> background_deferred
  -> waiting_network
  -> cancelled
  -> failed

paused
  -> transferring
  -> cancelled
  -> failed

background_deferred
  -> transferring
  -> waiting_network
  -> cancelled

waiting_network
  -> transferring
  -> cancelled
  -> failed

verifying
  -> transferring
  -> failed

committing
  -> completed
  -> failed
```

### 4.2 文件项状态

```text
planned
  -> offered
  -> accepted
  -> skipped
  -> conflict_waiting
  -> rejected

accepted
  -> receiving
  -> received
  -> verified
  -> committed
  -> failed
```

### 4.3 恢复规则

恢复前必须完成以下检查。

1. 任务记录存在。
2. 对端公钥未变化。
3. 清单摘要一致。
4. 暂存文件存在。
5. 检查点不超过文件大小。
6. 已确认分块哈希仍匹配。
7. 目标卷仍可写。
8. 用户没有取消任务。

任一检查失败时，核心不自动续传。
核心返回具体错误码。
用户可以选择重新开始或删除暂存数据。

## 5. 文件语义

### 5.1 大文件

- 偏移使用 `u64`。
- 文件大小使用 `u64`。
- 不把整个文件读入内存。
- 不把整个文件编码成单个消息。
- 发送端使用稳定文件句柄。
- 发送端在读取前检查文件大小和修改时间。
- 文件变化时返回 `source_changed`。
- 接收端使用追加写和固定检查点。
- 分块窗口为 `8 MiB`。
- 每 `16 MiB` 执行一次持久检查点。
- 完成前执行最终同步和校验。

### 5.2 文件夹

- 目录按清单顺序处理。
- 空目录保留。
- 目录项不发送内容。
- 新目标根目录可以整体暂存后重命名。
- 合并到已有目录时按文件项提交。
- 目录传输不承诺整个目录树的单事务原子性。
- 失败时保留已完成文件。
- 用户取消时不回滚已完成文件。
- 失败项和已完成项必须明确显示。

### 5.3 符号链接

- 枚举时使用 `follow_links(false)`。
- 符号链接记录为独立文件项。
- 首版默认拒绝符号链接。
- 首版不读取链接目标内容。
- 首版不创建绝对路径链接。
- 首版不创建指向接收根外的链接。
- 后续版本支持时必须执行目标规范化检查。
- 后续版本默认使用 `skip`，由用户显式选择保留。

### 5.4 权限

- 协议记录可选的 `mode_hint`。
- POSIX 平台保留可执行位。
- POSIX 平台保留只读属性。
- 不复制 ACL。
- 不复制扩展属性。
- 不复制所有者。
- 不复制组。
- Windows 使用只读属性。
- Windows 不伪造 POSIX 权限。
- 文件默认权限为当前用户可读写。
- 目录默认权限为当前用户可读写执行。
- 权限不足时返回 `permission_denied`。

### 5.5 文件名和路径

- 协议路径使用 NFC。
- 路径分隔符固定为 `/`。
- 接收端转换成本地路径。
- 接收端拒绝绝对路径。
- 接收端拒绝盘符路径。
- 接收端拒绝 `..` 段。
- 接收端拒绝 NUL 和控制字符。
- 接收端拒绝 Windows 保留名。
- 接收端拒绝 Windows 尾随点或空格。
- 接收端拒绝超长路径。
- 接收端执行大小写碰撞检测。
- 大小写碰撞返回 `path_collision`。
- 不自动改写发送方文件名。
- `keep_both` 只在目标端生成新名称。

### 5.6 冲突和覆盖

| 策略 | 行为 | 默认 |
| --- | --- | --- |
| `keep_both` | 保留旧文件，新文件加序号 | 是 |
| `replace` | 校验后替换目标文件 | 否 |
| `skip` | 不接收冲突项 | 否 |
| `ask` | 每项询问用户 | UI 可用 |

冲突检测发生在接收确认阶段。
接收方可以批量应用同一策略。
替换前必须完成暂存、同步、分块校验和文件校验。
替换失败时原文件保持可见。
Windows 替换使用平台原子替换适配器。
跨卷目标返回 `atomic_commit_unsupported`。
目录合并按文件项处理冲突。

### 5.7 临时文件

- 暂存根目录位于目标卷。
- 每个任务使用独立子目录。
- 每个文件使用独立 `.part` 文件。
- 暂存文件使用 `create_new`。
- 暂存文件不跟随符号链接。
- 暂存文件名不直接使用远端文件名。
- 暂存文件校验通过后重命名。
- 重命名后执行父目录同步。
- 失败时暂存文件按保留策略处理。
- 临时文件不能出现在最终目录树中。

### 5.8 校验

- 每个分块使用 BLAKE3。
- 每个文件使用 BLAKE3。
- 清单使用 BLAKE3。
- 分块校验失败只重试对应分块。
- 文件校验失败时重新读取已落盘范围。
- 文件校验连续失败三次后终止任务。
- SHA-256 作为可选 `compat_sha256` 字段。
- SHA-256 不参与首版接收授权。
- 传输层完整性不能替代应用校验。
- 校验结果写入持久记录。

### 5.9 重试

- QUIC 负责包级重传。
- 应用不重复发送已确认分块。
- 普通断线使用 `1 s`、`2 s`、`4 s`、`8 s`、`16 s`、`30 s` 退避。
- 退避加入随机抖动。
- 连续五次失败后进入 `waiting_network`。
- 回到前台立即执行一次连接验证。
- 身份变化不重试。
- 配对确认失败不重试。
- 校验失败最多重试三次。
- 用户取消不自动重试。
- 磁盘空间不足不自动重试。
- 磁盘空间恢复后由用户恢复任务。

### 5.10 保留期限

| 对象 | 默认期限 | 清理行为 |
| --- | --- | --- |
| 配对二维码 | `120 s` | 过期后拒绝完成配对 |
| 待接收请求 | `10 min` | 过期后发送方显示过期 |
| 暂停任务暂存 | `7 d` | 过期后清理暂存 |
| 取消任务暂存 | `24 h` | 过期后清理暂存 |
| 离线队列 | `7 d` | 过期后取消任务 |
| 已完成任务元数据 | `30 d` | 清理元数据，不删除最终文件 |
| 传输日志 | `7 d` | 清理日志 |
| 已接收最终文件 | 不自动删除 | 由用户管理 |

保留期限必须可由用户查看。
清理暂存前必须检查任务状态。
清理不能删除最终文件。
清理失败必须记录错误码。

### 5.11 取消

- 发送方取消发送 `transfer.cancel`。
- 接收方取消发送 `transfer.cancel`。
- 取消是尽力通知。断线时记录本地取消。
- 发送方停止读取源文件。
- 接收方停止写入暂存文件。
- 接收方保留暂存文件 `24 h`。
- 用户可选择立即删除暂存文件。
- 已完成文件不回滚。
- 取消状态不能被自动重试覆盖。

### 5.12 离线队列

- 只有已配对设备可以进入离线队列。
- 离线队列只保存任务元数据。
- 离线队列不保存文件内容副本。
- 任务上线后发送 `transfer.offer`。
- 接收方仍需明确接受。
- 发送前重新检查源文件。
- 源文件变化时返回 `source_changed`。
- 接收方拒绝时任务结束。
- 请求过期时任务结束。
- 离线队列不保证在系统后台执行。

### 5.13 移动端后台降级

#### iOS

1. 接收 `background` 生命周期事件。
2. 停止发起新分块。
3. 等待已写入分块完成本地同步。
4. 更新持久检查点。
5. 把任务标记为 `background_deferred`。
6. 不删除暂存文件。
7. 不发送自动接受。
8. 回到 `active` 后先验活。
9. 对端身份和清单一致时恢复。
10. 恢复失败时进入 `waiting_network`。

iOS 后台行为明确如下。

- 不承诺持续接收。
- 不承诺在后台完成大文件。
- 不承诺后台重连成功。
- 可以使用系统通知提示待接收。
- 系统通知不能替代接收确认。
- 用户重新打开应用后才能接受新任务。

#### Android 后续

- 后续使用前台服务。
- 前台服务显示常驻通知。
- 前台服务只用于用户明确开始的任务。
- 后台策略必须单独验收。

## 6. 安全设计

### 6.1 威胁模型

| 威胁 | 控制 |
| --- | --- |
| 二维码被拍照 | 一次性密钥、短期报价、双端确认 |
| 二维码被替换 | 公钥确认、确认码、用户核对 |
| 局域网伪造发现 | mDNS 不作为身份源 |
| Relay 运营者监听 | QUIC 端到端加密 |
| 中间人替换设备 | 公钥固定、签名和身份变化阻断 |
| 重放旧任务 | 随机任务标识、会话随机数、单调序号 |
| 路径穿越 | 接收根目录约束和路径校验 |
| 符号链接越界 | 首版拒绝符号链接 |
| 恶意大清单 | 字段上限、条目上限、分块解析 |
| 磁盘写满 | 预检、暂停、错误码 |
| 半成品可见 | 暂存文件和原子提交 |
| 降级攻击 | 固定协议版本和安全能力 |
| 0-RTT 重放 | 不接受 0-RTT 变更操作 |

### 6.2 二维码报价

二维码包含以下字段。

| 字段 | 用途 |
| --- | --- |
| `protocol_version` | 选择兼容协议 |
| `offer_id` | 标识一次配对 |
| `sender_device_id` | 标识发送方设备 |
| `sender_endpoint_id` | 提供 iroh 端点 |
| `sender_public_key` | 固定应用层身份 |
| `relay_hint` | 提供可选 relay 地址 |
| `pairing_key_commitment` | 验证一次性配对密钥 |
| `expires_at` | 限制报价有效期 |
| `capabilities` | 声明协议能力 |

一次性配对密钥可以放在二维码中。
一次性配对密钥不写入普通日志。
发送方和接收方使用一次性配对密钥完成挑战响应。
双方从握手 transcript 派生六位配对确认码。
双方用户必须核对同一确认码。
确认码不一致时终止配对。
配对完成后销毁一次性配对密钥。

### 6.3 设备身份

- 设备生成长期签名密钥。
- 设备保存长期公钥和私钥引用。
- 私钥优先保存在平台安全存储。
- 私钥不跨 FFI 返回。
- 私钥不写入 SQLite。
- 设备记录保存公钥和端点标识。
- 端点标识变化时要求重新配对。
- 设备公钥变化时要求重新配对。
- 自动连接只允许已固定设备。
- 任务恢复前重新检查身份。
- 用户删除设备时撤销本地信任。

### 6.4 统一安全存储合同

| 能力 | 合同 |
| --- | --- |
| `generate_device_key` | 生成长期设备密钥 |
| `public_key` | 返回公钥 |
| `sign_transcript` | 对规范 transcript 签名 |
| `delete_device_key` | 删除本地私钥 |
| `is_hardware_backed` | 返回硬件后备状态 |
| `key_handle` | 返回平台不透明句柄 |

平台适配建议如下。

| 平台 | 存储 | 备注 |
| --- | --- | --- |
| macOS | Keychain | 可评估 Secure Enclave |
| iOS | Keychain | 可评估 Secure Enclave |
| Windows | Credential Manager 或 CNG | Credential Manager 需要密钥包装方案 |
| Android 后续 | Keystore | 后续实现 |

安全存储合同要求如下。

- Rust 核心只持有密钥句柄。
- 签名通过平台适配器执行。
- 私钥不进入日志。
- 私钥不进入备份明文。
- 私钥不进入传输信封。
- 删除设备时删除本地密钥记录。
- 硬件后备不可用时明确返回能力标志。
- 不同平台的密钥类型必须统一。
- 优先选择可跨平台验证的签名算法。
- 具体算法和硬件能力需要单独安全评审。

### 6.5 协议安全

- 只接受 `covio-transfer/1`。
- 版本不匹配返回 `protocol_version_unsupported`。
- 不使用 0-RTT 发送接受、清单变更或取消。
- 控制流必须使用随机请求标识。
- 会话必须使用随机 nonce。
- 序号必须单调递增。
- 重放消息不改变状态。
- 清单必须通过摘要校验。
- 数据帧必须校验长度和偏移。
- 接收方拒绝未知 `kind`。
- 接收方拒绝未知必选字段。
- Relay 只看到加密的 QUIC 流量。
- 日志只记录任务标识和错误码。
- 日志不记录完整文件名列表。

## 7. 可靠性与资源策略

### 7.1 发送资源

- 单个发送缓冲区上限为 `8 MiB`。
- 单个分块上限为 `1 MiB`。
- 发送端只读取窗口内数据。
- 接收确认推进后才读取更多数据。
- 网络断开时停止读取。
- 文件句柄在任务暂停或结束时关闭。
- 源文件变化时终止任务。

### 7.2 接收资源

- 单个接收缓冲区上限为 `8 MiB`。
- 暂存文件按顺序写入。
- 每 `16 MiB` 执行一次同步和检查点。
- 检查点写入使用事务。
- 数据库写入失败时停止接收。
- 磁盘空间不足时暂停。
- 校验失败时不提交最终文件。

### 7.3 重连策略

- 连接断开后保留任务记录。
- 不保留旧响应等待者。
- 不盲重放未确认变更。
- 恢复时先请求对端检查点。
- 发送方从接收方确认字节继续。
- 接收方拒绝跳过分块。
- 每次恢复生成新的会话 nonce。
- 重连成功后更新 `last_seen`。

## 8. 错误码

| 错误码 | 触发条件 | 可重试 | 人工处理 |
| --- | --- | --- | --- |
| `pairing_offer_expired` | 二维码报价过期 | 否 | 重新生成二维码 |
| `pairing_code_mismatch` | 双端确认码不同 | 否 | 重新配对 |
| `peer_identity_changed` | 设备公钥或端点变化 | 否 | 用户重新确认 |
| `protocol_version_unsupported` | 协议版本不兼容 | 否 | 升级应用 |
| `transport_offline` | 当前无可用路径 | 是 | 等待网络或检查 relay |
| `relay_unavailable` | relay 无法连接 | 是 | 稍后重试或切换网络 |
| `transfer_offer_expired` | 接收请求过期 | 否 | 重新发起传输 |
| `offer_rejected` | 接收方拒绝 | 否 | 重新沟通后发起 |
| `manifest_invalid` | 清单字段或排序错误 | 否 | 重新生成清单 |
| `unsupported_entry_type` | 特殊文件或未知类型 | 否 | 排除该文件项 |
| `symlink_refused` | 首版遇到符号链接 | 否 | 跳过符号链接 |
| `path_invalid` | 绝对路径、穿越或非法字符 | 否 | 修改源文件名 |
| `path_collision` | 大小写或规范化后冲突 | 否 | 修改源路径或跳过 |
| `conflict_unresolved` | 用户未选择冲突策略 | 是 | 选择策略 |
| `insufficient_space` | 目标卷空间不足 | 是 | 释放空间后恢复 |
| `permission_denied` | 无目标读写权限 | 是 | 修改权限后恢复 |
| `source_changed` | 源文件在发送中变化 | 是 | 重新生成清单 |
| `chunk_hash_mismatch` | 分块校验失败 | 是 | 重试对应分块 |
| `file_hash_mismatch` | 文件最终校验失败 | 是 | 重传文件 |
| `resume_checkpoint_invalid` | 检查点损坏或越界 | 否 | 删除暂存并重启任务 |
| `atomic_commit_unsupported` | 跨卷或平台不支持替换 | 否 | 更改目标目录 |
| `background_suspended` | 系统暂停应用 | 是 | 回到前台恢复 |
| `storage_io_error` | 本地磁盘读写错误 | 是 | 检查存储后恢复 |
| `cancelled_by_sender` | 发送方取消 | 否 | 由用户重新发起 |
| `cancelled_by_receiver` | 接收方取消 | 否 | 由用户重新发起 |
| `internal_error` | 未分类内部错误 | 视情况 | 查看诊断日志 |

错误码必须稳定。
错误码不能复用为不同概念。
错误码进入持久记录和 UI 映射层。
错误消息不能作为程序分支条件。

## 9. 验收标准

### 9.1 首版必须通过

| 编号 | 场景 | 通过条件 |
| --- | --- | --- |
| A01 | macOS 到 Windows 单文件 | 字节一致，校验通过 |
| A02 | Windows 到 macOS 目录 | 空目录和普通文件保留 |
| A03 | macOS 到 iOS 前台传输 | 接收确认可见 |
| A04 | iOS 进入后台再恢复 | 从检查点继续 |
| A05 | 直连阻断后 relay | 任务最终完成 |
| A06 | relay 断开再恢复 | 不从头重传 |
| A07 | 同名文件 `keep_both` | 旧文件不变化 |
| A08 | 同名文件 `replace` | 校验后原子替换 |
| A09 | `skip` 冲突项 | 任务继续处理其他项 |
| A10 | 符号链接 | 返回 `symlink_refused` |
| A11 | 路径穿越 | 被拒绝且无外部写入 |
| A12 | 磁盘空间不足 | 暂停且可恢复 |
| A13 | 分块损坏 | 重试后恢复或失败 |
| A14 | 应用崩溃 | 重启后可识别任务 |
| A15 | 用户取消 | 不出现未完成最终文件 |
| A16 | 配对二维码过期 | 配对被拒绝 |
| A17 | 设备身份变化 | 自动连接被拒绝 |
| A18 | 大文件 `10 GiB` | 不出现内存无界增长 |
| A19 | 目录 `10,000` 文件项 | 清单和冲突检测完成 |
| A20 | 日志检查 | 无文件内容和配对密钥 |

### 9.2 后续范围

- Android 前台服务后台传输。
- 符号链接保留。
- xattr、ACL 和完整权限复制。
- 实时目录同步。
- 内容定义分块和去重。
- 多文件并行流。
- 手机后台下载代理。
- 自建 relay 集群。
- SHA-256 合规模式。

## 10. 实施计划

### 阶段一：协议验证

1. 验证 iroh 在 macOS 构建。
2. 验证 iroh 在 Windows 构建。
3. 验证 iroh 在 iOS 构建。
4. 验证公钥寻址和 relay 回退。
5. 验证 `1 MiB` 分块和 `8 MiB` 窗口。
6. 验证 `10 GiB` 单文件。
7. 记录证据和失败项。

### 阶段二：Rust 核心

1. 实现 `covio-transfer-domain`。
2. 实现 `covio-transfer-protocol`。
3. 实现 `covio-transfer-store`。
4. 实现 `covio-transfer-fs`。
5. 实现 `covio-transfer-transport`。
6. 实现错误码和事件。
7. 为状态机编写单元测试。

### 阶段三：文件语义

1. 实现清单生成。
2. 实现路径校验。
3. 实现冲突策略。
4. 实现暂存和原子提交。
5. 实现检查点。
6. 实现取消和保留策略。
7. 实现目录合并行为。

### 阶段四：平台桥接

1. 生成 C header 与 JNI 声明。
2. 增加 binding 漂移检查。
3. UniFFI 仅建立隔离试验。
4. 接入 SwiftUI 文件选择和分享入口。
5. 接入 Compose 文件选择和分享入口。
6. 接入系统通知。
7. 接入 iOS 生命周期事件。

### 阶段五：验证

1. 执行 [validation/README.md](validation/README.md) 的矩阵。
2. 执行真实设备配对。
3. 执行直连和 relay 断线。
4. 执行前后台恢复。
5. 执行冲突和取消。
6. 执行日志脱敏检查。
7. 记录实际结果。

## 11. 回滚条件

出现以下情况时暂停首版实现。

- iroh 无法在 iOS 构建。
- iroh 无法在 iOS 前台稳定连接。
- relay 回退无法达到可接受延迟。
- 原子提交在 Windows 目标文件系统失败。
- 大文件传输出现无界内存增长。
- 路径校验无法阻断越界。
- 设备身份变化不能被阻断。
- 日志泄露文件名或配对密钥。
- 接收方确认可以被绕过。

回滚路径如下。

1. 保留 `covio-transfer-domain`、协议和文件系统模块。
2. 替换 `covio-transfer-transport`。
3. 使用 `quinn` 和自有 relay 作为备选。
4. 暂不启用 `replace` 策略。
5. 暂不启用实时目录同步。
6. 暂不声称 iOS 后台持续接收。

## 12. 产品化条件

- 三端构建和真实设备验收通过。
- 公共 relay 隐私说明完成。
- 自建 relay 能力完成或明确接受公共 relay。
- 设备密钥存储通过安全评审。
- 路径和符号链接测试通过。
- 原子提交测试通过。
- 大文件和目录压力测试通过。
- 背景恢复测试通过。
- 日志脱敏测试通过。
- 错误码和 UI 文案完成。
- 保留策略可配置且可审计。
- 失败恢复不会覆盖用户最终文件。

## 13. 关联文档

- [主题索引](README.md)
- [问题边界](context.md)
- [调研分析](investigation.md)
- [结论](conclusion.md)
- [证据](evidence.md)
- [验证目录](validation/README.md)
- [传输案例](validation/case-transfer-metadata.md)
- [移动端案例](validation/case-mobile-lifecycle.md)
