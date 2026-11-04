# 本机 app 与 helper 升级事务

结论：PKG 把 app、固定 helper、LaunchDaemon plist 和安装记录作为一个事务处理。

## 状态

| 项目 | 内容 |
| --- | --- |
| 状态 | 已实现；#358 真机矩阵通过 |
| 日期 | `2026-10-25` |
| Issue | #357、#390、#562 |
| 上游决策 | [ADR-0020](../adr/adr-0020-local-only-helper-distribution.md)、[ADR-0031](../adr/adr-0031-semantic-versioning.md) |

## 目标

app 与 helper 必须来自同一个 `releaseId`。
任一步失败时，安装器恢复上一版 app、helper、plist 和 `installed-release.json`。
当前事务只用于 internal/local 分发。

## 事务边界

`Covio.app` 使用 `renamex_np(RENAME_SWAP)` 原子交换。
`CovioHelper` 安装在 app bundle 外的固定路径。
LaunchDaemon plist 安装在系统目录。
因此事务同时管理四类对象：

| 对象 | 事务位置 |
| --- | --- |
| app | `/Applications/Covio.app` |
| helper 和元数据 | `/Library/Application Support/Covio/bin/CovioHelper` 与 root-owned helper 元数据 |
| updater | `/Library/Application Support/Covio/Updater` |
| Helper LaunchDaemon | `/Library/LaunchDaemons/com.wyz.covio.helper.plist` |
| Updater LaunchDaemon | `/Library/LaunchDaemons/com.wyz.covio.updater.plist` |
| 安装记录 | `/Library/Application Support/Covio/installed-release.json` |

安装器先备份全部旧对象。
安装器最后提交全部新对象。
首次握手失败时，安装器恢复全部旧对象。

## 自动更新事务

自动更新复用同一套 prepare、commit 和 rollback 函数。
自动更新和 PKG 的边界不同：

| 项目 | PKG | 自动更新 |
| --- | --- | --- |
| 执行者 | Installer root script | root updater one-shot LaunchDaemon |
| App 和 helper | 可替换 | 可替换 |
| Updater engine | 可替换 | 可替换 |
| Launcher | 可替换 | 禁止替换 |
| Updater LaunchDaemon plist | 可替换 | 禁止替换 |
| Code-signing requirement | 可替换 | 禁止替换 |

自动更新在事务环境写入 `UPDATE_MODE='automatic'`。
事务检查已安装 launcher 的 root ownership、代码签名和 SHA-256。
事务检查 `installed-release.json` 与当前 updater engine 一致。
成功记录保留原 launcher 摘要，不写入新 app 内嵌 launcher 的摘要。

## PKG 布局

PKG 不直接覆盖 `/Applications/Covio.app`。
PKG 先把新 bundle 和恢复工具写入 root-owned 暂存区：

```text
/Library/Application Support/Covio/Installer/
├── bin/CovioTransaction
├── staged/Covio.app
├── transaction.sh
└── recover.sh
```

PKG 使用空 component plist。
Installer 把 staged app 当作普通 payload。
Installer 不把 staged app 识别为可重定位 bundle。
`preinstall` 准备事务并备份旧对象。
`postinstall` 验证暂存版本，交换 app，安装 helper，再完成握手。

## 提交条件

安装器在以下检查全部通过后才提交：

1. app、内嵌 manifest 和 helper 的 `releaseId`、`clientVersion`、`productVersion`、build、commit、协议和 channel 一致。
2. helper 文件的 SHA-256 与 manifest 一致。
3. app 和 helper 均为 arm64。
4. app 与 helper 的代码签名有效。
5. 新 build 不低于旧 build。不同 release 不允许复用同一 build。
6. 新 helper 位于固定 root-owned 路径。
7. LaunchDaemon plist 指向固定 helper 并声明 XPC Mach service。
8. 新 helper 与新 app 完成精确握手。
9. Updater 布局、launcher、engine、requirements 和 plist 完整。
10. Updater Launcher 启动匹配 release ID 的 engine，engine 写入 health。
11. root-owned `installed-release.json` 写入成功。

## 前置恢复

安装器先要求 Covio 正常退出。
升级感知版本通过 `prepareInstallTransaction` helper 命令恢复：

- 风扇系统控制。
- 充电上限原始状态。
- 全部 Covio 合盖租约。
- Covio 持有的 `SleepDisabled`。

任一恢复动作失败时，安装器在交换 bundle 前停止。

## 状态

| 状态 | 含义 | 恢复动作 |
| --- | --- | --- |
| `prepared` | 旧对象已备份，新版本位于 PKG | 可回滚 |
| `prepared-new` | 干净安装，旧版本不存在 | 可删除新版本 |
| `swapping` | 正在交换 bundle | 下次运行恢复旧版本 |
| `app-installed` | 新 bundle 已到位 | 握手失败时恢复旧版本 |
| `committed` | 新版本已提交 | 手动恢复使用上一份备份 |
| `rolled-back` | 已恢复旧对象 | 无 |
| `rollback-failed` | 回滚未完成 | 运行恢复命令并保留现场 |

## 安装记录

`/Library/Application Support/Covio/installed-release.json` 由 root 所有。
安装成功时，该文件写入 schema `2`。
记录包含 `clientVersion`、`productVersion`、build、Git commit、渠道和 helper 协议。
安装器继续读取 schema `1` 的旧记录。

`/Library/Application Support/Covio/install-report.json` 写入：

- `source`。
- `transactionId`。
- `releaseId`。
- `previousReleaseId`。
- `result`。
- `rollbackReason`。
- `recordedAt`。

## 恢复命令

自动恢复未完成事务：

```sh
sudo "/Library/Application Support/Covio/Installer/recover.sh"
```

手动恢复上一份成功备份：

```sh
sudo "/Library/Application Support/Covio/Installer/recover.sh" --manual-rollback
```

恢复命令先读取 `current-transaction`。
如果事务尚未写入 state，恢复命令将事务归档，不删除当前安装。
其他事务按 state 回滚。
恢复命令先停止 app。
恢复命令再恢复旧 app、旧 helper、旧 plist 和旧记录。
恢复命令最后启动旧 helper，并要求精确握手通过。

## 失败行为

| 失败 | 结果 |
| --- | --- |
| 前置签名或摘要校验失败 | 所有对象不变，不交换 bundle |
| 状态恢复失败 | app 和 helper 不变，升级停止 |
| 降级或混合 release | 所有对象不变，不交换 bundle |
| helper 首次握手失败 | 恢复旧 app、helper、plist 和记录 |
| updater 安装、布局校验或 health 失败 | 恢复旧 app、helper、updater、plist 和记录 |
| 自动更新替换 launcher | 事务拒绝提交 |
| 自动更新发现损坏的 updater 记录 | 事务拒绝提交 |
| 安装记录写入失败 | 恢复旧 app、helper、plist 和记录 |
| 交换后进程中断 | 恢复命令根据事务状态回滚 |
| 未开始事务阻塞 | 事务归档后允许重试，当前安装不变 |
| 其他路径的 Covio 进程存在 | 不影响已安装 app 的退出判断 |

## 验证边界

- 脚本测试使用真实 ad-hoc 签名和真实原子交换。
- 脚本测试覆盖成功、回滚、恢复失败、降级、摘要错误、签名错误、中断、`SMAppService` 迁移和干净安装。
- 当前分发不验证 Developer ID 或 notarization。
- 真机验证覆盖跨版本升级、干净安装、重复安装、真实进程崩溃和成对回滚。
- 当前没有验证系统重启期间的安装事务。
