# ADR-0005：本机用固定证书签名

- Status：accepted
- Kind：architecture
- Date：2026-10-15
- Supersedes：none
- Implements：#116

## 背景

TCC 用代码签名识别应用。工程原来在四处构建配置里写 `CODE_SIGN_IDENTITY = "-"`，即 ad-hoc 签名。

ad-hoc 签名没有 Team ID。识别依据退化成 cdhash：

```text
$ CACHE_DIR="$(python3 -I scripts/build_cache.py prepare "$PWD")"
$ codesign -d -r- "$CACHE_DIR/Build/Products/Debug/Covio.app"
# designated => cdhash H"c994eba9091859a67982e890baef6e97d782b088"
```

每次构建都产生新 cdhash。系统把新构建当成新应用。于是系统重新要辅助功能权限，并重发「已添加设备控制和数据访问」通知。授权在两次构建之间不保留。

三个约束：

1. CI 跑在 GitHub 运行器上。那里没有本机证书。默认配置必须能构建。
2. internal 包复用本机稳定证书。没有证书时，仅 CI 或直接本机打包可以使用 ad-hoc。公开分发要 Developer ID 证书与公证，不在本决策范围内。
3. 本机没有可用的签名身份。`security find-identity -v -p codesigning` 返回 0 个。

## 决策

1. 工程默认保持 ad-hoc 签名。任何机器都能构建，CI 也走这条。
2. 新增 `macosApp/Signing.xcconfig`，作为工程的 base configuration。
3. 该文件用 `#include?` 可选引入同目录的 `Signing.local.xcconfig`。
4. `Signing.local.xcconfig` 不进仓库。本机在那里放签名身份。
5. 签名身份用本机自建的代码签名证书，不用 Apple 开发者证书。

建证书的步骤：

```bash
cat > openssl.cnf <<'EOF'
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = Covio Dev
O = Covio
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
  -config openssl.cnf -keyout covio.key -out covio.crt
openssl pkcs12 -export -out covio.p12 -inkey covio.key -in covio.crt \
  -passout pass:covio -legacy
security import covio.p12 -k "$HOME/Library/Keychains/login.keychain-db" -P covio \
  -T /usr/bin/codesign -T /usr/bin/xcodebuild \
  -T /Applications/Xcode.app/Contents/MacOS/Xcode
security find-identity -p codesigning
```

`-legacy` 不能省。OpenSSL 3 默认用 AES-256-CBC 与 SHA-256。macOS 的 Security 框架读不了这种 PKCS#12，`security import` 会报 `MAC verification failed`。

最后一条命令应列出 `"Covio Dev"`。它同时带 `CSSMERR_TP_NOT_TRUSTED` 标记。这不影响使用：`codesign` 不要求证书被信任。不要用 `-v`，`-v` 只列受信任的身份，会显示 0 个。

然后在 `macosApp/Signing.local.xcconfig` 写：

```text
CODE_SIGN_IDENTITY = Covio Dev
CODE_SIGN_STYLE = Manual
```

导入成功后删掉临时目录里的 `covio.key` 与 `covio.p12`。私钥已在登录钥匙串里，临时文件是多余的副本。

## 新 worktree 的签名身份

`Signing.local.xcconfig` 不进仓库，所以每个 worktree 各要一份。

`scripts/setup-local-signing.sh` 负责补上。本机有证书、且该 worktree 还没有这个文件时，脚本写入它。四种情况不写：不是 macOS、工程没有 `Signing.xcconfig`、文件已存在、本机没有这张证书。

`scripts/build-macos-swift.sh` 与 `scripts/test-macos-swift.sh` 会先调用脚本，所以用脚本构建的 worktree 自动获得固定身份。

Xcode 图形界面里构建走 `Covio.xcscheme` 的 Build 预动作，也会调用脚本。因此每个 worktree 的第一次构建都会补上这个文件，不需要手动步骤。

## 内测包继承本机身份

`scripts/package-macos-swift.sh` 与 `scripts/package-macos-offline-swift.sh` 在 internal 渠道调用 `scripts/setup-local-signing.sh --print-identity`。本机有证书时，两个脚本使用同一身份签名 app、helper、嵌入框架和 DMG。

`scripts/create-release.sh` 强制设置 `COVIO_REQUIRE_STABLE_SIGNING=1`。没有稳定证书时，内测 Release 打包失败。CI 的 acceptance 作业直接调用打包脚本，因此无证书时仍可使用 ad-hoc。

