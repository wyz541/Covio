# Covio

Covio is a macOS menu-bar app.
It controls sleep behavior. It indexes native macOS screenshots in the Files area.

Covio is an independent implementation.
It does not use the Tendedero name, icon, or documentation images.

## Product design

- [Design contract](docs/covio-design-contract.json) is the machine-readable design authority.
- [Design contract schema](docs/covio-design-contract.schema.json) validates the contract structure.
- The Covio Figma file is the visual projection used for implementation verification.
- Static design status: 8 pages, 8 sections, 35 boards, 130 source component sets, 186 component nodes, and 42 prototype reactions. Static visual audit passed.

Each component carries a `composeMapping` and a `swiftMapping`.
The macOS host reads the Swift mapping. The Compose host reads the other one.

**Note:** The JSON schema cannot express "`swiftMapping` is required on macOS".
The check is in `scripts/validate-contract.py`.
The script also checks the rules that cross two sections of the contract.

## Research

- [Research archive](docs/research/README.md) defines the research archive rules and links each research topic.

## Workflow

Ideas turn into research reports, research reports into decisions, and decisions into issues.

- [Agent contract](AGENTS.md) is the rule set that Claude Code and Codex load each session.
- [Workflow](docs/process/workflow.md) is the seven-step process. The agent contract carries the per-session rules.
- [Architecture decisions](docs/adr/) hold the accepted decisions. The template is `docs/adr/adr-template.md`.

A big feature gets one parent issue and child issues, linked as GitHub sub-issues.
A small feature gets one issue.
Progress is read from GitHub. The repository does not hold issue definitions.

`main` is the trunk. Changes to `main` go through a pull request.

## Download (internal test)

Covio is under internal test.
Covio 0.0.1.7 is the current internal build.
This build uses the legacy `0.6.0 build 15` label.
The next build uses client version `0.0.1.6`.
It requires macOS 26 or later on Apple Silicon.
The default installer does not contain model weights.
Covio downloads the model after user confirmation.
This release does not provide an offline model installer.
Validation results are in `docs/research/installer-size-reduction/validation/`.

