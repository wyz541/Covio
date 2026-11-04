# ADR-0026：用四段客户端版本和结构化发布身份

- Status：superseded
- Superseded by：[ADR-0031](adr-0031-semantic-versioning.md)
- Kind：architecture
- Date：2026-11-02
- Supersedes：none
- Implements：#544
- 相关：ADR-0018、ADR-0020

## 背景

用户可见版本以前是 `productVersion + buildNumber`。这个写法显示为 `0.6.0 build 15`，不能直接表示升级顺序。渠道、Git commit 和 helper 协议也容易混进版本字符串。

发布、更新检查和安装事务需要稳定的比较规则。用户界面只需要一个纯数字版本。

## 决策

1. 客户端版本是四段十进制数字。客户端版本从 `buildNumber` 生成。
2. `buildNumber` 先补足四位十进制，再按千、百、十、个拆分。
3. 客户端版本的格式是 `千.百.十.个`。每段只有一位数字。
4. `buildNumber` 范围是 `1...9999`。超出范围时发布流水线失败。
5. 产品版本继续作为独立元数据。产品版本不进入用户可见客户端版本。
6. `CFBundleShortVersionString` 和 `CovioClientVersion` 使用客户端版本。
7. `CFBundleVersion` 和 `buildNumber` 使用同一个单调递增构建号。
8. `CovioProductVersion` 保存产品版本。产品版本不参与升级顺序比较。
9. 渠道、完整 Git commit 和 helper 协议使用独立字段。这些字段不进入客户端版本。
10. `releaseId` 的格式是 `<clientVersion>-g<fullGitSHA>`。Git commit 不参与版本排序。
11. internal tag 的格式是 `v<clientVersion>-internal`。
12. public tag 的格式是 `v<clientVersion>`。
13. 安装包文件名的版本段使用 `clientVersion`。示例是 `Covio-0.0.1.6.dmg`。
14. Source manifest schema `2` 保存 `productVersion`、`clientVersion`、`buildNumber`、`channel` 和 `helperProtocolVersion`。
15. app 与 helper 握手逐项比较 `clientVersion`、`productVersion`、`buildNumber`、Git commit、渠道、helper 协议和 `releaseId`。
16. 更新检查只接受稳定的四段纯数字 tag。internal tag 和旧语义版本 tag 不进入更新提示。
17. 安装记录使用 schema `2`。安装器继续读取 schema `1` 的旧记录和旧 app 身份。
18. 旧 tag 继续可读。示例是 `v0.6.0-internal.15`。旧 tag 只用于历史说明，不用于新的升级比较。
19. 当前已安装 build `15` 迁移到 build `16`。客户端版本从旧显示 `0.6.0 build 15` 变为 `0.0.1.6`。

| buildNumber | clientVersion |
| ---: | --- |
| `1` | `0.0.0.1` |
| `15` | `0.0.1.5` |
| `16` | `0.0.1.6` |
| `100` | `0.1.0.0` |
| `9999` | `9.9.9.9` |

## 后果

### 正面

- 用户看到纯数字客户端版本。
- 升级顺序只由 `buildNumber` 决定。
- 四个发布标识各有单一用途。
- Git commit、渠道和 helper 协议可以独立审计。
- 旧安装和旧 tag 可以继续识别。

### 负面

- 客户端版本不能从数字直接看出产品版本。
- 每次发布必须增加 `buildNumber`。
- 发布脚本必须同时维护客户端版本和产品版本。
- build `10000` 后必须制定新的版本方案。

### 风险

- 有人把 Git commit 或渠道追加到客户端版本。缓解：生成脚本、测试和更新检查只接受四段数字。
- 有人复用 `buildNumber`。缓解：安装事务拒绝相同 build 的不同 release。
- 旧安装无法读取新字段。缓解：安装器按旧身份格式读取 build `15`，新安装记录写入 schema `2`。
- 产品版本与客户端版本漂移。缓解：两者都从 source manifest 生成，发布校验比较 app、helper 和 manifest。

## 备选方案

### 备选 1：继续显示产品版本和 build

未采纳。这个写法不是纯数字，用户不能直接比较升级顺序。

### 备选 2：把 Git commit 放进客户端版本

未采纳。Git commit 不表达升级顺序，也会让用户可见版本过长。

### 备选 3：保留语义版本作为客户端版本

未采纳。当前产品版本和构建号的含义不同。四段数字可以直接表达 `buildNumber` 的排序。

## 未决事项

| 项目 | 状态 | 确认方法 |
| --- | --- | --- |
| build `10000` 后的版本格式 | 未决 | 达到 build `9000` 前建立新 ADR |
| public 发布启用时间 | 未决 | ADR-0020 不包含 public 分发，启用时建立新 ADR |

## 参考

- [ADR-0018：helper 发布身份](adr-0018-privileged-helper-release-identity.md)
- [ADR-0020：本机 helper 分发](adr-0020-local-only-helper-distribution.md)
- [发布流水线](../design/release-pipeline.md)
- GitHub issue #544
