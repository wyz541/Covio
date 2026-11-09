import XCTest
@testable import Covio

/// Workbench 的 Swift 合同、提交的 JSON 和运行时参数必须一致。
final class WorkbenchInteractionContractTests: XCTestCase {
    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private var contractURL: URL {
        Self.repoRoot.appendingPathComponent("docs/macos-interaction-contract.json")
    }

    /// 提交的 golden 文件必须等于 Swift 合同的确定性导出。
    func testCommittedJSONMatchesTheSwiftContract() throws {
        let committed = try Data(contentsOf: contractURL)
        XCTAssertEqual(try WorkbenchInteractionContract.current.encodedJSON(), committed)
    }

    /// 导出的 JSON 必须能无损解码回 Swift 合同。
    func testCommittedJSONDecodesToTheSwiftContract() throws {
        let data = try Data(contentsOf: contractURL)
        let decoded = try JSONDecoder().decode(WorkbenchInteractionContract.self, from: data)
        XCTAssertEqual(decoded, WorkbenchInteractionContract.current)
    }

    /// macOS 几何必须直接读取合同。
    func testHubGeometryComesFromTheContract() {
        let contract = WorkbenchInteractionContract.current
        XCTAssertEqual(HubMetrics.panelWidth, CGFloat(contract.geometry.panelWidthPoints))
        XCTAssertEqual(
            HubMetrics.contentPlateRadius,
            CGFloat(contract.geometry.panelCornerRadiusPoints)
        )
        XCTAssertEqual(
            HubMetrics.notchlessHotZoneWidth,
            CGFloat(contract.trigger.geometry.notchlessWidthPoints)
        )
        XCTAssertEqual(
            HubMetrics.notchlessHotZoneHeight,
            CGFloat(contract.trigger.geometry.notchlessHeightPoints)
        )
    }

    /// macOS 动效和自动收起必须直接读取合同。
    func testHubMotionComesFromTheContract() {
        let contract = WorkbenchInteractionContract.current
        XCTAssertEqual(HubMotion.expand, contract.reveal.durationSeconds)
        XCTAssertEqual(HubMotion.collapse, contract.conceal.durationSeconds)
        XCTAssertEqual(HubMotion.reducedMotion, contract.reducedMotion.durationSeconds)
        XCTAssertEqual(
            HubMotion.pointerExitCollapseDelay,
            contract.trigger.pointerExitCollapseSeconds
        )
        XCTAssertEqual(HubMotion.triggerDwell, contract.trigger.dwellSeconds)
        XCTAssertEqual(HubMotion.triggerCooldown, contract.trigger.cooldownSeconds)
    }

    /// 显示和隐藏方向必须固定为挂帘从上向下、从下向上。
    func testWorkbenchTransitionDirections() {
        let contract = WorkbenchInteractionContract.current
        XCTAssertEqual(contract.reveal.direction, .topToBottom)
        XCTAssertEqual(contract.conceal.direction, .bottomToTop)
        XCTAssertEqual(contract.reducedMotion.effect, .opacity)
        XCTAssertEqual(contract.reveal.easing.type, .spring)
        XCTAssertEqual(contract.conceal.easing.type, .easeOut)
    }

    /// 每个平台覆盖都必须有稳定 ID、理由和证据。
    func testPlatformOverridesAreTraceable() {
        let overrides = WorkbenchInteractionContract.current.platformOverrides
        XCTAssertEqual(Set(overrides.map(\.id)).count, overrides.count)
        for override in overrides {
            XCTAssertFalse(override.id.isEmpty)
            XCTAssertFalse(override.field.isEmpty)
            XCTAssertFalse(override.reason.isEmpty)
            XCTAssertFalse(override.evidence.isEmpty)
        }
    }
}
