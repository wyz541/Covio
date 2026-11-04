# Updater service

结论：Covio 使用独立的 root LaunchDaemon。不可变 launcher 只启动 root-owned versioned engine。

## 组件

| 组件 | 固定路径 | 作用 |
| --- | --- | --- |
| LaunchDaemon | `/Library/LaunchDaemons/com.wyz.covio.updater.plist` | 启动 launcher，并注册 Mach service |
| Launcher | `/Library/Application Support/Covio/Updater/bin/CovioUpdaterLauncher` | 校验并启动 engine |
| Engine | `/Library/Application Support/Covio/Updater/versions/<releaseId>/CovioUpdater` | 提供 XPC、检查和安装入口 |
| Current | `/Library/Application Support/Covio/Updater/current` | 当前 engine 的 release ID |
| Previous | `/Library/Application Support/Covio/Updater/previous` | 回退 engine 的 release ID |
| Health | `/Library/Application Support/Covio/Updater/health.json` | Launcher 检查 engine 是否就绪 |
| Client requirement | `/Library/Application Support/Covio/Updater/updater-client-requirement` | 限制 app 到 updater 的 XPC 连接 |
| Updater requirement | `/Library/Application Support/Covio/Updater/updater-requirement` | App 校验 updater 身份 |

`current` 和 `previous` 只保存 release ID。它们不保存任意路径。

## 安装流程

1. Migration PKG 取得 1 次管理员授权。
2. PKG 事务交换新的 Covio.app。
3. 事务停止旧 Updater Launcher 和 engine，并清理遗留进程。
4. App 以 root 执行 `--install-updater-as-root`。事务要求 App 只写文件，不启动 LaunchDaemon。
5. App 校验 app 与 updater 的 designated requirement。
6. App 安装 launcher、versioned engine、requirements 和 LaunchDaemon plist。
7. App 写入 `current`，并在已有版本时写入 `previous`。
8. 事务验证 Updater 布局和摘要。
9. 如果 App 没有生成完整布局，事务从已验证的新 App 复制 Updater 文件。
10. 事务 bootstrap Updater LaunchDaemon。
11. Launcher 启动 engine。
12. Engine 写入 health。
13. 事务验证 health 后写入安装记录。

Updater 安装、布局校验或 health 失败时，事务恢复旧 app、helper、updater、plist 和安装记录。

## 启动流程

```text
launchd
  → CovioUpdaterLauncher
  → 读取 current
  → 校验 release ID 和 engine
  → 启动 CovioUpdater
  → CovioUpdater 写入 health.json
  → launcher 确认 release ID 和 PID
```

Engine 是 launcher 的子进程。Launcher 在 engine 退出后重新启动它。

## 回退

1. Launcher 删除旧 health 文件。
2. Launcher 启动 `current` engine。
3. Engine 在 10 秒内写入匹配的 health。
4. 如果 health 缺失、release ID 错误或 PID 错误，launcher 终止 engine。
5. Launcher 将 `previous` 写入 `current`。
6. Launcher 启动旧 engine。

Engine 在 30 秒内连续退出 3 次时，launcher 也执行同样的回退。

## XPC API

```text
status() -> UpdaterStatus
checkNow() -> UpdaterOperationResult
installAvailable() -> UpdaterOperationResult
setAutomaticUpdates(enabled: Bool) -> UpdaterOperationResult
restartApp() -> UpdaterOperationResult
```

XPC 不接受调用方提供的路径、命令、URL 或任意字典。
自动更新偏好按调用 UID 写入 root-owned 文件。

## 调用方验证

1. Launcher 使用 root-owned app requirement 启动 XPC listener。
2. Listener 在激活前设置 `setConnectionCodeSigningRequirement`。
3. Updater 在每次调用中读取当前 NSXPC connection 的 kernel-provided audit metadata。
4. App 使用 root-owned updater requirement 校验 updater 身份。
5. 缺失 requirement 时，双向连接均失败关闭。

## 自动调度

Updater 在 root LaunchDaemon 内独立调度。App 未运行时，调度继续工作。

| 项目 | 行为 |
| --- | --- |
| 默认间隔 | 6 小时 |
| 启动检查 | 启动后 15 秒 |
| 默认偏好 | 按 console 用户 UID 开启 |
| 关闭自动安装 | 仍然允许手动检查 |
| 候选恢复 | Manifest、签名和版本状态保存在 root-owned `Updater` 目录 |

每次调度先读取当前 console 用户的偏好。偏好关闭时，调度不检查。
检查成功后，updater 保存已验证候选。Updater 重启后可以继续安装该候选。

## 事务结果

一次性事务 job 使用固定标签：

```text
com.wyz.covio.updater.transaction.<transactionId>
```

事务结果写入 `update-result.json`。
新 updater 启动后读取结果、结束一次性 job，并把结果合并到 `update-state.json`。
成功事务删除 staging 和更新归档。
失败事务保留日志，供下一次检查或 repair PKG 使用。

## 当前状态

`checkNow` 在没有安装更新公钥时返回 `notConfigured`。
正常自动更新只替换 `versions/<releaseId>/CovioUpdater` 和指针。
正常自动更新不替换 launcher、LaunchDaemon plist 或 code-signing requirement。
只有 migration PKG 或 repair PKG 可以替换 launcher。

## 测试

```sh
bash scripts/test-covio-updater.sh
```

测试覆盖：

- release ID allowlist。
- Launcher 拒绝目录逃逸。
- Engine selftest 状态。
- 新 engine health 错误时回退 `previous`。
- LaunchDaemon 指向不可变 launcher。
- Mach service、KeepAlive 和 ThrottleInterval 固定值。
- 已签名候选可以跨 updater 重启保存。
- 自动更新保留 launcher 和 LaunchDaemon。
- 自动偏好默认开启，并按 UID 读取。
- GitHub feed 只接受固定 internal tag、asset 名和 asset URL。
