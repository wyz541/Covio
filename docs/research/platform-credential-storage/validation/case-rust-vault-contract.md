# Rust vault 合同验证记录

本案例阻塞。当前没有统一 credential facade、记录仓库和测试入口。

## 文档状态

| 项目 | 内容 |
| --- | --- |
| 状态 | 阻塞 |
| 执行人 | 待填写 |
| 复核人 | 待填写 |
| 环境 | Rust 测试环境 |
| 版本 | Rust 1.85.0 或实现时的固定版本 |
| 主方案 | [主题索引](../README.md) |
| 证据附录 | [证据附录](../evidence.md) |
| 目录说明 | [验证目录](README.md) |

## 1. 验证目标

1. 验证根密钥不跨 FFI 返回。
2. 验证 AEAD 记录往返。
3. 验证 AAD 绑定和设备绑定。
4. 验证稳定错误码。
5. 验证轮换和迁移回滚。
6. 验证秘密零化。
7. 验证日志脱敏。
8. 验证记录损坏和根密钥缺失。

## 2. 预检记录

| 项目 | 值 | 状态 |
| --- | --- | --- |
| Rust 版本 | 待填写 | 尚未执行 |
| Cargo 版本 | 待填写 | 尚未执行 |
| 应用 commit | 待填写 | 尚未执行 |
| 测试后端 | 待实现 | 尚未执行 |
| FFI 测试入口 | 待实现 | 尚未执行 |
| 日志捕获入口 | 待实现 | 尚未执行 |
| 内存检查工具 | 待填写 | 尚未执行 |

## 3. 测试前采集

rustc --version

cargo --version

git rev-parse HEAD

cargo test --workspace --no-fail-fast

记录字段：

RustVersion:

CargoVersion:

Commit:

TestBackend:

FFIABIVersion:

LogSink:

## 4. 验证步骤

### V19：根密钥不跨 FFI 返回

前置：C ABI 或 UniFFI 测试入口可用。

请求：调用全部公开凭据操作，检查返回类型和快照字段。

记录：

Start time:

End time:

Public read method:

Root key field:

Snapshot secret field:

Response:

Error code:

Result: PENDING

通过条件：公开接口没有通用 secret read，返回值和 snapshot 不含根密钥。

### V20：AEAD、AAD 和设备绑定

前置：实现合成 KV 后端和记录仓库。

请求：写入测试记录，分别篡改密文、记录 ID、用途和设备 ID。

记录：

Start time:

End time:

Valid read:

Ciphertext tamper:

Record ID tamper:

Device ID tamper:

Error code:

Result: PENDING

通过条件：正常读取成功，所有篡改返回 credential_integrity_failed。

### V21：稳定错误码映射

前置：测试后端可以注入平台错误。

请求：注入 item-not-found、locked、auth-required、user-canceled、key-invalidated、capacity 和 internal。

记录：

Start time:

End time:

Item missing:

Locked:

Auth required:

User canceled:

Key invalidated:

Capacity:

Internal:

Result: PENDING

通过条件：每个条件得到唯一稳定错误码和正确 user_action。

### V22：轮换和迁移回滚

前置：测试仓库有多条记录和可注入故障。

请求：在写入新快照和切换指针之间注入失败。

记录：

Start time:

End time:

Failure point:

Old vault readable:

New vault readable:

Rollback result:

Error code:

Result: PENDING

通过条件：切换前失败时旧仓库完整可读，切换后失败时保留回滚标记。

### V23：秘密零化和日志脱敏

前置：日志捕获和内存检查工具可用。

请求：写入合成秘密，触发成功、失败、超时和取消路径。

记录：

Start time:

End time:

Secret in logs:

Secret in snapshot:

Secret in error:

Buffer after drop:

Response:

Result: PENDING

通过条件：日志、snapshot、错误和释放后缓冲区都没有秘密字节。

### V24：记录损坏和根密钥缺失

前置：测试仓库可用，可以损坏记录头和删除测试根密钥。

请求：分别损坏记录头、破坏 AEAD 标签和删除根密钥。

记录：

Start time:

End time:

Header corruption:

Tag corruption:

Missing root key:

Recovery state:

Error code:

Result: PENDING

通过条件：分别返回 credential_record_corrupt、credential_integrity_failed 和 credential_recovery_required。

## 5. 结果汇总

当前无实际结果。等待 facade、记录仓库和测试后端。

## 6. 清理记录

1. 删除测试 vault 目录。
2. 删除测试根密钥句柄。
3. 删除测试日志和摘要。
4. 恢复测试后端。
5. 确认没有合成秘密残留。
6. 记录清理结果。

清理结果：PENDING

## 7. 更新规则

执行测试后填写实际结果。
执行测试后更新 [验证目录](README.md)。
执行测试后更新 [证据附录](../evidence.md)。
结论变化时更新 [结论](../conclusion.md)。
接口变化时更新 [推荐方案](../solution.md)。

## 8. 关联文档

- [主题索引](../README.md)
- [证据附录](../evidence.md)
- [验证目录](README.md)
- [推荐方案](../solution.md)
