import Foundation

let APP_ID = "com.wyz.covio"
let APP_NAME = "Covio"
let SUPPORTED_HIBERNATE_MODES: Set<Int32> = [0, 3, 25]
let DEFAULT_PASTE_STACK_HOT_KEY = "shift+cmd+V"
let DEFAULT_CAPTURE_HOT_KEY = "shift+cmd+C"
let DEFAULT_CHARGE_LIMIT_PERCENT: Int32 = 70
let CHARGE_LIMIT_MIN_PERCENT: Int32 = 40
let CHARGE_LIMIT_MAX_PERCENT: Int32 = 100
let CHARGE_LIMIT_STEP_PERCENT: Int32 = 5
let CHARGE_LIMIT_HYSTERESIS_PERCENT: Int32 = 5
let CHARGE_LIMIT_MIN_RESUME_PERCENT: Int32 = 35
let POWER_HISTORY_MAX_EVENTS = 200
let POWER_HISTORY_MAX_AGE_DAYS = 7
let WORKBENCH_SCHEMA_VERSION: Int32 = 3
let WIDGET_AUTOMATIC_POSITION: Int32 = -1
let FILE_NAMING_SCHEMA_VERSION: Int32 = 1
let DEFAULT_FILE_NAMING_TEMPLATE = "{title}"
let DEFAULT_FILE_NAMING_MAX_UTF8_BYTES: Int32 = 240
let DEFAULT_FILE_NAMING_MIN_CONFIDENCE = 0.65
let MODEL_PACKAGE_SCHEMA_VERSION: Int32 = 1
let MODEL_DOWNLOAD_STATUS_SCHEMA_VERSION: Int32 = 1

enum PaneKind: String, Codable, CaseIterable, Sendable {
    case now, agent, clipboard, files, screenshots, devices, settings, board

    var key: String { rawValue }
    var isBuiltin: Bool { self != .board }
    var isCurrentBuiltin: Bool { isBuiltin && self != .screenshots }
    var defaultId: String { key }
    var titleCopyKey: String? { isBuiltin ? "copy/hub/tab/\(key)" : nil }
    var appearsInWorkbenchNavigation: Bool { self != .agent && self != .settings }
}

enum WidgetSize: String, Codable, CaseIterable, Sendable {
    case small, wide, tall, large
    var key: String { rawValue }
    static let fallback = WidgetSize.small
}

struct WidgetInstance: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var kind: String
    var size: WidgetSize = .small
    var settings: [String: String] = [:]
    var column: Int32 = WIDGET_AUTOMATIC_POSITION
    var row: Int32 = WIDGET_AUTOMATIC_POSITION
}

struct PaneInstance: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var kind: PaneKind
    var title: String = ""
    var icon: String = ""
    var isHidden: Bool = false
    var settings: [String: String] = [:]

    static func builtin(_ kind: PaneKind) -> PaneInstance {
        PaneInstance(id: kind.defaultId, kind: kind)
    }

    var isBuiltin: Bool { kind.isBuiltin }}

struct WorkbenchConfig: Codable, Equatable, Sendable {
    var schemaVersion: Int32 = WORKBENCH_SCHEMA_VERSION
    var panes: [PaneInstance] = defaultPanes()
    var homeWidgets: [WidgetInstance] = defaultWidgets()
    var selectedPaneId: String = PaneKind.now.defaultId

    static let maxPanes = 12
    static let maxWidgets = 24

    func normalized() -> WorkbenchConfig { self }
}

func defaultPanes() -> [PaneInstance] {
    PaneKind.allCases.filter(\.isCurrentBuiltin).map(PaneInstance.builtin)
}

func defaultWidgets() -> [WidgetInstance] {
    [
        WidgetInstance(id: "w-clock", kind: "w-clock", size: .wide),
        WidgetInstance(id: "w-battery", kind: "w-battery", size: .small),
        WidgetInstance(id: "w-transfer", kind: "w-transfer", size: .wide),
        WidgetInstance(id: "w-actions", kind: "w-actions", size: .tall),
        WidgetInstance(id: "w-shots", kind: "w-shots", size: .large),
        WidgetInstance(id: "w-devices", kind: "w-devices", size: .small),
    ]
}

enum ClosedLidPowerPolicy: String, Codable, CaseIterable, Sendable {
    case sleep, adapter, battery, any

    var keepsAwake: Bool { self != .sleep }
    var keepsAwakeOnAdapter: Bool { self == .adapter || self == .any }
    var keepsAwakeOnBattery: Bool { self == .battery || self == .any }

