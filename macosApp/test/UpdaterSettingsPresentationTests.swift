import XCTest
import kmpDomain
@testable import Covio

final class UpdaterSettingsPresentationTests: XCTestCase {
    private let releaseId = "0.0.1.9-g" + String(repeating: "a", count: 40)

    func testAvailableUpdateEnablesInstallAction() {
        let value = UpdaterSettingsPresentation(
            status: status(state: .available, availableVersion: "0.0.2.0"),
            busy: false,
            unavailable: false,
            language: .english
        )
        XCTAssertTrue(value.canInstall)
        XCTAssertFalse(value.canRestart)
        XCTAssertEqual(value.availableVersionText, "0.0.2.0")
        XCTAssertEqual(
            value.stateText,
            ContractCopy.copyDialogUpdateTitle.text(for: .english)
        )
    }

    func testRestartRequiredEnablesRestartAction() {
        let value = UpdaterSettingsPresentation(
            status: status(state: .restartRequired),
            busy: false,
            unavailable: false,
            language: .simplifiedChinese
        )
        XCTAssertFalse(value.canInstall)
        XCTAssertTrue(value.canRestart)
        XCTAssertEqual(
            value.stateText,
            ContractCopy.copyGeneralUpdateRestartRequired.text(for: .simplifiedChinese)
        )
    }

    func testBusyStateShowsChecking() {
        let value = UpdaterSettingsPresentation(
            status: status(state: .idle),
            busy: true,
            unavailable: false,
            language: .english
        )
        XCTAssertEqual(
            value.stateText,
            ContractCopy.copyGeneralUpdateChecking.text(for: .english)
        )
        XCTAssertFalse(value.canCheck)
        XCTAssertFalse(value.canChangeAutomaticUpdates)
    }

    func testMissingUpdaterShowsRepairMessage() {
        let value = UpdaterSettingsPresentation(
            status: nil,
            busy: false,
            unavailable: true,
            language: .simplifiedChinese
        )
        XCTAssertEqual(
            value.alertText,
            ContractCopy.copyGeneralUpdateUnavailable.text(for: .simplifiedChinese)
        )
        XCTAssertFalse(value.isAvailable)
        XCTAssertFalse(value.canCheck)
    }

    func testNotConfiguredStateIsExplained() {
        let value = UpdaterSettingsPresentation(
            status: status(state: .notConfigured),
            busy: false,
            unavailable: false,
            language: .english
        )
        XCTAssertEqual(
            value.alertText,
            ContractCopy.copyGeneralUpdateNotConfigured.text(for: .english)
        )
    }

    func testUnavailableUsesAShortStatusLabel() {
        let value = UpdaterSettingsPresentation(
            status: nil,
            busy: false,
            unavailable: true,
            language: .simplifiedChinese
        )
        XCTAssertEqual(
            value.stateText,
            ContractCopy.copyGeneralUpdateUnavailableState.text(for: .simplifiedChinese)
        )
    }

    func testNotConfiguredUsesAShortStatusLabel() {
        let value = UpdaterSettingsPresentation(
            status: status(state: .notConfigured),
            busy: false,
            unavailable: false,
            language: .english
        )
        XCTAssertEqual(
            value.stateText,
            ContractCopy.copyGeneralUpdateNotConfiguredState.text(for: .english)
        )
    }

    func testUnknownLastCheckValueIsPreserved() {
        let value = UpdaterSettingsPresentation(
            status: status(state: .idle, lastCheckAt: "test timestamp"),
            busy: false,
            unavailable: false,
            language: .english
        )
        XCTAssertEqual(value.lastCheckText, "test timestamp")
    }

    func testEveryEngineStateHasCopy() {
        for state in [
            UpdaterEngineState.notConfigured,
            .idle,
            .checking,
            .available,
            .downloading,
            .installing,
            .restartRequired,
            .failed,
            .repairRequired,
        ] {
            XCTAssertFalse(
                UpdaterSettingsPresentation.stateText(state, language: .english).isEmpty
            )
        }
    }

    private func status(
        state: UpdaterEngineState,
        lastCheckAt: String? = "2026-11-04T00:00:00Z",
        availableVersion: String? = nil
    ) -> UpdaterStatus {
        UpdaterStatus(
            schemaVersion: 1,
            updaterProtocolVersion: 1,
            releaseId: releaseId,
            state: state,
            automaticUpdatesEnabled: true,
            lastCheckAt: lastCheckAt,
            availableVersion: availableVersion,
            message: nil
        )
    }
}
