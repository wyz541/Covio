# ADR-0031：使用 Semantic Versioning 作为项目版本规范

- Status：accepted
- Kind：architecture
- Date：2026-11-04
- Supersedes：ADR-0026
- Implements：none
- 相关：[项目版本规范](../process/versioning.md)

## 背景

ADR-0026 使用四位客户端版本。四位版本便于把构建号映射为升级顺序，但它不是 SemVer。

Covio 还需要同时保存产品版本、构建号、渠道、Git commit 和 helper 协议。把这些字段混进一个字符串，会让版本语义和发布身份混淆。

## 决策

1. 项目版本使用 Semantic Versioning 2.0.0。
2. `clientVersion` 是完整项目版本。内测格式为 `MAJOR.MINOR.PATCH-internal.BUILD`，稳定版格式为 `MAJOR.MINOR.PATCH`。
3. `productVersion` 保存稳定的 `MAJOR.MINOR.PATCH`，并与 `clientVersion` 的主版本、次版本和修订版本一致。
4. `buildNumber` 是独立、单调递增的整数。它不是项目版本。
5. 项目版本不使用 build metadata。构建号、渠道和 Git commit 使用独立字段。
6. Git tag 使用 `v<clientVersion>`。`v` 是 tag 约定，不属于 SemVer 版本。
7. 安装包、更新清单和更新归档的文件名使用 `clientVersion`。
8. `releaseId` 继续使用 `<clientVersion>-g<fullGitSHA>`。`releaseId` 是发布身份，不是项目版本。
9. `CFBundleShortVersionString` 使用 `productVersion`。Apple 版本字段不带预发布后缀。
10. `CFBundleVersion` 使用 `buildNumber`。
11. 自定义 `CovioClientVersion` 保存完整 `clientVersion`。
12. 更新比较先使用 SemVer 优先级，再检查 `buildNumber` 必须增加。
13. 新发布不再创建四段版本。旧四位格式只用于读取历史记录和旧 helper 身份。
14. 旧客户端不能解析新的 SemVer tag。首个 SemVer 内测版手工安装。
15. 版本选择按兼容性执行：不兼容变化增加 `MAJOR`，兼容功能增加 `MINOR`，兼容修复增加 `PATCH`。

## 后果

### 正面

- 用户和工具共享同一套版本语义。
- Git tag、更新顺序和用户可见版本使用同一个值。
- 构建号、渠道和 Git commit 保持独立。
- 预发布版本有标准优先级。
- 旧安装记录仍可读取。

### 负面

- 首批旧内测客户端需要手工迁移。
- 发布脚本和更新器需要同时校验 SemVer 与构建号。
- Apple 版本字段和完整项目版本需要分别维护。

### 风险

- 有人把 `buildNumber` 当作版本。缓解：版本规范、测试和发布检查拒绝这种格式。
- 有人复用 `clientVersion`。缓解：发布脚本要求 `buildNumber` 增加。
- 旧客户端读不到新 Release。缓解：首个 SemVer 版本提供 PKG，并要求手工安装。
- 版本含义不一致。缓解：发布说明记录不兼容变化，代码评审检查主版本变化。

## 备选方案

### 备选 1：继续使用四位客户端版本

未采纳。四位版本不能表达标准 SemVer 优先级，也会让产品版本与升级版本长期分离。

### 备选 2：把构建号放进 SemVer build metadata

未采纳。Build metadata 不参与 SemVer 优先级，不能替代独立构建号。文件 URL 也会增加编码复杂度。

### 备选 3：只让产品版本使用 SemVer

未采纳。这样 tag、用户可见版本和产品版本仍会分叉，项目没有统一版本规范。

## 未决事项

| 项目 | 状态 | 确认方法 |
| --- | --- | --- |
| `buildNumber` 的长期上限 | 未决 | 接近 `9999` 前建立新 ADR |
| 旧客户端自动迁移 | out of scope | 首个 SemVer 版本手工安装 PKG |

## 参考

- [Semantic Versioning 2.0.0](https://semver.org/)
- [ADR-0026：四段客户端版本](adr-0026-four-part-client-version.md)
- [项目版本规范](../process/versioning.md)
- [发布流水线](../design/release-pipeline.md)
