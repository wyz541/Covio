import Foundation
import MLXLMCommon

enum AgentPane: String, CaseIterable, Sendable {
    case now
    case agent
    case clipboard
    case files
    case devices
    case settings

    var hubTab: HubTab {
        switch self {
        case .now: .now
        case .agent: .agent
        case .clipboard: .clipboard
        case .files: .files
        case .devices: .devices
        case .settings: .settings
        }
    }
}

enum AgentSettingKey: String, CaseIterable, Sendable {
    case appEnabled = "app.enabled"
    case notificationsEnabled = "notifications.enabled"
    case updateChecksEnabled = "updateChecks.enabled"
    case clipboardEnabled = "clipboard.enabled"
    case powerEnabled = "power.enabled"
    case batteryFloorPercent = "power.batteryFloorPercent"
    case language

    var typeName: String {
        switch self {
        case .batteryFloorPercent: "integer"
        case .language: "string"
        default: "boolean"
        }
    }

    func parse(_ text: String) -> AgentSettingValue? {
        switch self {
        case .batteryFloorPercent:
            guard let value = Int(text), (20...80).contains(value) else { return nil }
            return .integer(value)
        case .language:
            guard let preference = AppLanguagePreference.parse(text) else { return nil }
            return .string(preference.agentValue)
        default:
            switch text.lowercased() {
            case "true": return .boolean(true)
            case "false": return .boolean(false)
            default: return nil
            }
        }
    }

    func accepts(_ value: AgentSettingValue) -> Bool {
        switch self {
        case .batteryFloorPercent:
            guard case .integer = value else { return false }
        case .language:
            guard case .string = value else { return false }
        default:
            guard case .boolean = value else { return false }
        }
        return true
    }

    func valueText(_ value: AgentSettingValue) -> String {
        switch value {
        case .boolean(let enabled): enabled ? "true" : "false"
        case .integer(let number): String(number)
        case .string(let text): text
        }
    }
}

enum AgentSettingValue: Sendable, Equatable {
    case boolean(Bool)
    case integer(Int)
    case string(String)

    var jsonValue: JSONValue {
        switch self {
        case .boolean(let value): .bool(value)
        case .integer(let value): .int(value)
        case .string(let value): .string(value)
        }
    }
}

/// The Agent's only bridge into navigation and settings.
///
/// The closures are installed by the app shell after construction. They run on
/// the main actor, and every value crossing the Agent boundary is an enum case.
@MainActor
final class AgentUIActionRouter {
    typealias OpenPane = @MainActor (AgentPane) -> Bool
    typealias ReadSetting = @MainActor (AgentSettingKey) -> AgentSettingValue?
    typealias ChangeSetting = @MainActor (AgentSettingKey, AgentSettingValue) -> Bool

    private var openPaneAction: OpenPane?
    private var readSettingAction: ReadSetting?
    private var changeSettingAction: ChangeSetting?

    func install(
        openPane: OpenPane?,
        readSetting: ReadSetting?,
        changeSetting: ChangeSetting?
    ) {
        openPaneAction = openPane
        readSettingAction = readSetting
        changeSettingAction = changeSetting
    }

    func setOpenPaneAction(_ action: OpenPane?) {
        openPaneAction = action
    }

    func openPane(_ rawValue: String) -> AgentServiceResult {
        guard let pane = AgentPane(rawValue: rawValue), let openPaneAction else {
            return .failure("The requested page is not available.", code: .invalidArguments)
        }
        guard openPaneAction(pane) else {
            return .failure("The requested page could not be opened.", code: .executionFailed)
        }
        return AgentServiceResult(
            ok: true,
            summary: "Opened the \(pane.rawValue) page.",
            data: .object(["pane": .string(pane.rawValue)])
        )
    }

    func readSetting(_ rawValue: String) -> AgentServiceResult {
        guard let key = AgentSettingKey(rawValue: rawValue), let readSettingAction else {
            return .failure("The requested setting is not available.", code: .invalidArguments)
        }
        guard let value = readSettingAction(key), key.accepts(value) else {
            return .failure("The requested setting is unavailable.", code: .executionFailed)
        }
        return AgentServiceResult(
            ok: true,
            summary: "Read \(key.rawValue).",
            data: .object([
                "key": .string(key.rawValue),
                "type": .string(key.typeName),
                "value": value.jsonValue,
            ])
        )
    }

    func requestSettingChange(_ rawKey: String, valueText: String) -> AgentServiceResult {
        guard let key = AgentSettingKey(rawValue: rawKey),
              let value = key.parse(valueText),
              let changeSettingAction
        else {
            return .failure("The setting value is invalid.", code: .invalidArguments)
        }
        guard changeSettingAction(key, value) else {
            return .failure("The setting change was rejected.", code: .executionFailed)
        }
        return AgentServiceResult(
            ok: true,
            summary: "Changed \(key.rawValue) to \(key.valueText(value)).",
            data: .object([
                "key": .string(key.rawValue),
                "value": value.jsonValue,
            ])
        )
    }
}
