# Case 1：Windows Compose + JNI vertical slice

## 文档状态

| 项目 | 内容 |
| --- | --- |
| 案例编号 | `Case 1` |
| 状态 | 尚未执行 |
| 覆盖测试 | `V01` 至 `V10` |
| 日期 | 待填写 |
| 执行人 | 待填写 |
| 复核人 | 待填写 |

本文件不预填实验结果。
执行后由执行人回填时间、命令和输出摘要。
本案例使用无敏感数据的测试文件和文件夹。

## 1. 验证目标

确认 Windows Compose host 可以启动。
确认 Windows host 可以加载 Rust JNI 动态库。
确认 JNI 和 C ABI 使用同一 bridge 合同。
确认文件选择、Share Sheet、通知、托盘和顶部边缘触发可用。
确认 MSI 和便携 ZIP 可以安装和启动。
确认 egui 回滚路径仍然可用。

关联证据：`E-05` 至 `E-09`、`E-13` 至 `E-25`。
关联方案： [solution.md](../solution.md) 第 6、11、14、15 节。
关联验证计划： [validation/README.md](README.md)。

## 2. 预检记录

| 项目 | 值 |
| --- | --- |
| Windows 版本和 build | 待填写 |
| CPU 架构 | 待填写 |
| 测试机类型 | 待填写 |
| JDK 版本和 vendor | 待填写 |
| Compose Multiplatform 版本 | 待填写 |
| Compose Gradle plugin 版本 | 待填写 |
| Rust 版本 | 待填写 |
| WiX 版本 | 待填写 |
| commit | 待填写 |
| MSI 路径 | 待填写 |
| ZIP 路径 | 待填写 |
| egui 回滚包路径 | 待填写 |
| 缩放 | 待填写 |
| 主题 | 待填写 |

## 3. 测试前采集

1. 记录 `git rev-parse HEAD`。
2. 记录工作树状态。
3. 记录 JDK、Rust 和 WiX 版本。
4. 记录 MSI 和 ZIP 的 SHA-256。
5. 记录 egui 基线的冷启动、内存和包大小。
6. 备份测试应用数据目录。
7. 准备一个 100 MB 文件、一个 1 GB 文件和一个目录样本。
8. 记录测试前 JAB 状态。
9. 记录测试前系统缩放和主题。

命令模板：

```powershell
git rev-parse HEAD
git status --short
java -version
rustc --version
cargo --version
Get-FileHash <MSI_PATH> -Algorithm SHA256
Get-FileHash <ZIP_PATH> -Algorithm SHA256
```

## 4. V01：Compose host 启动

### 4.1 前置条件

1. 测试机安装 Windows 11 x64。
2. 测试机没有全局 JDK 依赖。
3. MSI 已生成。
4. 测试数据目录已备份。

### 4.2 命令或请求

```powershell
msiexec /i <MSI_PATH> /qn /norestart
Start-Process "<INSTALLED_COVIO_EXE>"
Get-Process Covio | Select-Object Id,WorkingSet64,CPU
```

### 4.3 预期结果

1. MSI 安装成功。
2. Covio 进程启动。
3. Compose 窗口出现。
4. 应用不要求用户安装 JDK。
5. 启动日志没有 JNI 加载错误。

### 4.4 实际结果

| 项目 | 值 |
| --- | --- |
| MSI 安装结果 | 待填写 |
| 进程是否启动 | 待填写 |
| Compose 窗口是否出现 | 待填写 |
| 是否依赖全局 JDK | 待填写 |
| 判定 | 待填写 |

### 4.5 错误码

待填写。无错误时写 `无`。

## 5. V02：Rust DLL 加载和 ABI 信息

### 5.1 前置条件

1. V01 已完成。
2. Rust DLL 已随安装包部署。
3. 应用可以读取 ABI 信息。

### 5.2 命令或请求

```text
从 Compose 调试页面读取 ABI info
记录 abi_major、abi_minor、protocol_major、protocol_minor 和 build_id
记录 DLL 的实际加载路径
```

### 5.3 预期结果

1. Kotlin 成功加载 Rust DLL。
2. `abi_major` 为 `1`。
3. `protocol_major` 为 `1`。
4. `struct_size` 与 header 一致。
5. 不出现 JNA。
6. 不出现手工 DLL 复制。

### 5.4 实际结果

| 项目 | 值 |
| --- | --- |
| DLL 路径 | 待填写 |
| `abi_major` | 待填写 |
| `abi_minor` | 待填写 |
| `protocol_major` | 待填写 |
| `protocol_minor` | 待填写 |
| `build_id` | 待填写 |
| 是否依赖 JNA | 待填写 |
| 判定 | 待填写 |

