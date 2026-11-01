# 研发工作流的调研依据

## 文档状态

| 项目 | 内容 |
| --- | --- |
| 文档版本 | `1.3` |
| 状态 | 初稿，可评审 |
| 日期 | `2026-11-01` |
| 适用对象 | 维护人、负责人 |
| 作用 | 支撑 [流程文件](../process/workflow.md) 的机制选择 |
| 问题类别 | 轻量团队的 issue 驱动流程设计 |

本文件回答五个问题。

1. Issue 与 Discussion 应如何分工。
2. 调研（spike）应当有什么结构。
3. 决策对象在工具里没有原生承载时，怎么回链。
4. 开放式想法如何从 Discussion 转入可追踪的 Issue 层级。
5. PR 证据与 Feature 级验收如何分属不同对象。

流程文件的正文是规范。本文件只记录规范的依据和缺口。

## 1. 结论

| 编号 | 结论 | 置信度 |
| --- | --- | --- |
| C-1 | spike 要有时间盒，且要有交付物。 | 中 |
| C-2 | issue 承载不了全部需求。需求细节留在评论与 PR，不另建并行文档。 | 中 |
| C-3 | 主流工具都没有原生的决策对象。回链靠文本约定。 | 高 |
| C-4 | 实施追踪有成熟做法：给已接受的决策建 tracking issue，或让决策编号等于 tracking issue 编号。 | 中高 |
| C-5 | 本流程只能用 GitHub 原生能力。能力边界见第 2.4 节。 | 高 |
| C-6 | 个人账号没有 issue types 与 issue fields。对象只能靠标签区分，字段只能靠 Project 字段承载。 | 高 |
| C-7 | Discussion 适合开放探索。形成可执行事项时再转入 Issue；纯问答和共识可以留在 Discussion。 | 中高 |
| C-8 | Discussion 不能成为原生 parent。Parent Feature 必须用 Issue 承载 Research、Task 与 Verify 的层级。 | 高 |
| C-9 | PR 证据与 Feature 级验收是两种对象。跨 Task 的验收应使用与 Task 同级的 Verify sub-issue。 | 高 |
| C-10 | Issue 适合具体任务、Bug 和计划改进。Discussion 适合开放交流、社区问答和没有明确负责人的讨论。明确事项不应被要求先进入 Discussion。 | 高 |

## 2. 依据

### 2.1 spike 的结构（C-1、C-2）

结论来源是 Reddit 与 Hacker News 上关于 spike 与调研 ticket 的讨论。

可归纳的共同点有两条。

1. spike 必须在开始前写下结束条件。没有时间盒的 spike 会变成无底洞。
2. spike 要有交付物。交付物是一份结论或一份数据，不是一段代码。

时间盒的常见区间是 1 到 3 个工作日。本流程取 2 个工作日为默认值，3 个工作日为上限。

同日得出的第二条结论：issue 不适合承载完整需求。issue 是讨论的起点。需求长起来之后，团队往往另建一份 PRD，于是同一条信息存在两处，随后漂移。本流程因此规定：同一条信息只维护一处。

### 2.2 决策回链（C-3）

GitHub、Linear、Jira 三者的数据模型里都没有「决策」这个对象。存在的是 issue、PR 与文档。因此「这个 Feature 依据哪条决策」只能靠约定表达。

本流程选择的约定是正文里的一行文本，例如 `decision: ADR-0042`、`discussion: <URL>`。选择文本而不是别的载体的理由有三条。

1. 文本可以被 GitHub 的 issue 搜索检索到。`gh issue list --search "decision pending"` 直接可用。
2. 文本不依赖任何第三方应用或 Project 的字段配置。
3. 文本在 issue、PR 与仓库文件里写法一致。

### 2.3 实施追踪（C-4）

调研列举了两种成熟做法。

| 做法 | 代表 | 机制 |
| --- | --- | --- |
| 每个已接受的决策建一个 tracking issue | Rust RFC | RFC 合并后开 tracking issue，负责推进与收口 |
| 决策编号等于 tracking issue 编号 | Kubernetes KEP | KEP 编号与 tracking issue 编号一致，互相可推导 |

