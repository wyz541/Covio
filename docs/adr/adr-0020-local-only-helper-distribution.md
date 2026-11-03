# ADR-0020：采用无 Apple Developer Program 的本机分发和 Legacy helper

- Status：accepted
- Kind：architecture
- Date：2026-10-25
- Supersedes：ADR-0018
- Superseded by：ADR-0027（仅常规 helper 升级授权与自动更新部分）
- Implements：#350
- 相关：#355、#358

## 背景

Covio 的合盖、充电和风扇控制需要 root helper。
ADR-0018 选择 `SMAppService.daemon`，并要求 Developer ID、hardened runtime 和 notarization。
该方案依赖 Apple Developer Program。

项目负责人已明确不加入 Apple Developer Program，也不申请 Developer ID。
因此当前项目不能取得以下能力：

- Developer ID Application 证书。
- Developer ID Installer 证书。
- Apple notarization。
- Gatekeeper 对普通用户的自动信任。

现有研究已经验证 ad-hoc 和自签名版本不能可靠完成 `SMAppService.daemon` 注册。
继续把 `SMAppService` 当作当前发布门槛，会使 Feature #350 永久阻塞。

## 决策

1. 当前分发类别限定为 internal/local，不提供公开 Release。
2. 当前渠道继续使用 `internal`。禁止生成 `latest`，禁止把制品称为公开发布。
3. 不把 Developer ID、notarization 或 Gatekeeper 作为当前交付门槛。
4. 保留 root helper。合盖、SMC 风扇写入和低档位充电控制不删除。
5. 当前有效服务管理路径改为 Legacy LaunchDaemon。
6. `SMAppService` 退出当前交付路径。其代码可以暂时保留，但不得阻塞构建、安装或验收。
7. helper 安装到 root-owned 固定路径：
   `/Library/Application Support/Covio/bin/CovioHelper`。
8. LaunchDaemon plist 安装到：
   `/Library/LaunchDaemons/com.wyz.covio.helper.plist`。
9. LaunchDaemon 使用固定 helper 路径和 `MachServices`，继续通过 XPC 通信。
10. 安装和升级 helper 必须取得一次明确的管理员授权。（常规自动升级部分由 ADR-0027 取代）
11. app、helper、Release 和本机安装记录继续使用同一个 `releaseId`。
12. app 继续验证 helper 的完整发布身份和 SHA-256。身份不一致时进入只读安全模式。
13. 本机升级继续使用成对安装、精确握手和成对回滚。
14. 本机签名优先使用稳定自签名证书，减少构建间 cdhash 变化。内测 Release 必须使用稳定证书；没有证书时 ad-hoc 只允许用于 CI 或本机调试。
15. 自签名和 ad-hoc 不提供发布者真实性。文档不得把它们描述为 Developer ID。
16. 更新只支持手动安装。禁用自动更新和公开更新检查。（由 ADR-0027 取代）
17. 每个本地包提供 SHA-256、安装报告和恢复命令。
18. 未来如需公开分发，必须先取得 Apple Developer Program，并写新 ADR 取代本决策。

> 2026-11-03 补充：ADR-0027 取代常规 helper 升级的授权要求和决策 16。首次安装与 repair PKG 仍请求 1 次管理员授权。其余决策不变。

## 后果

### 正面

- 项目不再依赖无法取得的证书。
- root 特权功能可以保留。
- helper 更新不再依赖 SMAppService 注册和系统批准。
- app 与 helper 的发布身份和回滚事务可以继续使用。
- 本机安装路径和故障恢复路径明确。

### 负面

- 普通用户会看到 Gatekeeper 警告，或必须从源码构建。
- 不能证明发布者身份。
- 每次更新需要管理员授权。
- 不支持无提示自动更新。
- macOS 可能改变 Legacy LaunchDaemon 的行为。
- 需要维护 root-owned helper 文件、LaunchDaemon plist 和安装事务。
- 不能把当前制品提交为 GitHub 正式 latest。

### 风险

- 下载制品可能被篡改。缓解：只从可信来源获取，并核对 SHA-256。
- ad-hoc 构建改变 cdhash。缓解：开发构建和内测 Release 使用稳定自签名证书，创建内测 Release 时拒绝 ad-hoc。
- helper 与服务版本混合。缓解：精确 releaseId 握手和成对回滚。
- 管理员安装脚本失败。缓解：安装前备份、安装后握手、失败自动恢复。
- 用户误以为包已公证。缓解：安装说明和 Release 正文写明 internal/local。
- Legacy daemon 被后续 macOS 限制。缓解：保留可测试的恢复路径，并在新 ADR 评估后继方案。

## 备选方案

### 备选 1：等待 Apple Developer Program

该方案保持 ADR-0018 的正式分发路径。
当前负责人不申请该计划，因此无法开始真实注册、公证和 Gatekeeper 验收。

未采纳。

### 备选 2：移除 root helper

该方案消除代码签名和 daemon 管理问题。
该方案同时删除风扇控制、合盖保持和低档位充电控制。

未采纳。

### 备选 3：继续使用 ad-hoc SMAppService

现有 ad-hoc 和自签名注册探针已经失败。
该方案不能形成可工作的干净安装路径。

未采纳。

### 备选 4：发布 App Store 版本

App Store 仍要求 Apple Developer Program。
该方案还限制 root daemon 和系统控制能力。

未采纳。

## 未决事项

| 项目 | 状态 | 确认方法 |
| --- | --- | --- |
| 稳定自签名证书生成 | completed (#504) | 本机证书、内测包身份和连续安装验证 |
| Legacy XPC 客户端 requirement | pending | 正签名与错误签名客户端测试 |
| helper 固定路径安装与卸载 | pending | 干净安装与清理矩阵 |
| app-helper 事务回滚 | pending | N-1 升级、握手失败和中断恢复 |
| 风扇、充电和租约恢复 | pending | 真实设备升级矩阵 |
| 内部包可重复安装 | pending | 连续安装、回滚后重装 |
| 未来公开分发 | out of scope | 取得 Apple Developer Program 后写新 ADR |

## 参考

- [#350 Feature](https://github.com/wyz541/kmp-Covio/issues/350)
- [#355 SMAppService migration](https://github.com/wyz541/kmp-Covio/issues/355)
- [#357 Transactional upgrade](https://github.com/wyz541/kmp-Covio/issues/357)
- [#358 Real-Mac validation](https://github.com/wyz541/kmp-Covio/issues/358)
- [特权能力架构调研](../research/privileged-helper-architecture/README.md)
- [ADR-0018](adr-0018-privileged-helper-release-identity.md)
