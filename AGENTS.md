# Covio 工作约定

本文件是 agent 的强制契约。Codex 直接读本文件。Claude Code 通过 `CLAUDE.md` 导入。

## 1. 项目基线

Covio 是 macOS 菜单栏应用。界面是 SwiftUI 宿主，放在 `macosApp/`。
共享领域逻辑是 KMP 模块，放在 `kmpDomain/`。
构建系统是 Amper 0.12.1，不是 Gradle。
测试按 `docs/process/workflow.md` 的「测试门禁」分层执行。
日常迭代运行需求相关的测试。
提交 PR 前运行受影响模块的测试。
跨模块、配置合同、helper 协议、持久化、发布或大范围改动运行 `bash scripts/test-all.sh`。
改了 UI 的还要在真机验收。真机截图写入 PR 的「Visual verification」。截图缺失时，PR 不得转入 ready 或合并。
主干是 `main`。

## 2. 流程

```text
明确 Bug 或小任务 → Issue → PR

明确大功能 → Parent Feature（Issue）
               ├─ Research sub-issue
               ├─ Task sub-issue → PR
               └─ Verify sub-issue → 验收证据

开放问题或共识未定 → Discussion → 可选转入 Issue
```

1. 调研报告放 `docs/research/<主题>/`。格式见 `docs/research/AUTHORING.md`。
2. 决策放 `docs/adr/adr-NNNN-<slug>.md`。模板见 `docs/adr/adr-template.md`。
3. Issue 建在 GitHub 上。仓库里不放 issue 定义文件，不设本地编号。

## 3. Parent Feature 与小功能

明确的大功能或调研建一个 Parent Feature，用 GitHub 原生 sub-issue 关联 Research、Task 与 Verify。
进度由 GitHub 自动汇总。不要另外维护进度表。
明确的小功能直接建 task issue，明确 Bug 直接建 bug issue。

一个 task sub-issue 的粒度是一个会话能做完，对应一条分支和一个 PR。
Research 是 sub-issue，但产出是结论，不要求分支和 PR。
Verify 与 Task 同级，是 Parent Feature 的 sub-issue。Verify 的产出是验收证据，不要求分支和 PR。
Research、Task、Verify 和 Bug 分别使用 `research`、`task`、`verify`、`bug` 标签。

## 4. 工作流

流程定义在 `docs/process/workflow.md`。本文件管执行。每次会话按下面的规则做。

1. 开场先归位。判断本次任务在 S1 到 S7 中的哪一步，按该步的条目与完成标准推进。
2. 先判断入口。目标、范围、负责人和完成条件明确时，直接建 Issue。只有方向、范围、优先级或共识未定时，才使用 Discussion。
3. Discussion 是可选来源，不是必经入口，也不能作为原生 parent。Discussion 形成可执行事项时创建对应 Issue，并写回链接。
4. 做法有未知项时开 Research sub-issue。一个 Research 只回答一个问题。时间盒不超 3 个工作日。
5. 调研结论写在 issue 正文，不写评论。正文含结论、依据和后续动作。结论未写回正文前不关 issue。
6. 长期决策进 S4。写新 ADR 走 PR，合并前 Status 改成 `accepted`。
7. 需要跟踪的工作走 S5 建 Parent Feature。Research 完成后，再拆 Task sub-issue。每个 Task 写一行验收标准，工期 1 到 3 天。
8. 跨多个 Task 或 PR 的真机、端到端或发布前验收建 Verify sub-issue。Verify 与 Task 同级，并用 `blocked by` 指向被验收的 Task。
9. UI issue 的正文必须写 `表现预期`，不要求 After 截图。单个 PR 必须使用 `Visual verification`，亮色和深色各放一组 `Before`/`After` 表。跨 PR 的最终 UI 验收写在 Verify issue，并链接 PR 证据。
10. 引用另一个对象时走 S6。值未定时写 `pending`，5 个工作日内回填。
11. 对象用标签区分。Parent Feature 用 `feature`，调研 sub-issue 用 `research`，小功能与 Task sub-issue 用 `task`，验收 sub-issue 用 `verify`，Bug 用 `bug`。
12. 个人账号没有 issue types 与 issue fields。不要用 `--type`，也不要找 issue fields。
   字段用 Project 8 的字段，名字见 `docs/process/project-fields.md`。
   Start date 与 Target date 只在 Project 里维护，不写进 issue 正文。
13. 需要你在 Web 界面操作的步骤，写明操作位置，不要跳过。

## 5. 文档

改动涉及行为时，同步改文档。

| 知识 | 位置 |
| --- | --- |
| 设计合同 | `docs/covio-design-contract.json` |
| 架构决策 | `docs/adr/` |
| 目标架构 | `docs/design/` |
| UI 截图 | PR 的 `Visual verification`；文件放 `docs/design/previews/` |
| 研究结论 | `docs/research/` |
| 工作流规则 | `docs/process/workflow.md` |
| Project 字段 | `docs/process/project-fields.md` |
| 进度 | [Project 8](https://github.com/users/wyz541/projects/8) |

文档用中文。命令、路径、API 名称和版本号保留原文。不写本机绝对路径。

## 6. commit

```text
Add the workbench store

Refs #27
Co-Authored-By: Claude Code <noreply@anthropic.com>
```

1. 标题行用英文祈使句，首字母大写，不超过 72 字符，不加句号，不加 `feat:` 这类前缀。
2. 有对应 issue 时在正文写 `Refs #N`。没有就不写。
3. agent 创建的提交加 `Co-Authored-By: Claude Code <noreply@anthropic.com>`。

不要用 `git commit` 不带 `-m`。

## 7. 禁止

1. 禁止直接向 `main` 推送。改 `main` 走 PR。
2. 禁止 `git add -A` 或 `git add .`。多个会话共用一个工作目录，会扫进别人的文件。
3. 禁止把本机绝对路径写进仓库文件。
4. 改设计合同后要重跑 `scripts/generate-contract-constants.py`。
