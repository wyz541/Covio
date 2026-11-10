# Covio 研究归档

## 职责

本目录保存 Covio 的研究、审计、证据和验证资料。
本目录为研究资料的唯一入口。
每个研究主题使用一个独立目录。
每个主题目录使用 `README.md` 作为统一索引。
主题索引说明前因、背景、过程、结果、预期和实现手段。
主题索引链接全部子文档和证据链。
新研究主题按 [AUTHORING.md](AUTHORING.md) 生成。

## 研究主题

| 主题 | 状态 | 索引 |
| --- | --- | --- |
| macOS 后台 GUI 自动化与虚拟化控制 | 初稿，可评审 | [README.md](macos-background-gui-automation/README.md) |
| 本地离线文件自动命名 | 初稿，可评审 | [README.md](file-auto-naming/README.md) |
| 跨设备内容读取能力 | 初稿，可评审 | [README.md](cross-device-content-access/README.md) |
| 跨设备共享暂存工作区 | 初稿，可评审 | [README.md](shared-transfer-workspace/README.md) |
| 跨平台凭据存储合同 | 初稿，可评审 | [README.md](platform-credential-storage/README.md) |
| Rust 跨平台文件传输 | 初稿，可评审 | [README.md](rust-file-transfer/README.md) |
| Compose Multiplatform 与 Rust bridge | 初稿，可评审 | [README.md](compose-rust-bridge/README.md) |
| 触控板多指手势入口 | 初稿，可评审 | [README.md](trackpad-gesture-entry/README.md) |
| iOS 免打开入口 | 初稿，可评审 | [README.md](mobile-ambient-entry/README.md) |
| 合盖睡眠控制与权限边界 | 初稿，可评审 | [README.md](lid-sleep-control/README.md) |
| 合盖黑屏与 framebuffer 显示链路 | 系统报告，可评审 | [REPORT.md](lid-framebuffer-mechanism/REPORT.md) |
| 硬件信息监听能力 | 第一版已落地 | [README.md](hardware-monitoring-capability/README.md) |
| macOS 历史性能与硬件报告 | 已实现，验收完成（真实 10 天 soak 取消） | [README.md](macos-performance-history/README.md) |
| 电池充电控制能力 | 初稿，可评审 | [README.md](battery-charge-control/README.md) |
| Stats 风扇控制 | 已完成源码调研 | [README.md](stats-fan-control/README.md) |
| 离线本地服务 Agent | 第一版已落地，验收通过 | [README.md](local-agent/README.md) |
| 特权能力架构与 helper 选择 | 初稿，可评审 | [README.md](privileged-helper-architecture/README.md) |
| macOS 安装包体积缩减 | internal/local 验证通过 | [README.md](installer-size-reduction/README.md) |
| helper 发布统一真机验证 | 主要场景通过 | [README.md](helper-release-unification/README.md) |
| 研发工作流的调研依据 | 单文件，不建主题目录 | [workflow-research.md](workflow-research.md) |

## 归档规则

- 研究报告、证据和验证记录放在同一个主题目录中。
- `docs/validation/` 不作为独立归档入口。
- 旧路径不保留跳转页。
- 链接使用相对路径。
- 文档使用中文。命令、路径、API 名称和版本号保留原文。
- 执行验证后更新主题索引和案例状态。
