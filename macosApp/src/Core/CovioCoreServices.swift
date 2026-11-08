import Foundation

func coreDecode<T: Decodable>(_ type: T.Type, from value: Any) throws -> T {
    let data = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
    return try JSONDecoder().decode(type, from: data)
}

func coreEncode<T: Encodable>(_ value: T) throws -> Any {
    let data = try JSONEncoder().encode(value)
    return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
}

private func coreClient(
    configPath: String = CovioCoreDefaults.configPath,
    shelfPath: String = CovioCoreDefaults.shelfPath,
    clipboardPath: String = CovioCoreDefaults.clipboardPath,
    workspacePath: String = CovioCoreDefaults.workspacePath
) -> CovioCoreClient {
    do {
        return try CovioCoreClient(
            configPath: configPath,
            shelfPath: shelfPath,
            clipboardPath: clipboardPath,
            workspacePath: workspacePath
        )
    } catch {
        fatalError("Cannot create Covio Rust core handle: \(error)")
    }
}

final class ConfigStore: @unchecked Sendable {
    struct Companion: Sendable {
        func create(path: String) -> ConfigStore { ConfigStore(path: path) }
        func defaults() -> AppConfig { AppConfig() }
        func defaultPath() -> String { CovioCoreDefaults.configPath }
    }

    static let companion = Companion()
    private let client: CovioCoreClient

    init(path: String) {
        client = coreClient(configPath: path)
    }

    func load() -> AppConfig {
        do {
            let value = try client.call("config.load")
            let root = value as? [String: Any]
            let config = root?["config"] ?? [:]
            return try coreDecode(AppConfig.self, from: config)
        } catch {
            return AppConfig()
        }
    }