    func appliesTo(_ state: PowerState) -> Bool {
        switch state {
        case .discharging: keepsAwakeOnBattery
        case .charging, .charged, .acPower: keepsAwakeOnAdapter
        case .unknown: false
        }
    }

    static func resolve(
        keepAwakeWhenLidClosed: Bool,
        keepsAwakeOnAdapter: Bool,
        keepsAwakeOnBattery: Bool
    ) -> ClosedLidPowerPolicy {
        guard keepAwakeWhenLidClosed else { return .sleep }
        if keepsAwakeOnAdapter && keepsAwakeOnBattery { return .any }
        if keepsAwakeOnBattery { return .battery }
        return .adapter
    }
}

enum ClosedLidDisplayMode: String, Codable, CaseIterable, Sendable {
    case system, displayOff, blackScreenPipeline
}

struct DisplayConfig: Codable, Equatable, Sendable {
    var schemaVersion: Int32 = 2
    var keepAwakeWhenLidClosed: Bool = true
    var closedLidPowerPolicy: ClosedLidPowerPolicy = .adapter
    var closedLidDisplayMode: ClosedLidDisplayMode = .blackScreenPipeline
    var pauseWhenExternalDisplayConnected: Bool = true

    func normalized() -> DisplayConfig {
        var copy = self
        copy.schemaVersion = 2
        copy.keepAwakeWhenLidClosed = closedLidPowerPolicy.keepsAwake
        return copy
    }

    static func fromLegacy(
        power: PowerConfig,
        keepsAwakeOnAdapter: Bool = false,
        keepsAwakeOnBattery: Bool = false
    ) -> DisplayConfig {
        let policy = ClosedLidPowerPolicy.resolve(
            keepAwakeWhenLidClosed: power.allowClosedLid,
            keepsAwakeOnAdapter: keepsAwakeOnAdapter,
            keepsAwakeOnBattery: keepsAwakeOnBattery
        )
        return DisplayConfig(
            keepAwakeWhenLidClosed: policy.keepsAwake,
            closedLidPowerPolicy: policy,
            closedLidDisplayMode: power.closedLidZeroBrightness
                ? .blackScreenPipeline : .displayOff,
            pauseWhenExternalDisplayConnected: power.pauseClosedLidWithExternalDisplay
        )
    }
}

struct PowerConfig: Codable, Equatable, Sendable {
    var enabled: Bool = true
    var keepAwakeOnAdapter: Bool = true
    var keepAwakeOnBattery: Bool = false
    var allowClosedLid: Bool = true
    var pauseClosedLidWithExternalDisplay: Bool = true
    var batteryFloorPercent: Int32 = 15
    var batteryFloorRecoveryPercent: Int32 = 20
    var yieldOnLowPowerMode: Bool = true
    var heatGuardEnabled: Bool = true
    var closedLidTimeCapMinutes: Int32 = 240
    var closedLidZeroBrightness: Bool = true

    func normalized() -> PowerConfig {
        var copy = self
        copy.batteryFloorPercent = min(max(copy.batteryFloorPercent, 0), 99)
        copy.batteryFloorRecoveryPercent = min(
            max(copy.batteryFloorRecoveryPercent, copy.batteryFloorPercent + 1),
            100
        )
        copy.closedLidTimeCapMinutes = min(max(copy.closedLidTimeCapMinutes, 1), 1_440)
        return copy
    }
}

enum FileNamingDateSource: String, Codable, CaseIterable, Sendable {
    case none, content, fileCreated
}

enum FileNamingConflictPolicy: String, Codable, CaseIterable, Sendable {
    case appendNumber, block
}

enum FileNamingKind: String, Codable, CaseIterable, Sendable {
    case text, pdf, image, code, mixed, unknown
}

enum FileNamingPolicyError: String, Codable, Error, Sendable {
    case missingTitleToken, unknownToken, unbalancedToken
    case invalidSeparator, invalidConflictSuffix, unsafeTemplate
}

enum FileNamingWarningCode: String, Codable, Sendable {
    case invalidRequest, invalidOriginalName, hiddenFileUnsupported, unknownType
    case lowConfidence, invalidPolicy, emptyTitle, unsafeName, nameTooLong
    case conflictBlocked, conflictAppended, unchanged, mixedInput, missingTokenValue
}

enum FileNamingPlanStatus: String, Codable, Sendable {
    case ready, blocked
}

