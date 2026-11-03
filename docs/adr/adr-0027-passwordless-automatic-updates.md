# ADR-0027：用独立更新器支持一次授权后的自动更新

- Status：accepted
- Kind：architecture
- Date：2026-11-03
- Supersedes：ADR-0020 的常规升级授权部分和自动更新限制（决策 10 的常规升级部分、决策 16）
- Implements：#553
- 相关：ADR-0005、ADR-0018、ADR-0020、ADR-0026、Discussion #552

## 背景

Covio 的合盖、充电和风扇控制依赖 root helper。当前 PKG 把 app、helper、LaunchDaemon plist 和安装记录放在同一个事务中。当前事务已经支持精确握手和成对回滚。

当前 `0.0.1.8` 会定时检查 internal Release。
检查结果只产生通知。
手动检查会打开 GitHub Release 页面。
用户仍需下载 PKG、退出 Covio、完成安装并输入管理员凭证。

新需求如下：

- 每台 Mac 首次安装最多请求 1 次管理员授权。
- 后续更新自动检查、下载、安装并重启 Covio。
- 后续更新不请求管理员密码。
- 更新覆盖 app、privileged helper 和 updater。
- 更新失败后恢复全部旧组件。

ADR-0020 决策 16 禁止自动更新。
因此本 ADR 取代常规 helper 升级的授权要求和自动更新限制。
本 ADR 不改变 ADR-0020 的 internal/local 分发范围。
本 ADR 也不改变首次安装、手工修复和公开分发门槛。

当前内测签名是自签名证书 `Covio Dev`。
本机可以生成同类证书。
因此 root updater 不得只信任本机自签名证书。
首次 PKG 是唯一人工信任锚。
更新真实性必须由独立的离线更新签名保护。

## 决策

