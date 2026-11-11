# Draft-first 发布流水线

## 状态

| 项目 | 内容 |
| --- | --- |
| 文档版本 | `1.1` |
| 状态 | 已实现；当前只创建 internal/local Draft |
| 日期 | `2026-11-12` |
| Issue | #356、#761 |
| 上游决策 | [ADR-0020](../adr/adr-0020-local-only-helper-distribution.md)、[ADR-0031](../adr/adr-0031-semantic-versioning.md)、[ADR-0035](../adr/adr-0035-cross-platform-product-scope.md) |

> 2026-11-10：ADR-0035 将当前范围限定为内部测试和 GitHub Releases。本文件描述现有 internal/local 基线。正式商店发布、正式更新器和安装器方案暂缓，正式发布前可以重新设计。

## 目标

发布先进入 Draft。
只有全部验证通过后，维护者才能显式发布。
任一步失败时，Draft 保持未发布状态。

## 平台门禁

| 门禁 | 执行位置 | 产物 |
| --- | --- | --- |
| Portable tests | `ci.yml` 的 Ubuntu job | 每个代码 PR；Rust、KMP removal、合同和发布脚本测试结果 |
| Windows x64 host | `ci.yml` 的 Windows x64 job | Windows 或 Rust 路径、完整门禁、手动运行 |
| Windows ARM64 host | `ci.yml` 的 Windows ARM64 job | 共享平台路径、完整门禁、手动运行 |
| Windows package | `ci.yml` 的 Windows package job | Compose 便携 ZIP、MSI、包元数据 |
| macOS package | 本地 Apple Silicon Mac | DMG、PKG、app zip、update zip、artifact boundary |
| iOS package | 本地 Apple Silicon Mac 与 Apple 签名身份 | 签名 IPA、包元数据 |
| Runtime acceptance | #613 的 Windows 和 macOS 真实设备 | 日期、设备、OS、artifact、commit 和结果 |

Hosted tests 只证明构建和仓库行为。
Hosted installer tests 只证明安装事务。
真实设备验收和最终 artifact proof 必须分别记录。


## 版本身份

| 字段 | 示例 | 用途 |
| --- | --- | --- |
| `clientVersion` | `0.6.0-internal.23` | 完整 SemVer，用于更新检查和安装包文件名 |
| `productVersion` | `0.6.0` | 稳定 SemVer 基线 |
| `buildNumber` | `23` | 单调递增构建号，不是项目版本 |
| `gitCommit` | 完整 40 位 SHA | 源码定位，不参与排序 |
| `channel` | `internal` 或 `public` | 发布渠道 |
| `helperProtocolVersion` | `10` | app 与 helper 的协议版本 |

internal 渠道生成 `clientVersion = productVersion-internal.buildNumber`。
public 渠道生成 `clientVersion = productVersion`。
示例：`0.6.0-internal.23` 和 `0.6.0`。
`buildNumber` 超过 `9999` 时，脚本失败关闭。

`releaseId` 使用 `<clientVersion>-g<fullGitSHA>`。
app 的 `CFBundleShortVersionString` 使用 `productVersion`。
app 的 `CFBundleVersion` 使用 `buildNumber`。
自定义 `CovioClientVersion` 保存完整 `clientVersion`。
`clientVersion`、`productVersion`、`buildNumber`、渠道、Git 和 helper 协议必须分别保存。

## 资产

一次发布包含：

```text
Covio-<clientVersion>.app.zip
CovioUpdate-<clientVersion>.zip
CovioUpdate-<clientVersion>.json
CovioUpdate-<clientVersion>.sig.json
Covio-<clientVersion>.dmg
Covio-<clientVersion>.pkg
Covio-Offline-<clientVersion>.dmg  # 可选
release-manifest.json
checksums.txt
release-evidence.json
release-notes.generated.md
release-operation.json
```

统一内测 Release 的 Windows 与 iOS 资产：

```text
Covio-<clientVersion>-windows-x64-portable.zip
Covio-<clientVersion>-windows-x64.msi
compose-package.json
Covio-<clientVersion>-ios-arm64.ipa
ios-package.json
```

Windows job 运行 `scripts/package-windows-compose.sh`。
MSI 由 `jpackage --type msi` 生成。
`compose-package.json` 记录 `clientVersion`、`buildNumber`、渠道、Git commit、制品 SHA-256 和大小。

iOS job 运行 `scripts/package-ios-swift.sh`。
脚本使用 `COVIO_IOS_TEAM_ID` 选择 Apple 签名身份。
脚本导出开发、Ad Hoc 或 App Store IPA。
脚本检查 embedded provisioning profile、代码签名、版本号和 Git commit。
没有签名身份或 provisioning profile 时，脚本失败。

macOS job 运行 `scripts/package-macos-swift.sh`。
打包完成后，`scripts/verify-macos-artifact.sh` 检查 app、DMG 和 PKG。
检查范围包括文件名、Mach-O 动态依赖和 code signature。
发现 KMP、JVM、Kotlin、Compose 或 JNA 时，打包失败。
`test-all.sh` 会先测试两个 boundary checker 的正例和反例。