struct FileNamingPolicy: Codable, Equatable, Sendable {
    var schemaVersion: Int32 = FILE_NAMING_SCHEMA_VERSION
    var template: String = DEFAULT_FILE_NAMING_TEMPLATE
    var maxUTF8Bytes: Int32 = DEFAULT_FILE_NAMING_MAX_UTF8_BYTES
    var separator: String = "-"
    var lowercaseLatin: Bool = false
    var preserveExtension: Bool = true
    var dateSource: FileNamingDateSource = .none
    var conflictPolicy: FileNamingConflictPolicy = .appendNumber
    var conflictSuffix: String = " ({n})"
    var minConfidence: Double = DEFAULT_FILE_NAMING_MIN_CONFIDENCE
    var requirePreview: Bool = true
    var allowVision: Bool = true

    func normalized() -> FileNamingPolicy {
        var copy = self
        copy.schemaVersion = FILE_NAMING_SCHEMA_VERSION
        copy.template = template.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.maxUTF8Bytes = min(max(maxUTF8Bytes, 1), 255)
        copy.separator = separator.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.preserveExtension = true
        while copy.conflictSuffix.last?.isWhitespace == true {
            copy.conflictSuffix.removeLast()
        }
        copy.minConfidence = minConfidence.isFinite ? min(max(minConfidence, 0), 1) : DEFAULT_FILE_NAMING_MIN_CONFIDENCE
        copy.requirePreview = true
        return copy
    }

    func validationErrors() -> [FileNamingPolicyError] {
        FileNamingPolicyEvaluator.validationErrors(policy: self)
    }
}

struct NamingFacts: Codable, Equatable, Sendable {
    var title: String
    var category: String = ""
    var date: String?
    var language: String?
    var confidence: Double = 1
    var kind: FileNamingKind = .text
}

struct FileNamingRequest: Codable, Equatable, Sendable {
    var candidateId: String
    var originalName: String
    var facts: NamingFacts
}

struct FileNamingWarning: Codable, Equatable, Sendable {
    var code: FileNamingWarningCode
    var detail: String = ""
}

struct FileNamingPlan: Codable, Equatable, Identifiable, Sendable {
    var candidateId: String
    var originalName: String
    var targetName: String?
    var `extension`: String = ""
    var status: FileNamingPlanStatus
    var confidence: Double = 0
    var warnings: [FileNamingWarning] = []

    var id: String { candidateId }
    var canApply: Bool { status == .ready }
}

struct AppConfig: Codable, Equatable, Sendable {
    var schemaVersion: Int32 = 4
    var language: String = ""
    var enabled: Bool = true
    var launchAtLogin: Bool = false
    var lowBatteryCapacitySleep: Bool = true
    var lowBatteryCapacity: Int32 = 6
    var lowTimeRemainingMinutes: Int32 = 10
    var disableIdleSleepInCharging: Bool = false
    var disableLidSleepInCharging: Bool = false
    var disableLidSleepOnBattery: Bool = false
    var darkWakeAwarenessEnabled: Bool = true
    var lidSleepImmediateOnClose: Bool = true
    var notificationsEnabled: Bool = true
    var trackpadGestureEnabled: Bool = false
    var updateCheckEnabled: Bool = true
    var updateCheckIntervalHours: Int32 = 24
    var lastUpdateCheckEpochSeconds: Int64 = 0
    var hibernateMode: Int32?
    var firstRun: Bool = true
    var shelfEnabled: Bool = false
    var screenshotInboxEnabled: Bool = false
    var shelfSoundsEnabled: Bool = false
    var clipboardEnabled: Bool = true
    var clipboardPasteStackHotKey: String = DEFAULT_PASTE_STACK_HOT_KEY
    var clipboardCaptureHotKey: String = DEFAULT_CAPTURE_HOT_KEY
    var power: PowerConfig = PowerConfig()
    var display: DisplayConfig?
    var chargeLimitEnabled: Bool = true
    var chargeLimitPercent: Int32 = DEFAULT_CHARGE_LIMIT_PERCENT
    var chargeLimitActiveDischarge: Bool = false
    var fileNaming: FileNamingPolicy = FileNamingPolicy()

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case language
        case enabled
        case launchAtLogin
        case lowBatteryCapacitySleep
        case lowBatteryCapacity
        case lowTimeRemainingMinutes = "lowTimeRemaining"
        case disableIdleSleepInCharging
        case disableLidSleepInCharging
        case disableLidSleepOnBattery
        case darkWakeAwarenessEnabled
        case lidSleepImmediateOnClose
        case notificationsEnabled
        case trackpadGestureEnabled
        case updateCheckEnabled
        case updateCheckIntervalHours
        case lastUpdateCheckEpochSeconds
        case hibernateMode
        case firstRun
        case shelfEnabled
        case screenshotInboxEnabled
        case shelfSoundsEnabled
        case clipboardEnabled
        case clipboardPasteStackHotKey
        case clipboardCaptureHotKey
        case power
        case display
        case chargeLimitEnabled
        case chargeLimitPercent
        case chargeLimitActiveDischarge
        case fileNaming
    }

    func normalized() -> AppConfig {
        do {
            let response = try CovioCoreRuntime.shared.call(
                "config.normalize",
                payload: ["config": jsonObject()]
            )
            guard let root = response as? [String: Any] else { return self }
            return try coreDecode(AppConfig.self, from: root["config"] ?? [:])
        } catch { return self }
    }
}

