# Covio 目录传输

- 状态：core implemented；传输 host 待接入
- 日期：2026-11-11
- Issue：#739
- 依据：[Rust 文件传输](../research/rust-file-transfer/solution.md)
- 前置实现：[Covio 单文件传输](single-file-transfer.md)

## 1. 结论

Rust core 已提供目录快照、冲突计划、目录接收、检查点恢复和保留清理。
目录清单保留普通文件和空目录。
目录清单只保留修改时间、只读属性和可执行位。
首版拒绝符号链接。
接收端只从已校验检查点续传。
保留清理不删除最终文件。

```mermaid
flowchart LR
  S["Source directory"] --> M["DirectoryManifest"]
  M --> P["Conflict plan"]
  P --> F["Per-file chunks"]
  F --> C["Verified checkpoints"]
  C --> T["Atomic target commit"]
  T --> R["Retention cleanup"]
```

## 2. 清单合同

`DirectoryManifest` 使用 CBOR 编码。
清单摘要使用 BLAKE3。
清单最多包含 `10,000` 个目录项。
单个文件最多 `10 GiB`。
单个目录传输最多 `100 GiB`。

| 字段 | 内容 |
| --- | --- |
| `root_name` | 根目录名 |
| `root_metadata` | 根目录元数据 |
| `entries` | 按相对路径排序的目录项 |
| `total_bytes` | 文件字节总数 |
| `file_count` | 文件项数量 |
| `directory_count` | 非根目录项数量 |
| `created_at_ms` | 创建时间 |
| `expires_at_ms` | 报价过期时间 |

每个目录项包含以下字段。

- `relative_path`：使用 `/` 分隔的 NFC 相对路径。
- `kind`：`file`、`directory` 或 `symlink`。
- `size`：普通文件字节数。目录项为 `0`。
- `blake3`：普通文件摘要。目录项没有此字段。
- `metadata`：修改时间、只读属性和可执行位。

根目录由 `root_name` 表示。
空目录作为独立目录项写入清单。
父目录项必须位于子项之前。
大小写碰撞返回 `path_collision`。

## 3. 路径规则

发送端和接收端使用同一路径规则。

1. 路径必须是 NFC。
2. 路径必须使用 `/` 分隔。
3. 路径不能是绝对路径。
4. 路径不能包含 `..` 段。
5. 路径不能包含 NUL 或控制字符。
6. 路径不能包含 Windows 保留名。
7. 路径段不能以点或空格结尾。
8. 路径不能包含 Windows 非法字符。
9. 单个路径段最多 `255` 字节。
10. 单个相对路径最多 `4,096` 字节。

接收端执行 Unicode 大小写碰撞检查。
接收端不自动改写发送方路径。
`keep_both` 只在目标端生成新名称。

## 4. 符号链接

目录扫描使用不跟随链接的元数据。
清单校验返回 `symlink_refused`。
接收端遇到目标符号链接时也返回 `symlink_refused`。
首版不读取链接目标。
首版不创建链接。

## 5. 冲突策略

| 策略 | 文件已存在 | 目录已存在 |
| --- | --- | --- |
| `keep_both` | 新文件使用 `name (1).ext` | 合并目录 |
| `replace` | 校验后替换文件 | 合并目录 |
| `skip` | 跳过新文件 | 合并目录 |

冲突检测发生在接收确认阶段。
计划写入 `directory_jobs.plan_json`。
`keep_both` 检查现有路径和计划路径。
文件与目录类型冲突返回 `path_collision`。
替换操作使用平台原子替换能力。
替换失败时旧文件保持可见。

## 6. 续传合同

每个普通文件使用独立的暂存文件。
暂存文件名使用源路径的 BLAKE3 摘要。
暂存目录与最终目标位于同一卷。

```text
<destination>/
├── .covio/staging/<transfer-id>/files/<path-hash>.part
└── <root-name>/<relative-path>
```

接收端执行以下顺序。

1. 校验清单和分块范围。
2. 读取并校验每个持久分块。
3. 只保留连续的已校验前缀。
4. 截断检查点之后的未校验字节。
5. 从已校验偏移继续接收。
6. 校验完整文件摘要。
7. 提交文件并更新持久计划。

检查点损坏、分块缺失或摘要不匹配时返回 `resume_checkpoint_invalid`。
应用重启后，core 从 SQLite 读取目录任务和分块检查点。

## 7. 提交顺序

目录传输不承诺整棵目录树的单事务原子性。
每个文件独立校验和提交。
已完成文件在后续失败时保留。
用户取消时不回滚已完成文件。
空目录在最终完成阶段创建。

## 8. 保留期限

| 对象 | 默认期限 | 清理行为 |
| --- | --- | --- |
| 暂停任务暂存 | `7 d` | 删除暂存和检查点 |
| 取消任务暂存 | `24 h` | 删除暂存和检查点 |
| 失败任务暂存 | `7 d` | 删除暂存和检查点 |
| 终态任务元数据 | `30 d` | 删除任务、分块和事件 |
| 已完成最终文件 | 不自动删除 | 由用户管理 |

清理前检查任务状态。
清理只处理暂存目录和数据库记录。
清理不删除最终文件。
清理失败写入结果，不停止其他任务。
策略可由用户配置。

## 9. 代码入口

| 模块 | 责任 |
| --- | --- |
| `file_transfer/directory/manifest.rs` | 目录清单、元数据、扫描和摘要 |
| `file_transfer/directory/path.rs` | NFC、Windows 安全规则和碰撞键 |
| `file_transfer/directory/conflict.rs` | 冲突策略和最终路径计划 |
| `file_transfer/directory/recovery.rs` | 已验证范围和未校验尾部处理 |
| `file_transfer/directory/retention.rs` | 保留期限规则 |
| `file_transfer/directory/receiver.rs` | 接收、提交、完成和清理 |
| `file_transfer/store.rs` | 目录任务、分块、计划和检查点 |

## 10. 验证

以下测试通过。

- 嵌套目录、普通文件和空目录。
- 可执行位、只读属性和修改时间进入清单。
- 符号链接拒绝。
- Windows 保留名和尾随字符拒绝。
- `keep_both`、`replace` 和 `skip` 计划。
- 损坏清单和大小写碰撞拒绝。
- 中断后从已校验分块恢复。
- 取消暂存和检查点清理。
- 完成元数据清理不删除最终文件。

命令如下。

```text
cargo test -p covio-core directory --lib
cargo test -p covio-core --test directory_transfer
cargo test -p covio-core --test file_transfer
cargo clippy -p covio-core --all-targets -- -D warnings
cargo clippy -p covio-platform --all-targets -- -D warnings
```

## 11. 未决事项

- SwiftUI 和 Compose host 尚未接入目录选择、冲突确认和进度界面。
- iroh 控制流尚未增加目录级编排消息。
- 当前实现使用现有单文件数据帧逐项传输目录内容。
- 三平台真机目录传输由 #743 验收。
