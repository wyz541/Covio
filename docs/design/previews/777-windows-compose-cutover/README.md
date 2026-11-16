# Windows Compose cutover evidence

- 日期：2026-11-16
- Issue：[#777](https://github.com/wyz541/Covio/issues/777)
- Commit：`6341177`
- CI：[run 43819268998](https://github.com/wyz541/Covio/actions/runs/43819268998)
- 环境：GitHub 托管 Windows Server 2025 x64 runner

## Hosted 截图

| 页面 | 主题 | 文件 |
| --- | --- | --- |
| Devices | light | `devices-light-candidate-1.png` |
| Devices | dark | `devices-dark-candidate-1.png` |
| Pair | light | `pairing-light-candidate-1.png` |
| Pair | dark | `pairing-dark-candidate-1.png` |

截图使用测试设备。PNG 尺寸为 `1044 x 788`。

## Windows 11 offscreen render

- 环境：Windows 11 Enterprise `10.0.26200` x64，locale `zh-CN`
- 方法：`ImageComposeScene` 离屏 render，`Density(1f)`，`1180 x 820`
- PNG：`1180 x 820`
- 范围：Devices、Pair、Send、Receive 四个页面，亮色和深色两个主题

| 页面 | 主题 | 文件 |
| --- | --- | --- |
| Devices | light | `devices-light-windows11-offscreen.png` |
| Devices | dark | `devices-dark-windows11-offscreen.png` |
| Pair | light | `pair-light-windows11-offscreen.png` |
| Pair | dark | `pair-dark-windows11-offscreen.png` |
| Send | light | `send-light-windows11-offscreen.png` |
| Send | dark | `send-dark-windows11-offscreen.png` |
| Receive | light | `receive-light-windows11-offscreen.png` |
| Receive | dark | `receive-dark-windows11-offscreen.png` |

这些图片证明 Compose layout 和 theme render。
这些图片不证明窗口 chrome、桌面屏幕捕获、真实 UIA 或 screen reader 行为。

## 性能记录

| 指标 | Compose 中位数 | 研究门槛 | 结果 |
| --- | ---: | ---: | --- |
| Cold start | `1813 ms` | `3000 ms P95` | 通过 |
| Frame average | `15.66 ms` | 记录项 | 记录 |
| Frame P95 | `16.18 ms` | `16.7 ms` | 通过 |
| Working set | `165031936 B` | `250 MiB` | 通过 |
| Portable ZIP | `87975012 B` | `200 MiB` | 通过 |

Compose host 使用 Skiko software renderer。
Hosted runner 的报告刷新率为 `64 Hz`，对应帧预算 `15.62 ms`。
全部记录指标通过研究门槛。
物理 Windows 11 设备证据、键盘与焦点评审和正式阈值批准仍未完成。