enum PowerState: String, Codable, CaseIterable, Sendable {
    case discharging, charging, charged, acPower, unknown
    var isCharging: Bool { self == .charging || self == .charged || self == .acPower }
}

struct BatteryStatus: Codable, Equatable, Sendable {
    var percent: Int32
    var state: PowerState
    var remainingSeconds: Int64?

    var isDischarging: Bool { state == .discharging }
}

enum LidState: String, Codable, CaseIterable, Sendable {
    case unknown, open, closed
}

enum HelperStatus: String, Codable, CaseIterable, Sendable {
    case match, missing, outdated, identityMismatch, untrusted
    var allowsPrivilegedWrites: Bool { self == .match }
}

enum SleepEvent: String, Codable, Equatable, Sendable {
    case willSleep
    case wakeSignal
}

enum WakeKind: String, Codable, CaseIterable, Sendable {
    case dark, full
}

struct WakeEvent: Codable, Equatable, Sendable {
    var kind: WakeKind
    var atEpochSeconds: Int64
    var reason: String
}

struct WakeLogSnapshot: Codable, Equatable, Sendable {
    var events: [WakeEvent] = []
    var darkWakeCount24h: Int32 = 0
    var latest: WakeEvent? { events.last }
}

struct DarkWakeStatus: Codable, Equatable, Sendable {
    var available: Bool = false
    var scanning: Bool = false
    var lastAtEpochSeconds: Int64?
    var lastKind: WakeKind?
    var lastReason: String?
    var count24h: Int32 = 0
}

struct ShelfItem: Codable, Equatable, Identifiable, Sendable {
    var path: String
    var addedAtEpochSeconds: Int64

    var id: String { path }
    var normalized: ShelfItem {
        ShelfItem(path: path.trimmingCharacters(in: .whitespacesAndNewlines), addedAtEpochSeconds: max(0, addedAtEpochSeconds))
    }
}

struct ScreenshotInboxSnapshot: Codable, Equatable, Sendable {
    var location: String?
    var locationScreenshot: String?
    var showThumbnail: Bool?
}

struct ShelfStoreState: Codable, Equatable, Sendable {
    var items: [ShelfItem] = []
    var revealed: Bool = true
    var preferenceSnapshot: ScreenshotInboxSnapshot?
}

enum ClipKind: String, Codable, CaseIterable, Sendable {
    case text = "TEXT"
    case link = "LINK"
    case image = "IMAGE"
    case color = "COLOR"
    case files = "FILES"
}

struct ClipItem: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var kind: ClipKind
    var text: String
    var filePath: String
    var byteSize: Int64
    var createdAtEpochSeconds: Int64
    var pinned: Bool
    var sourceBundleId: String

    var isUsable: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !filePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct ClipPolicy: Codable, Equatable, Sendable {
    var maxItems: Int32 = 100
    var maxAgeDays: Int32 = 7
    var maxTotalBytes: Int64 = 200 * 1024 * 1024
}

struct ClipboardState: Codable, Equatable, Sendable {
    var items: [ClipItem] = []
    var pasteStack: [String] = []
    var paused: Bool = false
    var policy: ClipPolicy = ClipPolicy()
}

enum WorkspaceKind: String, Codable, CaseIterable, Sendable {
    case file = "FILE"
    case image = "IMAGE"
    case audio = "AUDIO"
    case pdf = "PDF"
    case text = "TEXT"
}

enum WorkspaceAvailability: String, Codable, CaseIterable, Sendable {
    case local = "LOCAL"
    case remote = "REMOTE"
    case fetching = "FETCHING"
    case evicted = "EVICTED"
}

struct WorkspaceEntry: Codable, Equatable, Identifiable, Sendable {
    var entryId: String
    var kind: WorkspaceKind
    var displayName: String
    var byteSize: Int64
    var contentType: String
    var createdAtEpochSeconds: Int64
    var originDeviceId: String
    var expiresAtEpochSeconds: Int64
    var availability: WorkspaceAvailability
    var pinned: Bool

