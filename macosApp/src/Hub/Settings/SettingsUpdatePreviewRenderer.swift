#if DEBUG
import AppKit
import SwiftUI

private struct SettingsUpdatePreviewRoot: View {
    let presentation: UpdaterSettingsPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: MacTheme.space6) {
            PaneHeading(
                title: ContractCopy.copyPageGeneralTitle.text(for: presentation.language),
                summary: ContractCopy.copyPageGeneralSummary.text(for: presentation.language)
            )
            UpdaterSettingsCardContent(
                presentation: presentation,
                language: presentation.language,
                onAutomaticUpdates: { _ in },
                onCheck: {},
                onInstall: {},
                onRestart: {}
            )
        }
        .padding(HubMetrics.panelPadding)
        .frame(width: 960, height: 420, alignment: .topLeading)
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
            language: .simplifiedChinese
        )
        let hosting = NSHostingView(
            rootView: SettingsUpdatePreviewRoot(presentation: presentation)
                .environment(\.colorScheme, colorScheme)
        )
        let size = NSSize(width: 960, height: 420)
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
