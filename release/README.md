# Release identity

`release/release-manifest.json` is the source of truth for:

- Semantic Versioning client version
- stable product version
- build number
- release channel
- helper protocol version

Run the generator after changing the manifest:

```sh
python3 scripts/release_manifest.py write
```

Check for drift:

```sh
python3 scripts/release_manifest.py check
```

Increment the build number or start a new version:

```sh
python3 scripts/release_manifest.py bump
python3 scripts/release_manifest.py bump --version 0.6.0
```

Generate the final artifact manifest from the signed helper and built installers:

```sh
python3 scripts/release_manifest.py generate-artifact \
  --helper dist/Covio-Offline.app/Contents/MacOS/CovioHelper \
  --default-dmg dist/Covio-<clientVersion>.dmg \
  --offline-dmg dist/Covio-Offline-<clientVersion>.dmg \
  --model-manifest macosApp/src/AutoNaming/FileNamingModelManifest.json \
  --output dist/release-manifest.json
```

For a default-only artifact manifest, omit `--offline-dmg` and `--model-manifest`.

Internal releases add these update assets:

- `CovioUpdate-<clientVersion>.zip`
- `CovioUpdate-<clientVersion>.json`
- `CovioUpdate-<clientVersion>.sig.json`

统一内测 Release 还包含：

- `Covio-<clientVersion>-ios-arm64.ipa`
- `ios-package.json`
- `Covio-<clientVersion>-windows-x64-portable.zip`
- `Covio-<clientVersion>-windows-x64.msi`
- `compose-package.json`

iOS IPA 与 Windows 压缩包必须使用相同的 `clientVersion`、`buildNumber`、渠道和 Git commit。
发布流水线在创建或发布 Draft 前校验每个平台的制品。

The generated files are:

- `macosApp/src/Design/GeneratedReleaseIdentity.swift`
- `macosApp/ReleaseIdentity.generated.xcconfig`

Attach the Windows and iOS package records before creating an internal Draft:

```sh
python3 -I scripts/release_manifest.py attach-platforms dist/release-manifest.json \
  --helper dist/Covio.app/Contents/MacOS/CovioHelper \
  --ios-package dist/ios-package.json \
  --windows-package dist/compose-package.json
```

Do not edit generated files by hand.

The source manifest contains the release inputs.
The artifact manifest adds `gitCommit`, `releaseId`, `helperSHA256`, both installer identities and the model identity.
`CovioHelper` statically links the Rust core; the app bundle must not supply its runtime dependencies.

Build the default slim app:

```sh
bash scripts/setup-local-signing.sh
bash scripts/package-macos-swift.sh
```

构建并导出签名的 iOS 真机 IPA：

```sh
COVIO_IOS_TEAM_ID=<team-id> bash scripts/package-ios-swift.sh
```

把 `COVIO_IOS_EXPORT_METHOD` 设为 `development`、`ad-hoc`、`app-store` 或 `app-store-connect`。
默认值是 `development`，用于内测设备直接安装。
Mac 必须有 Apple Development 证书和包含测试设备的 provisioning profile。
IPA 未签名或身份与 `release/release-manifest.json` 不一致时，脚本失败。
iOS 签名、安装和验证步骤见[本地 iOS 验证](../docs/process/ios-validation.md)。

从同一 commit 的 CI 运行下载 Windows Compose 包：

```sh
gh run download <run-id> \
  --name windows-compose-package-<run-id> \
  --dir build/windows-compose-package
```

`scripts/covio release draft` 会自动下载目标 commit 的成功 CI 制品。

`scripts/covio release draft` and direct Release packaging reuse persistent caches outside the clean release worktree.
The packaging job locks the macOS build caches, and every release identity and asset check still runs.

- DerivedData defaults to the primary checkout at `build/release-xcode-cache`.
- Swift Package checkout defaults to the primary checkout at `build/release-source-packages`.
Set `COVIO_RELEASE_DERIVED_DATA` or `COVIO_RELEASE_SOURCE_PACKAGES` to use another cache directory.
The package script uses `xcodebuild build` and reads `Build/Products/Release/Covio.app`.
It does not run a fresh Xcode archive for every release.
The macOS package embeds no KMP framework. It links the Rust static library into the app and helper.

Internal Release creation requires a stable local signing identity.
The app and helper must use the same certificate.
CI packaging without a certificate still uses ad-hoc signing.
GitHub Actions does not run the macOS SwiftUI host.
Run `bash scripts/test-all.sh` on the release Mac before creating a Draft.

Build the optional offline app and DMG:

```sh
COVIO_FILE_NAMING_MODEL_DIR=build/models/Qwen3VL-2B-Instruct-4bit \
  bash scripts/package-macos-offline-swift.sh
```

The shortcut `scripts/covio` runs the steps below in release order.
See `docs/design/release-pipeline.md`, section 快捷命令.

```sh
scripts/covio release status
scripts/covio release prepare
scripts/covio release draft
scripts/covio release publish
scripts/covio local
```

Prepare the automatic update signing key once:

```sh
bash scripts/setup-update-signing-key.sh covio-internal-2026-01
```

The private key stays in login Keychain. The public key is committed in
`release/update-public-keys.json`.

Build and create a Draft Release:

```sh
bash scripts/create-release.sh
```

内部 Draft 要求 iOS 包元数据和 Windows Compose 包。
`create-release.sh` 把两项记录写入 `release-manifest.json` 和 `release-evidence.json`。
然后，脚本创建一个包含 macOS、Windows 和 iOS 制品的 Draft。

Verify all downloaded Draft assets and publish explicitly:

```sh
bash scripts/publish-release.sh v<tag>
```

Install or upgrade with the signed PKG:

```sh
installer -pkg Covio-<version>.pkg -target /
```

The PKG validates the staged app and helper before changing `/Applications/Covio.app`.
It atomically exchanges the app bundle, installs the fixed helper and LaunchDaemon, and checks the handshake before commit.

Recover an interrupted transaction:

```sh
sudo "/Library/Application Support/Covio/Installer/recover.sh"
```