1. 当前自动更新只服务 `internal` 渠道。公开分发继续不在当前范围内。
2. 首次安装或修复 PKG 最多请求 1 次管理员授权。该 PKG 是唯一人工信任锚。
3. 首次 PKG 安装独立的 root `CovioUpdater`。更新权限不加入现有硬件 helper。
4. 常规更新不得再次调用 `installer -pkg`，不得调用 `sudo`，不得请求管理员凭证。
5. App 保持普通用户权限。App 不得直接替换 `/Applications/Covio.app`、root helper 或 updater。
6. App 通过版本化 XPC 与 updater 通信。XPC 只接受固定的操作枚举。
7. Updater XPC 不接受调用方提供的路径、命令、参数、仓库 URL 或下载 URL。
8. Updater 校验调用方的代码签名和 Apple audit token。仅校验 PID、用户名或进程路径不满足要求。
9. Updater 使用固定仓库 `wyz541/kmp-Covio` 和固定 `internal` 渠道。Release 选择不信任可变的 `latest` URL。
10. Updater 只接受 Release 中的签名 manifest 和签名更新归档。网页内容和 PKG 安装脚本不是更新信任来源。
11. 更新 manifest 使用 Ed25519 离线签名。Manifest 包含 `keyId`、渠道、版本、build、commit、release ID、协议、归档 URL 和 SHA-256。签名放在独立签名资产中。
12. App 和 updater 只内置更新公钥。更新私钥不得进入仓库、CI、Release 资产或普通用户钥匙串。
13. Updater 拒绝降级、相同 build 的不同 release、错误渠道、错误协议、错误 key ID、错误摘要和不允许的 URL。
14. Update archive 使用固定布局。Archive 至少包含 `Covio.app`、helper、updater engine、组件 manifest 和所需 LaunchDaemon plist。
15. Update archive 不包含可执行安装脚本。Updater 使用内置的固定事务代码完成安装。
16. Updater 在 root-only staging 目录中校验 archive。校验失败时删除 staging，不触碰已安装组件。
17. 自动更新在 internal 渠道默认开启。用户可以在设置中关闭自动安装，并可以执行手动检查。
18. Updater 按固定周期独立检查。App 未运行时，updater 仍可以下载和安装兼容更新。
19. 安装前，updater 要求旧 helper 恢复风扇、充电上限、合盖租约和 `SleepDisabled` 状态。
20. 安装前，updater 在 root-owned 目录写入持久事务记录。记录包含旧身份、新身份、阶段和恢复动作。
21. App、helper、updater engine 和安装记录必须在同一事务中提交。不得只更新其中一个组件。
22. App bundle 使用原子交换。Helper、updater engine 和 plist 使用 root-owned staging、`fsync` 和原子 rename。
23. 更新后，updater 启动新 helper 并完成精确身份握手。握手失败时回滚全部组件。
24. 回滚成功后，updater 启动旧 helper。旧 helper 不可用时，Covio 进入只读安全模式并提供 repair PKG 入口。
25. 成功提交后，updater 写入 `installed-release.json`。记录包含 app、helper 和 updater 的 release ID、版本、commit、协议和 SHA-256。
26. Updater 自身使用稳定 launcher 和可替换 engine。LaunchDaemon 指向稳定 launcher，不直接指向版本目录。
27. 版本目录位于 root-owned `Updater/versions/<releaseId>/`。`current` 指针只由 root updater 原子替换。
28. 新 updater engine 启动或握手失败时，稳定 launcher 使用 `previous` 指针恢复旧 engine。
29. 稳定 launcher 自身更新时，updater 备份旧 launcher，原子替换新 launcher，再执行 `launchctl kickstart -k`。新 launcher 不响应时回滚。
30. 普通 app 只能执行 `status`、`checkNow`、`installAvailable`、`setAutomaticUpdates` 和 `restartApp` 等固定操作。
31. Updater 不支持调用方指定任意 app、helper、package、shell、命令或 URL。
32. 本机管理员被视为拥有整机控制权。本 ADR 不防御已取得 root 或本地管理员权限的攻击者。
33. 更新签名不替代 Developer ID。公开分发仍需要 Developer ID、notarization 和新的分发 ADR。
34. Repair PKG 继续支持一次管理员授权。Repair PKG 用于恢复缺失或被篡改的 updater。

## 组件布局

```text
/Applications/
└── Covio.app

/Library/Application Support/Covio/
├── bin/
│   └── CovioHelper
├── Updater/
│   ├── bin/
│   │   └── CovioUpdaterLauncher
│   ├── versions/
│   │   └── <releaseId>/
│   │       └── CovioUpdater
│   ├── current
│   ├── previous
│   └── transactions/
├── installed-release.json
└── install-report.json

/Library/LaunchDaemons/
├── com.wyz.covio.helper.plist
└── com.wyz.covio.updater.plist
```

所有安装目录和文件由 `root:wheel` 所有。普通用户对 updater 目录只有只读权限。

## 更新流程

```text
稳定 launcher 启动 updater engine
    ↓
updater 读取固定 internal feed
    ↓
下载 manifest 和 update archive 到 root-only staging
    ↓
校验组件代码签名、Ed25519 manifest 签名、SHA-256、渠道、build 和协议
    ↓
要求旧 helper 恢复系统写入
    ↓
写入事务记录并备份旧组件
    ↓
原子替换 app、helper、updater engine 和 plist
    ↓
启动新 helper 并完成精确握手
    ├─ 成功：提交记录，重启 app
    └─ 失败：恢复旧组件并启动旧 helper
```

## 更新清单

更新 manifest 至少包含以下字段：