本流程采用前者的思路：决策写成仓库里的 ADR 文件，执行放在 GitHub issue 上，两侧用 `decision:` 与 `Implements:` 互相指向。编号不相等，指向靠文本。

不采用后者。理由是 ADR 的编号属于仓库，issue 的编号属于 GitHub。两者合并会让编号在跨仓库引用时产生歧义。

### 2.4 GitHub 能力边界（C-5）

流程只能使用 GitHub 原生能力。因此先确认了下列能力的有无。

| 能力 | 状态 | 依据 |
| --- | --- | --- |
| issue types | **个人账号没有。** 类型属于组织级。 | GraphQL 的 `repository.issueTypes` 返回 `null`；`gh issue create --type` 报 `available types:` 为空 |
| issue fields | **个人账号没有。** | `GET /user/issue-fields` 返回 404 |
| 标签 | 可用。两种账号都一样。 | 已建四个标签并验证加得上 |
| Project 字段 | 可用。两种账号都一样。 | 已核对 Project 8 的 19 个字段，见 [Project 字段](../process/project-fields.md) |
| 读 Project 字段 | 需要 `read:project` 权限。 | 无该权限时 `gh project field-list` 报错；加上后成功 |
| 写 Project 字段 | 需要 `project` 权限。 | 只有 `read:project` 的令牌改不了字段 |
| 表单自动加标签 | 可用。标签不存在时不加。 | 官方文档：`labels` 接受数组或逗号分隔字符串 |
| 表单字段类型 | `markdown`、`textarea`、`input`、`dropdown`、`checkboxes`、`upload` | 官方文档的表单 schema 页 |
| Discussions | 仓库开关无 REST 接口。 | 仓库 Settings 页手工启用 |

**由此得出的设计约束：** 对象只能用标签区分，字段只能放在 Project 里。类型这一层整体去掉。这个结论与「issue types 属于组织级」一致：个人账号没有组织，所以没有类型。

**一条被证伪的中间结论：** 建 `Research` 类型时，`POST /user/issue-types` 返回成功，仓库的 `GET /repos/{owner}/{repo}/issue-types` 也列出了它。当时据此以为类型通路可用。随后发现类型建得出来但设不到 issue 上，命令行与 REST 都不行。类型对象是组织级的，个人账号即使建得出来也用不上。这条记录保留，作为「能读到不等于能用」的例子。该类型未随本流程保留。

### 2.5 Issue 与 Discussion 的分工（C-7、C-8、C-10）

