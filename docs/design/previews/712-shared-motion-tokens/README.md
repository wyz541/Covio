# #712 共享动效参数

## 验证信息

- 日期：2026-11-09。
- 系统：Windows 11 Enterprise `10.0.26200`，x64。
- 截图：无。本 Issue 不改变视觉结果。
- 权威来源：`docs/covio-design-contract.json`。

## 参数映射

| 合同令牌 | Rust 常量 | Windows 用途 | 值 |
| --- | --- | --- | --- |
| `token/motion/hub-expand` | `HUB_EXPAND` | Workbench 展开 | 250 ms |
| `token/motion/hub-collapse` | `HUB_COLLAPSE` | Workbench 收回 | 190 ms |
| `token/motion/reduced-motion` | `REDUCED_MOTION` | 减少动态效果 | 120 ms |
| `token/motion/pointer-exit-collapse` | `POINTER_EXIT_COLLAPSE` | 指针移出等待 | 500 ms |

## 生成链路

1. 设计合同保存动效参数。
2. `scripts/generate-contract-constants.py` 读取合同。
3. 脚本生成 Swift 的 `ContractTokens.swift`。
4. 脚本生成 Rust 的 `contract_motion.rs`。
5. Windows 从 `covio_core::contract_motion` 读取常量。

## 自动验证

- `python3 -I scripts/generate-contract-constants.py --check` 通过。
- 生成文件包含 11 个动效令牌。
- Rust 测试逐项比对合同与生成常量。
- Windows 不再定义 Workbench 动画时长。
- 现有 Windows 动画行为保持不变。

## 验收结果

- macOS 和 Windows 使用同一合同参数。
- 修改合同后，重跑生成器会同时更新 Swift 与 Rust。
- CI 会拒绝过期的生成文件。