`release-evidence.json` 记录全部资产摘要、releaseId、commit、协议、平台身份和验证结果。
`CovioUpdate-<clientVersion>.zip` 只包含根级 `Covio.app`。
Manifest 和签名信封由当前 Release 的同一组 app、helper 和 updater 生成。
`release-notes.generated.md` 从同一份证据生成。
`checksums.txt` 包含 macOS、Windows 和 iOS 的全部发布资产与平台元数据。
发布离线包时，`checksums.txt` 还包含 `Covio-Offline-<clientVersion>.dmg`。
`release-manifest.json` 记录默认包、可选离线包和模型 revision。
统一内测发布还记录 `requiredPlatforms`、Windows 制品和 iOS 制品。
`Covio.app` 的 Resources 携带 bundle identity manifest，不包含安装包摘要。
PKG 把 app 写入暂存区，再通过原子 bundle 交换完成 app 与 helper 的成对安装。

## 创建 Draft

内部渠道先准备 Keychain 签名密钥：

```sh
bash scripts/setup-update-signing-key.sh covio-internal-2026-01
```

准备 iOS 签名环境：

```sh
export COVIO_IOS_TEAM_ID=<team-id>
export COVIO_IOS_EXPORT_METHOD=development
```

`scripts/covio release draft` 自动下载目标 commit 的 Windows Compose CI 制品。
直接运行 `create-release.sh` 时，先设置 `COVIO_WINDOWS_COMPOSE_PACKAGE_DIR`。

创建内部 Draft：

```sh
bash scripts/create-release.sh
```

`create-release.sh` 拒绝没有 update 签名密钥的内部发布。
脚本不把私钥写入仓库、Draft、日志或临时文件。

附带离线整包：

```sh
COVIO_FILE_NAMING_MODEL_DIR=build/models/Qwen3VL-2B-Instruct-4bit \
  bash scripts/create-release.sh --with-offline
```

该命令默认构建制品并创建 Draft。
内部 tag 使用 `v<clientVersion>`。`clientVersion` 已包含 `internal.<buildNumber>`。
内部 Draft 同时标记为 pre-release。旧四位客户端需要手工安装首个 SemVer 版本。

复用刚构建的制品：

```sh
bash scripts/create-release.sh --skip-package
```

只检查命令，不调用 GitHub：

```sh
bash scripts/create-release.sh --dry-run --skip-package
```

## 发布 Draft

```sh
bash scripts/publish-release.sh v<clientVersion>
```

发布命令重新下载 Draft 资产。
发布命令重算 release evidence。
发布命令检查 Draft、tag、pre-release 标记和 app/helper 成对资产。
任一检查失败时，命令在 `gh release edit` 前退出。
`publish-release.sh` 已执行完整验证。因此，正式发布前不需要再单独运行一次 `--dry-run`。

内部渠道发布后保持 pre-release。
内部渠道不会成为正式 latest。

## 内测签名

`scripts/create-release.sh` 为 internal 渠道设置 `COVIO_REQUIRE_STABLE_SIGNING=1`。
内测 Release 的 app 与 helper 必须使用同一张本机稳定证书。
内测包不启用 hardened runtime。自签证书没有 Team ID，启用后 Library Validation 会拒绝加载内嵌框架。
公共包继续要求 hardened runtime。
证书 Authority 不一致、缺失或 app/helper 为 ad-hoc 时，Draft 创建失败。
app、helper 和嵌入代码的 `Identifier` 与 `designated =>` 由 `scripts/verify_macos_signing.py` 检查。

CI acceptance 直接调用打包脚本。CI 没有证书，因此该路径仍允许 ad-hoc。

## 正式发布环境

正式渠道必须设置：

```text
COVIO_CODE_SIGN_IDENTITY
COVIO_INSTALLER_SIGN_IDENTITY
COVIO_DEVELOPMENT_TEAM
COVIO_NOTARY_PROFILE
```

正式渠道还必须满足：

- app 和 helper 使用 Developer ID Application 和 hardened runtime。
- DMG 使用 Developer ID Application。
- PKG 使用 Developer ID Installer。
- app、DMG 和 PKG 通过 notarization staple。
- app 和 PKG 通过 Gatekeeper。
- helper 和 app 的 releaseId、commit、协议和摘要完全一致。
- app 和 helper 都包含在 app zip 中。

当前分发只允许 internal/local Draft。
公开分发不在 ADR-0020 范围内。
未来公开分发需要新的 ADR、Apple Developer Program、Developer ID 和 notarization。

## 快捷命令

`scripts/covio` 把下面的脚本按发布顺序串起来。
`scripts/covio` 不复制校验逻辑。

```text
release status    只读：origin/main 的身份、tag、CI 与 Release 状态
release prepare   新 worktree → bump → 说明草稿 → draft PR
   ↓ 维护者重写说明，合并 PR
release draft     origin/main 的 detached worktree → create-release.sh
   ↓ 维护者安装 Draft 中的 PKG 并验收
release publish   确认 → publish-release.sh
release clean     删除已发布 tag 的 release worktree
```