    var id: String { entryId }
    var isUsable: Bool { Self.isValidEntryId(entryId) }
    var localBytes: Int64 {
        availability == .local || availability == .fetching ? byteSize : 0
    }

    static func isValidEntryId(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }
}

struct WorkspacePolicy: Codable, Equatable, Sendable {
    var maxTotalBytes: Int64 = 5 * 1024 * 1024 * 1024
    var maxEntryBytes: Int64 = 2 * 1024 * 1024 * 1024
    var retentionDays: Int32 = 30
    var lazyFetchThresholdBytes: Int64 = 50 * 1024 * 1024

    func normalized() -> WorkspacePolicy {
        var copy = self
        copy.maxTotalBytes = max(0, maxTotalBytes)
        copy.maxEntryBytes = min(max(0, maxEntryBytes), copy.maxTotalBytes)
        copy.retentionDays = min(max(0, retentionDays), 3_650)
        copy.lazyFetchThresholdBytes = max(0, lazyFetchThresholdBytes)
        return copy
    }
}

struct WorkspaceState: Codable, Equatable, Sendable {
    var schemaVersion: Int32 = 1
    var entries: [WorkspaceEntry] = []
    var policy: WorkspacePolicy = WorkspacePolicy()
}

struct WorkspaceTombstone: Codable, Equatable, Sendable {
    var entryId: String
    var deletedAtEpochSeconds: Int64 = 0
}

enum WorkspaceAdmission: String, Codable, CaseIterable, Sendable {
    case accepted, duplicate, invalid, tooLarge, quotaExceeded, failed
}

struct WorkspacePutResult: Codable, Equatable, Sendable {
    var state: WorkspaceState
    var entry: WorkspaceEntry?
    var admission: WorkspaceAdmission
    var persisted: Bool
    var accepted: Bool { admission == .accepted }
}

struct WorkspacePlan: Codable, Equatable, Sendable {
    var kept: [WorkspaceEntry]
    var expired: [WorkspaceEntry]
    var evicted: [WorkspaceEntry]
    var totalBytes: Int64
}

struct UpdateInfo: Codable, Equatable, Sendable {
    var version: String
    var title: String
    var releaseUrl: String
    var publishedAt: String = ""
}

struct AppState: Codable, Equatable, Sendable {
    var battery: BatteryStatus?
    var lid: LidState = .unknown
    var enabled: Bool = true
    var idleSleepAvailable: Bool = true
    var idleSleepPrevention: IdleSleepPrevention = .none
    var lidSleepAvailable: Bool = true
    var idleCancelRemainingSeconds: Int64?
    var lidCancelRemainingSeconds: Int64?
    var darkWake: DarkWakeStatus = DarkWakeStatus()
    var helperStatus: HelperStatus = .missing
    var lidLeaseStatus: LidLeaseStatus = LidLeaseStatus()
    var lastError: String?
}

struct HelperReply: Codable, Equatable, Sendable {
    var version: String
    var requestId: String
    var ok: Bool
    var result: [String: String]?
    var error: String?
    var sourceLine: String?

    enum CodingKeys: String, CodingKey {
        case version
        case requestId
        case ok
        case result
        case error
    }

    init(
        version: String,
        requestId: String,
        ok: Bool,
        result: [String: String]?,
        error: String?
    ) {
        self.version = version
        self.requestId = requestId
        self.ok = ok
        self.result = result
        self.error = error
        sourceLine = nil
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(String.self, forKey: .version)
        requestId = try values.decode(String.self, forKey: .requestId)
        ok = try values.decode(Bool.self, forKey: .ok)
        result = try values.decodeIfPresent([String: String].self, forKey: .result)
        error = try values.decodeIfPresent(String.self, forKey: .error)
        sourceLine = nil
    }
}

struct HelperRequest: Codable, Equatable, Sendable {
    var version: String
    var requestId: String
    var command: String
    var payload: [String: String] = [:]
    var sourceLine: String?

    enum CodingKeys: String, CodingKey {
        case version
        case requestId
        case command
        case payload
    }

    init(version: String, requestId: String, command: String, payload: [String: String] = [:]) {
        self.version = version
        self.requestId = requestId
        self.command = command
        self.payload = payload
        sourceLine = nil
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(String.self, forKey: .version)
        requestId = try values.decode(String.self, forKey: .requestId)
        command = try values.decode(String.self, forKey: .command)
        payload = try values.decodeIfPresent([String: String].self, forKey: .payload) ?? [:]
        sourceLine = nil
    }
}

