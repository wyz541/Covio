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

## 当前状态

`checkNow` 在没有安装更新公钥时返回 `notConfigured`。
`installAvailable` 在更新事务完成前返回失败。
这两个状态让 Settings 可以区分“未配置”和“已是最新”。

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
