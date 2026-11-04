# Covio Rust workspace

本目录保存 Covio 的跨平台非 UI core。

## Crates

| Crate | 责任 |
| --- | --- |
| `covio-core` | configuration、shelf、clipboard、workspace、generation、revision、request id、deadline 和 typed core error |
| `covio-bridge` | 版本化 command、response、event、snapshot、cancel 和 shutdown envelope |
| `covio-platform` | data paths、atomic filesystem、Keychain、Credential Manager、Windows capability adapter 和 inventory |
| `covio-ffi` | macOS C ABI、opaque handle、callback、shutdown 和 Swift 可导入 header |
| `covio-windows` | Windows egui product host、托盘、单实例、core worker、capability composition 和 installer smoke |

`covio-core` 的配置 codec 读取 Kotlin 生成的 fixture。保存时保留未知的根键和 `power`、`display`、`fileNaming` 子键。
Shelf、clipboard 与 workspace 使用同一 filesystem capability，并读取 Kotlin 共用的 durable-state fixture。
Workspace 使用 SHA-256 内容寻址、bounded range reads、staging、atomic move 和 tombstone。

`covio-platform` 定义 capability。macOS adapter 使用 Security.framework 读写 Keychain。Windows adapter 使用 Windows Credential Manager，不提供明文 fallback。
`StdFileStore` 使用同目录替换提供 cross-platform atomic write，并保留 bounded read、append 和 move。
Windows adapter 提供 clipboard、native file picker、toast notification、current-user startup、screenshot directory discovery 和 updater process handoff。
Windows 对 socket 与 macOS 专属 power capability 返回 typed unavailable。

`covio-ffi` 暴露版本化 C ABI。Handle 只做 bridge envelope 校验、request tracking、cancel、event / snapshot callback 和 shutdown，不复制业务规则。

`covio-windows` 在 Windows 上使用 Rust + egui。Windows host 直接持有 core worker，不启动 JVM。
Host 提供 Screenshot shelf、clipboard history、workspace、settings 和 update handoff UI。
Installer 使用 Inno Setup，安装到 `%LOCALAPPDATA%\Programs\Covio`，不要求管理员权限。
macOS、Android、iOS 和 Web 不是这个 host 的目标。

后续 crate 按 [迁移计划](../docs/design/rust-core-migration.md) 增加。

## 测试

```sh
bash scripts/test-rust.sh
bash scripts/test-windows-rust.sh
COVIO_WINDOWS_BUILD_NUMBER=24 COVIO_WINDOWS_APP_VERSION=0.6.0-internal.24 \
  COVIO_WINDOWS_OUTPUT_DIR=build/windows-previous bash scripts/package-windows.sh
bash scripts/package-windows.sh
bash scripts/verify-windows-artifact.sh rust/target/release/covio-windows.exe
pwsh -NoProfile -File scripts/test-windows-installer.ps1
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
cargo run -p covio-windows -- --headless-smoke
```

Windows CI 还运行：

```sh
bash scripts/test-windows-rust.sh
```

该脚本执行 Credential Manager round-trip、atomic write、clipboard、startup、updater handoff 和 typed capability smoke。

## Bridge 规则

1. 协议版本当前为 `1`。
2. 一个控制消息默认不超过 `1 MiB`。
3. 名称只接受小写 ASCII 起始字符，以及小写字母、数字、`-`、`_`、`.`、`:`。
4. Request id 最多 `128` 字节。
5. Stale generation、stale revision、deadline、cancel 和 shutdown 返回 typed error。
6. Public error 不直接序列化 core 内部错误文本。
7. 大内容使用后续实现的 opaque handle，不进入普通 JSON control envelope。