### 5.5 错误码

待填写。无错误时写 `无`。

## 6. V03：C ABI 与 JNI 同 fixture

### 6.1 前置条件

1. bridge fixture 已建立。
2. C ABI 测试 harness 已建立。
3. JNI 测试 harness 已建立。
4. 两个 harness 使用同一 JSON fixture。

### 6.2 命令或请求

```powershell
cargo test -p covio-bridge -p covio-ffi
<JNI_FIXTURE_TEST_COMMAND>
```

### 6.3 预期结果

1. 同一请求产生同一业务结果。
2. 同一错误产生同一错误码。
3. 响应 request ID 一致。
4. generation 一致。
5. 事件 sequence 单调。
6. 大文件内容不进入控制消息。

### 6.4 实际结果

| 项目 | 值 |
| --- | --- |
| C ABI fixture | 待填写 |
| JNI fixture | 待填写 |
| 业务结果是否一致 | 待填写 |
| 错误码是否一致 | 待填写 |
| 事件顺序 | 待填写 |
| 判定 | 待填写 |

### 6.5 错误码

待填写。无错误时写 `无`。

## 7. V04：Stale handle 和 stale generation

### 7.1 前置条件

1. V02 已完成。
2. 测试 harness 可以重建 session。

### 7.2 命令或请求

```text
使用旧 handle 调用 submit
使用旧 generation 调用 submit
关闭 session 后再调用 submit
```

### 7.3 预期结果

1. 旧 handle 返回 `invalid_handle`。
2. 旧 generation 返回 `stale_generation`。
3. 进程不崩溃。
4. UI 要求重建 session。

### 7.4 实际结果

| 请求 | 错误码 | 进程状态 | 判定 |
| --- | --- | --- | --- |
| 旧 handle | 待填写 | 待填写 | 待填写 |
| 旧 generation | 待填写 | 待填写 | 待填写 |
| 关闭后 handle | 待填写 | 待填写 | 待填写 |

### 7.5 错误码

待填写。无错误时写 `无`。

## 8. V05：取消、deadline 和 backpressure

### 8.1 前置条件

1. 测试传输可以暂停。
2. 测试请求有 request ID。
3. 测试 harness 可以触发超时和队列压力。

### 8.2 命令或请求

```text
提交一个长任务，然后调用 cancel
提交一个 timeoutMs 很小的请求
连续提交超过上限的请求
```

### 8.3 预期结果

1. 取消返回 `cancelled`。
2. 超时返回 `deadline_exceeded`。
3. 队列满返回 `backpressure`。
4. 进程不崩溃。
5. 取消后恢复点仍可读。

### 8.4 实际结果

| 场景 | 结果 | 错误码 | 判定 |
| --- | --- | --- | --- |
| 取消 | 待填写 | 待填写 | 待填写 |
| deadline | 待填写 | 待填写 | 待填写 |
| backpressure | 待填写 | 待填写 | 待填写 |

### 8.5 错误码

待填写。无错误时写 `无`。

## 9. V06：Panic containment

### 9.1 前置条件

1. 测试构建提供受控 panic 注入。
2. 测试构建不包含生产数据。
3. 测试进程可以重启。

### 9.2 命令或请求

```text
调用受控 panic fixture
记录 C ABI 和 JNI 的返回结果
记录进程状态
```

### 9.3 预期结果

1. 返回 `internal_panic`。
2. 进程不崩溃。
3. 错误消息不含敏感信息。
4. session 标记为不可继续使用。
5. UI 可以重建 session。

### 9.4 实际结果

| 项目 | 值 |
| --- | --- |
| C ABI 返回 | 待填写 |
| JNI 返回 | 待填写 |
| 进程状态 | 待填写 |
| session 是否重建 | 待填写 |
| 判定 | 待填写 |

### 9.5 错误码

待填写。无错误时写 `无`。

## 10. V07：文件选择器与内容租约

### 10.1 前置条件

1. 应用已启动。
2. 测试文件已准备。
3. 文件不含敏感信息。

### 10.2 命令或请求

```text
在 Compose 页面点击选择文件
选择 100 MB 测试文件
返回内容租约
让 Rust 读取首个分块和最后一个分块
```

### 10.3 预期结果

1. 文件选择器打开。
2. 选择结果生成内容租约。
3. Rust 可以读取文件。
4. 文件内容不进入桥接 JSON。
5. 租约释放后不能继续读取。

### 10.4 实际结果

| 项目 | 值 |
| --- | --- |
| 选择器是否打开 | 待填写 |
| 租约是否生成 | 待填写 |
| Rust 是否读取成功 | 待填写 |
| 是否出现文件内容 JSON | 待填写 |
| 判定 | 待填写 |

