# 项目版本规范

结论：Covio 使用 Semantic Versioning 2.0.0。项目版本是 `MAJOR.MINOR.PATCH`。

## 1. 版本格式

| 发布类型 | 格式 | 示例 |
| --- | --- | --- |
| 内测 | `MAJOR.MINOR.PATCH-internal.BUILD` | `0.6.0-internal.23` |
| 稳定版 | `MAJOR.MINOR.PATCH` | `0.6.0` |

规则：

1. 版本号不带 `v` 前缀。
2. 主版本、次版本和修订版本不使用前导零。
3. 内测预发布标识固定为 `internal.<buildNumber>`。
4. 项目版本不使用 build metadata。构建号、渠道和 Git commit 分开保存。
5. Git tag 使用 `v<clientVersion>`。`v` 是 tag 前缀，不属于版本本体。

## 2. 版本含义

1. `MAJOR` 增加时，旧版本的数据、配置或使用方式可能不兼容。
2. `MINOR` 增加时，新增向后兼容的功能。
3. `PATCH` 增加时，只包含向后兼容的修复。
4. `0.y.z` 阶段也执行同一规则。
5. 一个已发布版本不得重新打包成相同版本。内容变化时，增加版本或构建号。

## 3. 发布字段

| 字段 | 规则 | 示例 |
| --- | --- | --- |
| `productVersion` | 稳定的三段 SemVer | `0.6.0` |
| `clientVersion` | 完整项目版本 | `0.6.0-internal.23` |
| `buildNumber` | 单调递增整数，不是项目版本 | `23` |
| `releaseId` | `<clientVersion>-g<fullGitSHA>` | `0.6.0-internal.23-g...` |

`releaseId` 是发布身份，不是 SemVer 版本。

Apple 元数据规则：

| 键 | 值 |
| --- | --- |
| `CFBundleShortVersionString` | `productVersion` |
| `CFBundleVersion` | `buildNumber` |
| `CovioClientVersion` | `clientVersion` |

## 4. 版本优先级

1. 先比较 `MAJOR`。
2. `MAJOR` 相同时，比较 `MINOR`。
3. `MINOR` 相同时，比较 `PATCH`。
4. 三段相同时，稳定版高于预发布版。
5. 预发布标识按 SemVer 规则比较。`internal.10` 高于 `internal.9`。
6. build metadata 不参与优先级比较。

## 5. 发布步骤

1. 确定新的 `productVersion`。
2. 增加 `buildNumber`。
3. 如果渠道是 `internal`，生成 `clientVersion = productVersion-internal.buildNumber`。
4. 如果渠道是 `public`，令 `clientVersion = productVersion`。
5. 运行 `python3 -I scripts/release_manifest.py write`。
6. 运行 `python3 -I scripts/release_manifest.py check`。
7. 运行 `bash scripts/test-all.sh`。

## 6. 迁移规则

1. 历史四位版本继续用于读取旧安装记录。
2. 新 tag、安装包名、更新清单和用户可见版本使用 SemVer。
3. 新代码可以读取旧 helper 身份，并把旧版判为 `OUTDATED`。
4. 旧版客户端不能解析新的 SemVer tag。首个 SemVer 内测版必须手工安装。

## 7. 禁止

1. 禁止新增四段版本。
2. 禁止把渠道、commit 或 build metadata 写进 `MAJOR.MINOR.PATCH`。
3. 禁止复用已发布的 `clientVersion`。
4. 禁止让 `CFBundleShortVersionString` 带预发布后缀。

## 参考

- [Semantic Versioning 2.0.0](https://semver.org/)
- [ADR-0031：使用 Semantic Versioning](../adr/adr-0031-semantic-versioning.md)
