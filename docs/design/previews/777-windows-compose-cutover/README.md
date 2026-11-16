# Windows Compose cutover evidence

- 日期：2026-11-16
- Issue：[#777](https://github.com/wyz541/Covio/issues/777)
- Commit：`6341177`
- CI：[run 43819268998](https://github.com/wyz541/Covio/actions/runs/43819268998)
- 环境：GitHub 托管 Windows Server 2025 x64 runner

## 截图

| 页面 | 主题 | 文件 |
| --- | --- | --- |
| Devices | light | `devices-light-candidate-1.png` |
| Devices | dark | `devices-dark-candidate-1.png` |
| Pair | light | `pairing-light-candidate-1.png` |
| Pair | dark | `pairing-dark-candidate-1.png` |

截图使用测试设备。PNG 尺寸为 `1044 x 788`。

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
