#!/bin/bash
set -euo pipefail

# 全量测试入口。跨模块、协议、发布和 CI 门禁排障时使用。
# 日常迭代按 `docs/process/workflow.md` 的「测试门禁」运行相关测试。
#
# 十九步，任一步失败就停：
#   1. 发布身份与脚本检查。
#   2. Rust core 与 bridge 的 fmt、Clippy 和测试。
#   3. Windows host、installer 和 capability smoke。
#   4. Windows Compose host、JNI round-trip、截图和 opt-in package。
#   5. macOS 与 Windows artifact boundary checker。
#   6. KMP shared module 已删除，Compose host 路径保留。
#   7. 合同常量有没有漂移。
#   8. Bridge 合同头文件有没有漂移。
#   9. 合同的跨段规则。schema 表达不了的那些。
#   10. Issue 与 PR 模板是否把视觉证据放在正确对象。
#   11. Release 缓存路径与 linked worktree 解析。
#   12. Debug 构建缓存路径、保留和清理规则。
#   13. 性能门禁工具。
#   14. 割接脚本的断言。
#   15. 本机 app-helper 升级与回滚事务。
#   16. Updater launcher、XPC engine 和回退状态机。
#   17. 文件自动命名模型清单。
#   18. macOS SwiftUI 宿主的 XCTest。
#   19. iOS 工程结构和 SwiftUI 宿主 XCTest。
#
# 安装事务步骤也会跑合同检查。分开列是为了让它们单独报错。

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

step() { printf '\n=== %s ===\n' "$1"; }

step "发布身份"
python3 -I "$ROOT/scripts/release_manifest.py" check
python3 -I "$ROOT/scripts/test_release_manifest.py"
python3 -I "$ROOT/scripts/test_release_pipeline.py"
python3 -I "$ROOT/scripts/test_release_notes.py"
python3 -I "$ROOT/scripts/test_update_manifest.py"
python3 -I "$ROOT/scripts/generate-update-trust.py" --check
python3 -I "$ROOT/scripts/test_verify_macos_signing.py"

step "Rust core"
bash "$ROOT/scripts/test-rust.sh"

step "Windows host"
bash "$ROOT/scripts/test-windows-rust.sh"

step "Windows Compose host"
bash "$ROOT/scripts/test-windows-compose.sh"

step "Artifact boundary scripts"
bash "$ROOT/scripts/test-verify-macos-artifact.sh"
bash "$ROOT/scripts/test-verify-windows-artifact.sh"

step "KMP removal boundary"
python3 -I "$ROOT/scripts/verify-kmp-removal.py"

step "设计合同生成物"
# `-I` 是隔离模式：不读当前目录，防止目录里被放一个同名模块顶替标准库。
python3 -I "$ROOT/scripts/generate-contract-constants.py" --check

step "Bridge 合同头文件"
python3 -I "$ROOT/scripts/generate-bridge-contracts.py" --check

step "设计合同跨段规则"
python3 -I "$ROOT/scripts/validate-contract.py"

step "工作流模板"
python3 -I "$ROOT/scripts/validate-workflow.py"

step "Release 缓存"
bash "$ROOT/scripts/test-release-cache.sh"

step "Debug 构建缓存"
python3 -I "$ROOT/scripts/test_build_cache.py"

step "性能门禁工具"
python3 -I "$ROOT/scripts/test_performance_benchmark.py"

step "本机 helper 固定路径验证"
bash "$ROOT/scripts/verify-helper-cutover.sh" selftest

step "本机升级事务"
bash "$ROOT/scripts/test-transactional-installer.sh"
bash "$ROOT/scripts/test-update-installer.sh"

step "Updater service"
bash "$ROOT/scripts/test-covio-updater.sh"

step "文件自动命名模型清单"
python3 -I "$ROOT/scripts/file_naming_model.py" verify-all

step "macOS SwiftUI 宿主"
bash "$ROOT/scripts/test-macos-swift.sh"

step "iOS 工程结构"
python3 -I "$ROOT/scripts/validate-ios-project.py"

if [[ "$(uname -s)" == "Darwin" ]]; then
  step "iOS SwiftUI 宿主"
  bash "$ROOT/scripts/test-ios-swift.sh"
fi

printf '\n全部通过。\n'