enum ThermalState: String, Codable, CaseIterable, Sendable {
    case nominal, fair, serious, critical, unknown
}

struct PowerObservation: Codable, Equatable, Sendable {
    var batteryPercent: Int32?
    var hasBattery: Bool?
    var powerState: PowerState = .unknown
    var externalDisplayCount: Int32?
    var lidState: LidState = .unknown
    var thermalState: ThermalState = .unknown
    var lowPowerModeEnabled: Bool?
}

struct PowerSnapshot: Codable, Equatable, Sendable {
    var observation: PowerObservation = PowerObservation()
    var helperStatus: HelperStatus = .untrusted
    var sleepDisabled: Bool?
    var covioOwnsSleepDisabled: Bool?
}

enum HoldLeaseSource: String, Codable, CaseIterable, Sendable {
    case manual, timer, rule, agent, test
}

enum HoldLeaseLevel: String, Codable, CaseIterable, Sendable {
    case system, systemAndDisplay, closedLid
}

struct HoldLease: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var level: HoldLeaseLevel
    var source: HoldLeaseSource = .manual
    var reason: String = ""
    var createdAtEpochSeconds: Int64 = 0
    var expiresAtEpochSeconds: Int64?
}

enum IdleSleepPrevention: String, Codable, CaseIterable, Sendable {
    case unknown, none, system, systemAndDisplay
    var isActive: Bool { self == .system || self == .systemAndDisplay }
}

struct IdleSleepAssertionResult: Codable, Equatable, Sendable {
    var requested: IdleSleepPrevention
    var actual: IdleSleepPrevention
    var success: Bool
    var error: String?
}

struct HoldLeaseSnapshot: Codable, Equatable, Sendable {
    var leases: [HoldLease] = []
    var desiredPrevention: IdleSleepPrevention = .none
    var actualPrevention: IdleSleepPrevention = .unknown
    var suspended: Bool = false
    var lastError: String?
    var systemSleepPrevented: Bool { actualPrevention.isActive }
    var displaySleepPrevented: Bool { actualPrevention == .systemAndDisplay }
}

struct LidLeaseStatus: Codable, Equatable, Sendable {
    var available: Bool = false
    var protocolVersion: String?
    var sleepDisabled: Bool?
    var covioOwned: Bool?
    var activeLeaseCount: Int32 = 0
    var expiresAtEpochSeconds: Int64?
    var error: String?
    var leaseActive: Bool { activeLeaseCount > 0 && covioOwned == true }
}

enum SafetyVeto: String, Codable, CaseIterable, Sendable {
    case powerDisabled, explicitlyPaused, batteryFloor
    case thermalSerious, thermalCritical, lowPowerMode
    case closedLidTimeCap, closedLidDisabled, helperUnavailable
    case batteryStateUnknown, externalDisplayConnected, externalDisplayUnknown
    case sleepDisabledStateUnknown, externalSleepDisabledConflict
}

struct PowerDecision: Codable, Equatable, Sendable {
    var preventUserIdleSystemSleep: Bool = false
    var preventUserIdleDisplaySleep: Bool = false
    var preventLidSleep: Bool = false
    var appliedLeaseLevel: HoldLeaseLevel?
    var activeLeaseIds: [String] = []
    var automaticRuleApplied: Bool = false
    var safetyVetoes: [SafetyVeto] = []
    var batteryGuardLatched: Bool = false
    var sleepAllowed: Bool {
        !preventUserIdleSystemSleep && !preventUserIdleDisplaySleep && !preventLidSleep
    }
}

enum FileAreaOrigin: String, Codable, CaseIterable, Sendable { case screenshot, workspace }
enum FileAreaKind: String, Codable, CaseIterable, Sendable { case screenshot, image, text, pdf, audio, file }
enum FileAreaAvailability: String, Codable, CaseIterable, Sendable { case local, remote, fetching, unavailable }
enum FileAreaFilter: String, Codable, CaseIterable, Sendable { case all, screenshots, files, text, transfers }

struct FileAreaCapabilities: Codable, Equatable, Sendable {
    var canOpen: Bool = false
    var canCopy: Bool = false
    var canCopyText: Bool = false
    var canMarkup: Bool = false
    var canDragOut: Bool = false
    var canSaveToWorkspace: Bool = false
    var canReveal: Bool = false
    var canPin: Bool = false
    var canRemove: Bool = false
    var canDownload: Bool = false
    var canCancel: Bool = false
}

