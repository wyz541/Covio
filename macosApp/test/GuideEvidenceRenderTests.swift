import AppKit
import SwiftUI
import XCTest
@testable import Covio

/// 为项目说明书生成真实 SwiftUI 组件的证据图。
///
/// 产物写到 `build/guide-evidence/`。测试只渲染现有产品组件，
/// 不改运行时的配置、截图目录或系统设置。
@MainActor
final class GuideEvidenceRenderTests: XCTestCase {
    func testRenderPilotComponentEvidence() async throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let outputDirectory = repositoryRoot.appendingPathComponent("build/guide-evidence", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        try await render(
            GuideButtonEvidenceView(),
            size: NSSize(width: 720, height: 180),
            output: outputDirectory.appendingPathComponent("button.png")
        )

    }

    func testRenderSettingControlEvidence() async throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let outputDirectory = repositoryRoot.appendingPathComponent("build/guide-evidence", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        try await render(
            GuideSwitchEvidenceView(),
            size: NSSize(width: 720, height: 250),
            output: outputDirectory.appendingPathComponent("switch.png")
        )
        try await render(
            GuideNumberFieldEvidenceView(),
            size: NSSize(width: 720, height: 250),
            output: outputDirectory.appendingPathComponent("number-field.png")
        )
        try await render(
            GuideSegmentedEvidenceView(),
            size: NSSize(width: 720, height: 270),
            output: outputDirectory.appendingPathComponent("segmented.png")
        )
        try await render(
            GuideSettingRowEvidenceView(),
            size: NSSize(width: 720, height: 250),
            output: outputDirectory.appendingPathComponent("setting-row.png")
        )
    }

    private func render<Content: View>(
        _ content: Content,
        size: NSSize,
        output: URL,
        waitMilliseconds: UInt64 = 250
    ) async throws {
        let root = NSHostingView(rootView: content.frame(width: size.width, height: size.height))
        root.frame = NSRect(origin: .zero, size: size)
        root.layoutSubtreeIfNeeded()

        let window = NSWindow(
            contentRect: root.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = root
        window.orderFront(nil)
        root.layoutSubtreeIfNeeded()
        try? await Task.sleep(for: .milliseconds(waitMilliseconds))
        root.layoutSubtreeIfNeeded()

        let representation = try XCTUnwrap(root.bitmapImageRepForCachingDisplay(in: root.bounds))
        root.cacheDisplay(in: root.bounds, to: representation)
        let data = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(data.count, 1_000)
        try data.write(to: output, options: .atomic)
        window.orderOut(nil)
        window.contentView = nil
    }

    private func makeScreenshotSource(repositoryRoot: URL) throws -> Data {
        let trayEvidence = repositoryRoot.appendingPathComponent(
            "guide/src/content/docs/components/tray-icon/evidence/2026-10-22__macbook-pro__macos-27.0.1__dark__EV-TRAY-001.png"
        )
        let imageURL = FileManager.default.fileExists(atPath: trayEvidence.path)
            ? trayEvidence
            : repositoryRoot.appendingPathComponent("assets/Covio.png")
        let image = try XCTUnwrap(NSImage(contentsOf: imageURL))
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }
}

@MainActor
private struct GuideButtonEvidenceView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                MacButton(title: "主要操作", kind: .primary) {}
                MacButton(title: "次要操作", kind: .secondary) {}
                MacButton(title: "清除", kind: .plain) {}
            }

            HStack(spacing: 12) {
                MacButton(title: "不可用", isEnabled: false) {}
                MacButton(title: "不可用主操作", kind: .primary, isEnabled: false) {}
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(MacTheme.canvas)
    }
}

@MainActor
private struct GuideSwitchEvidenceView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: MacTheme.space4) {
            Text("关闭")
            HStack {
                Text("自动检查更新")
                Spacer()
                MacSwitch(label: "自动检查更新", isOn: .constant(false))
            }
            Text("开启")
            HStack {
                Text("自动检查更新")
                Spacer()
                MacSwitch(label: "自动检查更新", isOn: .constant(true))
            }
            HStack {
                Text("不可用")
                Spacer()
                MacSwitch(label: "自动检查更新", isOn: .constant(true), isEnabled: false)
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(MacTheme.textPrimary)
        .padding(MacTheme.space8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(MacTheme.canvas)
    }
}

@MainActor
private struct GuideNumberFieldEvidenceView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: MacTheme.space4) {
            HStack {
                Text("有效数值")
                Spacer()
                MacNumberField(label: "充电上限", text: .constant("85"))
            }
            HStack {
                Text("非数字输入")
                Spacer()
                MacNumberField(label: "充电上限", text: .constant("八十五"))
            }
            HStack {
                Text("不可用")
                Spacer()
                MacNumberField(label: "充电上限", text: .constant("85"), isEnabled: false)
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(MacTheme.textPrimary)
        .padding(MacTheme.space8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(MacTheme.canvas)
    }
}

@MainActor
private struct GuideSegmentedEvidenceView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: MacTheme.space5) {
            Text("界面语言")
            MacSegmented(options: ["简体中文", "English"], selectedIndex: 0) { _ in }
            Text("休眠模式")
            MacSegmented(options: ["0", "3", "25"], selectedIndex: 1) { _ in }
                .disabled(true)
        }
        .font(.system(size: 13))
        .foregroundStyle(MacTheme.textPrimary)
        .padding(MacTheme.space8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(MacTheme.canvas)
    }
}

@MainActor
private struct GuideSettingRowEvidenceView: View {
    var body: some View {
        MacCard {
            MacSettingRow(title: "登录时启动", description: "登录 macOS 后自动启动 Covio") {
                MacSwitch(label: "登录时启动", isOn: .constant(true))
            }
            MacSettingRow(title: "通知", description: "完成操作后显示系统通知") {
                MacSwitch(label: "通知", isOn: .constant(false))
            }
        }
        .padding(MacTheme.space8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(MacTheme.canvas)
    }
}
