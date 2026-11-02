# CovioHelper 服务生命周期

结论：Covio 使用一个固定路径的全局 root helper 和 Legacy LaunchDaemon 提供特权能力。Helper 不是用户可见的设置项。当前分发仅限 internal/local。

## 文档状态

| 项目 | 内容 |
| --- | --- |
| 状态 | 已实现；真机安装、升级和回滚矩阵待 #358 |
| 日期 | `2026-10-25` |
| Issue | #390 |
| 上游决策 | [ADR-0020](../adr/adr-0020-local-only-helper-distribution.md)、[ADR-0026](../adr/adr-0026-four-part-client-version.md) |

## 目标

`CovioHelper` 是独立的最小 root daemon。
app 使用 XPC 调用 `CovioHelper`。
app 使用一次管理员授权安装固定 helper、LaunchDaemon plist 和元数据。
当前路径不使用 `SMAppService`。
当前路径不要求 Developer ID、notarization 或 Gatekeeper 信任。

## 安装布局

app bundle 携带以下文件：

```text
Covio.app/
└── Contents/
    ├── MacOS/
    │   ├── Covio
    │   └── CovioHelper
    └── Library/
        └── LaunchDaemons/
            └── com.wyz.covio.helper.plist
```

安装事务产生以下系统文件：

```text
/Library/Application Support/Covio/
├── bin/
│   └── CovioHelper
├── allowed_uid
├── client-requirement
├── version
└── Covio.app

/Library/LaunchDaemons/
└── com.wyz.covio.helper.plist
```

`/Library/Application Support/Covio/bin/CovioHelper` 由 `root:wheel` 所有。
LaunchDaemon plist 使用这个固定路径。
LaunchDaemon plist 声明 Mach service `com.wyz.covio.helper.xpc`。
helper 从 root-owned `client-requirement` 读取 app 的代码签名要求。
helper 对每个 XPC 客户端检查代码签名要求。

## 自包含边界

`CovioHelper` 静态链接 `kmpDomain`。
`CovioHelper` 不加载 app 内的 `kmpDomain.framework`。
`CovioHelper` 不链接 SwiftUI、AppKit、Vision、AVFoundation 或模型运行库。

## 身份握手

app 比较以下值：

- `releaseId`。
- `clientVersion`。
- `productVersion`。
- `buildNumber`。
- `gitCommit`。
- `helperProtocolVersion`。
- `helperSHA256`。
- `channel`。

运行中的 helper 与 app 不一致时，app 进入只读安全模式。
只读安全模式禁止睡眠、充电上限、主动放电和风扇写入。

## 状态

| 状态 | 含义 | 用户动作 |
| --- | --- | --- |
| `enabled` | LaunchDaemon plist 和固定 helper 都存在 | 无 |
| `legacy` | 只检测到旧 socket 或没有固定 helper 的旧 plist | 执行一次迁移 |
| `notRegistered` | 没有检测到全局 helper 服务 | 重新安装或升级 Covio |
| `error` | 安装、启动或签名检查失败 | 查看错误并修复 |
| `MATCH` | app 与运行中的 helper 身份一致 | 无 |
| `MISSING` | app 无法连接帮助进程 | 重新安装或升级 Covio |
| `OUTDATED` | 帮助进程不支持当前身份协议 | 升级 Covio |
| `IDENTITY_MISMATCH` | 发布身份或摘要不一致 | 进入只读；重新安装或升级 Covio |
| `UNTRUSTED` | 帮助进程或客户端签名不可信 | 进入只读；重新安装或升级 Covio |

## 安装与修复

1. 用户安装或升级 Covio PKG。
2. 安装事务恢复充电上限和风扇控制。
3. app 请求一次管理员授权。
4. 安装脚本把 `CovioHelper` 写到固定路径。
5. 安装脚本写入 root-owned 元数据。
6. 安装脚本把 LaunchDaemon plist 写到临时文件，再原子替换旧 plist。
7. 安装脚本执行 `launchctl bootout`。
8. 安装脚本执行 `launchctl bootstrap`。
9. helper 启动 XPC listener。
10. app 完成发布身份握手。
11. 只有 `MATCH` 开放特权写入。

第 2 步失败时禁止安装。
第 4 至 8 步失败时，app 保持只读安全模式。

## 升级事务

PKG 升级把 app、固定 helper、LaunchDaemon plist 和安装记录作为一个事务处理。
安装器先恢复旧 helper 持有的系统状态。
安装器再备份旧 app、旧 helper、旧 plist 和旧记录。
安装器交换 app bundle，然后用新 app 安装成对的 helper 和 plist。
首次握手失败时，安装器恢复全部四类文件。

完整流程见 [本机升级事务](local-upgrade-transaction.md)。

## SMAppService 迁移

旧 build 可能安装了 `SMAppService` daemon。
安装事务先恢复特权状态，再注销旧 `SMAppService`。
安装事务随后安装固定路径 helper 和 Legacy LaunchDaemon。
旧 service 的迁移不要求 Developer ID 或 notarization。

## 用户修复

1. 打开 Covio 的日志或诊断信息。
2. 如果状态是 `MISSING`、`OUTDATED` 或 `LEGACY`，重新安装同一个内部 PKG。
3. 如果状态是 `IDENTITY_MISMATCH`，确认 app 与帮助进程来自同一 `releaseId`。
4. 如果状态是 `UNTRUSTED`，重新签名 app 和帮助进程。
5. 如果安装中断，运行恢复命令。

正常设置页和各功能卡片不显示 helper 安装、版本或修复入口。

```sh
sudo "/Library/Application Support/Covio/Installer/recover.sh"
```

## 验证命令

```sh
bash scripts/verify-helper-cutover.sh preflight
bash scripts/verify-helper-cutover.sh selftest
```

完成安装后执行：

```sh
bash scripts/verify-helper-cutover.sh verify
```

`verify` 检查固定路径、所有权、plist、元数据、helper 摘要和运行中的 XPC 握手。

## 验证边界

- 非签名测试验证固定路径、plist、共享常量、事务、身份摘要和 XPC 编译。
- 当前分发不验证 Developer ID、notarization 或 Gatekeeper 启动。
- 首次安装、升级、回滚和重启恢复由 #358 在真机验证。