    @discardableResult
    func save(config: AppConfig) -> Bool {
        do {
            _ = try client.call("config.save", payload: ["config": try coreEncode(config)])
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    func clear() -> Bool {
        do {
            let value = try client.call("config.clear")
            return (value as? [String: Any])?["removed"] as? Bool ?? false
        } catch {
            return false
        }
    }
}

final class ShelfStore: @unchecked Sendable {
    struct Companion: Sendable {
        let MAX_ITEMS: Int32 = 12

        func create(path: String) -> ShelfStore { ShelfStore(path: path) }

        func canonicalPath(value: String) -> String {
            guard let response = try? CovioCoreRuntime.shared.call(
                "shelf.canonicalPath",
                payload: ["value": value]
            ) as? [String: Any] else {
                return ShelfStore.canonicalPathFallback(value)
            }
            return response["value"] as? String ?? ShelfStore.canonicalPathFallback(value)
        }

        func normalizeItems(
            items: [ShelfItem],
            limit: Int32,
            exists: (String) -> Bool
        ) -> [ShelfItem] {
            let existing = items.map(\.path).filter { exists($0) }
            do {
                let payload: [String: Any] = [
                    "items": try coreEncode(items),
                    "existingPaths": existing,
                    "limit": Int(limit),
                ]
                let response = try CovioCoreRuntime.shared.call("shelf.normalizeItems", payload: payload)
                let object = response as? [String: Any]
                return try coreDecode([ShelfItem].self, from: object?["items"] ?? [])
            } catch {
                return []
            }
        }
    }

    static let companion = Companion()
    private let client: CovioCoreClient

    init(path: String) {
        client = coreClient(shelfPath: path)
    }

    func load() -> ShelfStoreState {
        do {
            let value = try client.call("shelf.load")
            let root = value as? [String: Any]
            return try coreDecode(ShelfStoreState.self, from: root?["state"] ?? [:])
        } catch {
            return ShelfStoreState()
        }
    }

    func save(state: ShelfStoreState) -> ShelfStoreState {
        do {
            let value = try client.call("shelf.save", payload: ["state": try coreEncode(state)])
            let root = value as? [String: Any]
            return try coreDecode(ShelfStoreState.self, from: root?["state"] ?? [:])
        } catch {
            return state
        }
    }

    func clear() -> Bool {
        do {
            let value = try client.call("shelf.clear")
            return (value as? [String: Any])?["removed"] as? Bool ?? false
        } catch {
            return false
        }
    }

    static func canonicalPathFallback(_ value: String) -> String {
        URL(fileURLWithPath: value).standardizedFileURL.path
    }
}

final class ClipboardStore: @unchecked Sendable {
    struct Companion: Sendable {
        func create(path: String) -> ClipboardStore { ClipboardStore(path: path) }
        func defaultDirectory() -> String {
            URL(fileURLWithPath: CovioCoreDefaults.clipboardPath).deletingLastPathComponent().path
        }
        func defaultPath() -> String { CovioCoreDefaults.clipboardPath }
    }

    static let companion = Companion()
    private let client: CovioCoreClient

    init(path: String) {
        client = coreClient(clipboardPath: path)
    }

    func load() -> ClipboardState {
        do {
            let value = try client.call("clipboard.load")
            let root = value as? [String: Any]
            return try coreDecode(ClipboardState.self, from: root?["state"] ?? [:])
        } catch {
            return ClipboardState()
        }
    }

    func save(state: ClipboardState) -> ClipboardState {
        do {
            let value = try client.call("clipboard.save", payload: ["state": try coreEncode(state)])
            let root = value as? [String: Any]
            return try coreDecode(ClipboardState.self, from: root?["state"] ?? [:])
        } catch {
            return state
        }
    }

    func clear() -> Bool {
        do {
            let value = try client.call("clipboard.clear")
            return (value as? [String: Any])?["removed"] as? Bool ?? false
        } catch {
            return false
        }
    }
}

final class ClipboardLogic: @unchecked Sendable {
    static let shared = ClipboardLogic()

    func classify(text: String) -> ClipKind {
        guard let response = try? CovioCoreRuntime.shared.call(
            "clipboard.classify",
            payload: ["text": text]
        ) as? [String: Any],
              let raw = response["kind"] as? String,
              let kind = ClipKind(rawValue: raw) else {
            return .text
        }
        return kind
    }

    func prune(
        items: [ClipItem],
        policy: ClipPolicy,
        nowEpochSeconds: Int64,
        exists: (String) -> Bool
    ) -> [ClipItem] {
        let existing = items.flatMap { item -> [String] in
            guard !item.filePath.isEmpty, exists(item.filePath) else { return [] }
            return [item.filePath]
        }
        do {
            let payload: [String: Any] = [
                "items": try coreEncode(items),
                "policy": try coreEncode(policy),
                "existingPaths": existing,
            ]
            let value = try CovioCoreRuntime.shared.call(
                "clipboard.prune",
                payload: payload,
                nowEpochSeconds: nowEpochSeconds
            )
            let root = value as? [String: Any]
            return try coreDecode([ClipItem].self, from: root?["items"] ?? [])
        } catch {
            return []
        }
    }

    func nextPaste(state: ClipboardState) -> ClipboardNext {
        do {
            let value = try CovioCoreRuntime.shared.call(
                "clipboard.nextPaste",
                payload: ["state": try coreEncode(state)]
            )
            let root = value as? [String: Any]
            let next = try coreDecode(ClipboardState.self, from: root?["state"] ?? [:])
            let item: ClipItem? = if let value = root?["item"] {
                try coreDecode(ClipItem.self, from: value)
            } else {
                nil
            }
            return ClipboardNext(first: next, second: item)
        } catch {
            return ClipboardNext(first: state, second: nil)
        }
    }

    func pushPasteStack(stack: [String], id: String) -> [String] {
        guard let value = try? CovioCoreRuntime.shared.call(
            "clipboard.pushPaste",
            payload: ["stack": stack, "id": id]
        ) as? [String: Any],
              let stack = value["stack"] as? [String] else {
            return stack.filter { $0 != id } + [id]
        }
        return stack
    }
}

final class WorkspaceStore: @unchecked Sendable {
    struct Companion: Sendable {
        func create(directory: String) -> WorkspaceStore { WorkspaceStore(directory: directory) }
        func defaultDirectory() -> String { CovioCoreDefaults.workspacePath }
    }

    static let companion = Companion()
    private let client: CovioCoreClient

    init(directory: String) {
        client = coreClient(workspacePath: directory)
    }

    func load() -> WorkspaceState {
        do {
            let value = try client.call("workspace.load")
            let root = value as? [String: Any]
            return try coreDecode(WorkspaceState.self, from: root?["state"] ?? [:])
        } catch {
            return WorkspaceState()
        }
    }

    func save(state: WorkspaceState) -> WorkspaceState {
        do {
            let value = try client.call("workspace.save", payload: ["state": try coreEncode(state)])
            let root = value as? [String: Any]
            return try coreDecode(WorkspaceState.self, from: root?["state"] ?? [:])
        } catch {
            return state
        }
    }

    func loadTombstones() -> [WorkspaceTombstone] {
        do {
            let value = try client.call("workspace.loadTombstones")
            let root = value as? [String: Any]
            return try coreDecode([WorkspaceTombstone].self, from: root?["tombstones"] ?? [])
        } catch {
            return []
        }
    }

    func putFile(
        state: WorkspaceState,
        sourcePath: String,
        displayName: String,
        contentType: String,
        originDeviceId: String,
        nowEpochSeconds: Int64
    ) -> WorkspacePutResult {
        do {
            let payload: [String: Any] = [
                "state": try coreEncode(state),
                "sourcePath": sourcePath,
                "displayName": displayName,
                "contentType": contentType,
                "originDeviceId": originDeviceId,
            ]
            let value = try client.call(
                "workspace.putFile",
                payload: payload,
                nowEpochSeconds: nowEpochSeconds
            )
            return try coreDecode(WorkspacePutResult.self, from: value)
        } catch {
            return WorkspacePutResult(state: state, entry: nil, admission: .failed, persisted: false)
        }
    }

    func putText(
        state: WorkspaceState,
        text: String,
        displayName: String,
        contentType: String,
        originDeviceId: String,
        nowEpochSeconds: Int64
    ) -> WorkspacePutResult {
        do {
            let payload: [String: Any] = [
                "state": try coreEncode(state),
                "text": text,
                "displayName": displayName,
                "contentType": contentType,
                "originDeviceId": originDeviceId,
            ]
            let value = try client.call(
                "workspace.putText",
                payload: payload,
                nowEpochSeconds: nowEpochSeconds
            )
            return try coreDecode(WorkspacePutResult.self, from: value)
        } catch {
            return WorkspacePutResult(state: state, entry: nil, admission: .failed, persisted: false)
        }
    }

    func setPinned(state: WorkspaceState, entryId: String, pinned: Bool) -> WorkspaceState {
        do {
            let payload: [String: Any] = [
                "state": try coreEncode(state),
                "entryId": entryId,
                "pinned": pinned,
            ]
            let value = try client.call("workspace.setPinned", payload: payload)
            let root = value as? [String: Any]
            return try coreDecode(WorkspaceState.self, from: root?["state"] ?? [:])
        } catch {
            return state
        }
    }

    func remove(state: WorkspaceState, entryId: String, nowEpochSeconds: Int64) -> WorkspaceState {
        do {
            let payload: [String: Any] = [
                "state": try coreEncode(state),
                "entryId": entryId,
            ]
            let value = try client.call(
                "workspace.remove",
                payload: payload,
                nowEpochSeconds: nowEpochSeconds
            )
            let root = value as? [String: Any]
            return try coreDecode(WorkspaceState.self, from: root?["state"] ?? [:])
        } catch {
            return state
        }
    }

    func sweep(policy: WorkspacePolicy, nowEpochSeconds: Int64) -> WorkspacePlan {
        do {
            let value = try client.call(
                "workspace.sweep",
                payload: ["policy": try coreEncode(policy)],
                nowEpochSeconds: nowEpochSeconds
            )
            let root = value as? [String: Any]
            return try coreDecode(WorkspacePlan.self, from: root?["plan"] ?? [:])
        } catch {
            return WorkspacePlan(kept: [], expired: [], evicted: [], totalBytes: 0)
        }
    }

    func clear() -> Bool {
        do {
            let value = try client.call("workspace.clear")
            return (value as? [String: Any])?["removed"] as? Bool ?? false
        } catch {
            return false
        }
    }

    func contentPath(entryId: String) -> String? {
        guard let value = try? client.call(
            "workspace.contentPath",
            payload: ["entryId": entryId]
        ) as? [String: Any] else {
            return nil
        }
        return value["path"] as? String
    }

    func hasContent(entryId: String) -> Bool {
        contentPath(entryId: entryId) != nil
    }
}

final class WorkspaceLogic: @unchecked Sendable {
    static let shared = WorkspaceLogic()

    func displayOrder(entries: [WorkspaceEntry]) -> [WorkspaceEntry] {
        let input = entries
        guard let value = try? CovioCoreRuntime.shared.call(
            "workspace.displayOrder",
            payload: ["entries": (try? coreEncode(input)) ?? []]
        ) as? [String: Any],
              let encoded = value["entries"] else {
            return input
        }
        return (try? coreDecode([WorkspaceEntry].self, from: encoded)) ?? input
    }

    func localBytes(entries: [WorkspaceEntry]) -> Int64 {
        entries.reduce(0) { $0 + $1.localBytes }
    }
}

final class FileAreaProjection: @unchecked Sendable {
    static let shared = FileAreaProjection()

    func build(
        shelfItems: [ShelfItem],
        workspaceEntries: [WorkspaceEntry],
        existingScreenshotPaths: [String]
    ) -> [FileAreaItem] {
        let existing = Set(existingScreenshotPaths.map(ShelfStore.companion.canonicalPath))
        var seen = Set<String>()
        let screenshots = shelfItems.compactMap { raw -> FileAreaItem? in
            let item = raw.normalized
            guard !item.path.isEmpty else { return nil }
            let path = ShelfStore.companion.canonicalPath(value: item.path)
            guard existing.contains(path), seen.insert(path).inserted else { return nil }
            return FileAreaItem(
                id: "screenshot:\(path)",
                origin: .screenshot,
                itemId: path,
                displayName: URL(fileURLWithPath: path).lastPathComponent,
                kind: .screenshot,
                createdAtEpochSeconds: max(0, item.addedAtEpochSeconds),
                capabilities: FileAreaCapabilities(
                    canOpen: true, canCopy: true, canMarkup: true, canDragOut: true,
                    canSaveToWorkspace: true, canRemove: true
                )
            )
        }
        let workspace = workspaceEntries.compactMap { raw -> FileAreaItem? in
            guard raw.isUsable else { return nil }
            let availability: FileAreaAvailability = switch raw.availability {
            case .local: .local
            case .remote: .remote
            case .fetching: .fetching
            case .evicted: .unavailable
            }
            let kind: FileAreaKind = switch raw.kind {
            case .image: .image
            case .text: .text
            case .pdf: .pdf
            case .audio: .audio
            case .file: .file
            }
            let local = availability == .local
            return FileAreaItem(
                id: "workspace:\(raw.entryId)",
                origin: .workspace,
                itemId: raw.entryId,
                displayName: raw.displayName.isEmpty ? String(raw.entryId.prefix(12)) : raw.displayName,
                kind: kind,
                createdAtEpochSeconds: max(0, raw.createdAtEpochSeconds),
                byteSize: max(0, raw.byteSize),
                originDeviceId: raw.originDeviceId,
                expiresAtEpochSeconds: max(0, raw.expiresAtEpochSeconds),
                availability: availability,
                pinned: raw.pinned,
                capabilities: FileAreaCapabilities(
                    canOpen: local,
                    canCopy: local && kind != .text,
                    canCopyText: local && kind == .text,
                    canDragOut: local,
                    canReveal: local,
                    canPin: true,
                    canRemove: true,
                    canDownload: availability == .remote,
                    canCancel: availability == .fetching
                )
            )
        }
        return (screenshots + workspace).sorted {
            if $0.pinned != $1.pinned { return $0.pinned && !$1.pinned }
            if $0.createdAtEpochSeconds != $1.createdAtEpochSeconds {
                return $0.createdAtEpochSeconds > $1.createdAtEpochSeconds
            }
            if $0.origin != $1.origin { return $0.origin == .screenshot }
            return $0.id < $1.id
        }
    }

    func filter(items: [FileAreaItem], filter: FileAreaFilter) -> [FileAreaItem] {
        items.filter { $0.matches(filter) }
    }
}

extension ShelfStoreState {
    struct Companion: Sendable {
        func defaults() -> ShelfStoreState { ShelfStoreState() }
    }
    static let companion = Companion()
}

extension WorkspaceState {
    struct Companion: Sendable {
        func defaults() -> WorkspaceState { WorkspaceState() }
    }
    static let companion = Companion()
}

extension WorkspacePolicy {
    struct Companion: Sendable {
        func defaults() -> WorkspacePolicy { WorkspacePolicy() }
    }
    static let companion = Companion()

    func doCopy(
        maxTotalBytes: Int64? = nil,
        maxEntryBytes: Int64? = nil,
        retentionDays: Int32? = nil,
        lazyFetchThresholdBytes: Int64? = nil
    ) -> WorkspacePolicy {
        var copy = self
        copy.maxTotalBytes = maxTotalBytes ?? self.maxTotalBytes
        copy.maxEntryBytes = maxEntryBytes ?? self.maxEntryBytes
        copy.retentionDays = retentionDays ?? self.retentionDays
        copy.lazyFetchThresholdBytes = lazyFetchThresholdBytes ?? self.lazyFetchThresholdBytes
        return copy
    }
}

extension DisplayConfig {
    struct Companion: Sendable {
        func defaults() -> DisplayConfig { DisplayConfig() }
        func fromLegacy(
            power: PowerConfig,
            keepsAwakeOnAdapter: Bool = false,
            keepsAwakeOnBattery: Bool = false
        ) -> DisplayConfig {
            DisplayConfig.fromLegacy(
                power: power,
                keepsAwakeOnAdapter: keepsAwakeOnAdapter,
                keepsAwakeOnBattery: keepsAwakeOnBattery
            )
        }
    }
    static let companion = Companion()
}

extension ShelfStoreState {
    func doCopy(
        items: [ShelfItem],
        revealed: Bool,
        preferenceSnapshot: ScreenshotInboxSnapshot?
    ) -> ShelfStoreState {
        ShelfStoreState(
            items: items,
            revealed: revealed,
            preferenceSnapshot: preferenceSnapshot
        )
    }
}

extension ClipItem {
    func doCopy(
        id: String? = nil,
        kind: ClipKind? = nil,
        text: String? = nil,
        filePath: String? = nil,
        byteSize: Int64? = nil,
        createdAtEpochSeconds: Int64? = nil,
        pinned: Bool? = nil,
        sourceBundleId: String? = nil
    ) -> ClipItem {
        ClipItem(
            id: id ?? self.id,
            kind: kind ?? self.kind,
            text: text ?? self.text,
            filePath: filePath ?? self.filePath,
            byteSize: byteSize ?? self.byteSize,
            createdAtEpochSeconds: createdAtEpochSeconds ?? self.createdAtEpochSeconds,
            pinned: pinned ?? self.pinned,
            sourceBundleId: sourceBundleId ?? self.sourceBundleId
        )
    }
}

extension WorkspaceState {
    func doCopy(
        schemaVersion: Int32? = nil,
        entries: [WorkspaceEntry]? = nil,
        policy: WorkspacePolicy? = nil
    ) -> WorkspaceState {
        WorkspaceState(
            schemaVersion: schemaVersion ?? self.schemaVersion,
            entries: entries ?? self.entries,
            policy: policy ?? self.policy
        )
    }
}

extension WorkspaceEntry {
    func doCopy(
        entryId: String? = nil,
        kind: WorkspaceKind? = nil,
        displayName: String? = nil,
        byteSize: Int64? = nil,
        contentType: String? = nil,
        createdAtEpochSeconds: Int64? = nil,
        originDeviceId: String? = nil,
        expiresAtEpochSeconds: Int64? = nil,
        availability: WorkspaceAvailability? = nil,
        pinned: Bool? = nil
    ) -> WorkspaceEntry {
        WorkspaceEntry(
            entryId: entryId ?? self.entryId,
            kind: kind ?? self.kind,
            displayName: displayName ?? self.displayName,
            byteSize: byteSize ?? self.byteSize,
            contentType: contentType ?? self.contentType,
            createdAtEpochSeconds: createdAtEpochSeconds ?? self.createdAtEpochSeconds,
            originDeviceId: originDeviceId ?? self.originDeviceId,
            expiresAtEpochSeconds: expiresAtEpochSeconds ?? self.expiresAtEpochSeconds,
            availability: availability ?? self.availability,
            pinned: pinned ?? self.pinned
        )
    }
}

enum PmsetConfigParser {
    static func sleepTimeoutSeconds(text: String?) -> Int64? {
        let value = try? CovioCoreRuntime.shared.call(
            "pmset.config.sleepTimeoutSeconds",
            payload: text.map { ["text": $0] } ?? [:]
        ) as? [String: Any]
        return (value?["seconds"] as? NSNumber)?.int64Value
    }

    static func hibernateMode(text: String?) -> Int32? {
        let value = try? CovioCoreRuntime.shared.call(
            "pmset.config.hibernateMode",
            payload: text.map { ["text": $0] } ?? [:]
        ) as? [String: Any]
        return (value?["mode"] as? NSNumber)?.int32Value
    }

    static func sleepDisabled(text: String?) -> Bool? {
        let value = try? CovioCoreRuntime.shared.call(
            "pmset.config.sleepDisabled",
            payload: text.map { ["text": $0] } ?? [:]
        ) as? [String: Any]
        return value?["disabled"] as? Bool
    }
}

struct ScreenshotPreferencePolicy {
    static let shared = ScreenshotPreferencePolicy()

    let COMMAND_TIMEOUT_MILLIS: Int64 = 5_000
    let DOMAIN = "com.apple.screencapture"
    let KEY_LOCATION = "location"
    let KEY_LOCATION_SCREENSHOT = "location-screenshot"
    let KEY_SHOW_THUMBNAIL = "show-thumbnail"

    func parseString(exitCode: Int32, output: String) -> String? {
        guard let response = try? CovioCoreRuntime.shared.call(
            "screenshotPreference.parseString",
            payload: ["exitCode": exitCode, "output": output]
        ) as? [String: Any] else { return nil }
        return response["value"] as? String
    }

    func parseBoolean(exitCode: Int32, output: String) -> Bool? {
        guard let response = try? CovioCoreRuntime.shared.call(
            "screenshotPreference.parseBoolean",
            payload: ["exitCode": exitCode, "output": output]
        ) as? [String: Any], let value = response["value"] as? Bool else { return nil }
        return value
    }

    func writeArgument(value: String, isString: Bool) -> String {
        guard let response = try? CovioCoreRuntime.shared.call(
            "screenshotPreference.writeArgument",
            payload: ["value": value, "isString": isString]
        ) as? [String: Any] else { return isString ? value : (value == "1" ? "true" : "false") }
        return response["value"] as? String ?? value
    }

    func deleteIsSuccess(exitCode: Int32, output: String) -> Bool {
        guard let response = try? CovioCoreRuntime.shared.call(
            "screenshotPreference.deleteIsSuccess",
            payload: ["exitCode": exitCode, "output": output]
        ) as? [String: Any] else { return false }
        return response["result"] as? Bool ?? false
    }
}

struct PowerPolicy {
    static let shared = PowerPolicy()

    func decide(
        config: PowerConfig,
        snapshot: PowerSnapshot,
        leases: [HoldLease],
        nowEpochSeconds: Int64,
        paused: Bool,
        batteryGuardLatched: Bool
    ) -> PowerDecision {
        do {
            let payload: [String: Any] = [
                "config": try coreEncode(config),
                "snapshot": try coreEncode(snapshot),
                "leases": try coreEncode(leases),
                "nowEpochSeconds": nowEpochSeconds,
                "paused": paused,
                "batteryGuardLatched": batteryGuardLatched,
            ]
            let value = try CovioCoreRuntime.shared.call("power.decide", payload: payload)
            guard let root = value as? [String: Any], let decision = root["decision"] else {
                return blockedPowerDecision()
            }
            return try coreDecode(PowerDecision.self, from: decision)
        } catch {
            return blockedPowerDecision()
        }
    }

    private func blockedPowerDecision() -> PowerDecision {
        PowerDecision(
            preventUserIdleSystemSleep: false,
            preventUserIdleDisplaySleep: false,
            preventLidSleep: false,
            appliedLeaseLevel: nil,
            activeLeaseIds: [],
            automaticRuleApplied: false,
            safetyVetoes: [.explicitlyPaused],
            batteryGuardLatched: false
        )
    }
}

enum ShelfLogic {
    static func acceptsShelfFile(
        path: String,
        dedicatedDirectory: String,
        hasScreenCaptureAttribute: (String) -> Bool
    ) -> Bool {
        do {
            let value = try CovioCoreRuntime.shared.call(
                "shelf.acceptsFile",
                payload: [
                    "path": path,
                    "dedicatedDirectory": dedicatedDirectory,
                    "hasScreenCaptureAttribute": hasScreenCaptureAttribute(path),
                ]
            )
            return (value as? [String: Any])?["result"] as? Bool ?? false
        } catch {
            return false
        }
    }
}

enum PmsetWakeLogParser {
    static func parse(text: String, nowEpochSeconds: Int64) -> WakeLogSnapshot {
        guard let value = try? CovioCoreRuntime.shared.call(
            "pmset.wake.parse",
            payload: ["text": text],
            nowEpochSeconds: nowEpochSeconds
        ) as? [String: Any],
              let snapshot = value["snapshot"] else {
            return WakeLogSnapshot()
        }
        return (try? coreDecode(WakeLogSnapshot.self, from: snapshot)) ?? WakeLogSnapshot()
    }

    static func parseFile(path: String, nowEpochSeconds: Int64) -> WakeLogSnapshot? {
        guard let value = try? CovioCoreRuntime.shared.call(
            "pmset.wake.parseFile",
            payload: ["path": path],
            nowEpochSeconds: nowEpochSeconds
        ) as? [String: Any],
              let snapshot = value["snapshot"] else {
            return nil
        }
        return try? coreDecode(WakeLogSnapshot.self, from: snapshot)
    }

    static func parseTimestamp(value: String) -> Int64? {
        guard let result = try? CovioCoreRuntime.shared.call(
            "pmset.wake.parseTimestamp",
            payload: ["value": value]
        ) as? [String: Any] else { return nil }
        return (result["seconds"] as? NSNumber)?.int64Value
    }
}

struct DesignContractReader {
    static let shared = DesignContractReader()

    func defaultContractPath() -> String { "docs/covio-design-contract.json" }

    func parse(text: String) -> DesignContractValidationResult {
        do {
            let value = try CovioCoreRuntime.shared.call(
                "design.parse",
                payload: ["text": text]
            )
            return try coreDecode(DesignContractValidationResult.self, from: value)
        } catch {
            return DesignContractValidationResult(
                contract: nil,
                diagnostics: [
                    DesignContractDiagnostic(severity: .error, path: "", message: "合同读取失败")
                ]
            )
        }
    }

    func readFile(path: String) -> DesignContractValidationResult {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            return DesignContractValidationResult(
                contract: nil,
                diagnostics: [
                    DesignContractDiagnostic(severity: .error, path: path, message: "读不到合同文件")
                ]
            )
        }
        return parse(text: text)
    }
}

enum UpdatePolicy {
    static func shouldCheck(config: AppConfig, nowEpochSeconds: Int64) -> Bool {
        guard let value = try? CovioCoreRuntime.shared.call(
            "update.shouldCheck",
            payload: ["config": (try? coreEncode(config)) ?? [:]]
        ) as? [String: Any] else { return false }
        return value["result"] as? Bool ?? false
    }

