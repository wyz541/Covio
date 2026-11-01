# Draft-first 发布流水线

## 状态

| 项目 | 内容 |
| --- | --- |
| 文档版本 | `1.0` |
| 状态 | 已实现；当前只创建 internal/local Draft |
| 日期 | `2026-10-25` |
| Issue | #356 |
| 上游决策 | [ADR-0020](../adr/adr-0020-local-only-helper-distribution.md) |

## 目标

发布先进入 Draft。
只有全部验证通过后，维护者才能显式发布。
任一步失败时，Draft 保持未发布状态。

## 资产

一次发布包含：

```text
Covio-<version>.app.zip
Covio-<version>.dmg
Covio-<version>.pkg
Covio-Offline-<version>.dmg  # 可选
release-manifest.json
checksums.txt
release-evidence.json
release-notes.generated.md
release-operation.json
```

`release-evidence.json` 记录全部资产摘要、releaseId、commit、协议和验证结果。
`release-notes.generated.md` 从同一份证据生成。
`checksums.txt` 包含 app zip、默认 DMG、PKG 和 artifact manifest。
发布离线包时，`checksums.txt` 还包含 `Covio-Offline-<version>.dmg`。
`release-manifest.json` 记录默认包、可选离线包和模型 revision。
`Covio.app` 的 Resources 携带 bundle identity manifest，不包含安装包摘要。
PKG 把 app 写入暂存区，再通过原子 bundle 交换完成 app 与 helper 的成对安装。

## 创建 Draft

内部渠道：

```sh
bash scripts/create-release.sh
```

附带离线整包：

```sh
COVIO_FILE_NAMING_MODEL_DIR=build/models/Qwen3VL-2B-Instruct-4bit \
  bash scripts/create-release.sh --with-offline
```

该命令默认构建制品并创建 Draft。
内部 tag 使用 `v<version>-internal.<build>`。
内部 Draft 同时标记为 pre-release。

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
bash scripts/publish-release.sh v<tag>
```

发布命令重新下载 Draft 资产。
发布命令重算 release evidence。
发布命令检查 Draft、tag、pre-release 标记和 app/helper 成对资产。
任一检查失败时，命令在 `gh release edit` 前退出。

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
| app/helper 版本、build、commit、协议一致 | 必须 | 必须 |
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