### 10.5 错误码

待填写。无错误时写 `无`。

## 11. V08：Share Sheet 与 HWND

### 11.1 前置条件

1. Compose 窗口已创建。
2. 窗口处于可见状态。
3. 测试文件已选择。
4. 应用可能运行在 unpackaged MSI 环境。

### 11.2 命令或请求

```text
从 Compose 页面点击分享
记录 windowHandle
记录 Share Sheet 是否打开
选择取消和完成两种路径
```

### 11.3 预期结果

1. `windowHandle` 返回非零 HWND。
2. Windows Share Sheet 打开。
3. 用户取消返回 `cancelled`。
4. 完成返回 `ok`。
5. 应用不崩溃。

### 11.4 实际结果

| 项目 | 值 |
| --- | --- |
| HWND | 待填写 |
| Share Sheet 是否打开 | 待填写 |
| 取消结果 | 待填写 |
| 完成结果 | 待填写 |
| 判定 | 待填写 |

### 11.5 错误码

待填写。无错误时写 `无`。

## 12. V09：通知发送和点击激活

### 12.1 前置条件

1. 应用已注册通知。
2. 测试通知标题和正文已准备。
3. 应用可以记录激活参数。

### 12.2 命令或请求

```text
发送测试通知
点击通知
记录应用是否回到前台
记录目标页面
```

### 12.3 预期结果

1. 通知出现在 Windows 通知中心。
2. 点击通知启动或激活应用。
3. 应用打开正确页面。
4. 通知正文不含敏感信息。

### 12.4 实际结果

| 项目 | 值 |
| --- | --- |
| 通知是否显示 | 待填写 |
| 点击是否激活 | 待填写 |
| 目标页面 | 待填写 |
| 判定 | 待填写 |

### 12.5 错误码

待填写。无错误时写 `无`。

## 13. V10：托盘、hotkey 和顶部边缘

### 13.1 前置条件

1. 应用已启动。
2. 应用窗口已显示。
3. 托盘区域可用。

### 13.2 命令或请求

```text
隐藏窗口
从托盘恢复窗口
按全局 hotkey
把鼠标移到屏幕顶部边缘
记录显示、隐藏和焦点状态
```

### 13.3 预期结果

1. 托盘可以显示和隐藏 Hub。
2. 全局 hotkey 可以切换 Hub。
3. 顶部边缘可以触发 Hub。
4. 窗口保持置顶语义。
5. 应用不出现在任务栏。若无法实现，记录为失败。

### 13.4 实际结果

| 项目 | 值 |
| --- | --- |
| 托盘 | 待填写 |
| hotkey | 待填写 |
| 顶部边缘 | 待填写 |
| 任务栏隐藏 | 待填写 |
| 判定 | 待填写 |

### 13.5 错误码

待填写。无错误时写 `无`。

## 14. 结果汇总

| 测试 | 状态 | 通过项 | 失败项 |
| --- | --- | --- | --- |
| `V01` | 尚未执行 | 待填写 | 待填写 |
| `V02` | 尚未执行 | 待填写 | 待填写 |
| `V03` | 尚未执行 | 待填写 | 待填写 |
| `V04` | 尚未执行 | 待填写 | 待填写 |
| `V05` | 尚未执行 | 待填写 | 待填写 |
| `V06` | 尚未执行 | 待填写 | 待填写 |
| `V07` | 尚未执行 | 待填写 | 待填写 |
| `V08` | 尚未执行 | 待填写 | 待填写 |
| `V09` | 尚未执行 | 待填写 | 待填写 |
| `V10` | 尚未执行 | 待填写 | 待填写 |

## 15. 清理记录

| 项目 | 值 |
| --- | --- |
| 删除的测试文件 | 待填写 |
| 删除的测试文件夹 | 待填写 |
| 卸载的 MSI | 待填写 |
| 恢复的缩放 | 待填写 |
| 恢复的主题 | 待填写 |
| 恢复的 JAB 设置 | 待填写 |
| 清理时间 | 待填写 |

## 16. 更新规则

1. 执行后把状态改为 `通过`、`部分通过` 或 `失败`。
2. 状态变化同步到 [validation/README.md](README.md) 的测试矩阵。
3. 新观察回填到 [evidence.md](../evidence.md)。
4. 反证回填到 [evidence.md](../evidence.md) 的反证章节。
5. 结论变化时更新 [conclusion.md](../conclusion.md)。
6. 方案变化时更新 [solution.md](../solution.md)。

## 17. 关联文档

- [主题索引](../README.md)
- [验证目录](README.md)
- [证据附录](../evidence.md)
- [方案](../solution.md)