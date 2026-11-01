#!/bin/bash
set -euo pipefail

# 全量测试入口。跨模块、协议、发布和 CI 门禁排障时使用。
# 日常迭代按 `docs/process/workflow.md` 的「测试门禁」运行相关测试。
#
# 八步，任一步失败就停：
#   1. 共享层的 Kotlin 测试。两个平台都跑，macosArm64 也在内。
#   2. 合同常量有没有漂移。
#   3. 合同的跨段规则。schema 表达不了的那些。
#   4. Issue 与 PR 模板是否把视觉证据放在正确对象。
#   5. 割接脚本的断言。
#   6. 本机 app-helper 升级与回滚事务。
#   7. 文件自动命名模型清单。
#   8. macOS SwiftUI 宿主的 XCTest。
#
# 第 6 步自己也会跑第 2、3 步。分开列是为了让它们单独报错，一眼能看出问题在哪。

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

step() { printf '\n=== %s ===\n' "$1"; }

step "发布身份"
python3 -I "$ROOT/scripts/release_manifest.py" check
python3 -I "$ROOT/scripts/test_release_manifest.py"
python3 -I "$ROOT/scripts/test_release_pipeline.py"
python3 -I "$ROOT/scripts/test_release_notes.py"
python3 -I "$ROOT/scripts/test_verify_macos_signing.py"

step "Kotlin 共享层"
bash "$ROOT/scripts/provision-amper-github-downloads.sh"
/bin/sh ./kotlin test

step "设计合同常量"
# `-I` 是隔离模式：不读当前目录，防止目录里被放一个同名模块顶替标准库。
python3 -I "$ROOT/scripts/generate-contract-constants.py" --check

step "设计合同跨段规则"
python3 -I "$ROOT/scripts/validate-contract.py"

step "工作流模板"
python3 -I "$ROOT/scripts/validate-workflow.py"

step "本机 helper 固定路径验证"
bash "$ROOT/scripts/verify-helper-cutover.sh" selftest

step "本机升级事务"
bash "$ROOT/scripts/test-transactional-installer.sh"

step "文件自动命名模型清单"
python3 -I "$ROOT/scripts/file_naming_model.py" verify-all

step "macOS SwiftUI 宿主"
bash "$ROOT/scripts/test-macos-swift.sh"

printf '\n全部通过。\n'
