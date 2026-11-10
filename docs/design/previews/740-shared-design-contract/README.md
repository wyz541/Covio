# Issue 740 共享设计合同视觉证据

## 验证信息

- 日期：`2026-11-10`。
- 设备：Windows x64 开发工作站。
- 系统：Windows 11 25H2，build `26200.9711`。
- UI 缩放：`1.5`。
- 页面：Workspace。
- 状态：已写入种子工作区数据。
- 实现 commit：`e670315`。
- 改动：Windows 界面字体改用 Segoe UI Variable。字体不可用时回退到 Segoe UI。

## 验收 ID

- `acceptance/visual/platform-font-mapping`
- `acceptance/visual/typography-hierarchy`

## 结果

字体改动保留文档中的文字层级。
语义令牌保留浅色和深色界面的表面层级。

## 改动后

| 浅色 | 深色 |
| --- | --- |
| [after-workbench-light.png](after-workbench-light.png) | [after-workbench-dark.png](after-workbench-dark.png) |

## 历史对照

以下历史截图来自 [#608](../608-windows-product-workspace-light-current-1.png) 的 Workspace 页面。
历史截图早于本轮字体和排版合同迁移。因此历史截图只作参考，不是同一 commit 的受控 Before。

- [历史浅色截图](../608-windows-product-workspace-light-current-1.png)
- [历史深色截图](../608-windows-product-workspace-dark-current-1.png)

## 命令

```sh
bash scripts/test-windows-rust.sh
```

Windows 主机测试生成了两张改动后截图。
