# Release identity

`release/release-manifest.json` is the source of truth for:

- product version
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
  --default-dmg dist/Covio-0.5.2.dmg \
  --offline-dmg dist/Covio-Offline-0.5.2.dmg \
  --model-manifest macosApp/src/AutoNaming/FileNamingModelManifest.json \
  --output dist/release-manifest.json
```

For a default-only artifact manifest, omit `--offline-dmg` and `--model-manifest`.

The generated files are:

- `kmpDomain/src/com/wyz/covio/core/GeneratedReleaseIdentity.kt`
- `macosApp/src/Design/GeneratedReleaseIdentity.swift`
- `macosApp/ReleaseIdentity.generated.xcconfig`

Do not edit generated files by hand.

The source manifest contains the release inputs.
The artifact manifest adds `gitCommit`, `releaseId`, `helperSHA256`, both installer identities and the model identity.
`CovioHelper` statically links `kmpDomain`; the app bundle must not supply its runtime dependencies.

Build the default slim app:

```sh
bash scripts/setup-local-signing.sh
bash scripts/package-macos-swift.sh
```

Internal Release creation requires a stable local signing identity.
The app and helper must use the same certificate.
CI packaging without a certificate still uses ad-hoc signing.

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

Build and create a Draft Release:

```sh
bash scripts/create-release.sh
```

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
