#if DEBUG
import AppKit
import SwiftUI

private struct SettingsUpdatePreviewRoot: View {
    let presentation: UpdaterSettingsPresentation
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GeneralSettingsHeader(language: language)

            Form {
                Section {
                    Toggle(isOn: .constant(true)) {
                        Text(ContractCopy.copyGeneralDarkwake.text(for: language))
                    }
                    .toggleStyle(.switch)

                    LabeledContent(ContractCopy.copyGeneralDarkwakeLast.text(for: language)) {
                        Text("2026-11-03 08:12")
                            .foregroundStyle(.secondary)
                    }

                    Picker(ContractCopy.copyGeneralSleepMode.text(for: language), selection: .constant(3)) {
                        Text("3 · Default").tag(3)
                    }
                    .pickerStyle(.menu)

                    Picker(ContractCopy.copyGeneralLanguage.text(for: language), selection: .constant(0)) {
                        Text(ContractCopy.copyGeneralLanguageSystem.text(for: language)).tag(0)
                    }
                    .pickerStyle(.menu)
                }

                Section {
                    Toggle(isOn: .constant(false)) {
                        Text(ContractCopy.copyGeneralLaunchAtLogin.text(for: language))
                    }
                    .toggleStyle(.switch)

                    Toggle(isOn: .constant(true)) {
                        Text(ContractCopy.copyGeneralNotifications.text(for: language))
                    }
                    .toggleStyle(.switch)
                }

                Section {
                    UpdaterSettingsFormContent(
                        presentation: presentation,
                        language: language,
                        onAutomaticUpdates: { _ in },
                        onCheck: {},
                        onInstall: {},
                        onRestart: {}
                    )
                } header: {
                    Text(ContractCopy.copyGeneralSectionUpdates.text(for: language))
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: 760, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, HubMetrics.panelPadding)
        .frame(width: 960, height: 600, alignment: .topLeading)
        .background(MacTheme.canvas)
    }
}

@MainActor
enum SettingsUpdatePreviewRenderer {
    static func render(to path: String) async -> Bool {
        let previousMode = GlassSurfaceMode.current
        GlassSurfaceMode.current = .material
        defer { GlassSurfaceMode.current = previousMode }

        let isDark = ProcessInfo.processInfo.environment["AppleInterfaceStyle"]?
            .lowercased() == "dark"
            || ProcessInfo.processInfo.environment["COVIO_FORCE_APPEARANCE"]?.lowercased() == "dark"
        let colorScheme: ColorScheme = isDark ? .dark : .light
        let language = AppLanguage.simplifiedChinese
        let presentation = UpdaterSettingsPresentation(
            status: UpdaterStatus(
                schemaVersion: 1,
                updaterProtocolVersion: 1,
                releaseId: "0.0.1.9-g\(String(repeating: "a", count: 40))",
                state: .available,
                automaticUpdatesEnabled: true,
                lastCheckAt: "2026-11-04T00:00:00Z",
                availableVersion: "0.0.2.0",
                message: nil
            ),
            busy: false,
            unavailable: false,
            language: language
        )
        let size = NSSize(width: 960, height: 600)
        let hosting = NSHostingView(
            rootView: SettingsUpdatePreviewRoot(
                presentation: presentation,
                language: language
            )
            .environment(\.colorScheme, colorScheme)
        )
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        window.contentView = hosting
        window.orderFront(nil)
        hosting.layoutSubtreeIfNeeded()
        do {
            try await Task.sleep(for: .milliseconds(350))
        } catch {
            window.orderOut(nil)
            return false
        }
        hosting.layoutSubtreeIfNeeded()
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            window.orderOut(nil)
            return false
        }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        window.orderOut(nil)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            return false
        }
        do {
            try png.write(to: URL(fileURLWithPath: path), options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
#endif