    static func selectUpdate(candidate: UpdateInfo?, currentVersion: String) -> UpdateInfo? {
        do {
            let payload: [String: Any] = [
                "candidate": try candidate.map(coreEncode) ?? NSNull(),
                "currentVersion": currentVersion,
            ]
            let value = try CovioCoreRuntime.shared.call("update.select", payload: payload) as? [String: Any]
            guard let result = value?["result"], !(result is NSNull) else { return nil }
            return try coreDecode(UpdateInfo.self, from: result)
        } catch {
            return nil
        }
    }
}

func isStableVersion(_ value: String) -> Bool {
    guard let result = try? CovioCoreRuntime.shared.call(
        "version.isStable",
        payload: ["value": value]
    ) as? [String: Any] else { return false }
    return result["result"] as? Bool ?? false
}

func isNewerVersion(_ candidate: String, _ current: String) -> Bool {
    guard let result = try? CovioCoreRuntime.shared.call(
        "version.isNewer",
        payload: ["candidate": candidate, "current": current]
    ) as? [String: Any] else { return false }
    return result["result"] as? Bool ?? false
}

func isStableClientVersion(_ value: String) -> Bool { ClientVersion.parse(value) != nil }
func isNewerClientVersion(_ candidate: String, _ current: String) -> Bool {
    guard let candidate = ClientVersion.parse(candidate), let current = ClientVersion.parse(current) else { return false }
    return candidate > current
}

extension SemanticVersion {
    static func parse(_ value: String) -> SemanticVersion? {
        guard let response = try? CovioCoreRuntime.shared.call(
            "version.parse",
            payload: ["value": value]
        ) as? [String: Any],
              let version = response["version"], !(version is NSNull) else { return nil }
        return try? coreDecode(SemanticVersion.self, from: version)
    }

