# Covio Rust workspace

本目录保存 Covio 的跨平台非 UI core。

## Crates

| Crate | 责任 |
| --- | --- |
| `covio-core` | configuration、generation、revision、request id、deadline 和 typed core error |
| `covio-bridge` | 版本化 command、response、event、snapshot、cancel 和 shutdown envelope |
| `covio-platform` | data paths、filesystem capability 和 secure-storage port |

`covio-core` 的配置 codec 读取 Kotlin 生成的 fixture。保存时保留未知的根键和 `power`、`display`、`fileNaming` 子键。

`covio-platform` 只定义 capability。没有 native adapter 时，secret access 返回 `Unavailable`，不提供明文 fallback。

后续 crate 按 [迁移计划](../docs/design/rust-core-migration.md) 增加。

## 测试

```sh
bash scripts/test-rust.sh
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