- [Default DMG](https://github.com/wyz541/kmp-Covio/releases/download/v0.0.1.7-internal/Covio-0.0.1.7.dmg)
- [Transactional PKG](https://github.com/wyz541/kmp-Covio/releases/download/v0.0.1.7-internal/Covio-0.0.1.7.pkg)
- [Release page](https://github.com/wyz541/kmp-Covio/releases/tag/v0.0.1.7-internal)
- [Checksums](https://github.com/wyz541/kmp-Covio/releases/download/v0.0.1.7-internal/checksums.txt)
- [Covio 0.6.0 internal build 15](https://github.com/wyz541/kmp-Covio/releases/tag/v0.6.0-internal.15) is the previous internal test.
- [Covio 0.6.0 internal build 14](https://github.com/wyz541/kmp-Covio/releases/tag/v0.6.0-internal.14) is an older internal test.
- [Covio 0.6.0 internal build 13](https://github.com/wyz541/kmp-Covio/releases/tag/v0.6.0-internal.13) is an older internal test.
- [Covio 0.6.0 internal build 12](https://github.com/wyz541/kmp-Covio/releases/tag/v0.6.0-internal.12) is an older internal test.
- [Covio 0.6.0 internal build 11](https://github.com/wyz541/kmp-Covio/releases/tag/v0.6.0-internal.11) is an older internal test.
- [Covio 0.6.0 internal build 10](https://github.com/wyz541/kmp-Covio/releases/tag/v0.6.0-internal.10) is an older internal test.
- [Covio 0.6.0 internal build 9](https://github.com/wyz541/kmp-Covio/releases/tag/v0.6.0-internal.9) is the previous internal test.
- [Covio 0.6.0 internal build 8](https://github.com/wyz541/kmp-Covio/releases/tag/v0.6.0-internal.8) is the previous internal test.
- [Covio 0.6.0 internal build 7](https://github.com/wyz541/kmp-Covio/releases/tag/v0.6.0-internal.7) is the previous internal test.
- [Covio 0.6.0 internal build 6](https://github.com/wyz541/kmp-Covio/releases/tag/v0.6.0-internal.6) is an older internal test.
- [Covio 0.5.2 internal build 5](https://github.com/wyz541/kmp-Covio/releases/tag/v0.5.2-internal.5) is an older internal test.
- [Covio 0.5.1](https://github.com/wyz541/kmp-Covio/releases/tag/v0.5.1) is an older internal test.
- [Covio 0.4.2](https://github.com/wyz541/kmp-Covio/releases/tag/v0.4.2) is an older internal test.

Install steps:

1. Open `Covio-0.6.0.dmg`.
2. Drag `Covio.app` to `Applications`.
3. Open `Covio.app`.
4. Open an AI feature and confirm the model download.

Covio uses a clean install.
Covio does not copy settings from older internal-test builds.

**Warning:** This build uses an ad-hoc signature.
macOS Gatekeeper rejects this build.
Allow the app in Privacy & Security, or clear the quarantine flag:

```sh
xattr -dr com.apple.quarantine /Applications/Covio.app
```

Checksums are in the release `checksums.txt` asset.

## Version identity

The user-facing client version has four decimal digits: `0.0.1.6`.
The build number is padded to four digits and split into `thousands.hundreds.tens.ones`.
Examples: build `15` is `0.0.1.5`, build `16` is `0.0.1.6`, and build `100` is `0.1.0.0`.
The product version `0.6.0` is separate metadata.
The channel, Git commit, and helper protocol are also separate fields.

The internal tag is `v<clientVersion>-internal`.
A stable tag is `v<clientVersion>`.
The release ID is `<clientVersion>-g<fullGitSHA>`.
The build number controls upgrade order. The Git commit does not control upgrade order.

## What changed in build 7

- Helper status probes run outside the main thread.
- An unavailable or mismatched helper no longer blocks the UI.
- Workbench navigation keeps a stable layout.
- Changing the interface language keeps workbench navigation consistent.
- Home widgets support free positioning.
- The default charge limit is 70%.
- The experimental closed-lid black screen preview is enabled by default.
- All build 6 features remain available.

## What is new in 0.6.0

- The workbench opens with a two-finger downward swipe on the built-in trackpad.
- Workbench navigation uses text-only tabs, one glass search field, and a fixed action slot.
- Covio follows the macOS system language when no app language is set.
- Clipboard uses a recency-first list, type filters, search, pinned groups, and a fixed detail pane.
- Clipboard supports keyboard selection, two-step selection reset, double-click paste, and VoiceOver actions.
- Clipboard text details render Markdown while copy, paste, search, and storage keep the original text.
- Monitor battery and power cards share one layout. Redundant badges are removed.
- Closed-lid protection reports success only after the helper applies the setting and owns the lease.
- The default installer is slim. Covio downloads and verifies the model after user confirmation.
- App and helper upgrades use the transactional PKG path.
- All 0.5.2 features remain available.

## What is new in 0.5.2

- The default installer no longer carries model weights.
- The optional offline installer carries the verified Qwen3-VL 2B model.
- The app downloads the fixed model revision after user confirmation.
- The downloader resumes after restart and verifies every file before registration.
- Charge-limit target repair continues while the battery is charging.
- Target repair retries are rate-limited and no longer remain blocked in `applying`.
- The current-target field reports the target that macOS actually registered.
- Active discharge keeps the configured limit instead of falling back to the old target.
- A developer-only fan capability preview uses Swift Charts.
  Production fan control is unchanged.
- All 0.5.1 features remain available.
- `config.json` remains compatible with 0.4.2.

## What is new in 0.5.1

- The workbench ignores navigation hover for 0.5 seconds after it opens. Clicking still works.
- Power and fan card popovers keep the workbench open while the user operates them.
- Closing the last popover restores the normal pointer-exit collapse behavior.
- Workbench navigation buttons use Liquid Glass.
- The Files area indexes native macOS screenshots without taking over screenshot capture.
- `config.json` remains compatible with 0.4.2.

## What is new in 0.5.0

- The macOS interface is SwiftUI. Shared logic is Kotlin Multiplatform.
- The app requires macOS 26 or later.
- The Hub uses a Liquid Glass base plate and an adaptive glass navigation layer.
- Settings search opens the matching row and highlights it.
- Clipboard history keeps recent text, images, and files.
- Files adds local offline auto naming with preview, safe rename, and undo.
- The Files tab indexes native macOS screenshots. Covio does not take over screenshot capture.
- Monitor shows CPU, GPU, memory, disk, network, battery, and power telemetry.
- The power card shows charging data, power events, and top energy users.
- The fan card shows RPM trends and provides automatic and manual fan control.
- Sleep, lid, DarkWake, helper, and LaunchAgent functions remain available.
- `config.json` is compatible with 0.4.2 in both directions.

The sections below describe earlier releases. See **Screenshots** for current behavior.

## What is new in 0.4.2

- The project name is Covio.
- The Kotlin package is `com.wyz.covio`.
- The application identifier is `com.wyz.covio`.
- The app uses `Covio` for settings, logs, the helper, and the LaunchAgent.

## What is new in 0.4.1

- The app fixes a crash that happened when you opened Markup from a screenshot card.
- The app opens Markup on the main thread through a native helper.
- If Markup is unavailable, the app opens Preview.

## What is new in 0.4.0

- The app adds the screenshot toolbar.
- The app keeps the sleep, lid, DarkWake, helper, and LaunchAgent functions.
- The app adds a full-width screenshot toolbar at the top of the mouse screen.
- Screenshot takeover is on by default.
- New screenshots appear in the toolbar.
- A click copies the image and file URL.
- A double-click opens the preview.
- A long press opens macOS Markup. If Markup is unavailable, Preview opens.
- A right-click opens the screenshot menu.
- Dragging to an app copies the file and keeps the card.
- Dragging to a folder or the Desktop moves the file and removes the card.
- Dragging to the Trash deletes the file and removes the card.
- A canceled or failed drag returns the card.
- `Control+Option+T` shows or hides the toolbar.
- The Tray menu and the Top Shelf settings page control screenshot behavior.
- The settings and log use the `com.wyz.covio` application identifier.

## Screenshots

Covio uses native macOS screenshot capture.
Covio does not change these settings:

- `location`
- `location-screenshot`
- `show-thumbnail`

Covio watches the screenshot directory that macOS uses.
A new screenshot appears in the Hub under **Files** and then **Screenshots**.
The screenshot file stays in its original directory.

Covio stores screenshot paths in `shelf.json`.
Covio does not store a second copy of the image.
Covio does not send screenshot data to the network.

If an older Covio version changed the system screenshot settings, Covio restores the saved values once.
Covio then removes the saved preference snapshot.

## Clipboard history

Covio keeps a clipboard history. Open the Hub and select the Clipboard tab.

- Copy text, links, colors, images, or files. Covio adds each one to the list.
- Select an item to copy it back to the clipboard.
- Select Paste to copy the item and press `Command+V` in the front app.
- Select Pin to keep an item. Clear All keeps pinned items.
- Select Pause to stop recording. Covio keeps the list.
- `Shift+Command+V` pastes the next item from the paste stack.
- `Shift+Command+C` copies the selection of the front app.

The Clipboard settings page shows the two shortcuts. Select a different combination when another app already uses one. Covio shows `Registration failed` in that case.

Paste needs the Accessibility permission. Without it, copying still works and you press `Command+V` yourself.

The retention policy keeps 100 items, 7 days, and 200 MB.
Pinned items are always kept.
Images are stored as files. Text recognition runs on each image, so you can find an image by the text inside it.

The clipboard directory is:

```text
~/Library/Application Support/Covio/Clipboard
```

Clipboard data stays on this Mac.
Covio does not send clipboard data to the network.

## Local file auto naming

Open the Hub and select the Files tab.
Select `Auto Name…` and choose one or more files.

Covio extracts local content and proposes a name.
The supported inputs are text, code, PDF, images, and mixed files.
The app shows the original name, proposed name, evidence, confidence risk, conflict state, and per-item result.
Covio does not rename until you select and confirm the ready items.

The feature uses `Qwen3-VL-2B-Instruct-4bit` through MLX Swift.
The model runs on this Mac.
Covio does not call a remote AI service.
File content does not leave the Mac.

The default naming policy is under `fileNaming` in `config.json`:

```json
{
  "fileNaming": {
    "schemaVersion": 1,
    "template": "{title}",
    "maxUTF8Bytes": 240,
    "separator": "-",
    "lowercaseLatin": false,
    "preserveExtension": true,
    "dateSource": "none",
    "conflictPolicy": "appendNumber",
    "conflictSuffix": " ({n})",
    "minConfidence": 0.65,
    "requirePreview": true,
    "allowVision": true
  }
}
```

The template can use `{title}` and `{category}`.
`{date}` and `{language}` are reserved fields.
This build leaves the reserved fields empty and blocks templates that require them.
The template must contain `{title}`.
The extension, preview requirement, character checks, and no-overwrite rule cannot be disabled.

Covio writes the undo plan before it renames a file.
Undo plans are stored in:

```text
~/Library/Application Support/com.wyz.covio/rename-undo
```

The model license and attribution are in `THIRD_PARTY_NOTICES.md`.

## Sleep and lid features

- Sleep at the low-battery capacity threshold.
- Sleep at the low-battery time threshold.
- Prevent idle sleep on AC power.
- Prevent lid sleep on AC power.
- Prevent lid sleep on battery power. This option drains the battery.
- Experimental closed-lid zero brightness is on by default. It keeps the panel dark only while the built-in display remains online and active.
- You must start a closed-lid session before closing the lid. A display that is already asleep cannot be revived by writing brightness.
- Detect DarkWake and full wake events from the `pmset` wake log.
- Sleep immediately when the lid closes.
- Cancel a prevention rule after a selected delay.
- Run Sleep Now or Turn Display Off from the Tray menu.
- Set hibernation mode 0, 3, or 25.
- Detect lid changes with `IOServiceAddInterestNotification`.
- Start at login with a LaunchAgent.
- Restart after a crash with `KeepAlive.SuccessfulExit=false`.
- Clear the configuration from the Tray menu or the General settings page.
- Cache the system idle timeout for 60 seconds.
- Cache the wake log for 60 seconds.
- Show notifications and write a rotating log.
- Check the GitHub Releases page for a stable update.
- Show English and Simplified Chinese text.

## Requirements

- macOS 26 or later. Covio 0.4.x stays on macOS 12.
- An Apple Silicon Mac.
- Xcode 27 to build the SwiftUI host.
- JDK 25 for the shared layer.

## Build and test

Run every test:

```sh
bash scripts/test-all.sh
```

The script runs the Kotlin tests, checks the design-contract constants, checks the contract rules that the schema cannot express, checks with the helper cutover script, and runs the macOS XCTest suite.

Build one side only:

```sh
/bin/sh ./kotlin test          # the shared layer, on jvm and macosArm64
bash scripts/build-kmp-framework.sh   # write build/kmp-framework/kmpDomain.framework
bash scripts/build-macos-swift.sh     # build the SwiftUI host
bash scripts/test-macos-swift.sh      # run the SwiftUI host XCTest suite
```

After you change the design contract, run these two:

```sh
python3 scripts/validate-contract.py            # the cross-section rules
python3 scripts/generate-contract-constants.py  # rewrite the Swift constants
```

The SwiftUI host reads its text and its tokens from `ContractCopy.swift` and `ContractTokens.swift`.
Both files are generated. Do not edit them by hand.

The macOS host is SwiftUI. The shared layer is Kotlin Multiplatform, module `kmpDomain`.
The host links `kmpDomain.framework`. Open `macosApp/Covio.xcodeproj` to work on the host.

The project signs ad-hoc by default.
Ad-hoc signing has no Team ID, so macOS identifies the app by its cdhash.
Every build changes the cdhash, so macOS treats each build as a new app.
Then macOS asks for Accessibility again, and posts the "Device Control and Data Access" notice again.

To keep the grant across builds, pin a code-signing certificate:

1. Create a certificate. The steps are in `docs/adr/adr-0005-local-code-signing.md`.
2. Create `macosApp/Signing.local.xcconfig`:

   ```text
   CODE_SIGN_IDENTITY = Covio Dev
   CODE_SIGN_STYLE = Manual
   ```

3. Build the app, then grant Accessibility once. Later builds keep the grant.

`macosApp/Signing.local.xcconfig` is in `.gitignore`.
CI has no certificate, so CI uses the ad-hoc default.

The build and test scripts verify the main app and its nested code.
When a local certificate is configured, the check compares the signing identity with the previous development build.
The first build creates `build/xcode-dd/development-signing-Debug-build.json`.
Delete this baseline only when a certificate or Bundle ID change is intentional.

Run the check directly with:

```sh
python3 -I scripts/verify_macos_signing.py \
  build/xcode-dd/Build/Products/Debug/Covio.app \
  --require-stable \
  --baseline build/xcode-dd/development-signing-Debug-build.json
```

The `CDHash` can change after a rebuild.
The `Identifier` and `designated =>` value must stay the same.
Keep the development app at one path during the authorization test.
The canonical install path is `/Applications/Covio.app`.
Do not switch between separate app copies.
Use temporary fixtures for permission tests, not the real Desktop.

The SwiftUI host is on macOS only.
It uses the same `config.json` as the Compose version.
The two versions use different lock files, so both can run at the same time.

## Package

The default app is slim and does not contain model weights.
The optional offline package contains the verified model.
Model weights are not in Git.

1. Prepare the release identity:

   ```sh
   bash scripts/setup-local-signing.sh
   python3 scripts/release_manifest.py bump
   python3 scripts/release_manifest.py check
   ```

   Internal Release creation requires the `Covio Dev` identity.
   `scripts/create-release.sh` fails when the stable identity is missing.

2. Package the default slim app:

   ```sh
   bash scripts/package-macos-swift.sh
   ```

   The default DMG must not exceed `50 MB` and must not contain model weights.

3. Optionally download the model and build the offline package:

   ```sh
   python3 scripts/file_naming_model.py download build/models/Qwen3VL-2B-Instruct-4bit
   COVIO_FILE_NAMING_MODEL_DIR=build/models/Qwen3VL-2B-Instruct-4bit \
     bash scripts/package-macos-offline-swift.sh
   ```

4. Verify the optional offline DMG in a network-denied sandbox:

   ```sh
   bash scripts/verify-file-naming-bundle.sh dist/Covio-Offline-0.0.1.6.dmg
   ```

The package script writes these files:

- `dist/Covio.app`
- `dist/Covio-0.0.1.6.dmg`
- `dist/Covio-0.0.1.6.pkg`
- `dist/Covio-0.0.1.6.app.zip`
- `dist/release-manifest.json`

The offline packaging command adds:

- `dist/Covio-Offline.app`
- `dist/Covio-Offline-0.0.1.6.dmg`

The default script verifies the model manifest and rejects model weights in the app.
The offline script verifies model file sizes, SHA-256 values, license, and NOTICE.
The offline script embeds the model under `Contents/Resources/Models/Qwen3VL-2B-Instruct-4bit/`.
The script reads client version, product version, build number, channel, Git commit, and helper protocol from `release/release-manifest.json`.
The bundle must carry the same separate fields.
The script writes the final release identity, Git commit, helper SHA-256, installer identities, and model identity to `dist/release-manifest.json`.
The app contains `Contents/MacOS/CovioHelper`. The PKG installs the matching helper and LaunchDaemon at fixed root-owned paths.
The script checks that the bundle carries `macosApp/src/Covio.icns`.
The internal package uses the local `Covio Dev` identity when available.
CI packaging without a certificate uses an ad-hoc signature.
The script builds the DMG with `diskutil image create`.
The script prints app and DMG byte sizes.

The default app downloads model packages through `macosApp/src/Model/LocalModelDownload.swift`.
The downloader uses a fixed manifest revision and stores files under `$HOME/Library/Application Support/com.wyz.covio/Models/`.
It pauses and resumes through the Hub download cache.
It verifies the complete package before registering it.
The manifest, status, registry, and path rules live in `kmpDomain/src/com/wyz/covio/core/ModelPackageContract.kt`.
A JVM or Windows host supplies transport and storage adapters. The model runtime remains platform-specific.
The Windows runtime boundary is recorded in [#391](https://github.com/wyz541/kmp-Covio/issues/391).
The Agent and file naming views show one shared model setup panel.
The panel shows model size, license, network need, progress, failures, import, and removal.

Create a Draft Release with the default slim package:

```sh
bash scripts/create-release.sh
```

Create a Draft with the optional offline package:

```sh
COVIO_FILE_NAMING_MODEL_DIR=build/models/Qwen3VL-2B-Instruct-4bit \
  bash scripts/create-release.sh --with-offline
```

Publish the verified Draft with:

```sh
bash scripts/publish-release.sh v<clientVersion>-internal
```

`.pkg` is the transactional install and upgrade entry.
The PKG stages the new app, exchanges the app bundle atomically, and validates the new helper handshake before writing the installed release record.
Recover an interrupted install transaction:

```sh
sudo "/Library/Application Support/Covio/Installer/recover.sh"
```

The offline model adds about 1.8 GB before DMG compression.
Use `python3 scripts/file_naming_model.py verify-manifest` to validate the fixed file list without downloading weights.

The icon source is `assets/Covio.iconset`. Run `iconutil --convert icns --output macosApp/src/Covio.icns assets/Covio.iconset` after a change.
The Xcode target copies `macosApp/src/Covio.icns` into the bundle, so every build carries the icon.

The app is arm64 only. `kmpDomain.framework` has one slice, `macosArm64`.

## Real-Mac acceptance checklist

Run this checklist before a public release.
The current internal test does not complete this checklist.

File naming passed the 12-sample matrix on a 64 GB Apple Silicon Mac.
Exact 8 GB hardware validation is tracked by [#185](https://github.com/wyz541/kmp-Covio/issues/185).

1. Install the build under test.
2. Confirm the app version and build number match `release/release-manifest.json`.
3. Install the privileged helper.
4. Confirm the helper release identity and executable SHA-256 match the app.
5. Record `defaults read com.apple.screencapture`. Take a screenshot. Confirm the values do not change.
6. Confirm the native macOS thumbnail remains visible.
7. Confirm the screenshot appears in **Files** → **Screenshots**.
8. Copy, preview, and mark up the screenshot from the file area.
9. Remove the screenshot from the index. Confirm the file remains on disk.
10. Confirm an old `shelf.json` item still appears.
11. Enable "Prevent lid sleep on AC power". Close the lid on AC power. Confirm SSH stays connected.
12. Enable "Prevent lid sleep on battery power". Close the lid on battery power. Confirm SSH stays connected.
13. Turn off the battery switch while the lid is closed. Confirm the Mac sleeps and SSH disconnects.
14. Reach the low battery threshold. Confirm the low battery rule wins.
15. Confirm the General page shows the DarkWake time, reason, and 24-hour count.
16. Fully wake the Mac. Confirm the timers restore or the policy recalculates.
17. Change the sleep mode between 0, 3, and 25.
18. Clear the configuration. Confirm the default values return.
19. Quit the app. Confirm the LaunchAgent does not restart it.
20. Force-quit the app. Confirm the LaunchAgent restarts it.
21. Remove the helper. Confirm `SleepDisabled` is `0`.
22. Set the macOS preferred language to Simplified Chinese. Start Covio. Confirm the interface is Chinese.
23. Set the macOS preferred language to English. Start Covio. Confirm the interface is English.
24. Select **Follow System** in Covio. Change the macOS preferred language to one other than Chinese or English. Restart Covio. Confirm the interface is English.
25. Select **English** manually. Change the macOS preferred language to Simplified Chinese. Restart Covio. Confirm the interface remains English.
