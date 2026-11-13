# 本地 iOS 验证

**结论：iOS 发布必须通过签名构建、制品校验、Draft 校验和真机安装四步。**

## 1. 适用范围

本流程用于验证 Covio 的 iOS 真机制品。
验证对象是同一 commit 构建的签名 IPA 和统一 internal Draft。

## 2. 前置条件

- Mac 使用 Apple Silicon。
- Xcode 版本是 27 或更高。
- Keychain 中有 Apple Development 或 Apple Distribution 身份。
- Apple 签名身份属于目标 Team ID。
- iPhone 已连接 Mac，并已打开 Developer Mode。
- provisioning profile 包含测试 iPhone 的 UDID。

记录以下环境信息：

- Mac 型号。
- macOS 版本。
- Xcode 版本。
- iPhone 型号。
- iOS 版本。
- commit。

## 3. 构建签名 IPA

1. 设置 Team ID。
2. 设置导出方式。
3. 运行打包脚本。

```sh
export COVIO_IOS_TEAM_ID=<team-id>
export COVIO_IOS_EXPORT_METHOD=development
bash scripts/package-ios-swift.sh
```

输出文件：

```text
dist/Covio-<clientVersion>-ios-arm64.ipa
dist/ios-package.json
```

打包脚本检查 embedded provisioning profile、代码签名、签名团队、版本号和 Git commit。
签名身份缺失或 provisioning profile 无效时，打包脚本失败。

**警告：** provisioning profile 会过期。检查 profile 的 ExpirationDate。过期前重新生成 Draft。

## 4. 校验制品和 Draft

1. 读取 IPA 摘要和签名信息。
2. 核对 IPA 文件的 SHA-256。
3. 执行 Draft 完整验证。

```sh
jq '.artifact, .signing' dist/ios-package.json
shasum -a 256 dist/Covio-<clientVersion>-ios-arm64.ipa
bash scripts/publish-release.sh v<clientVersion> --dry-run
```

预期输出包含：

```text
release verification passed
draft release can be promoted
```

`--dry-run` 不发布 Draft。
该命令重新下载 Draft 资产，并验证三个平台的身份、摘要、签名和版本。

## 5. 安装到真机

1. 列出已连接设备。
2. 解压 IPA。
3. 安装 `Payload/Covio.app`。

```sh
xcrun devicectl list devices
IOS_VERIFY_DIR="$(mktemp -d "${TMPDIR:-/tmp}/covio-ios.XXXXXX")"
/usr/bin/ditto -x -k dist/Covio-<clientVersion>-ios-arm64.ipa "$IOS_VERIFY_DIR"
xcrun devicectl device install app \
  --device <device-id> \
  "$IOS_VERIFY_DIR/Payload/Covio.app"
```

`devicectl` 接受设备名称、UDID、序列号或其他列出的标识。
安装会替换同一 bundle identifier 的应用。

## 6. 验证安装结果

1. 启动应用。
2. 查询已安装版本。
3. 确认版本号、build number 和 SHA-256 与 Draft 一致。

```sh
xcrun devicectl device process launch \
  --device <device-id> \
  --terminate-existing \
  com.wyz.covio.ios
xcrun devicectl device info apps \
  --device <device-id> \
  --bundle-id com.wyz.covio.ios
```

预期结果：

- `Covio` 已安装。
- `Bundle Identifier` 是 `com.wyz.covio.ios`。
- `Version` 等于 `productVersion`。
- `Bundle Version` 等于 `buildNumber`。
- 应用可以启动。

需要保留本地解压目录时，把目录登记到 Issue 或项目证据目录。
不需要时清理临时目录。

## 7. 证据

Issue 或 PR 至少记录：

- 验证日期。
- Mac 型号和 macOS 版本。
- Xcode 版本。
- iPhone 型号和 iOS 版本。
- release tag 和 commit。
- IPA 文件名和 SHA-256。
- Team ID 和导出方式。
- 打包、Draft 校验、安装和启动结果。
