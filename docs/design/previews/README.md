# UI 截图

本目录保存需要长期追踪的 UI 证据。
普通 UI 截图优先附在 PR 的 `Visual verification`。
发布候选和长期证据再存入本目录。

Compose Web 打样已由 [ADR-0021](../../adr/adr-0021-deprecate-compose-web-preview.md) 废弃。
旧图继续作为历史证据保留。

## 证据分级

| 改动 | 证据 |
| --- | --- |
| 局部 UI | 受影响模式的一组 Before/After |
| 外观、导航或材质 | 亮色和深色两组 Before/After |
| 发布候选 | 亮色、深色和真机环境 |

## 命名

需要入库的文件使用：

```text
<issue 号>-<页面名>-<状态>-<角色>-<序号>.png
```

角色使用 `current`、`candidate`、`selected`、`before` 或 `after`。
同一场景重截时，序号加一。旧图不删除。

## 注意

截图使用测试数据。
截图遮挡用户名、文件名、通知和其他个人信息。
截图不是发布物。