    static func parseTag(_ value: String) -> SemanticVersion? {
        guard value.hasPrefix("v") else { return nil }
        return parse(String(value.dropFirst()))
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        isNewerVersion(rhs.description, lhs.description)
    }
}

extension ClientVersion {
    static func parse(_ value: String) -> ClientVersion? {
        let pattern = #"^[vV]?(\d)\.(\d)\.(\d)\.(\d)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              match.numberOfRanges == 5 else { return nil }
        func digit(_ index: Int) -> UInt8? {
            guard let range = Range(match.range(at: index), in: value) else { return nil }
            return UInt8(value[range])
        }
        guard let thousands = digit(1), let hundreds = digit(2), let tens = digit(3), let ones = digit(4) else { return nil }
        return ClientVersion(thousands: thousands, hundreds: hundreds, tens: tens, ones: ones)
    }

    static func fromBuild(_ buildNumber: Int64) -> ClientVersion? {
        guard (1...9_999).contains(buildNumber) else { return nil }
        let digits = String(format: "%04lld", buildNumber)
        let values = digits.compactMap { $0.wholeNumberValue }.map(UInt8.init)
        guard values.count == 4 else { return nil }
        return ClientVersion(thousands: values[0], hundreds: values[1], tens: values[2], ones: values[3])
    }
}

extension SemanticVersion: CustomStringConvertible {
    var description: String {
        var value = baseVersion
        if !prerelease.isEmpty { value += "-" + prerelease.joined(separator: ".") }
        if !buildMetadata.isEmpty { value += "+" + buildMetadata.joined(separator: ".") }
        return value
    }
    func isInternalBuild(_ buildNumber: Int64) -> Bool {
        buildMetadata.isEmpty && prerelease == ["internal", String(buildNumber)]
    }
}

extension ClientVersion: CustomStringConvertible {
    var description: String { "\(thousands).\(hundreds).\(tens).\(ones)" }
}

enum FileNamingPolicyEvaluator {
    static func validationErrors(policy: FileNamingPolicy) -> [FileNamingPolicyError] {
        let template = policy.template.trimmingCharacters(in: .whitespacesAndNewlines)
        let regex = try! NSRegularExpression(pattern: #"[{]([^{}]+)[}]"#)
        let range = NSRange(template.startIndex..., in: template)
        let tokens = regex.matches(in: template, range: range).compactMap { match -> String? in
            guard let range = Range(match.range(at: 1), in: template) else { return nil }
            return String(template[range])
        }
        let withoutTokens = regex.stringByReplacingMatches(in: template, range: range, withTemplate: "")
        var errors: [FileNamingPolicyError] = []
        if !tokens.contains("title") { errors.append(.missingTitleToken) }
        if tokens.contains(where: { !["title", "category", "date", "language"].contains($0) }) {
            errors.append(.unknownToken)
        }
        if withoutTokens.contains("{") || withoutTokens.contains("}") {
            errors.append(.unbalancedToken)
        }
        if withoutTokens.contains(where: isUnsafeFileCharacter) {
            errors.append(.unsafeTemplate)
        }
        if !isValidSeparator(policy.separator) { errors.append(.invalidSeparator) }
        if policy.conflictPolicy == .appendNumber && !isValidConflictSuffix(policy.conflictSuffix) {
            errors.append(.invalidConflictSuffix)
        }
        return Array(Set(errors))
    }

    private static func isUnsafeFileCharacter(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first else { return true }
        return scalar.value <= 0x1F || (0x7F...0x9F).contains(scalar.value)
            || #"<>:"/\|?*"#.contains(character)
    }

    private static func isValidSeparator(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 3 && value.allSatisfy {
            $0.isLetter || $0.isNumber || "-_.()".contains($0)
        } && !value.contains(where: isUnsafeFileCharacter)
    }

    private static func isValidConflictSuffix(_ value: String) -> Bool {
        guard !value.isEmpty, value.contains("{n}") else { return false }
        let without = value.replacingOccurrences(of: "{n}", with: "")
        return !without.contains("{") && !without.contains("}")
            && !without.contains(where: isUnsafeFileCharacter)
    }
}

final class ChargeLimitPolicy: @unchecked Sendable {
    static let shared = ChargeLimitPolicy()

    func isValidUpperLimit(percent: Int32) -> Bool {
        guard let value = try? CovioCoreRuntime.shared.call(
            "chargeLimit.isValidUpperLimit",
            payload: ["percent": percent]
        ) as? [String: Any] else { return false }
        return value["result"] as? Bool ?? false
    }

    func normalizeUpperLimit(percent: Int32) -> Int32 {
        guard let value = try? CovioCoreRuntime.shared.call(
            "chargeLimit.normalizeUpperLimit",
            payload: ["percent": percent]
        ) as? [String: Any] else { return DEFAULT_CHARGE_LIMIT_PERCENT }
        return (value["percent"] as? NSNumber)?.int32Value ?? DEFAULT_CHARGE_LIMIT_PERCENT
    }

    func resumeThreshold(upperLimitPercent: Int32) -> Int32 {
        guard let value = try? CovioCoreRuntime.shared.call(
            "chargeLimit.resumeThreshold",
            payload: ["upperLimitPercent": upperLimitPercent]
        ) as? [String: Any] else { return CHARGE_LIMIT_MIN_RESUME_PERCENT }
        return (value["percent"] as? NSNumber)?.int32Value ?? CHARGE_LIMIT_MIN_RESUME_PERCENT
    }

