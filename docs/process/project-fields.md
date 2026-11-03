# Project 字段

[Project 8「Covio」](https://github.com/users/wyz541/projects/8)是字段的唯一来源。

```text
gh project field-list 8 --owner wyz541
```

读取字段需要 `read:project` 权限。
设置字段或添加条目需要 `project` 权限。
自动加入已开启，筛选条件是 `repo:wyz541/kmp-Covio is:issue`。

## 常规字段

| 名称 | 类型 | 用途 |
| --- | --- | --- |
| `Status` | 单选 | 全部 Issue，随状态更新 |
| `Priority` | 单选 | Feature，取值 `P0`、`P1`、`P2` |
| `Target date` | 日期 | 活跃 Feature |

`Parent issue`、`Sub-issues progress` 和 linked PR 使用 GitHub 原生字段。
不要维护第二份进度表。

## 历史字段

`Size`、`Start date` 和 `Estimate` 保留已有值。
新 Issue 不要求填写这些字段。
不批量删除历史值。
需要清理时，先单独确认数据影响。

## 检查

使用 Project 保存视图或自动化检查。
不维护人工周检清单。

- Research 超过截止日期。
- Feature 超过 Target date。
- Verify 存在未解除的阻塞。

## 相关

- [研发工作流](workflow.md)
- [Agent 契约](../../AGENTS.md)
