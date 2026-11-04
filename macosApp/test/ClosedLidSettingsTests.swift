import XCTest
@testable import Covio

final class ClosedLidSettingsTests: XCTestCase {
    func testPowerSessionPickerExposesOnlyOpenLidModes() {
        XCTAssertEqual(
            PowerSessionPresentation.availableModes,
            [.system, .display]
        )
    }

    func testClosedLidTimeCapIsOnlyShownWhenThePolicyKeepsAwake() {
        XCTAssertFalse(ClosedLidSettingsPresentation.showsTimeCap(for: .sleep))
        XCTAssertTrue(ClosedLidSettingsPresentation.showsTimeCap(for: .adapter))
        XCTAssertTrue(ClosedLidSettingsPresentation.showsTimeCap(for: .battery))
        XCTAssertTrue(ClosedLidSettingsPresentation.showsTimeCap(for: .any))
    }

    func testClosedLidTimeCapOptionsStayInsideTheRuntimeRange() {
        let options = ClosedLidSettingsPresentation.timeCapOptions
        XCTAssertEqual(options, options.sorted())
        XCTAssertTrue(options.allSatisfy { (30...1_440).contains($0) })
        XCTAssertTrue(options.contains(240))
    }

    func testGuardMessageListsClosedLidPauseReasons() throws {
        let message = try XCTUnwrap(
            ClosedLidSettingsPresentation.guardMessage(
                for: [.batteryFloor, .externalDisplayConnected, .helperUnavailable],
                policy: .adapter,
                language: .simplifiedChinese
            )
        )

        XCTAssertTrue(message.contains("电量已到下限"))
        XCTAssertTrue(message.contains("已连接外接屏"))
        XCTAssertFalse(message.contains("Covio 系统支持"))
    }

    func testGuardMessageDeduplicatesThermalReasons() throws {
        let message = try XCTUnwrap(
            ClosedLidSettingsPresentation.guardMessage(
                for: [.thermalSerious, .thermalCritical],
                policy: .any,
                language: .simplifiedChinese
            )
        )

        XCTAssertEqual(message.components(separatedBy: "温度保护已生效").count - 1, 1)
    }

    func testSleepingPolicyDoesNotShowAClosedLidGuardMessage() {
        XCTAssertNil(
            ClosedLidSettingsPresentation.guardMessage(
                for: [.thermalCritical],
                policy: .sleep,
                language: .simplifiedChinese
            )
        )
    }

    func testVisibleCopyStatesPowerAndScreenOwnership() {
        XCTAssertTrue(
            ContractCopy.copyPowerSectionSession
                .text(for: .simplifiedChinese)
                .contains("开盖")
        )
        XCTAssertEqual(
            ContractCopy.copyMonitorDisplayClosedLidTitle.text(for: .simplifiedChinese),
            "合盖策略"
        )
        XCTAssertTrue(
            ContractCopy.copyPowerClosedLidPointer
                .text(for: .simplifiedChinese)
                .contains("屏幕卡片")
        )
    }
}
