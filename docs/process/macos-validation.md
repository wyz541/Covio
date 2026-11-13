# 本地 macOS 验证

**结论：GitHub Actions 不运行 macOS 检查。完整 macOS 验证在本地 Apple Silicon Mac 运行。**

## 1. 适用范围

本流程适用于 Covio 的 macOS 构建、测试、打包和硬件验收。

GitHub Actions 不得使用 macOS runner。macOS 结果保存在 PR、Issue 或本地证据目录，不上传到 GitHub Actions artifact。

## 2. 环境

- Apple Silicon Mac。
- macOS 26 或更高版本。
- Xcode 27。
- Rust stable。

记录以下环境信息：

- Mac 型号。
- 内存容量。
- macOS 版本。
- Xcode 版本。
- commit。

## 3. 全量门禁

在仓库根目录运行：

```sh
bash scripts/test-all.sh
```

预期结果：

- Rust workspace 通过。
- KMP 与 Kotlin 产品路径不存在。
- 合同和工作流检查通过。
- helper、安装器和 Updater 测试通过。
- macOS XCTest 通过。
- 命令最后输出 `全部通过。`。

高风险改动和正式发布必须通过此命令。

Release app target 会裁剪可执行文件的本地符号。dSYM 单独生成并保留，用于崩溃符号化。不要把发布 app 的未裁剪二进制归档为正式产物。

## 4. Agent 验收

在仓库根目录运行：

```sh
export COVIO_FILE_NAMING_MODEL_DIR="$PWD/build/agent-model"
python3 -I scripts/file_naming_model.py download "$COVIO_FILE_NAMING_MODEL_DIR"
bash scripts/package-macos-swift.sh
bash scripts/verify-agent-bundle.sh dist/Covio.app
```

预期结果：`Offline Agent bundle verification passed.`

## 5. 文件命名验收

在仓库根目录运行：

```sh
export COVIO_FILE_NAMING_MODEL_DIR="$PWD/build/file-naming-model"
python3 -I scripts/file_naming_model.py download "$COVIO_FILE_NAMING_MODEL_DIR"
bash scripts/package-macos-swift.sh
COVIO_FILE_NAMING_MODEL_DIR="$COVIO_FILE_NAMING_MODEL_DIR" \
  bash scripts/package-macos-offline-swift.sh
COVIO_FILE_NAMING_ACCEPTANCE=1 \
  bash scripts/verify-file-naming-bundle.sh dist/Covio-Offline.app
```

预期结果：12 个样例全部通过，验证器输出成功结果。

## 6. 性能门禁

性能门禁使用同一台机器、同一电源状态和隔离的 HOME 目录交替运行 baseline 与 candidate。

macOS 命令：

```sh
python3 -I scripts/performance/macos_benchmark.py \
  --baseline-label "KMP 0.0.2.3" \
  --baseline-app "$HOME/workspace/active/covio-rust-cutover-605/rollback-0.0.2.3/Covio.app" \
  --candidate-label "Rust current" \
  --candidate-app "$PWD/build/release-xcode-cache/Build/Products/Release/Covio.app" \
  --baseline-artifact "App ZIP=$PWD/dist/kmp-Covio.zip" \
  --candidate-artifact "App ZIP=$PWD/dist/Covio.zip" \
  --runs 10 \
  --settle-seconds 30 \
  --sample-seconds 5 \
  --stop-running \
  --enforce \
  --output "$PWD/build/performance/$(date +%Y%m%d-%H%M%S)"
```

参数规则：

- `--baseline-app` 和 `--candidate-app` 可以只给一个。
- `--enforce` 只在两边都有至少 3 次成功样本时给出 pass 或 fail。
- 默认门禁禁止 candidate 在 warm launch、RSS、私有足迹和 CPU 上回退。
- `--max-*-regression-percent` 和 `--max-cpu-increase-points` 可以调整阈值。
- 不传 `--stop-running` 时，已有 Covio 进程会让命令失败。

输出：

| 文件 | 内容 |
| --- | --- |
| `results.csv` | 每次 warm launch 的原始数据 |
| `results.json` | 环境、样本、聚合、比较和门禁结果 |
| `summary.md` | 人类可读摘要 |

数据质量取值：

- `complete`：baseline 和 candidate 都达到请求次数。
- `contaminated`：样本完整，但背景负载或背景 CPU 超出门禁阈值。
- `partial`：两边都有至少 3 次成功样本，但少于请求次数。
- `insufficient`：任一结果少于 3 次。
- `single-app`：只测量了一个 app。

Windows 11 x64 单产品命令：

```powershell
pwsh -File scripts/performance/windows_benchmark.ps1 `
  -CandidatePath C:\bench\rust\Covio.exe `
  -CandidateLabel "Rust current" `
  -Runs 10 `
  -SettleSeconds 30 `
  -SampleSeconds 5 `
  -OutputDirectory build\performance\windows
```

Windows 前置条件：

- Windows 11 x64 固定测试机。
- 单产品模式记录 Rust 性能预算。
- Covio 没有 Windows x64 KMP 产品，因此单产品结果不是 KMP 对比。
- 不把 Windows ARM64 结果当作 x64 结论。

有可比 baseline 时，脚本仍支持同时传入 `-BaselinePath` 和 `-CandidatePath`。

## 7. 证据

PR 的 `Proof` 至少记录：

- 命令。
- 结果。
- Mac 型号。
- 内存容量。
- macOS 版本。
- Xcode 版本。
- commit。

UI 改动还要按 `.github/pull_request_template.md` 提供 Before/After。

测试失败、证据缺失或环境不完整时，PR 保持 draft。

## 8. 构建缓存与清理

macOS 构建脚本使用有界本地缓存。
默认路径是 `~/Library/Caches/Covio/DerivedData`。
每个 worktree 使用一个稳定的子目录。

Release 打包使用主 checkout 的缓存。
缓存路径是 `build/release-xcode-cache`。
Swift Package 缓存路径是 `build/release-source-packages`。
打包锁防止并发任务改写同一份 Release 缓存。

查看 Debug 和本机安装缓存：

```sh
scripts/covio cache status
```

预览清理计划：

```sh
scripts/covio cache clean
```

确认计划后执行删除：

```sh
scripts/covio cache clean --apply
```

清理默认保留最近使用的 4 个 worktree 缓存。
对应 worktree 已不存在时，缓存可以删除。
缓存超过 7 天且 worktree 干净时，缓存可以删除。
Debug 缓存总量目标为 8 GiB。
当前 worktree 和脏 worktree 始终保留。
清理还会移除指向不存在 `Covio.app` 的 LaunchServices 登记。

缓存路径使用 `COVIO_DEBUG_DERIVED_DATA_ROOT` 覆盖。
不要把覆盖值指向其他用户的数据目录。

直接打开 `macosApp/Covio.xcodeproj` 时，Xcode 可能使用默认 DerivedData。
这些目录不进入仓库缓存根。
关闭 Xcode 后，在 Xcode Settings 中删除对应目录。
也可以先确认没有构建进程，再删除 `~/Library/Developer/Xcode/DerivedData/Covio-*`。

`dist/` 保存当前打包和验收需要的版本化产物。已发布且不再使用的 release
worktree 用 `scripts/covio release clean` 删除。普通开发 worktree 合并后通过
Git 或 Paseo 的正常生命周期关闭。

模型文件由验收命令写入 `build/`。不再需要时运行：

```sh
find build/agent-model -depth -delete
find build/file-naming-model -depth -delete
```

## 9. 相关验证

iOS 签名、安装和验证步骤见[本地 iOS 验证](ios-validation.md)。