struct FileAreaItem: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var origin: FileAreaOrigin
    var itemId: String
    var displayName: String
    var kind: FileAreaKind
    var createdAtEpochSeconds: Int64 = 0
    var byteSize: Int64 = 0
    var originDeviceId: String = ""
    var expiresAtEpochSeconds: Int64 = 0
    var availability: FileAreaAvailability = .local
    var pinned: Bool = false
    var capabilities: FileAreaCapabilities = FileAreaCapabilities()

    var isTransfer: Bool { availability != .local }
    func matches(_ filter: FileAreaFilter) -> Bool {
        switch filter {
        case .all: true
        case .screenshots: origin == .screenshot
        case .files: origin == .workspace && kind != .text && kind != .screenshot
        case .text: kind == .text
        case .transfers: isTransfer
        }
    }
}

enum ChargeLimitSupport: String, Codable, CaseIterable, Sendable { case supported, unsupported, unknown }
enum ChargeLimitPhase: String, Codable, CaseIterable, Sendable {
    case off, noBattery, unplugged, applying, discharging, stoppingDischarge
    case charging, sailing, holding, aboveLimit, full, calibration
    case systemProtection, conflict, error, unsupported, helperMissing
}
enum ChargeLimitAction: String, Codable, CaseIterable, Sendable { case none, setTarget, releaseTarget }

struct ChargeLimitObservation: Codable, Equatable, Sendable {
    var enabled: Bool
    var upperLimitPercent: Int32
    var adapterConnected: Bool
    var currentPercent: Int32?
    var helperInstalled: Bool = true
    var support: ChargeLimitSupport = .supported
    var batteryPresent: Bool = true
    var isCharged: Bool = false
    var calibrationActive: Bool = false
    var systemProtectionActive: Bool = false
    var conflict: Bool = false
    var errorMessage: String?
    var observedTargetPercent: Int32?
    var writePending: Bool = false
    var bypassEngaged: Bool = false
    var activeDischargeEnabled: Bool = false
    var activelyDischarging: Bool = false
}

struct ChargeLimitPolicyState: Codable, Equatable, Sendable {
    var chargingLatch: Bool = false
}

struct ChargeLimitDecision: Codable, Equatable, Sendable {
    var phase: ChargeLimitPhase
    var action: ChargeLimitAction = .none
    var targetPercent: Int32?
    var resumeThresholdPercent: Int32 = 0
    var chargingLatch: Bool = false
    var bypassEngaged: Bool = false
    var errorMessage: String?
}

enum PowerHistoryKind: String, Codable, CaseIterable, Sendable {
    case adapterConnected = "ADAPTER_CONNECTED"
    case adapterDisconnected = "ADAPTER_DISCONNECTED"
    case slept = "SLEPT"
    case darkWake = "DARK_WAKE"
    case fullWake = "FULL_WAKE"
    case holdStarted = "HOLD_STARTED"
    case guardReleased = "GUARD_RELEASED"
    case externalConflict = "EXTERNAL_CONFLICT"
    case externalConflictCleared = "EXTERNAL_CONFLICT_CLEARED"
}

