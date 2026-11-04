# ADR-0032：托管 CI 只运行可移植门禁

- Status：proposed
- Kind：architecture
- Date：2026-11-04
- Supersedes：none
- Implements：#627

## 背景

Covio 的每个 PR 和 `main` push 都会运行三个 macOS 作业。相同改动会先在 PR 运行，再在合并后重复运行。2026-10-05 至 2026-11-04 的 Actions 记录显示约 6973 个 macOS 作业分钟。2026-11-01 至 2026-11-04 的账单显示 `kmp-Covio` 使用 2239 个 macOS 分钟，价格为 `$138.82`。

GitHub 托管 macOS 分钟约是 Linux 分钟的 10 倍。主要成本来自 `macOS SwiftUI` 作业。该作业每次运行约 9 分钟，30 天累计 5071 分钟。Rust、Kotlin JVM 和多数合同检查不依赖 macOS。

## 决策

1. `ci.yml` 只在 `pull_request` 和 `workflow_dispatch` 运行，不再响应 `push`。
2. 自动门禁只使用 `ubuntu-latest`，并取消同一 PR 的过期运行。
3. Linux 门禁运行 Rust workspace、Kotlin JVM 和可移植检查。
4. Kotlin 和 Rust 作业步骤按改动路径执行，纯 SwiftUI 改动只运行快速检查。
5. macOS XCTest、helper、安装器和硬件验收只在发布 Mac 或手动工作流运行。
6. `scripts/test-all.sh` 保留为高风险改动、正式发布和手动验收的全量入口。

按近 30 天 350 次 PR 门禁和每次 8 分钟的保守估算，Linux 门禁使用 2800 分钟，费用为 `$16.80`。基线 macOS 费用为 `$432.31`。估算费用是基线的 3.9%。

## 后果

### 正面

- 自动 CI 费用预计降至基线的 5% 以下。
- PR 不再重复支付 `main` push 的成本。
- Rust、Kotlin JVM 和合同错误仍由托管 CI 拦截。
- macOS 专项验收不占用日常 PR 等待时间。

### 负面

- GitHub 自动门禁不验证 SwiftUI XCTest。
- UI 和安装器回归依赖发布 Mac 或手动工作流。
- PR 需要记录本地 macOS 测试与真机证据。

### 风险

- 风险：PR 可能跳过 macOS 回归。缓解：PR 保留真机证据；正式发布前运行全量 macOS 验收。
- 风险：路径分类可能漏掉测试依赖。缓解：无法判断影响范围时运行 `scripts/test-all.sh`。
- 风险：手动验收可能被遗忘。缓解：发布清单要求记录手动工作流或发布 Mac 结果。

## 备选方案

### 备选 1：保留 macOS 自动门禁

继续运行三个 macOS 作业，只增加缓存和并发取消。缓存不能消除每次测试的固定成本和 macOS 单价。未采纳。

### 备选 2：使用自托管 Mac

把 macOS 作业迁移到自托管运行器。该方案需要持续维护机器、隔离和权限，个人项目成本更高。未采纳。

### 备选 3：只为 macOS 作业增加路径过滤

只在 Swift 文件变化时运行 macOS 作业。UI 改动仍会产生长作业，路径分类也更复杂。未采纳。

## 未决事项

| 项目 | 状态 | 确认方法 |
| --- | --- | --- |
| 新方案的实际月度费用 | 待观察 | 下一完整账单周期读取 GitHub billing usage |
| 手动 macOS 验收频率 | 待观察 | 记录正式发布和手动工作流运行 |

## 参考

- GitHub Actions billing usage：`2026-11-01` 至 `2026-11-04`。
- Actions 运行记录：`2026-10-05` 至 `2026-11-04`。
- 测试流程：`docs/process/workflow.md`。
