#if DEBUG
import AppKit
import SwiftUI
import kmpDomain

private struct AgentPreviewRoot: View {
    private let language = AppLanguage.simplifiedChinese
    @State private var agent = AgentChatRuntime.preview()

    var body: some View {
        AgentTabView(agent: agent, language: language)
            .padding(HubMetrics.panelPadding)
            .frame(
                width: HubMetrics.panelWidth,
                height: HubMetrics.agentBodyHeight + HubMetrics.panelPadding * 2
            )
            .background(MacTheme.canvas)
    }
}

@MainActor
enum AgentPreviewRenderer {
    static func render(to path: String) async -> Bool {
        let previousMode = GlassSurfaceMode.current
        GlassSurfaceMode.current = .material
        defer { GlassSurfaceMode.current = previousMode }

        let colorScheme: ColorScheme = ProcessInfo.processInfo.environment["AppleInterfaceStyle"]?
            .lowercased() == "dark" ? .dark : .light
        let size = NSSize(
            width: HubMetrics.panelWidth,
            height: HubMetrics.agentBodyHeight + HubMetrics.panelPadding * 2
        )
        let hosting = NSHostingView(
            rootView: AgentPreviewRoot().environment(\.colorScheme, colorScheme)
        )
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
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
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return false }
        do {
            try png.write(to: URL(fileURLWithPath: path), options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
#endif
