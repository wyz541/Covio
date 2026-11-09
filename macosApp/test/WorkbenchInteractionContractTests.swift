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
        XCTAssertEqual(
            Set(overrides.map(\.field)),
            Set([
                "trigger.cooldownMs",
                "trigger.dwellMs",
                "trigger.geometry.centeredHalfWidthPercent",
                "trigger.geometry.topEdgeThicknessPixels",
            ])
        )
        for override in overrides {
            XCTAssertFalse(override.id.isEmpty)
            XCTAssertFalse(override.field.isEmpty)
            XCTAssertFalse(override.reason.isEmpty)
            XCTAssertFalse(override.evidence.isEmpty)
        }
    }

    /// macOS 和 Windows 必须读取同一份行为向量。
    func testCommittedVectorsMatchTheSwiftContract() throws {
        let data = try Data(
            contentsOf: Self.repoRoot.appendingPathComponent(
                "docs/macos-interaction-contract.vectors.json"
            )
        )
        let vectors = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let contract = WorkbenchInteractionContract.current
        XCTAssertEqual(vectors["contractId"] as? String, contract.contractId)
        XCTAssertEqual(
            vectors["contractSchemaVersion"] as? String,
            contract.schemaVersion
        )
        XCTAssertEqual(vectors["platform"] as? String, "windows")

        let transitions = try XCTUnwrap(
            vectors["easing"] as? [String: Any]
        )
        let tolerance = try XCTUnwrap(transitions["tolerance"] as? Double)
        let samples = try XCTUnwrap(
            transitions["transitions"] as? [[String: Any]]
        )
        for sample in samples {
            let key = try XCTUnwrap(sample["contractKey"] as? String)
            let transition = key == "reveal" ? contract.reveal : contract.conceal
            let easing = try XCTUnwrap(sample["easing"] as? [String: Any])
            XCTAssertEqual(easing["type"] as? String, transition.easing.type.rawValue)
            XCTAssertEqual(
                easing["responseSeconds"] as? Double,
                transition.easing.responseSeconds
            )
            XCTAssertEqual(
                easing["dampingFraction"] as? Double,
                transition.easing.dampingFraction
            )
            XCTAssertEqual(
                try XCTUnwrap(sample["durationMs"] as? Double),
                transition.durationMs
            )
            for point in try XCTUnwrap(sample["samples"] as? [[String: Any]]) {
                let time = try XCTUnwrap(point["time"] as? Double)
                let expected = try XCTUnwrap(point["progress"] as? Double)
                let actual = transition.easing.progress(
                    at: time,
                    durationSeconds: transition.durationSeconds
                )
                XCTAssertEqual(actual, expected, accuracy: tolerance)
            }
        }

        let mappings = try XCTUnwrap(vectors["platformMappings"] as? [[String: Any]])
        XCTAssertEqual(
            Set(mappings.compactMap { $0["field"] as? String }),
            Set(contract.platformOverrides.map(\.field))
        )
        for mapping in mappings {
            let field = try XCTUnwrap(mapping["field"] as? String)
            let expected = try XCTUnwrap(mapping["value"] as? Double)
            let actual = try XCTUnwrap(
                contract.platformOverrides.first { $0.field == field }
            )
            XCTAssertEqual(actual.value, expected, field)
        }

        let stateTransitions = try XCTUnwrap(
            vectors["stateTransitions"] as? [[String: Any]]
        )
        XCTAssertEqual(stateTransitions[0]["direction"] as? String, "topToBottom")
        XCTAssertEqual(stateTransitions[1]["direction"] as? String, "bottomToTop")

        let geometry = try XCTUnwrap(vectors["geometry"] as? [String: Any])
        XCTAssertEqual(
            try XCTUnwrap(geometry["panelWidthPoints"] as? Double),
            contract.geometry.panelWidthPoints
        )
        XCTAssertEqual(
            try XCTUnwrap(geometry["panelCornerRadiusPoints"] as? Double),
            contract.geometry.panelCornerRadiusPoints
        )
        let reducedMotion = try XCTUnwrap(vectors["reducedMotion"] as? [String: Any])
        XCTAssertEqual(
            try XCTUnwrap(reducedMotion["durationMs"] as? Double),
            contract.reducedMotion.durationMs
        )
        XCTAssertEqual(reducedMotion["effect"] as? String, "opacity")

        let testedValues = try XCTUnwrap(vectors["testedContractKeys"] as? [String])
        XCTAssertEqual(testedValues.count, 24)
        let testedKeys = Set(testedValues)
        XCTAssertEqual(testedKeys.count, testedValues.count)
        for key in [
            "trigger.dwellMs",
            "trigger.cooldownMs",
            "trigger.geometry.centeredHalfWidthPercent",
            "trigger.geometry.topEdgeThicknessPixels",
            "reveal.easing",
            "conceal.easing",
            "reducedMotion.effect",
            "geometry.panelCornerRadiusPoints",
        ] {
            XCTAssertTrue(testedKeys.contains(key), key)
        }

        for evidence in try XCTUnwrap(vectors["evidence"] as? [[String: Any]]) {
            for path in try XCTUnwrap(evidence["paths"] as? [String]) {
                XCTAssertTrue(
                    FileManager.default.fileExists(
                        atPath: Self.repoRoot.appendingPathComponent(path).path
                    ),
                    path
                )
            }
        }
    }

}