[GitHub 官方文档](https://docs.github.com/en/get-started/using-github/communicating-on-github)把 Issue 定义为项目具体事项的跟踪工具。典型对象包括 Bug、计划改进、任务和对仓库文件的提问。Issue 通常有明确负责人，并进入项目的缺陷跟踪流程。

同一份 GitHub 文档把 [Discussion](https://docs.github.com/en/discussions/collaborating-with-your-community-using-discussions/about-discussions)定义为论坛式交流工具。典型对象包括开放式想法、社区问答、公告、信息分享和需要协作的讨论。Discussion 通常没有明确负责人，也不一定产出可执行任务。

因此，入口先判断目标、范围、负责人和完成条件，再判断对象类型。

| 事项状态 | 入口 |
| --- | --- |
| 可复现的 Bug | Bug issue |
| 一个会话能完成，验收明确 | Standalone Task issue |
| 需要多个 PR 或先改设计，交付目标明确 | Parent Feature，再拆 Task sub-issue |
| 问题明确，但方法、成本、风险或可行性未知 | Parent Feature，再挂 Research sub-issue |
| 方向、范围、优先级或共识未定 | Discussion |

Discussion 形成可执行事项时，创建对应 Issue，并在原帖写链接。Discussion 也可以只形成问答或共识，不产出任务。

Issue 的评论可以继续讨论具体细节。明确事项直接进入 Issue，不要求先建 Discussion。GitHub 的原生 parent 只能是 Issue。存在 Discussion 来源时，Parent Feature 用 `discussion: <URL>` 回链。Parent Feature 在调研前创建，只表示工作容器，不表示已经承诺实施。

截至 2026-10-29，仓库已启用 Discussions，但 Discussion 总数为 0。实际采用情况需要继续观察。

### 2.6 Verify 的层级（C-9）

PR 的 `Visual verification` 和 `Proof` 只覆盖当前 PR。它们不能表达跨多个 Task 的端到端验收，也不能长期保存 Feature 级结果。

本流程因此增加 Verify sub-issue。Verify 与 Task 同级，都是 Parent Feature 的 child。Verify 的完成条件是验收场景通过且证据写回正文。Verify 不要求分支和 PR。

只在以下任一情况创建 Verify。

1. 验收跨越多个 Task 或 PR。
2. 验收需要真机、外接设备、人工交互或不易复现的环境。
3. 验收需要在合并后或发布前再次执行。
4. 证据需要独立保存并长期追踪。

单个 Task 的 UI 和测试证据仍写在 PR。这样避免同一份证据在 Task 与 PR 中重复维护。

## 3. 来源等级

| 等级 | 来源 | 用途 | 置信度 |
| --- | --- | --- | --- |
| A | GitHub 官方文档的 Issues、Discussions 与 issue forms 页面 | 对象分工、表单能力与字段约束 | 高 |
| B | 本仓库的 `gh api` 调用结果 | 本账号的能力边界 | 高，范围限于本账号 |
| E | Reddit 与 Hacker News 的相关讨论 | spike 与 issue 粒度的做法 | 低 |

`C-1` 与 `C-2` 只有 E 级来源。因此本流程把它们写成约定，不写成硬性要求，并把数值留成可调的参数。见流程文件的「参数与来源」。

## 4. 已知缺口

1. spike 的具体数值没有 A 级来源。2 到 3 个工作日是经验值。团队可以按实际情况改。
2. `Parent issue` 与 `Sub-issues progress` 是 Project 的内置字段。两者的名字已核对，读写未实测。
3. 「每周检查」的执行成本没有数据。维护人需要在运行几周后自行评估。
4. 标签是弱约束。issue 建好后忘了加标签，工具不会拦。缓解办法是每周检查时按标签过一遍。
5. 个人账号是否将来会提供 issue types 与 issue fields，未知。若提供，本流程可以用类型替代部分标签。
6. Discussion 当前没有实际内容。团队是否会使用 Discussion 进行开放探索，尚未验证。
7. 当前流程尚未统计 Issue 与 Discussion 的实际分流情况。运行一段时间后，用对象数量和转 Issue 比例复核规则。

## 5. 反证与限制

- 把结论写进 issue 正文而不写评论，代价是正文会变长。本流程接受这个代价，因为评论按时间排列，结论会被后续讨论淹没。
- 文本回链没有强校验。写错编号不会被工具拦住。缓解办法是每周检查第 1 条、第 4 条与第 5 条。
- `decision: pending` 依赖人主动回填。没有自动化手段可以强制。
- Parent Feature 在决策前创建，可能被误解为已经承诺实施。缓解办法是每周检查与表单说明。
- Verify 与 Task 的边界依赖负责人判断。范围过宽时会产生重复验收；范围过窄时会遗漏端到端结果。缓解办法是使用第 2.6 节的四个创建条件。

## 6. 复核方法

1. 重新执行第 2.4 节表中的 `gh api` 调用，核对能力边界是否变化。
2. 打开 GitHub 官方文档的表单 schema 页，核对字段类型与约束。
3. 核对流程文件里的数值与本文件第 2.1 节是否一致。

## 7. 关联文档

- [流程文件](../process/workflow.md)
- [ADR 模板](../adr/adr-template.md)
- [Agent 契约](../../AGENTS.md)
- [GitHub：选择讨论工具](https://docs.github.com/en/get-started/using-github/communicating-on-github)
- [GitHub：About discussions](https://docs.github.com/en/discussions/collaborating-with-your-community-using-discussions/about-discussions)
