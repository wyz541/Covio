# Compose 与 Rust bridge 验证计划

## 1. 文档状态

| 项目 | 内容 |
| --- | --- |
| 文档版本 | `1.0` |
| 状态 | 初稿，可评审 |
| 日期 | `2026-11-10` |
| 验证状态 | 尚未执行 |
| 主题索引 | [README.md](../README.md) |
| 证据附录 | [evidence.md](../evidence.md) |

本文件定义验证目标、范围、矩阵、风险和清理要求。
实际执行记录写入 [case-windows-compose-jni.md](case-windows-compose-jni.md)。

## 2. 案例索引

| 案例 | 范围 | 状态 | 结果文件 |
| --- | --- | --- | --- |
| `Case 1` | Windows Compose + JNI vertical slice | 尚未执行 | [case-windows-compose-jni.md](case-windows-compose-jni.md) |

## 3. 验证目标

确认 Windows Compose host 可以加载 Rust JNI 库。
确认 C ABI 与 JNI 使用同一 bridge 合同。
确认设计合同可以生成 Kotlin 和 Swift 产物。
确认 Windows 原生能力可以通过平台 adapter 使用。
确认 MSI 和便携 ZIP 可以从 GitHub Releases 内部测试渠道安装。
确认 egui 回滚路径可执行。

关联证据：
- Compose 平台与打包：`E-01` 至 `E-12`。
- JNI 与 UniFFI：`E-13` 至 `E-17`。
- 当前源码：`E-18` 至 `E-22`。
- 字体与 Windows 能力：`E-23` 至 `E-25`。
- 后台与 Android：`E-26`、`E-27`。

## 4. 范围内事项

1. Windows 11 x64。
2. Compose Multiplatform desktop。
3. JVM runtime。
4. JNI 动态库加载。
5. C ABI 与 JNI fixture。
6. 设计令牌、文案和语义。
7. Windows Share Sheet 发送。
8. Windows 文件选择器。
9. Windows toast 通知。
10. 托盘、全局热键和顶部边缘触发。
11. Java Access Bridge。
12. MSI、便携 ZIP 和 SHA-256。
13. egui 回滚。
14. 设计合同字体和平台映射评审。

## 5. 范围外事项

1. macOS 产品验收。
2. iOS 产品验收。
3. Android 第一版交付。
4. Windows Share Target。
5. Windows arm64。
6. 正式代码签名和公证。
7. 正式自动更新。
8. 云账号和云内容存储。
9. 文件传输协议和加密握手。
10. 正式商店发布。

## 6. 当前事实

1. Compose Multiplatform `1.12.2` 是当前稳定 release（`E-02`）。
2. Windows 支持 MSI 和 EXE（`E-05`）。
3. Windows package version 使用三字段数字（`E-06`）。
4. `jpackage` 需要目标平台构建和 WiX（`E-07`）。
5. Compose 在 Windows 暴露 HWND（`E-08`）。
6. Windows Compose 无障碍依赖 JAB（`E-09`）。
7. 默认 UniFFI Kotlin 依赖 JNA（`E-13`）。
8. 实验性 UniFFI JNI backend 未稳定（`E-14`）。
9. 当前 C header 已出现漂移（`E-19`）。
10. 当前设计合同没有 Kotlin 输出（`E-22`）。
11. Windows Share 发送路径支持 unpackaged app（`E-25`）。
12. 当前环境没有 Kotlin 和 Gradle。原型尚未执行。

## 7. 成功标准

1. Windows 11 x64 干净机器可以安装 MSI。
2. 安装后的 Compose host 自动加载 Rust DLL。
3. Kotlin 不依赖 JNA。
4. C ABI 与 JNI 通过同一 fixture。
5. stale handle 和 stale generation 不崩溃。
6. panic 不终止进程。
7. 取消返回 `cancelled`。
8. 事件 sequence 单调递增。
9. 大文件内容不进入控制 JSON。
10. 设计令牌和文案与合同一致。
11. 六个代表页面通过亮色、深色和缩放验收。
12. JAWS 或 NVDA 可以操作主要控件。
13. Share Sheet 可以从 Compose 窗口打开。
14. 文件选择结果可以被 Rust 读取。
15. 通知点击可以回到正确页面。
16. 托盘、hotkey 和顶部边缘触发可用。
17. MSI、ZIP 和 SHA-256 可以从 GitHub pre-release 下载。
18. egui 回滚包可以安装并读取同一数据。

## 8. 前置条件

1. Windows 11 x64 测试机。
2. 管理员权限仅用于安装和卸载测试。
3. JDK 17 或更高版本。
4. WiX 3.0 或更高版本。
5. Compose Multiplatform 固定版本。
6. Rust 稳定工具链。
7. 测试用 Rust DLL。
8. 测试用 MSI 和便携 ZIP。
9. 测试用 GitHub draft 或 pre-release。
10. 六个代表页面的设计基线。
11. JAWS 或 NVDA。
12. Windows 100%、125%、150% 和 200% 缩放环境。
13. egui 回滚包。
14. 无敏感数据的测试文件和文件夹。