    func evaluate(
        observation: ChargeLimitObservation,
        previous: ChargeLimitPolicyState = ChargeLimitPolicyState()
    ) -> ChargeLimitDecision {
        do {
            let value = try CovioCoreRuntime.shared.call(
                "chargeLimit.evaluate",
                payload: [
                    "observation": try coreEncode(observation),
                    "previous": try coreEncode(previous),
                ]
            )
            let root = value as? [String: Any]
            return try coreDecode(ChargeLimitDecision.self, from: root?["decision"] ?? [:])
        } catch {
            return ChargeLimitDecision(
                phase: .error,
                targetPercent: nil,
                errorMessage: "Charge limit policy failed"
            )
        }
    }
}

extension Bool { var boolValue: Bool { self } }
extension Int32 {
    var intValue: Int32 { self }
    var int32Value: Int32 { self }
}
extension Int64 { var int64Value: Int64 { self } }
extension Optional where Wrapped == Bool { var boolValue: Bool? { self } }
extension Optional where Wrapped == Int32 { var intValue: Int32? { self } }
extension Optional where Wrapped == Int64 { var int64Value: Int64? { self } }

extension CovioRuntimeConstants {
    static var APP_ID: String { "com.wyz.covio" }
    static var APP_NAME: String { "Covio" }
}

extension SleepEvent {
    static var willsleep: SleepEvent { .willSleep }
    static var wakesignal: SleepEvent { .wakeSignal }
}

extension WidgetSize {
    static var entries: [WidgetSize] { allCases }

    struct Companion: Sendable {
        var FALLBACK: WidgetSize { .fallback }
    }

    static let companion = Companion()
}

extension PaneKind {
    static var entries: [PaneKind] { allCases }
}

extension AppConfig {
    func doCopy(
        schemaVersion: Int32,
        language: String,
        enabled: Bool,
        launchAtLogin: Bool,
        lowBatteryCapacitySleep: Bool,
        lowBatteryCapacity: Int32,
        lowTimeRemainingMinutes: Int32,
        disableIdleSleepInCharging: Bool,
        disableLidSleepInCharging: Bool,
        disableLidSleepOnBattery: Bool,
        darkWakeAwarenessEnabled: Bool,
        lidSleepImmediateOnClose: Bool,
        notificationsEnabled: Bool,
        trackpadGestureEnabled: Bool,
        updateCheckEnabled: Bool,
        updateCheckIntervalHours: Int32,
        lastUpdateCheckEpochSeconds: Int64,
        hibernateMode: Int32?,
        firstRun: Bool,
        shelfEnabled: Bool,
        screenshotInboxEnabled: Bool,
        shelfSoundsEnabled: Bool,
        clipboardEnabled: Bool,
        clipboardPasteStackHotKey: String,
        clipboardCaptureHotKey: String,
        power: PowerConfig,
        display: DisplayConfig?,
        chargeLimitEnabled: Bool,
        chargeLimitPercent: Int32,
        chargeLimitActiveDischarge: Bool,
        fileNaming: FileNamingPolicy
    ) -> AppConfig {
        AppConfig(
            schemaVersion: schemaVersion,
            language: language,
            enabled: enabled,
            launchAtLogin: launchAtLogin,
            lowBatteryCapacitySleep: lowBatteryCapacitySleep,
            lowBatteryCapacity: lowBatteryCapacity,
            lowTimeRemainingMinutes: lowTimeRemainingMinutes,
            disableIdleSleepInCharging: disableIdleSleepInCharging,
            disableLidSleepInCharging: disableLidSleepInCharging,
            disableLidSleepOnBattery: disableLidSleepOnBattery,
            darkWakeAwarenessEnabled: darkWakeAwarenessEnabled,
            lidSleepImmediateOnClose: lidSleepImmediateOnClose,
            notificationsEnabled: notificationsEnabled,
            trackpadGestureEnabled: trackpadGestureEnabled,
            updateCheckEnabled: updateCheckEnabled,
            updateCheckIntervalHours: updateCheckIntervalHours,
            lastUpdateCheckEpochSeconds: lastUpdateCheckEpochSeconds,
            hibernateMode: hibernateMode,
            firstRun: firstRun,
            shelfEnabled: shelfEnabled,
            screenshotInboxEnabled: screenshotInboxEnabled,
            shelfSoundsEnabled: shelfSoundsEnabled,
            clipboardEnabled: clipboardEnabled,
            clipboardPasteStackHotKey: clipboardPasteStackHotKey,
            clipboardCaptureHotKey: clipboardCaptureHotKey,
            power: power,
            display: display,
            chargeLimitEnabled: chargeLimitEnabled,
            chargeLimitPercent: chargeLimitPercent,
            chargeLimitActiveDischarge: chargeLimitActiveDischarge,
            fileNaming: fileNaming
        )
    }
}

extension AppState {
    func doCopy(
        battery: BatteryStatus?,
        lid: LidState,
        enabled: Bool,
        idleSleepAvailable: Bool,
        idleSleepPrevention: IdleSleepPrevention,
        lidSleepAvailable: Bool,
        idleCancelRemainingSeconds: Int64?,
        lidCancelRemainingSeconds: Int64?,
        darkWake: DarkWakeStatus,
        helperStatus: HelperStatus,
        lidLeaseStatus: LidLeaseStatus,
        lastError: String?
    ) -> AppState {
        AppState(
            battery: battery,
            lid: lid,
            enabled: enabled,
            idleSleepAvailable: idleSleepAvailable,
            idleSleepPrevention: idleSleepPrevention,
            lidSleepAvailable: lidSleepAvailable,
            idleCancelRemainingSeconds: idleCancelRemainingSeconds,
            lidCancelRemainingSeconds: lidCancelRemainingSeconds,
            darkWake: darkWake,
            helperStatus: helperStatus,
            lidLeaseStatus: lidLeaseStatus,
            lastError: lastError
        )
    }
}

extension WidgetInstance {
    var normalized: WidgetInstance {
        let positioned = column >= 0 && row >= 0
        return WidgetInstance(
            id: String(id.trimmingCharacters(in: .whitespacesAndNewlines).prefix(64)),
            kind: String(kind.trimmingCharacters(in: .whitespacesAndNewlines).prefix(64)),
            size: size,
            settings: settings,
            column: positioned ? column : WIDGET_AUTOMATIC_POSITION,
            row: positioned ? row : WIDGET_AUTOMATIC_POSITION
        )
    }

    func withGridFrame(size: WidgetSize, column: Int32, row: Int32) -> WidgetInstance {
        WidgetInstance(id: id, kind: kind, size: size, settings: settings, column: column, row: row)
    }
}

extension PaneInstance {
    var normalized: PaneInstance {
        PaneInstance(
            id: String(id.trimmingCharacters(in: .whitespacesAndNewlines).prefix(64)),
            kind: kind,
            title: String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24)),
            icon: String(icon.trimmingCharacters(in: .whitespacesAndNewlines).prefix(64)),
            isHidden: isHidden,
            settings: settings
        )
    }
}

extension WorkbenchConfig {
    struct Companion: Sendable {
        let MAX_PANES: Int32 = 12
        let MAX_WIDGETS: Int32 = 24
        func defaults() -> WorkbenchConfig { WorkbenchConfig() }
    }
    static let companion = Companion()

    var visiblePanes: [PaneInstance] {
        panes.filter { !$0.isHidden && $0.kind.appearsInWorkbenchNavigation }
    }

    func pane(id: String) -> PaneInstance? { panes.first { $0.id == id } }

    func addPane(pane: PaneInstance) -> WorkbenchConfig {
        let candidate = pane.normalized
        guard !candidate.id.isEmpty, !candidate.isBuiltin else { return self }
        guard !panes.contains(where: { $0.id == candidate.id }), panes.count < Self.maxPanes else { return self }
        var copy = self
        copy.panes.append(candidate)
        return copy
    }

    func removePane(id: String) -> WorkbenchConfig {
        guard let target = pane(id: id), !target.isBuiltin else { return self }
        var copy = self
        copy.panes.removeAll { $0.id == id }
        return copy
    }

    func setPaneHidden(id: String, hidden: Bool) -> WorkbenchConfig {
        var copy = self
        copy.panes = panes.map { pane in
            guard pane.id == id else { return pane }
            var pane = pane
            pane.isHidden = hidden
            return pane
        }
        return copy
    }

    func renamePane(id: String, title: String) -> WorkbenchConfig {
        var copy = self
        copy.panes = panes.map { pane in
            guard pane.id == id else { return pane }
            var pane = pane
            pane.title = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24))
            return pane
        }
        return copy
    }

    func movePane(id: String, toIndex: Int32) -> WorkbenchConfig {
        guard let from = panes.firstIndex(where: { $0.id == id }) else { return self }
        var reordered = panes
        let moved = reordered.remove(at: from)
        reordered.insert(moved, at: min(max(Int(toIndex), 0), reordered.count))
        var copy = self
        copy.panes = reordered
        return copy
    }

    func doCopy(
        schemaVersion: Int32? = nil,
        panes: [PaneInstance]? = nil,
        homeWidgets: [WidgetInstance]? = nil
    ) -> WorkbenchConfig {
        WorkbenchConfig(
            schemaVersion: schemaVersion ?? self.schemaVersion,
            panes: panes ?? self.panes,
            homeWidgets: homeWidgets ?? self.homeWidgets,
            selectedPaneId: selectedPaneId
        )
    }
}