| 字段 | 用途 |
| --- | --- |
| `schemaVersion` | Manifest schema 版本 |
| `keyId` | 选择内置公钥 |
| `channel` | 限制安装渠道 |
| `clientVersion` | 用户可见版本 |
| `buildNumber` | 单调升级顺序 |
| `gitCommit` | 关联 Git 来源 |
| `releaseId` | 绑定本次发布 |
| `helperProtocolVersion` | 检查 helper 兼容性 |
| `updaterProtocolVersion` | 检查 updater XPC 兼容性 |
| `minimumMacOSVersion` | 限制系统版本 |
| `archiveURL` | 指向固定仓库 Release 资产 |
| `archiveSHA256` | 校验下载文件 |
| `archiveSize` | 限制下载大小 |
| `componentHashes` | 校验 app、helper 和 updater |
| `publishedAt` | 记录发布时间 |

签名文件使用独立 `.sig` 资产。签名值只覆盖 manifest 的规范化字节。Manifest 不包含自身签名。Manifest 或签名无法解析时，updater 拒绝更新。

## 更新签名轮换

1. 当前私钥只用于离线签名。私钥保存在受控离线介质中，并设置口令保护。
2. Bridge Release 由当前私钥签名，并在 app 或 updater 中内置下一个公钥。
3. Updater 验证 Bridge Release 后，新公钥随 Bridge Release 生效。
4. 新私钥接管后续 Release 的签名。
5. 旧公钥在迁移窗口内继续保留，窗口结束后通过新的签名 Release 移除。
6. 签名资产可以包含多个签名。每个出现的签名都必须有效。接受更新时，至少一个签名必须来自当前受信任的 key ID。

## App 与 Updater 的 XPC 边界

Updater 对 app 暴露以下操作：

| 操作 | 输入 | 结果 |
| --- | --- | --- |
| `status` | 无 | 返回当前版本、检查状态、下载状态和安装状态 |
| `checkNow` | 无 | 使用固定 feed 立即检查 |
| `installAvailable` | 无 | 安装 updater 已校验的候选版本 |
| `setAutomaticUpdates` | 布尔值 | 更新 root-owned 自动更新偏好 |
| `restartApp` | 无 | 重启固定路径的 Covio.app |

Updater 验证调用方签名和 audit token。
Updater 不接受调用方传入的可执行文件、脚本、命令、路径或远端 URL。
App 关闭时，updater 继续按 root-owned 偏好执行检查。

## 后果

### 正面

- 用户只需在首次安装或修复时完成 1 次管理员授权。
- 后续更新可以覆盖 app、helper 和 updater。
- 硬件 helper 不扩大职责，不直接获得更新权限。
- 更新流程不执行来自 PKG 或 archive 的安装脚本。
- 更新真实性不依赖本机自签名证书或 Gatekeeper。
- 现有精确握手和成对回滚可以继续使用。
- Updater engine 可以独立更新，稳定 launcher 减少自更新风险。

### 负面

- 新增 root LaunchDaemon、XPC 服务和更新事务代码。
- 新增离线签名、公钥轮换和 Release publish 步骤。
- 更新 archive、manifest 和自更新需要独立测试矩阵。
- 自动更新可能中断用户当前操作。设置必须提供关闭入口。
- 更新器和 helper 更新失败时需要完整回滚。
- 公开分发仍不能使用当前方案替代 Developer ID 和 notarization。

### 风险

- 更新私钥泄露会让攻击者获得所有内测设备的 root 更新能力。缓解：离线保存、口令保护、Bridge Release 轮换和签名审计。
- Updater 存在漏洞会扩大 root 攻击面。缓解：固定 XPC 操作、调用方验证、最小依赖和独立安全测试。
- 更新 archive 包含路径穿越或意外可执行文件。缓解：固定布局、allowlist、归档路径校验和组件摘要校验。
- 新 helper 启动失败会造成写入能力中断。缓解：旧 helper 备份、精确握手和自动回滚。
- 新 updater engine 启动失败会阻止后续更新。缓解：稳定 launcher、`current`/`previous` 指针和启动检查。
- 断电发生在替换过程中。缓解：持久事务记录、原子 rename、启动恢复和旧组件备份。
- 用户无法区分通知中的更新来源。缓解：设置显示渠道、版本、签名 key ID 和安装结果。
- 本机管理员可以修改 root-owned updater。缓解：将其排除在威胁模型外，不声称防御整机控制者。