各命令的前置检查：

| 命令 | 拒绝执行的条件 |
| --- | --- |
| `release prepare` | 上一个 tag 还没有发布 |
| `release prepare` | 分支或 worktree 已存在 |
| `release draft` | tag 已有 Release |
| `release draft` | `RELEASE_NOTES.md` 标题不是本 build，或仍有 `TODO(release)` |
| `release draft` | origin/main 的 CI 未全部通过（`--skip-ci-check` 跳过） |
| `release publish` | tag 不是 Draft，或维护者未输入 `y`（`--yes` 跳过） |
| `release clean` | worktree 有未提交改动、提交不在 main 上，或 Release 未发布 |

`release prepare` 用 `scripts/release_notes.py` 生成说明草稿。
草稿列出上一个 tag 之后合并的 PR 标题，并写入 `TODO(release)` 标记。
维护者按用户可见的变化重写草稿，然后删除标记。
`release_notes.py` 同时更新 README 的下载链接与历史版本列表。

`release draft` 只从 origin/main 构建。
因此 Release 的 commit 就是 bump PR 合并后的 main，不是本地分支。
`release draft` 和直接 Release 打包复用主 checkout 的持久缓存。
缓存只减少重复编译。缓存不改变 release identity、签名或资产验证。
打包任务锁定 macOS 构建缓存。缓存路径如下：

- `build/release-xcode-cache`：DerivedData。
- `build/release-source-packages`：Swift Package checkout。

设置 `COVIO_RELEASE_DERIVED_DATA` 或 `COVIO_RELEASE_SOURCE_PACKAGES` 可以改缓存位置。
Release 使用普通 `xcodebuild build`。
打包输入是 `Build/Products/Release/Covio.app`。
共享缓存因此可以复用未变化的 MLX 和 SwiftPM 构建产物。
Package 解析单独运行并记录 `package resolve` 阶段耗时。
macOS 包不嵌入 KMP Framework。app 和 helper 都静态链接 Rust core。
Release 只缓存 Xcode DerivedData 与 Swift Package checkout。
GitHub Actions 不运行任何 macOS 构建。
macOS 测试和 Release 构建由本地 Apple Silicon Mac 负责。
创建 Draft 前，维护者必须在本机运行 `bash scripts/test-all.sh`。
本地验收步骤见 `docs/process/macos-validation.md`。

### 本机安装

```sh
scripts/covio local          # Release 配置，替换 /Applications/Covio.app
scripts/covio local --pkg    # 打包并用事务 PKG 安装
```

`local` 允许未提交的改动，用于开发迭代。
`local` 替换 app 后检查 helper 身份。身份不一致时，`local` 重装 helper。
`local` 最后重写 `installed-release.json`。因此下一次 PKG 升级的前置检查能通过。
`local --pkg` 要求工作树干净，与 Release 的安装路径相同。

**警告：** `local` 与 `local --pkg` 需要管理员授权，并会退出正在运行的 Covio。
安装期间风扇、充电上限和合盖控制会短暂失效。

## 失败行为

| 阶段 | 失败结果 |
| --- | --- |
| 构建 | 不创建 Release |
| 资产校验 | 不创建 Release |
| Draft 上传 | 已创建的 Draft 保持未发布 |
| Draft 重验 | Draft 保持未发布 |
| 操作记录上传 | Draft 保持未发布 |
| 显式发布 | Draft 保持未发布 |

## 检查项

| 检查 | 内部 | 正式 |
| --- | --- | --- |
| release manifest 和源清单一致 | 必须 | 必须 |
| app/helper releaseId 一致 | 必须 | 必须 |
| app/helper 的 clientVersion、productVersion、buildNumber、commit、渠道和协议一致 | 必须 | 必须 |
| helper SHA-256 一致 | 必须 | 必须 |
| app/helper 架构为 arm64 | 必须 | 必须 |
| app zip、DMG、PKG 和 checksums 完整 | 必须 | 必须 |
| 默认 app 不含模型权重 | 必须 | 必须 |
| 离线包包含固定 revision 模型 | 提供离线包时 | 提供离线包时 |
| artifact manifest 记录全部安装包和模型身份 | 必须 | 必须 |
| DMG 中的 app/helper 与 app zip 一致 | 必须 | 必须 |
| PKG 包含暂存 app、helper、交易工具和恢复命令 | 必须 | 必须 |
| Developer ID Application | 不要求 | 必须 |
| Developer ID Installer | 不要求 | 必须 |
| hardened runtime | 不要求 | 必须 |
| notarization 和 Gatekeeper | 不要求 | 必须 |

## 操作记录

`release-operation.json` 记录：

- action。
- repository 和 tag。
- channel。
- releaseId 和 Git commit。
- 全部资产摘要。
- 验证状态。
- 记录时间。

创建 Draft 时上传 `create-draft` 记录。
发布前用 `publish` 记录替换 Draft 中的旧记录。

## 验证命令

```sh
python3 -I scripts/test_release_pipeline.py
python3 -I scripts/test_release_notes.py
shellcheck scripts/covio
bash scripts/test-all.sh
```