struct PowerHistoryEvent: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var kind: PowerHistoryKind
    var atEpochSeconds: Int64
    var detail: String = ""
    var isUsable: Bool { !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

struct PowerHistoryState: Codable, Equatable, Sendable {
    var schemaVersion: Int32 = 1
    var events: [PowerHistoryEvent] = []
}

struct PowerHistoryPolicy: Codable, Equatable, Sendable {
    var maxEvents: Int32 = Int32(POWER_HISTORY_MAX_EVENTS)
    var maxAgeDays: Int32 = Int32(POWER_HISTORY_MAX_AGE_DAYS)
}

struct SemanticVersion: Codable, Equatable, Comparable, Sendable {
    var major: UInt32
    var minor: UInt32
    var patch: UInt32
    var prerelease: [String] = []
    var buildMetadata: [String] = []

    var baseVersion: String { "\(major).\(minor).\(patch)" }
    var isStable: Bool { prerelease.isEmpty }
}

struct ClientVersion: Codable, Equatable, Comparable, Sendable {
    var thousands: UInt8
    var hundreds: UInt8
    var tens: UInt8
    var ones: UInt8

    static func < (lhs: ClientVersion, rhs: ClientVersion) -> Bool {
        [lhs.thousands, lhs.hundreds, lhs.tens, lhs.ones].lexicographicallyPrecedes(
            [rhs.thousands, rhs.hundreds, rhs.tens, rhs.ones]
        )
    }
}

enum DesignContractSeverity: String, Codable, CaseIterable, Sendable { case error, warning }

struct DesignContractDiagnostic: Codable, Equatable, Sendable {
    var severity: DesignContractSeverity
    var path: String
    var message: String
    func describe() -> String { "\(severity.rawValue.uppercased()) \(path): \(message)" }
}

struct DesignCopyEntry: Codable, Equatable, Identifiable, Sendable {
    var key: String
    var en: String
    var zhHans: String
    var id: String { key }
}

struct DesignToken: Codable, Equatable, Identifiable, Sendable {
    var key: String
    var type: String
    var purpose: String
    var light: String?
    var dark: String?
    var durationMs: Double?
    var minMs: Double?
    var maxMs: Double?
    var reducedMotionMs: Double?
    var curve: String?
    var id: String { key }
    var isMotion: Bool { type == "duration" }
}

struct DesignContract: Codable, Equatable, Sendable {
    var schemaVersion: String
    var tokens: [DesignToken]
    var copy: [DesignCopyEntry]
    var components: [String]
    var platformMappings: [String]
    var motionTokens: [DesignToken] { tokens.filter(\.isMotion) }
    func token(_ key: String) -> DesignToken? { tokens.first { $0.key == key } }
    func entry(_ key: String) -> DesignCopyEntry? { copy.first { $0.key == key } }
    func entry(key: String) -> DesignCopyEntry? { entry(key) }
}

struct DesignContractValidationResult: Codable, Equatable, Sendable {
    var contract: DesignContract?
    var diagnostics: [DesignContractDiagnostic] = []
    var isValid: Bool { !diagnostics.contains { $0.severity == .error } }
    var errors: [DesignContractDiagnostic] { diagnostics.filter { $0.severity == .error } }
    var warnings: [DesignContractDiagnostic] { diagnostics.filter { $0.severity == .warning } }
}

private extension Encodable {
    func jsonObject() -> Any {
        guard let data = try? JSONEncoder().encode(self),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return [:]
        }
        return object
    }
}

struct ModelPackageFileContract: Codable, Equatable, Sendable {
    var path: String
    var size: Int64
    var sha256: String
}

struct ModelPackageManifestContract: Codable, Equatable, Sendable {
    var schemaVersion: Int32
    var tier: String
    var modelID: String
    var revision: String
    var displayName: String
    var runtimeDirectory: String
    var license: String
    var licenseFile: String
    var noticeFile: String
    var totalBytes: Int64
    var files: [ModelPackageFileContract]
}

struct ModelPackageExpectationContract: Codable, Equatable, Sendable {
    var tier: String
    var modelID: String
    var revision: String
    var runtimeDirectory: String
    var totalBytes: Int64
    var license: String
}

enum ModelPackageContractError: String, Codable, Sendable {
    case manifestUnreadable, unsupportedSchema, tierMismatch, modelMismatch
    case revisionMismatch, licenseRejected, invalidPath, fileMissing, totalSizeMismatch
}

struct ModelPackageContractValidation: Codable, Equatable, Sendable {
    var valid: Bool
    var errorCode: String?
    var detail: String
}

enum ModelDownloadPhaseContract: String, Codable, CaseIterable, Sendable {
    case notDownloaded, downloading, paused, verifying, ready, failed
    var wire: String { rawValue }
}

enum ModelDownloadErrorCodeContract: String, Codable, CaseIterable, Sendable {
    case busy, sourceUnavailable, manifestInvalid, revisionMismatch
    case insufficientHardware, insufficientMemory, insufficientDisk
    case cancelled, downloadFailed, verificationFailed, existingPackageInvalid, activationFailed
}

struct ModelDownloadStatusContract: Codable, Equatable, Sendable {
    var schemaVersion: Int32 = MODEL_DOWNLOAD_STATUS_SCHEMA_VERSION
    var tier: String
    var modelID: String
    var displayName: String
    var revision: String
    var license: String
    var totalBytes: Int64
    var phase: ModelDownloadPhaseContract
    var fractionCompleted: Double
    var downloadedBytes: Int64
    var errorCode: ModelDownloadErrorCodeContract?
    var detail: String?
    var updatedAtEpochMilliseconds: Int64
    var modelId: String { modelID }
}

struct ModelPackageRegistrationContract: Codable, Equatable, Sendable {
    var tier: String
    var directoryPath: String
    var modelID: String
    var revision: String
    var totalBytes: Int64
    var license: String
    var verifiedAtEpochMilliseconds: Int64
    var modelId: String { modelID }
}

struct ModelPackageRegistryContract: Codable, Equatable, Sendable {
    var selectedTier: String?
    var packages: [ModelPackageRegistrationContract] = []
}