final class WorkbenchStore: @unchecked Sendable {
    struct Companion: Sendable {
        func create(path: String) -> WorkbenchStore { WorkbenchStore(path: path) }
        func defaultWorkbenchPath() -> String {
            URL(fileURLWithPath: CovioCoreDefaults.applicationSupportRoot)
                .appendingPathComponent("Covio/Workbench/workbench.json").path
        }
    }
    static let companion = Companion()
    private let path: String
    private let lock = NSLock()

    init(path: String) { self.path = path }

    func load() -> WorkbenchConfig {
        lock.lock(); defer { lock.unlock() }
        guard let data = FileManager.default.contents(atPath: path),
              let config = try? JSONDecoder().decode(WorkbenchConfig.self, from: data) else {
            return WorkbenchConfig()
        }
        return config.normalized()
    }

    func save(config: WorkbenchConfig) -> Bool {
        lock.lock(); defer { lock.unlock() }
        do {
            try FileManager.default.createDirectory(
                at: URL(fileURLWithPath: path).deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(config.normalized())
            let temporary = path + ".tmp"
            try data.write(to: URL(fileURLWithPath: temporary), options: .atomic)
            _ = try? FileManager.default.removeItem(atPath: path)
            try FileManager.default.moveItem(atPath: temporary, toPath: path)
            return true
        } catch {
            return false
        }
    }

    func clear() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return (try? FileManager.default.removeItem(atPath: path)) != nil
    }
}

struct ClipboardNext: Sendable {
    let first: ClipboardState
    let second: ClipItem?
}

extension ClipboardState {
    func doCopy(
        items: [ClipItem]? = nil,
        pasteStack: [String]? = nil,
        paused: Bool? = nil,
        policy: ClipPolicy? = nil
    ) -> ClipboardState {
        ClipboardState(
            items: items ?? self.items,
            pasteStack: pasteStack ?? self.pasteStack,
            paused: paused ?? self.paused,
            policy: policy ?? self.policy
        )
    }
}

extension FileNamingWarningCode {
    var name: String { rawValue }
}

extension ClosedLidPowerPolicy {
    func appliesTo(powerState: PowerState) -> Bool {
        switch powerState {
        case .discharging:
            keepsAwakeOnBattery
        case .charging, .charged, .acPower:
            keepsAwakeOnAdapter
        case .unknown:
            false
        }
    }
}

extension ClipPolicy {
    struct Companion: Sendable {
        func defaults() -> ClipPolicy { ClipPolicy() }
        func normalized(_ value: ClipPolicy) -> ClipPolicy {
            ClipPolicy(
                maxItems: min(max(value.maxItems, 1), 1_000),
                maxAgeDays: min(max(value.maxAgeDays, 0), 3_650),
                maxTotalBytes: max(value.maxTotalBytes, 0)
            )
        }
    }
    static let companion = Companion()
    func normalized() -> ClipPolicy { Self.companion.normalized(self) }
}

extension ClipboardState {
    struct Companion: Sendable {
        func defaults() -> ClipboardState { ClipboardState() }
    }
    static let companion = Companion()
}

extension ClipItem {
    var identity: String {
        switch kind {
        case .image, .files:
            return "f:\(ShelfStore.companion.canonicalPath(value: filePath))"
        case .text, .link, .color:
            return "t:\(text.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
    }
}

extension ClipboardLogic {
    func importPaths(item: ClipItem) -> [String] {
        switch item.kind {
        case .image:
            let path = item.filePath.trimmingCharacters(in: .whitespacesAndNewlines)
            return path.isEmpty ? [] : [path]
        case .files:
            return Array(Set((item.text.split(separator: "\n").map(String.init) + [item.filePath])
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty })).sorted()
        default:
            return []
        }
    }
}

extension FileNamingPolicy {
    struct Companion: Sendable {
        func defaults() -> FileNamingPolicy { FileNamingPolicy() }
    }
    static let companion = Companion()
    var template_: String { template }
}

extension WorkspacePlan {
    var changed: Bool { !expired.isEmpty || !evicted.isEmpty }
    var removed: [WorkspaceEntry] { expired + evicted }
}

extension WorkspaceLogic {
    func suggestedTextName(text: String) -> String {
        let firstLine = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let cleaned = firstLine.unicodeScalars.map { scalar -> Character in
            if CharacterSet.controlCharacters.contains(scalar) || forbidden.contains(scalar) {
                return " "
            }
            return Character(scalar)
        }
        let title = String(cleaned)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .prefix(80)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return title.isEmpty ? "clipboard.txt" : "\(title).txt"
    }
}

final class FileNamingPlanner: @unchecked Sendable {
    static let shared = FileNamingPlanner()

    func plan(
        request: FileNamingRequest,
        policy: FileNamingPolicy,
        existingNames: Set<String>
    ) -> FileNamingPlan {
        planBatch(requests: [request], policy: policy, existingNames: existingNames)[0]
    }

    func planBatch(
        requests: [FileNamingRequest],
        policy: FileNamingPolicy,
        existingNames: Set<String>
    ) -> [FileNamingPlan] {
        let rules = policy.normalized()
        let policyErrors = rules.validationErrors()
        var used = Set(existingNames.map(lookupName))
        return requests.map { request in
            let originalName = (request.originalName as NSString).lastPathComponent
            let ext = (originalName as NSString).pathExtension
            let confidence = request.facts.confidence.isFinite
                ? min(max(request.facts.confidence, 0), 1)
                : 0
            var warnings: [FileNamingWarning] = []
            func blocked(_ target: String? = nil) -> FileNamingPlan {
                FileNamingPlan(
                    candidateId: request.candidateId,
                    originalName: originalName,
                    targetName: target,
                    extension: ext.isEmpty ? "" : "." + ext,
                    status: .blocked,
                    confidence: confidence,
                    warnings: warnings
                )
            }
            if request.candidateId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                warnings.append(FileNamingWarning(code: .invalidRequest, detail: "Candidate ID is empty"))
                return blocked()
            }
            if !policyErrors.isEmpty {
                warnings.append(FileNamingWarning(
                    code: .invalidPolicy,
                    detail: policyErrors.map(\.rawValue).joined(separator: ",")
                ))
                return blocked()
            }
            if originalName.hasPrefix(".") {
                warnings.append(FileNamingWarning(code: .hiddenFileUnsupported, detail: originalName))
                return blocked()
            }
            if request.facts.kind == .unknown {
                warnings.append(FileNamingWarning(code: .unknownType))
                return blocked()
            }
            if confidence < rules.minConfidence {
                warnings.append(FileNamingWarning(
                    code: .lowConfidence,
                    detail: "\(confidence) < \(rules.minConfidence)"
                ))
                return blocked()
            }
            if request.facts.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                warnings.append(FileNamingWarning(code: .emptyTitle))
                return blocked()
            }
            if request.facts.kind == .mixed {
                warnings.append(FileNamingWarning(code: .mixedInput))
            }
            var stem = rules.template.replacingOccurrences(of: "{title}", with: request.facts.title)
            stem = stem.replacingOccurrences(of: "{category}", with: request.facts.category)
            stem = stem.replacingOccurrences(of: "{date}", with: request.facts.date ?? "")
            stem = stem.replacingOccurrences(of: "{language}", with: request.facts.language ?? "")
            stem = stem.split(whereSeparator: \.isWhitespace).joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if rules.lowercaseLatin { stem = stem.lowercased() }
            let extensionText = ext.isEmpty ? "" : "." + ext
            let remaining = Int(rules.maxUTF8Bytes) - extensionText.utf8.count
            if remaining <= 0 {
                warnings.append(FileNamingWarning(code: .nameTooLong, detail: "Extension uses the byte budget"))
                return blocked()
            }
            stem = String(stem.prefix(remaining))
            var target = stem + extensionText
            let ownLookup = lookupName(originalName)
            if lookupName(target) != ownLookup && used.contains(lookupName(target)) {
                if rules.conflictPolicy == .block {
                    warnings.append(FileNamingWarning(code: .conflictBlocked, detail: target))
                    return blocked(target)
                }
                var found: String?
                for index in 2...10_001 {
                    let suffix = rules.conflictSuffix.replacingOccurrences(of: "{n}", with: String(index))
                    let candidate = stem + suffix + extensionText
                    if !used.contains(lookupName(candidate)) {
                        found = candidate
                        break
                    }
                }
                guard let unique = found else {
                    warnings.append(FileNamingWarning(code: .conflictBlocked, detail: target))
                    return blocked(target)
                }
                target = unique
                warnings.append(FileNamingWarning(code: .conflictAppended, detail: target))
            }
            if lookupName(target) == ownLookup {
                warnings.append(FileNamingWarning(code: .unchanged))
            }
            used.insert(lookupName(target))
            return FileNamingPlan(
                candidateId: request.candidateId,
                originalName: originalName,
                targetName: target,
                extension: extensionText,
                status: .ready,
                confidence: confidence,
                warnings: warnings
            )
        }
    }

    private func lookupName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .widthInsensitive], locale: .current)
    }
}

