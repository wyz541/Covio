# 本地 macOS 验证

**结论：GitHub Actions 不运行 macOS 检查。完整 macOS 验证在本地 Apple Silicon Mac 运行。**

## 1. 适用范围

本流程适用于 Covio 的 macOS 构建、测试、打包和硬件验收。

GitHub Actions 不得使用 macOS runner。macOS 结果保存在 PR、Issue 或本地证据目录，不上传到 GitHub Actions artifact。

## 2. 环境

- Apple Silicon Mac。
- macOS 26 或更高版本。
- Xcode 27。
- JDK 25。
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
- Kotlin 的 JVM 与 macOS 测试通过。
- 合同和工作流检查通过。
- helper、安装器和 Updater 测试通过。
- macOS XCTest 通过。
- 命令最后输出 `全部通过。`。

高风险改动和正式发布必须通过此命令。

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

## 6. 证据

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

## 7. 清理

验收生成的文件留在 `build/` 和 `dist/`，由仓库忽略规则管理。

模型文件由验收命令写入 `build/`。不再需要时运行：

```sh
find build/agent-model -depth -delete
find build/file-naming-model -depth -delete
```