## 备选方案

### 备选 1：每次更新继续安装 PKG

该方案复用现有安装事务。
该方案仍会在每次更新时请求管理员授权。
该方案不满足“后续更新不需要管理员凭证”的要求。

未采纳。

### 备选 2：App 调用 `installer -pkg` 或 `sudo`

该方案改动较少。
该方案要求 app 持有 root 操作入口。
该方案会执行 PKG 提供的 root 脚本。
该方案违反最小权限原则。

未采纳。

### 备选 3：把更新权限加入现有硬件 helper

该方案减少一个 LaunchDaemon。
该方案把硬件控制和任意软件更新放在同一个 root 进程。
该方案扩大硬件 helper 的攻击面。
该方案使 helper 启动问题同时阻塞更新修复。

未采纳。

### 备选 4：只更新用户态 app，继续手动更新 helper

该方案可以避开 root helper 更新。
该方案会留下 app 与 helper 混合版本。
该方案不满足 app、helper 和 updater 成对更新的要求。

未采纳。

### 备选 5：等待 Developer ID 和 `SMAppService`

公开分发最终需要 Developer ID、notarization 和系统托管服务。
当前 internal/local 范围没有这些能力。
该方案会使当前需求无限期阻塞。

未采纳为当前方案。

## 未决事项

| 项目 | 状态 | 确认方法 |
| --- | --- | --- |
| Manifest 与 update archive 的最终 schema | pending | Research 结论写回 Feature #553 |
| Updater XPC 调用方的精确签名要求 | pending | 正签名和错误签名客户端测试 |
| 稳定 launcher 的崩溃检测和 `previous` 回退实现 | pending | 启动失败和连续崩溃真机测试 |
| 自动更新的默认检查周期和空闲窗口 | pending | 设置交互与真机验收 |
| 离线私钥的介质、备份和轮换周期 | pending | 发布运行手册与轮换演练 |
| `0.0.1.8` 迁移包的 build 和 Release 顺序 | pending | 发布迁移包后执行 N-1 自动更新验收 |
| 公开分发的 Developer ID 和 notarization | out of scope | 建立新的公开分发 ADR |

## 验收要求

- 从已安装的 `0.0.1.8` 安装一次迁移 PKG。只出现 1 次管理员授权。
- 发布更高 build 后，updater 自动完成 app、helper 和 updater 更新，不出现管理员提示。
- 更新前后 app、helper 和 updater 的 release ID、commit、协议和 SHA-256 一致。
- 篡改 manifest、archive、组件或签名后拒绝安装。
- 错误渠道、错误 build 和降级 archive 被拒绝。
- 下载中断、进程退出和断电恢复后可以运行旧版本。
- Helper 握手失败后恢复旧 app、helper 和 updater。
- Updater engine 自更新后继续响应 XPC。
- 稳定 launcher 自更新失败后恢复旧 launcher。
- 普通本地用户不能通过 XPC 执行任意路径、命令、参数或 URL。
- 设置状态在亮色和深色真机上可读。

## 参考

- [Feature #553](https://github.com/wyz541/kmp-Covio/issues/553)
- [Discussion #552](https://github.com/wyz541/kmp-Covio/discussions/552)
- [ADR-0005：本机用固定证书签名](adr-0005-local-code-signing.md)
- [ADR-0018：独立特权 helper 和发布身份](adr-0018-privileged-helper-release-identity.md)
- [ADR-0020：本机分发和 Legacy helper](adr-0020-local-only-helper-distribution.md)
- [ADR-0026：四段客户端版本和结构化发布身份](adr-0026-four-part-client-version.md)
- [本机 app 与 helper 升级事务](../design/local-upgrade-transaction.md)
- [Helper 服务边界](../design/helper-service.md)
- [发布流水线](../design/release-pipeline.md)