## 9. 风险

| 风险 | 影响 | 缓解 |
| --- | --- | --- |
| JVM 启动慢 | 体验失败 | 记录 P95；与 egui 基线比较 |
| JVM 内存高 | 常驻失败 | 记录工作集；设置门槛 |
| DLL 加载失败 | 应用不可用 | 检查 `compose.application.resources.dir` |
| JAB 未启用 | 无障碍失败 | 打包 `jdk.accessibility` |
| Share HWND 失效 | 分享失败 | 在窗口创建后取得 `windowHandle` |
| 托盘行为不同 | 入口缺失 | 建立 adapter 原型 |
| 顶部边缘触发不同 | 交互回归 | 保留 egui 回滚 |
| MSI 版本不合法 | 构建失败 | 映射为 `MAJOR.MINOR.BUILD` |
| 资产过大 | 发布失败 | 记录实际大小；`jlink` 裁剪 |
| 未签名安装包 | SmartScreen 提示 | 内测说明；暂缓正式发布 |
| 回滚读取失败 | 数据风险 | 保持数据格式兼容；备份 |
| Android 16 KB 对齐 | 后续设备崩溃 | 后续检查 `.so` |

## 10. 测试矩阵

| 编号 | 场景 | 当前状态 | 结果文件 |
| --- | --- | --- | --- |
| `V01` | Windows Compose host 启动 | 尚未执行 | [case-windows-compose-jni.md](case-windows-compose-jni.md) |
| `V02` | Rust DLL 加载和 ABI 信息 | 尚未执行 | [case-windows-compose-jni.md](case-windows-compose-jni.md) |
| `V03` | C ABI 与 JNI 同 fixture | 尚未执行 | [case-windows-compose-jni.md](case-windows-compose-jni.md) |
| `V04` | stale handle 和 stale generation | 尚未执行 | [case-windows-compose-jni.md](case-windows-compose-jni.md) |
| `V05` | 取消、deadline 和 backpressure | 尚未执行 | [case-windows-compose-jni.md](case-windows-compose-jni.md) |
| `V06` | panic containment | 尚未执行 | [case-windows-compose-jni.md](case-windows-compose-jni.md) |
| `V07` | 文件选择器与内容租约 | 尚未执行 | [case-windows-compose-jni.md](case-windows-compose-jni.md) |
| `V08` | Share Sheet 与 HWND | 尚未执行 | [case-windows-compose-jni.md](case-windows-compose-jni.md) |
| `V09` | 通知发送和点击激活 | 尚未执行 | [case-windows-compose-jni.md](case-windows-compose-jni.md) |
| `V10` | 托盘、hotkey 和顶部边缘 | 尚未执行 | [case-windows-compose-jni.md](case-windows-compose-jni.md) |
| `V11` | JAB、JAWS 和 NVDA | 尚未执行 | [case-windows-compose-jni.md](case-windows-compose-jni.md) |
| `V12` | 六页面视觉与缩放 | 尚未执行 | [case-windows-compose-jni.md](case-windows-compose-jni.md) |
| `V13` | 冷启动、内存和帧时间 | 尚未执行 | [case-windows-compose-jni.md](case-windows-compose-jni.md) |
| `V14` | MSI、ZIP 和 SHA-256 | 尚未执行 | [case-windows-compose-jni.md](case-windows-compose-jni.md) |
| `V15` | egui 回滚 | 尚未执行 | [case-windows-compose-jni.md](case-windows-compose-jni.md) |
| `V16` | Android 16 KB 对齐 | 尚未执行 | [case-windows-compose-jni.md](case-windows-compose-jni.md) |

## 11. 证据要求

1. 记录日期、设备、Windows build、commit、JDK 和 Compose 版本。
2. 记录 MSI 和 ZIP 的 SHA-256。
3. 记录安装、升级、卸载和回滚结果。
4. 记录冷启动的采样次数和 P95。
5. 记录空闲工作集采样时间。
6. 记录帧时间和输入延迟采样方法。
7. 记录 Share Sheet 的窗口状态和结果。
8. 记录通知点击后的页面。
9. 记录 JAWS 或 NVDA 版本。
10. 记录缩放、主题和截图路径。
11. 记录失败错误码和复现步骤。
12. 不记录凭据值、文件内容或完整隐私信息。

## 12. 清理步骤

1. 卸载测试 MSI。
2. 删除测试 ZIP。
3. 恢复测试前系统缩放。
4. 恢复测试前主题和高对比度设置。
5. 恢复 JAB 设置。
6. 删除测试文件和文件夹。
7. 删除测试通知。
8. 删除测试应用数据。先备份再删除。
9. 关闭测试进程。
10. 恢复 egui 回滚环境。
11. 记录清理时间和结果。

## 13. 关联文档

- [主题索引](../README.md)
- [上下文](../context.md)
- [调研分析](../investigation.md)
- [结论](../conclusion.md)
- [方案](../solution.md)
- [证据](../evidence.md)
- [Case 1](case-windows-compose-jni.md)