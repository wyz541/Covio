# 文件传输验证目录

## 文档状态

| 项目 | 内容 |
| --- | --- |
| 文档版本 | `1.0` |
| 状态 | 尚未执行 |
| 日期 | `2026-11-10` |
| 主文 | [主题索引](../README.md) |
| 证据附录 | [证据附录](../evidence.md) |
| 传输案例 | [传输案例](case-transfer-metadata.md) |
| 移动端案例 | [移动端案例](case-mobile-lifecycle.md) |

## 1. 案例索引

| 案例 | 主题 | 当前状态 | 结果文件 |
| --- | --- | --- | --- |
| Case 1 | 传输、校验和元数据 | 尚未执行 | [case-transfer-metadata.md](case-transfer-metadata.md) |
| Case 2 | iOS 前后台和续传 | 尚未执行 | [case-mobile-lifecycle.md](case-mobile-lifecycle.md) |

本目录只定义验证计划。
本目录不预填验证结果。
验证失败时保留错误码和原因。
验证部分通过时列出通过项和失败项。

## 2. 目标

验证 Rust 核心可以完成二维码配对。
验证发送方和接收方可以完成双向确认。
验证接收方可以看到并接受传输。
验证直连失败后可以回退 relay。
验证大文件可以流式传输。
验证目录可以保留空目录。
验证冲突策略不会破坏已有文件。
验证分块和文件校验。
验证暂存文件可以原子提交。
验证网络断开后可以从检查点恢复。
验证 iOS 后台暂停不会标记失败。
验证前台恢复后可以继续接收或续传。
验证取消不会留下最终半成品。
验证日志不包含文件内容和配对密钥。

## 3. 范围

### 3.1 范围内

- macOS 作为发送方。
- Windows 作为接收方。
- Windows 作为发送方。
- macOS 作为接收方。
- iOS 作为接收方。
- iOS 作为发送方。
- iroh 直连。
- iroh relay 回退。
- 单文件和目录。
- 冲突策略。
- 分块校验。
- 暂存和原子提交。
- 网络中断和恢复。
- iOS 前后台切换。
- 取消和保留策略。
- 日志脱敏。

### 3.2 范围外

- Android 实现。
- 正式发布验收。
- 多用户共享。
- 实时目录同步。
- 符号链接保留。
- 完整 ACL 和 xattr。
- 公网匿名投递。
- 公共 relay 的长期容量测试。
- 法律和合规认证。

## 4. 当前事实

- Covio 尚未实现本协议。
- iroh iOS 构建尚未执行。
- quinn iOS 构建尚未执行。
- Windows 原子替换尚未执行。
- BLAKE3 吞吐尚未测量。
- iOS 真机后台尚未测试。
- Paseo 源码只用于原则参考。
- 本任务没有修改 GitHub Discussion。

## 5. 成功标准

- 接收方明确确认后才发送文件内容。
- 配对确认码在双端一致。
- 设备公钥变化会阻止自动连接。
- 直连失败可以切换到 relay。
- 大文件不使用无界内存。
- 目录中的空目录保留。
- 同名文件按策略处理。
- 符号链接被拒绝或跳过。符号链接不被跟随。
- 路径穿越被拒绝。
- 分块校验失败不会提交最终文件。
- 文件最终校验失败不会提交最终文件。
- 应用重启后可以识别任务。
- 网络恢复后从持久检查点继续。
- iOS 后台状态显示为暂停。
- iOS 前台恢复后重新验活。
- 取消后不出现未完成最终文件。
- 日志不包含文件内容和配对密钥。
- 所有失败有稳定错误码。

## 6. 前置条件

1. macOS 测试机已安装 Covio 测试构建。
2. Windows 测试机已安装 Covio 测试构建。
3. iOS 真机已安装 Covio 测试构建。
4. 三台设备时间已同步。
5. 三台设备已准备测试账户。
6. 测试目录已准备可恢复副本。
7. 测试网络支持直连。
8. 测试网络支持 relay。
9. 测试目标有足够空间。
10. 测试日志已开启脱敏模式。
11. 测试设备已记录型号和系统版本。
12. 测试 commit 已记录。

