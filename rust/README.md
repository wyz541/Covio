# Covio Rust workspace

本目录保存 Covio 的跨平台非 UI core。

## Crates

| Crate | 责任 |
| --- | --- |
| `covio-core` | configuration、shelf、clipboard、workspace、generation、revision、request id、deadline 和 typed core error |
| `covio-bridge` | 版本化 command、response、event、snapshot、cancel 和 shutdown envelope |
| `covio-platform` | data paths、filesystem、Keychain secure storage 和 capability inventory |
| `covio-ffi` | macOS C ABI、opaque handle、callback、shutdown 和 Swift 可导入 header |

`covio-core` 的配置 codec 读取 Kotlin 生成的 fixture。保存时保留未知的根键和 `power`、`display`、`fileNaming` 子键。
Shelf、clipboard 与 workspace 使用同一 filesystem capability，并读取 Kotlin 共用的 durable-state fixture。
Workspace 使用 SHA-256 内容寻址、bounded range reads、staging、atomic move 和 tombstone。

`covio-platform` 定义 capability。macOS adapter 使用 Security.framework 读写 Keychain，不提供明文 fallback。
`StdFileStore` 提供 bounded read、atomic write、append 和 move。
process、socket、notification、power 和 update adapter 在 capability inventory 中保持 unavailable，直到产品 composition 接入真实 adapter。

`covio-ffi` 暴露版本化 C ABI。Handle 只做 bridge envelope 校验、request tracking、cancel、event / snapshot callback 和 shutdown，不复制业务规则。

后续 crate 按 [迁移计划](../docs/design/rust-core-migration.md) 增加。

## 测试

```sh
bash scripts/test-rust.sh
```

脚本还会在 macOS 上构建 `build/rust-macos-ffi/debug/lib/libcovio_ffi.dylib`，并用 `swiftc` 编译和运行 C ABI smoke test。

单独构建 C ABI：

```sh
bash scripts/build-rust-macos-ffi.sh release
```

脚本要求 `cargo`、`rustfmt` 和 Clippy 可用。
本机工具位于 `~/tools/cargo/bin` 时，脚本自动使用该目录。

单独运行：

```sh
cd rust
cargo fmt --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
```

## Bridge 规则

1. 协议版本当前为 `1`。
2. 一个控制消息默认不超过 `1 MiB`。
3. 名称只接受小写 ASCII 起始字符，以及小写字母、数字、`-`、`_`、`.`、`:`。
4. Request id 最多 `128` 字节。
5. Stale generation、stale revision、deadline、cancel 和 shutdown 返回 typed error。
6. Public error 不直接序列化 core 内部错误文本。
7. 大内容使用后续实现的 opaque handle，不进入普通 JSON control envelope。
