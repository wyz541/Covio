#if DEBUG
import AppKit
import ScreenCaptureKit
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

private final class SettingsPreviewWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
enum SettingsUpdatePreviewRenderer {
    static func render(to path: String) async -> Bool {
        let isDark = ProcessInfo.processInfo.environment["AppleInterfaceStyle"]?
            .lowercased() == "dark"
            || ProcessInfo.processInfo.environment["COVIO_FORCE_APPEARANCE"]?.lowercased() == "dark"
        let colorScheme: ColorScheme = isDark ? .dark : .light
        let language = AppLanguage.simplifiedChinese
        let state: UpdaterEngineState
        switch ProcessInfo.processInfo.environment["COVIO_SETTINGS_UPDATE_PREVIEW_STATE"] {
        case "restartRequired":
            state = .restartRequired
        case "idle":
            state = .idle
        default:
            state = .available
        }
        let presentation = UpdaterSettingsPresentation(
            status: UpdaterStatus(
                schemaVersion: 1,
                updaterProtocolVersion: 1,
                releaseId: "0.6.0-internal.23-g\(String(repeating: "a", count: 40))",
                state: state,
                automaticUpdatesEnabled: true,
                lastCheckAt: "2026-11-04T00:00:00Z",
                availableVersion: state == .available ? "0.6.0-internal.24" : nil,
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
        let window = SettingsPreviewWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        window.contentView = hosting
        window.center()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeKey()
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        do {
            try await Task.sleep(for: .milliseconds(350))
        } catch {
            window.orderOut(nil)
            return false
        }
        hosting.needsLayout = true
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        let bitmap: NSBitmapImageRep
        if let image = await screenCapture(window: window, size: size) {
            bitmap = NSBitmapImageRep(cgImage: image)
        } else if let cached = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
            hosting.cacheDisplay(in: hosting.bounds, to: cached)
            bitmap = cached
        } else {
            window.orderOut(nil)
            return false
        }
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

    private static func screenCapture(window: NSWindow, size: CGSize) async -> CGImage? {
        for _ in 0..<4 {
            if let content = try? await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            ), let capturedWindow = content.windows.first(where: {
                $0.windowID == CGWindowID(window.windowNumber)
            }) {
                let configuration = SCStreamConfiguration()
                configuration.width = Int(size.width * 2)
                configuration.height = Int(size.height * 2)
                configuration.showsCursor = false
                let filter = SCContentFilter(desktopIndependentWindow: capturedWindow)
                return try? await SCScreenshotManager.captureImage(
                    contentFilter: filter,
                    configuration: configuration
                )
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }
}
#endif