**警告：** 测试前备份目标目录。替换策略会改变已有文件。测试完成后恢复备份。

## 7. 风险

- 替换策略可能覆盖测试文件。
- 大文件测试可能耗尽磁盘。
- 网络切换可能使测试不稳定。
- relay 可能受外部网络影响。
- iOS 后台时序不可完全控制。
- 强制终止应用可能丢失未同步数据。
- 测试日志可能记录文件路径。
- Windows 符号链接可能触发权限提示。
- 测试设备可能进入睡眠。
- 测试失败可能留下暂存文件。

## 8. 测试矩阵

| 编号 | 场景 | 当前状态 | 结果文件 |
| --- | --- | --- | --- |
| V01 | 二维码配对和六位确认码 | 尚未执行 | `case-transfer-metadata.md` |
| V02 | 配对身份变化阻断 | 尚未执行 | `case-transfer-metadata.md` |
| V03 | 接收方可见接受和拒绝 | 尚未执行 | `case-transfer-metadata.md` |
| V04 | macOS 到 Windows 单文件 | 尚未执行 | `case-transfer-metadata.md` |
| V05 | Windows 到 macOS 目录 | 尚未执行 | `case-transfer-metadata.md` |
| V06 | 直连失败后 relay 回退 | 尚未执行 | `case-transfer-metadata.md` |
| V07 | `10 GiB` 大文件流式传输 | 尚未执行 | `case-transfer-metadata.md` |
| V08 | 冲突 `keep_both` | 尚未执行 | `case-transfer-metadata.md` |
| V09 | 冲突 `replace` 原子提交 | 尚未执行 | `case-transfer-metadata.md` |
| V10 | 分块损坏和重试 | 尚未执行 | `case-transfer-metadata.md` |
| V11 | 路径穿越和符号链接拒绝 | 尚未执行 | `case-transfer-metadata.md` |
| V12 | 网络断开后检查点续传 | 尚未执行 | `case-transfer-metadata.md` |
| V13 | 磁盘空间不足暂停和恢复 | 尚未执行 | `case-transfer-metadata.md` |
| V14 | 应用崩溃后任务恢复 | 尚未执行 | `case-transfer-metadata.md` |
| V15 | 用户取消和暂存清理 | 尚未执行 | `case-transfer-metadata.md` |
| V16 | 离线队列和源文件变化 | 尚未执行 | `case-transfer-metadata.md` |
| V17 | iOS 后台暂停 | 尚未执行 | `case-mobile-lifecycle.md` |
| V18 | iOS 前台验活和恢复 | 尚未执行 | `case-mobile-lifecycle.md` |
| V19 | iOS 后台收到新请求 | 尚未执行 | `case-mobile-lifecycle.md` |
| V20 | iOS 取消和重启恢复 | 尚未执行 | `case-mobile-lifecycle.md` |

## 9. 证据要求

每个测试记录以下内容。

- 日期和时间。
- 测试 commit。
- 设备型号。
- 操作系统版本。
- 应用版本。
- 网络拓扑。
- 使用的传输路径。
- 原始任务的摘要。
- 文件数量和总字节。
- 分块大小和窗口大小。
- 开始状态和结束状态。
- 错误码。
- 校验摘要。
- 清理结果。
- Before 和 After 的文件清单。

日志证据必须脱敏。
证据不能包含配对密钥。
证据不能包含完整用户文件内容。
证据不能包含设备序列号。

## 10. 清理步骤

1. 取消所有未完成任务。
2. 删除测试暂存目录。
3. 恢复被替换的测试文件。
4. 删除测试配对设备。
5. 删除测试日志中的敏感副本。
6. 恢复网络配置。
7. 恢复电源和睡眠设置。
8. 检查目标目录无未完成文件。
9. 记录清理结果。
10. 关闭测试应用。

## 11. 关联文档

- [主题索引](../README.md)
- [问题边界](../context.md)
- [调研分析](../investigation.md)
- [结论](../conclusion.md)
- [推荐方案](../solution.md)
- [证据附录](../evidence.md)
- [传输案例](case-transfer-metadata.md)
- [移动端案例](case-mobile-lifecycle.md)