final class ModelPackageContract: @unchecked Sendable {
    static let shared = ModelPackageContract()

    func decodeManifest(text: String) -> ModelPackageManifestContract? {
        try? JSONDecoder().decode(ModelPackageManifestContract.self, from: Data(text.utf8))
    }
    func encodeManifest(manifest: ModelPackageManifestContract) -> String {
        (try? JSONEncoder().encode(manifest)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
    func decodeStatus(text: String) -> ModelDownloadStatusContract? {
        try? JSONDecoder().decode(ModelDownloadStatusContract.self, from: Data(text.utf8))
    }
    func encodeStatus(status: ModelDownloadStatusContract) -> String {
        (try? JSONEncoder().encode(status)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
    func decodeRegistry(text: String) -> ModelPackageRegistryContract? {
        try? JSONDecoder().decode(ModelPackageRegistryContract.self, from: Data(text.utf8))
    }
    func encodeRegistry(registry: ModelPackageRegistryContract) -> String {
        (try? JSONEncoder().encode(registry)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    func validateManifestText(
        manifestText: String,
        expectedTier: String,
        expectedModelId: String,
        expectedRevision: String,
        expectedRuntimeDirectory: String,
        expectedTotalBytes: Int64,
        expectedLicense: String
    ) -> ModelPackageContractValidation {
        guard let manifest = decodeManifest(text: manifestText) else {
            return ModelPackageContractValidation(valid: false, errorCode: "manifestUnreadable", detail: "The model manifest is not valid.")
        }
        return validateManifest(
            manifest: manifest,
            expectation: ModelPackageExpectationContract(
                tier: expectedTier,
                modelID: expectedModelId,
                revision: expectedRevision,
                runtimeDirectory: expectedRuntimeDirectory,
                totalBytes: expectedTotalBytes,
                license: expectedLicense
            )
        )
    }

    func validateManifest(
        manifest: ModelPackageManifestContract,
        expectation: ModelPackageExpectationContract
    ) -> ModelPackageContractValidation {
        func rejected(_ code: ModelPackageContractError, _ detail: String) -> ModelPackageContractValidation {
            ModelPackageContractValidation(valid: false, errorCode: code.rawValue, detail: detail)
        }
        if manifest.schemaVersion != MODEL_PACKAGE_SCHEMA_VERSION {
            return rejected(.unsupportedSchema, "The model manifest schema is not supported.")
        }
        if manifest.tier != expectation.tier || manifest.runtimeDirectory != expectation.runtimeDirectory {
            return rejected(.tierMismatch, "The model package does not match the selected tier.")
        }
        if manifest.modelID != expectation.modelID {
            return rejected(.modelMismatch, "The model package identity is not allowed for this tier.")
        }
        if manifest.revision != expectation.revision || manifest.revision.count != 40
            || !manifest.revision.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) {
            return rejected(.revisionMismatch, "The model package revision does not match the pinned revision.")
        }
        if manifest.license != expectation.license || manifest.license != "Apache-2.0" {
            return rejected(.licenseRejected, "The model package license is not accepted.")
        }
        if manifest.totalBytes < 0 || manifest.totalBytes != expectation.totalBytes {
            return rejected(.totalSizeMismatch, "The model package size does not match the trusted definition.")
        }
        if manifest.files.isEmpty {
            return rejected(.fileMissing, "The model package has no model files.")
        }
        var total: Int64 = 0
        var seen = Set<String>()
        for file in manifest.files {
            guard file.size >= 0, total <= Int64.max - file.size else {
                return rejected(.totalSizeMismatch, "The model package size is invalid.")
            }
            total += file.size
            guard isSafeFileName(name: file.path), seen.insert(file.path).inserted else {
                return rejected(.invalidPath, "The model package contains an invalid file path.")
            }
        }
        if manifest.totalBytes != total {
            return rejected(.totalSizeMismatch, "The model package size does not match its files.")
        }
        if !isSafeFileName(name: manifest.licenseFile) || !isSafeFileName(name: manifest.noticeFile) {
            return rejected(.invalidPath, "The model package contains an invalid attribution path.")
        }
        return ModelPackageContractValidation(valid: true, errorCode: nil, detail: "")
    }

    func isSafeFileName(name: String) -> Bool {
        if name.isEmpty || name == "." || name == ".." { return false }
        if name.unicodeScalars.contains(where: { $0.value < 0x20 })
            || name.contains(where: { "\\/:*?\"<>|[]".contains($0) }) { return false }
        if name.hasSuffix(" ") || name.hasSuffix(".") { return false }
        let stem = name.split(separator: ".", maxSplits: 1).first.map(String.init)?.uppercased() ?? ""
        let reserved = Set(["CON", "PRN", "AUX", "NUL"] + (1...9).flatMap { ["COM\($0)", "LPT\($0)"] })
        return !reserved.contains(stem)
    }
}

final class ModelDownloadStatePolicy: @unchecked Sendable {
    static let shared = ModelDownloadStatePolicy()
    func clampProgress(value: Double) -> Double { value.isFinite ? min(max(value, 0), 1) : 0 }
    func downloadedBytes(fractionCompleted: Double, totalBytes: Int64) -> Int64 {
        totalBytes <= 0 ? 0 : Int64(clampProgress(value: fractionCompleted) * Double(totalBytes))
    }
    func phaseKeyAfterInterruption(phaseKey: String) -> String {
        phaseKey == "downloading" || phaseKey == "verifying" ? "paused" : phaseKey
    }
    func phaseKeyAfterFailure(paused: Bool) -> String { paused ? "paused" : "failed" }
}

final class IdleSleepTimeoutCache: @unchecked Sendable {
    struct Companion: Sendable { let DEFAULT_TTL_MILLIS: Int64 = 60_000 }
    static let companion = Companion()
    static let DEFAULT_TTL_MILLIS: Int64 = 60_000
    private let clock: () -> Int64
    private let timeoutReader: () -> Int64?
    private let ttlMillis: Int64
    private let lock = NSLock()
    private var valid = false
    private var cachedAtMillis: Int64 = 0
    private var cachedTimeoutSeconds: Int64?

    init(
        clock: @escaping () -> Int64,
        timeoutReader: @escaping () -> Int64?,
        ttlMillis: Int64 = DEFAULT_TTL_MILLIS
    ) {
        self.clock = clock
        self.timeoutReader = timeoutReader
        self.ttlMillis = ttlMillis
    }

    func get() -> Int64? {
        let now = clock()
        lock.lock()
        if valid, now - cachedAtMillis >= 0, now - cachedAtMillis < ttlMillis {
            let value = cachedTimeoutSeconds
            lock.unlock()
            return value
        }
        lock.unlock()
        let value = timeoutReader()
        lock.lock()
        cachedTimeoutSeconds = value
        cachedAtMillis = now
        valid = true
        lock.unlock()
        return value
    }

    func invalidate() {
        lock.lock()
        valid = false
        cachedAtMillis = 0
        cachedTimeoutSeconds = nil
        lock.unlock()
    }
}

final class PowerHistoryLogic: @unchecked Sendable {
    static let shared = PowerHistoryLogic()

    func prune(_ events: [PowerHistoryEvent], policy: PowerHistoryPolicy, nowEpochSeconds: Int64) -> [PowerHistoryEvent] {
        let maxEvents = min(max(Int(policy.maxEvents), 1), 10_000)
        let maxAgeDays = min(max(Int(policy.maxAgeDays), 1), 365)
        let now = max(0, nowEpochSeconds)
        let cutoff = now > Int64(maxAgeDays) * 86_400 ? now - Int64(maxAgeDays) * 86_400 : 0
        var seen = Set<String>()
        return events.compactMap { raw -> PowerHistoryEvent? in
            let event = PowerHistoryEvent(
                id: raw.id.trimmingCharacters(in: .whitespacesAndNewlines),
                kind: raw.kind,
                atEpochSeconds: max(0, raw.atEpochSeconds),
                detail: raw.detail.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            guard event.isUsable, event.atEpochSeconds >= cutoff, event.atEpochSeconds <= now,
                  seen.insert(event.id).inserted else { return nil }
            return event
        }.sorted { $0.atEpochSeconds > $1.atEpochSeconds }.prefix(maxEvents).map { $0 }
    }

    func recent(events: [PowerHistoryEvent], nowEpochSeconds: Int64, windowSeconds: Int64 = 86_400) -> [PowerHistoryEvent] {
        let now = max(0, nowEpochSeconds)
        let cutoff = max(0, now - max(0, windowSeconds))
        var seen = Set<String>()
        return events.compactMap { raw -> PowerHistoryEvent? in
            let event = PowerHistoryEvent(
                id: raw.id.trimmingCharacters(in: .whitespacesAndNewlines),
                kind: raw.kind,
                atEpochSeconds: max(0, raw.atEpochSeconds),
                detail: raw.detail.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            guard event.isUsable, event.atEpochSeconds >= cutoff, event.atEpochSeconds <= now,
                  seen.insert(event.id).inserted else { return nil }
            return event
        }.sorted { $0.atEpochSeconds > $1.atEpochSeconds }
    }
}

final class PowerHistoryStore: @unchecked Sendable {
    struct Companion: Sendable {
        func create(path: String) -> PowerHistoryStore { PowerHistoryStore(path: path) }
        func defaultDirectory() -> String {
            URL(fileURLWithPath: CovioCoreDefaults.applicationSupportRoot)
                .appendingPathComponent("Covio/Power").path
        }
        func defaultPath() -> String { defaultDirectory() + "/history.json" }
    }
    static let companion = Companion()
    private let path: String
    private let lock = NSLock()

    init(path: String = Companion().defaultPath()) { self.path = path }

    func load(nowEpochSeconds: Int64) -> PowerHistoryState {
        lock.lock(); defer { lock.unlock() }
        guard let data = FileManager.default.contents(atPath: path),
              let state = try? JSONDecoder().decode(PowerHistoryState.self, from: data) else {
            return PowerHistoryState()
        }
        return normalized(state, now: nowEpochSeconds)
    }

    func append(event: PowerHistoryEvent, nowEpochSeconds: Int64) -> PowerHistoryState? {
        append(event: event, nowEpochSeconds: nowEpochSeconds, policy: PowerHistoryPolicy())
    }

    func append(event: PowerHistoryEvent, nowEpochSeconds: Int64, policy: PowerHistoryPolicy) -> PowerHistoryState? {
        lock.lock(); defer { lock.unlock() }
        guard event.isUsable else { return nil }
        let previous: PowerHistoryState
        if let data = FileManager.default.contents(atPath: path),
           let decoded = try? JSONDecoder().decode(PowerHistoryState.self, from: data) {
            previous = normalized(decoded, now: nowEpochSeconds)
        } else {
            previous = PowerHistoryState()
        }
        let next = normalized(PowerHistoryState(events: [event] + previous.events), now: nowEpochSeconds, policy: policy)
        do {
            try write(next)
            return next
        } catch { return nil }
    }

    func clear() -> Bool {
        lock.lock(); defer { lock.unlock() }
        let target = URL(fileURLWithPath: path)
        let temp = URL(fileURLWithPath: path + ".tmp")
        try? FileManager.default.removeItem(at: target)
        try? FileManager.default.removeItem(at: temp)
        return true
    }

    private func normalized(_ state: PowerHistoryState, now: Int64, policy: PowerHistoryPolicy = PowerHistoryPolicy()) -> PowerHistoryState {
        PowerHistoryState(schemaVersion: 1, events: PowerHistoryLogic.shared.prune(state.events, policy: policy, nowEpochSeconds: now))
    }

    private func write(_ state: PowerHistoryState) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(state)
        try data.write(to: URL(fileURLWithPath: path + ".tmp"), options: .atomic)
        _ = try? FileManager.default.removeItem(at: url)
        try FileManager.default.moveItem(atPath: path + ".tmp", toPath: path)
    }
}

enum HelperInstallScript {
    static let shared = HelperInstallScriptValue()
}

final class HelperInstallScriptValue: @unchecked Sendable {
    func installScript(
        executablePath: String,
        uid: String,
        version: String = CovioReleaseIdentity.APP_VERSION,
        clientRequirement: String? = nil
    ) -> String {
        let directory = shellEscaped(HelperProtocol.helperDirectory)
        let binaryDirectory = shellEscaped(HelperProtocol.helperBinaryPath).replacingOccurrences(of: "/CovioHelper", with: "")
        let binaryPath = shellEscaped(HelperProtocol.helperBinaryPath)
        let temporaryBinary = shellEscaped(HelperProtocol.helperBinaryPath + ".new")
        let allowedUid = shellEscaped(HelperProtocol.allowedUidPath)
        let requirementPath = shellEscaped(HelperProtocol.clientRequirementPath)
        let versionPath = shellEscaped(HelperProtocol.versionPath)
        let appPath = shellEscaped(HelperProtocol.appPathFile)
        let plistPath = shellEscaped(HelperProtocol.plistPath)
        let temporaryPlist = shellEscaped(HelperProtocol.plistPath + ".new")
        var script = "set -e\n"
        script += "install -d -m 0755 '\(directory)'\n"
        script += "chown root:wheel '\(directory)'\nchmod 0755 '\(directory)'\n"
        script += "install -d -m 0755 '\(binaryDirectory)'\n"
        script += "chown root:wheel '\(binaryDirectory)'\nchmod 0755 '\(binaryDirectory)'\n"
        script += "rm -f '\(temporaryBinary)' '\(temporaryPlist)'\n"
        script += "/usr/bin/ditto '\(shellEscaped(executablePath))' '\(temporaryBinary)'\n"
        script += "chown root:wheel '\(temporaryBinary)'\nchmod 0755 '\(temporaryBinary)'\n"
        script += "printf '%s\\n' '\(shellEscaped(uid))' > '\(allowedUid)'\n"
        script += "printf '%s\\n' '\(shellEscaped(version))' > '\(versionPath)'\n"
        script += "printf '%s\\n' '\(shellEscaped(executablePath))' > '\(appPath)'\n"
        script += "chown root:wheel '\(allowedUid)' '\(versionPath)' '\(appPath)'\n"
        script += "chmod 0644 '\(allowedUid)' '\(versionPath)' '\(appPath)'\n"
        if let clientRequirement, !clientRequirement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            script += "printf '%s\\n' '\(shellEscaped(clientRequirement))' > '\(requirementPath)'\n"
            script += "chown root:wheel '\(requirementPath)'\nchmod 0644 '\(requirementPath)'\n"
        } else {
            script += "rm -f '\(requirementPath)'\n"
        }
        script += "cat > '\(temporaryPlist)' <<'PLIST'\n\(plistText(executablePath: HelperProtocol.helperBinaryPath))\nPLIST\n"
        script += "chown root:wheel '\(temporaryPlist)'\nchmod 0644 '\(temporaryPlist)'\n"
        script += "/bin/launchctl bootout system '\(plistPath)' 2>/dev/null || true\n"
        script += "mv '\(temporaryBinary)' '\(binaryPath)'\n"
        script += "mv '\(temporaryPlist)' '\(plistPath)'\n"
        script += "/bin/launchctl bootstrap system '\(plistPath)'\n"
        return script
    }

    func uninstallScript() -> String {
        let plist = shellEscaped(HelperProtocol.plistPath)
        let binaryDirectory = shellEscaped(HelperProtocol.helperDirectory + "/bin")
        let state = shellEscaped(HelperProtocol.chargeLimitStatePath)
        let runtime = shellEscaped(HelperProtocol.chargeLimitRuntimePath)
        let requirement = shellEscaped(HelperProtocol.clientRequirementPath)
        let uid = shellEscaped(HelperProtocol.allowedUidPath)
        let version = shellEscaped(HelperProtocol.versionPath)
        let app = shellEscaped(HelperProtocol.appPathFile)
        let owner = shellEscaped(HelperProtocol.sleepOwnerPath)
        let socket = shellEscaped(HelperProtocol.socketPath)
        let log = shellEscaped(HelperProtocol.logPath)
        return """
        set -e
        if [ -e '\(state)' ] || [ -e '\(runtime)' ]; then
          printf '%s\\n' 'Covio charge limit state is still active. Restore it in Covio before uninstalling the helper.' >&2
          exit 1
        fi
        /usr/bin/pmset -a disablesleep 0 || true
        /bin/launchctl bootout system '\(plist)' 2>/dev/null || true
        rm -f '\(plist)'
        rm -rf '\(binaryDirectory)'
        rm -f '\(uid)' '\(requirement)' '\(version)' '\(app)' '\(owner)' '\(socket)' '\(log)'
        """
    }

    func plistText(executablePath: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(HelperProtocol.launchDaemonLabel)</string>
            <key>ProgramArguments</key>
            <array><string>\(xmlEscaped(executablePath))</string></array>
            <key>MachServices</key>
            <dict><key>\(HelperProtocol.xpcServiceName)</key><true/></dict>
            <key>RunAtLoad</key><true/>
            <key>KeepAlive</key><true/>
            <key>ProcessType</key><string>Interactive</string>
            <key>ThrottleInterval</key><integer>5</integer>
            <key>StandardOutPath</key><string>\(xmlEscaped(HelperProtocol.logPath))</string>
            <key>StandardErrorPath</key><string>\(xmlEscaped(HelperProtocol.logPath))</string>
        </dict>
        </plist>
        """
    }

    func shellEscaped(_ value: String) -> String { value.replacingOccurrences(of: "'", with: "'\\''") }
    func xmlEscaped(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
    func appleScriptEscaped(script: String) -> String {
        script.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "")
    }
}
