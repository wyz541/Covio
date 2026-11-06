import SwiftUI

/// 剪贴板设置页。
struct ClipboardPage: View {
    let runtime: AppRuntime
    @State private var permissionGranted = ClipboardPaste.hasAccessibilityPermission

    var body: some View {
        Form {
            Section {
                Toggle(
                    ContractCopy.copyClipboardSettingsEnabled.text(for: runtime.language),
                    isOn: Binding(
                        get: { runtime.config.clipboardEnabled },
                        set: { runtime.setClipboardEnabled($0) }
                    )
                )
                .toggleStyle(.switch)
                .settingsRowAnchor(SettingsRowID.clipboardEnabled)
            }

            Section {
                ForEach(ClipboardHotKeyAction.allCases, id: \.rawValue) { action in
                    HotKeyRow(action: action, runtime: runtime)
                }
            } header: {
                Text(ContractCopy.copyClipboardSettingsHotKeys.text(for: runtime.language))
            }
            .settingsRowAnchor(SettingsRowID.clipboardHotKeys)

            Section {
                LabeledContent(ContractCopy.copyClipboardSettingsAccessibility.text(for: runtime.language)) {
                    Text(accessibilityText)
                        .foregroundStyle(permissionGranted ? .green : .secondary)
                }

                HStack(spacing: MacTheme.space2) {
                    Button(ContractCopy.copyClipboardSettingsRequestPermission.text(for: runtime.language)) {
                        ClipboardPaste.requestAccessibilityPermission()
                    }
                    .buttonStyle(.borderedProminent)

                    Button(ContractCopy.copyClipboardActionOpenSettings.text(for: runtime.language)) {
                        ClipboardPaste.openAccessibilitySettings()
                    }
                    .buttonStyle(.bordered)
                }

                Label(
                    ContractCopy.copyClipboardSettingsAccessibilityFallback.text(for: runtime.language),
                    systemImage: "info.circle"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissionGranted = ClipboardPaste.hasAccessibilityPermission
        }
    }

    private var accessibilityText: String {
        (permissionGranted ? ContractCopy.copyClipboardSettingsGranted : ContractCopy.copyClipboardSettingsNotGranted)
            .text(for: runtime.language)
    }
}
