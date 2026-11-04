# ADR-0033：所有 macOS 验证只在本地运行

- Status：proposed
- Kind：architecture
- Date：2026-11-04
- Supersedes：ADR-0032
- Implements：#629

## 背景

ADR-0032 把日常门禁移到 Linux，但保留了三个手动 macOS 工作流。GitHub 仍允许触发 macOS 分钟。新的边界要求 GitHub Actions 不运行任何 macOS 构建。

本地 Apple Silicon Mac 有真实硬件、Xcode 和签名环境。macOS XCTest、helper、安装器、Agent 和文件命名验收可以在同一台机器执行。

## 决策

1. GitHub Actions 工作流不得使用 macOS runner。
2. 删除 `macos-release.yml`、`agent-acceptance.yml` 和 `file-naming-acceptance.yml`。
3. GitHub 托管 CI 保留 Linux 和 Windows 作业，不运行 macOS。
4. 完整 macOS 验证运行 `bash scripts/test-all.sh`。
5. Agent 和文件命名验收在本地 Apple Silicon Mac 运行。
6. PR 记录本地命令、结果、设备和系统版本。
7. 工作流校验拒绝任何 macOS runner。

## 后果

### 正面

- GitHub Actions 不再产生 macOS 分钟。
- macOS 验证使用真实硬件。
- 签名、模型和系统服务验收与产品环境一致。
- CI 配置不需要维护 macOS runner。

### 负面

- GitHub 无法提供 macOS 自动门禁。
- PR 作者必须持有 Apple Silicon Mac。
- 本地测试耗时由维护者承担。

### 风险

- 风险：PR 可能遗漏本地 macOS 验证。缓解：PR 模板记录本地结果，缺失时不得转为 ready。
- 风险：不同 Mac 的环境可能不一致。缓解：记录硬件、macOS 和 Xcode 版本。
- 风险：本地验收可能被遗忘。缓解：发布前必须运行 `scripts/test-all.sh`。

## 备选方案

### 备选 1：保留手动 macOS 工作流

保留手动入口可以随时使用 GitHub macOS。该方案仍会产生高单价分钟，不符合新边界。未采纳。

### 备选 2：使用自托管 macOS runner

自托管 runner 可以自动运行 macOS。该方案需要持续维护机器、隔离和权限。未采纳。

### 备选 3：使用其他托管 macOS CI

把 macOS 作业迁移到其他服务。该方案增加第二套 CI 配置和凭据管理。未采纳。

## 未决事项

| 项目 | 状态 | 确认方法 |
| --- | --- | --- |
| 后续是否引入云端 macOS 验收 | 待观察 | 新需求出现时创建新 ADR |

## 参考

- `docs/process/macos-validation.md`
- `scripts/test-all.sh`
- `scripts/verify-agent-bundle.sh`
- `scripts/verify-file-naming-bundle.sh`
