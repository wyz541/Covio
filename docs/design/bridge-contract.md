# Covio bridge 合同

- 状态：accepted
- 日期：2026-11-10
- 决策：[ADR-0035](../adr/adr-0035-cross-platform-product-scope.md)

## 1. 结论

C ABI 和 JNI 声明来自同一份合同。
合同文件是 `rust/crates/covio-ffi/bridge/bridge_contract.json`。
生成器是 `scripts/generate-bridge-contracts.py`。

生成物如下。

| 文件 | 用途 |
| --- | --- |
| `rust/crates/covio-ffi/include/covio_bridge.generated.h` | C ABI 类型、状态码和函数声明 |
| `rust/crates/covio-ffi/include/covio_bridge_jni.generated.h` | JNI 入口声明 |

不得手改生成物。

## 2. 合同内容

合同包含以下内容。

- ABI 版本。
- bridge protocol 版本。
- 默认控制消息上限。
- 内容传输模式。
- 状态码。
- session lifecycle。
- cancellation reason。
- C 函数签名。
- JNI 函数签名。

控制消息只传 request、response、event、snapshot、cancel、shutdown 和小型元数据。
文件内容只能通过 opaque handle 或 stream 传输。

## 3. 平台映射

| 平台 | 入口 | 说明 |
| --- | --- | --- |
| macOS | C ABI | Swift 导入 `covio_ffi.h` |
| iOS | C ABI | 与 macOS 共用同一头文件 |
| Windows | JNI | Compose host 通过 JNI 调用 |
| Android | JNI | 后续平台复用同一 JNI 合同 |

JNI 符号使用 `covio_jni_` 前缀。
Kotlin 或 JVM host 通过 `RegisterNatives` 绑定这些入口。

## 4. 版本和错误

`COVIO_FFI_ABI_VERSION` 标识二进制 ABI。
`COVIO_BRIDGE_PROTOCOL_VERSION` 标识控制协议。
状态码在 C、JNI 和 Rust 中使用同一数值。

版本不匹配时返回 `COVIO_STATUS_PROTOCOL_VERSION`。
状态陈旧时返回 `COVIO_STATUS_STALE_GENERATION`。
操作取消时返回 `COVIO_STATUS_CANCELLED`。
session 关闭时返回 `COVIO_STATUS_SHUTTING_DOWN`。
panic 在 FFI 边界转换为 `COVIO_STATUS_PANIC` 或 `COVIO_STATUS_INTERNAL`。

## 5. 生成和检查

写生成物：

```sh
python3 -I scripts/generate-bridge-contracts.py
```

检查漂移：

```sh
python3 -I scripts/generate-bridge-contracts.py --check
```

CI 运行漂移检查。
Rust 测试检查合同中的 ABI 版本、protocol 版本、状态码和 lifecycle 与 Rust 定义一致。
生成器检查 Rust bridge 函数表面没有遗漏或多余入口。

## 6. 约束

1. 不手改生成头文件。
2. 文件内容不进入普通 JSON control envelope。
3. JNI 不保存跨线程 `JNIEnv`。
4. Windows 产品路径不引入 JNA。
5. 新增 bridge 函数时先修改合同。
6. 状态码和版本变化必须有兼容性说明和测试。
7. C ABI 和 JNI 合同必须保持同名操作、相同错误码和相同版本规则。