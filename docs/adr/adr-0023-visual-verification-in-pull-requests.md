# ADR-0023：把 Visual verification 放到 PR

- Status：superseded
- Kind：process
- Date：2026-10-28
- Supersedes：none
- Superseded by：ADR-0028
- Implements：#442
- 相关：ADR-0021

## 背景

旧流程要求 UI issue 在正文放亮色和深色两组 Before/After。
UI 代码变更的 After 截图只能在实现后生成。
Issue 阶段要求截图会产生三个问题：

1. 作者可能在实现前制作与最终代码不一致的截图。
2. 作者可能为了填 issue 提前实现，打乱 issue 与 PR 的边界。
3. 开发者会在错误的对象中核对视觉证据。

Issue 负责定义问题与预期。
PR 负责代码、测试、真机截图和交付验收。

## 决策

1. UI issue 写目标、范围、表现预期和可判定验收标准。
2. UI issue 不要求 `Visual verification`。
3. UI 决策可以在 issue 的 `预览` 段提供候选方案。
4. 候选方案不等于真机验收。
5. UI 代码变更完成后，PR 必须提供 `Visual verification`。
6. PR 使用同一页面、同一状态的亮色和深色 Before/After 表。
7. PR 使用固定 commit 的 GitHub 图片地址。截图文件仍放 `docs/design/previews/`。
8. PR 记录截图来源、日期、设备型号、系统版本、页面、状态和 commit。
9. UI 代码 PR 缺少截图或图片链接失效时，不得转入 ready 或合并。
10. 不涉及 UI 的 PR 在 `Visual verification` 段写“不适用”。

ADR-0021 关于废弃 Compose Web 打样的决定继续有效。
本 ADR 只改变 `Visual verification` 的承载对象。

## 后果

### 正面

- Issue 和 PR 各自承载一个阶段。
- After 截图来自实际实现。
- 评审人在代码、测试和截图所在的对象中完成验收。
- Issue 模板不再要求无法提前产生的证据。

### 负面

- UI 改动需要维护 Issue、PR 两个正文。
- PR 模板增加一个必填验收段。
- 旧 issue 中的截图位置与新规则不同。

### 风险

- PR 作者可能漏填真机证据。缓解：PR 模板明确列出该段，缺少证据时不得 ready。
- 截图可能来自旧 commit。缓解：PR 证据记录 commit，并使用固定 commit URL。
- 规则可能再次漂移。缓解：AGENTS、工作流、Issue 模板、PR 模板、截图说明和 Covio issue/PR 技能同步更新。

## 备选方案

### 备选 1：继续在 Issue 放 Before/After

未采纳。After 截图只能在实现后产生。
Issue 阶段的 After 不是实际交付结果。

### 备选 2：Issue 放 Before，PR 放 After

未采纳。Before/After 会被拆到两个对象。
评审人无法在同一个上下文中比较截图。

### 备选 3：只在 PR 放 Visual verification

采纳。PR 同时承载代码、测试和真机证据。

## 未决事项

| 项目 | 状态 | 确认方法 |
| --- | --- | --- |
| 历史 issue 的截图是否迁移 | out of scope | 保留历史记录，不批量改写 |

## 参考

- [Issue #442](https://github.com/wyz541/kmp-Covio/issues/442)
- [ADR-0021：废弃 Compose Web 打样路径](adr-0021-deprecate-compose-web-preview.md)
