import Foundation

struct UpdaterSettingsPresentation: Equatable {
    let status: UpdaterStatus?
    let busy: Bool
    let unavailable: Bool
    let language: AppLanguage

    var isAvailable: Bool { status != nil }
    var automaticUpdatesEnabled: Bool { status?.automaticUpdatesEnabled ?? false }
    var canChangeAutomaticUpdates: Bool { !busy && status != nil }
    var canCheck: Bool { !busy && status != nil }

    var stateText: String {
        if busy {
            return ContractCopy.copyGeneralUpdateChecking.text(for: language)
        }
        guard let status else {
            return ContractCopy.copyGeneralUpdateUnavailableState.text(for: language)
        }
        return Self.stateText(status.state, language: language)
    }

    var lastCheckText: String {
        guard let value = status?.lastCheckAt else {
            return ContractCopy.copyGeneralUpdateNever.text(for: language)
        }
        return SettingsFormat.updateTime(iso8601: value)
    }

    var availableVersionText: String? {
        status?.availableVersion
    }

    var alertText: String? {
        if unavailable {
            return ContractCopy.copyGeneralUpdateUnavailable.text(for: language)
        }
        guard let status else { return nil }
        switch status.state {
        case .notConfigured:
            return ContractCopy.copyGeneralUpdateNotConfigured.text(for: language)
        case .failed, .repairRequired:
            return ContractCopy.copyGeneralUpdateRepairRequired.text(for: language)
        default:
            return nil
        }
    }

    var canInstall: Bool {
        !busy && status?.state == .available
    }

    var canRestart: Bool {
        !busy && status?.state == .restartRequired
    }

    static func stateText(
        _ state: UpdaterEngineState,
        language: AppLanguage
    ) -> String {
        switch state {
        case .notConfigured:
            ContractCopy.copyGeneralUpdateNotConfiguredState.text(for: language)
        case .idle:
            ContractCopy.copyGeneralUpdateReady.text(for: language)
        case .checking:
            ContractCopy.copyGeneralUpdateChecking.text(for: language)
        case .available:
            ContractCopy.copyDialogUpdateTitle.text(for: language)
        case .downloading:
            ContractCopy.copyGeneralUpdateDownloading.text(for: language)
        case .installing:
            ContractCopy.copyGeneralUpdateInstalling.text(for: language)
        case .restartRequired:
            ContractCopy.copyGeneralUpdateRestartRequired.text(for: language)
        case .failed:
            ContractCopy.copyGeneralUpdateFailed.text(for: language)
        case .repairRequired:
            ContractCopy.copyGeneralUpdateRepairRequired.text(for: language)
        }
    }
}