内测包生成后调用 `scripts/verify_macos_signing.py`。构建、开发和内测包共用固定证书根。`CDHash` 可以变化，`Identifier` 与 `designated =>` 必须保持相同。

## 开发签名自动检查

构建脚本与测试脚本在产物生成后调用 `scripts/verify_macos_signing.py`。检查覆盖主应用、helper 与嵌入框架。

本机有 `Signing.local.xcconfig` 时，检查要求非 ad-hoc 签名。
检查拒绝只绑定 cdhash 的 Designated Requirement。
构建与测试各用一份基线。
第一次成功检查把构建身份写到工作树缓存。
文件名是 `development-signing-Debug-build.json`。
测试基线文件名是 `development-signing-Debug-test.json`。
后续构建比较每个嵌套代码对象的 `Identifier` 与 `designated =>`。
`CDHash` 不参与比较。

CI 没有签名证书，因此构建保持 ad-hoc。检查在没有本机覆盖文件或基线时只验证签名完整性，不要求固定身份。显式传入 `--require-stable` 时，ad-hoc 产物会失败。

开发者可以手动运行：

```bash
CACHE_DIR="$(python3 -I scripts/build_cache.py prepare "$PWD")"
python3 -I scripts/verify_macos_signing.py \
  "$CACHE_DIR/Build/Products/Debug/Covio.app" \
  --require-stable \
  --baseline "$CACHE_DIR/development-signing-Debug-build.json"
```

证书或 Bundle ID 有意变更时，先确认变更目标。
然后删除两份签名基线。
其他情况不要删除基线。

开发授权验收使用固定缓存路径。
构建产物位于当前 worktree 的缓存目录。
安装验收固定为 `/Applications/Covio.app`。
不要在同一授权周期内切换多个 app 副本。
启动并授权一次后，重新构建并覆盖同一路径。
确认系统不再要求同一权限。
权限测试使用临时目录或测试夹具。
权限测试不访问真实 Desktop。

## 后果

### 正面

- 本机授权一次之后，重新构建不再弹窗。
- CI 与别人的克隆不受影响。
- 签名身份不进仓库，也不绑 Apple 账号。

### 负面

- 每台开发机要建一次证书。
- 换机器或删掉证书后，识别依据改变，要重新授权一次。

### 风险

- 证书进登录钥匙串后，其他进程可以用它签名。缓解：该证书只用于本机开发，不用于分发。
- 自签名证书过不了 Gatekeeper。缓解：internal 包继续走手动放行；公开分发时换 Developer ID 与 notarization。

## 备选方案

### 备选 1：Apple Development 证书

用 Xcode 的 Apple ID 账号建 Apple Development 证书，把 `DEVELOPMENT_TEAM` 写进工程。识别依据会锚定团队 ID，跨证书续期稳定。

未采纳的原因：本机 Xcode 没有登录的账号，构建报 `error: No Accounts`。建证书要在图形界面登录。而且它只解决本机开发，分发仍要另买 Developer ID。

### 备选 2：把签名身份写进工程

直接把四处 `CODE_SIGN_IDENTITY` 改成证书名。

未采纳的原因：CI 与本机之外的克隆会构建失败。

### 备选 3：只在构建脚本里传签名参数

`scripts/build-macos-swift.sh` 与 `scripts/test-macos-swift.sh` 加命令行参数。

未采纳的原因：Xcode 图形界面里构建仍走 ad-hoc。而那正是调试弹窗的场景之一。

## 未决事项

| 项目 | 状态 | 确认方法 |
| --- | --- | --- |
| 连续两次构建的 designated requirement 是否相同 | 已确认 | 见下 |
| 分发签名与公证 | pending | 另开 issue |

## 验证

本机建好 `Covio Dev` 证书后，改动一个 Swift 文件，连续构建两次。两次的 cdhash 不同，designated requirement 相同：

| 项目 | 第一次 | 第二次 |
| --- | --- | --- |
| `CDHash` | `3cfe010aeb8946315aa5be2458383c47b2e26f26` | `18efccab184a7933c262de37f9f4554662743885` |
| `Authority` | `Covio Dev` | `Covio Dev` |
| designated requirement | `identifier "com.wyz.covio" and certificate root = H"954adead95bb79d673dd0e818afc6ceaa6e0d623"` | 同左 |

识别依据锚定到证书，所以 TCC 的授权跨构建保留。

## 参考

- `macosApp/Signing.xcconfig`
- `scripts/package-macos-swift.sh`
