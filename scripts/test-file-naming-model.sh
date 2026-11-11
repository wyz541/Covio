#!/bin/bash
set -euo pipefail

# 用 Xcode 构建路径运行真实 MLX 模型。模型目录必须由调用者提供。
#
# 示例：
#   COVIO_FILE_NAMING_MODEL_DIR="$MODEL_DIR" bash scripts/test-file-naming-model.sh

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODEL_DIR="${COVIO_FILE_NAMING_MODEL_DIR:-}"
RESULT_PATH="${COVIO_FILE_NAMING_RESULTS_PATH:-$ROOT/build/file-naming-model-results.json}"
DERIVED_DATA="$(python3 -I "$ROOT/scripts/build_cache.py" prepare "$ROOT")"

if [[ "$(uname -s)" != "Darwin" || "$(uname -m)" != "arm64" ]]; then
  printf 'This script requires an Apple Silicon Mac.\n' >&2
  exit 1
fi
if [[ -z "$MODEL_DIR" ]]; then
  printf 'Set COVIO_FILE_NAMING_MODEL_DIR to a local Qwen3-VL model directory.\n' >&2
  exit 1
fi

cd "$ROOT"
bash "$ROOT/scripts/setup-local-signing.sh"
mkdir -p "$(dirname "$RESULT_PATH")" "$ROOT/build"
printf '%s\n' "$MODEL_DIR" > "$ROOT/build/file-naming-model-test-path.txt"
printf '%s\n' "$RESULT_PATH" > "$ROOT/build/file-naming-model-results-path.txt"

xcodebuild \
  -project "$ROOT/macosApp/Covio.xcodeproj" \
  -scheme Covio \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  -skipMacroValidation \
  -skipPackagePluginValidation \
  -only-testing:CovioTests/MLXNamingModelIntegrationTests \
  test

printf 'Model results: %s\n' "$RESULT_PATH"
