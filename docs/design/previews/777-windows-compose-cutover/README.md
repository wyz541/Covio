# Windows Compose cutover evidence

- 日期：2026-11-15
- Issue：[#777](https://github.com/wyz541/Covio/issues/777)
- Commit：`ae0b1d5052095a5e66e36f080d7b72cf82baef30`
- CI：[run 43723067184](https://github.com/wyz541/Covio/actions/runs/43723067184)
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
| Cold start | `4366 ms` | `3000 ms P95` | 未通过 |
| Frame average | `20.06 ms` | 记录项 | 记录 |
| Frame P95 | `32.37 ms` | `16.7 ms` | 未通过 |
| Working set | `284590080 B` | `250 MiB` | 未通过 |
| Portable ZIP | `87960308 B` | `200 MiB` | 通过 |

该基线来自 hosted runner。物理 Windows 11 设备证据和正式阈值批准仍未完成。
