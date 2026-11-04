import Foundation
import ServiceManagement

/// Helper 服务生命周期状态。发布身份握手状态仍由 `HelperStatus` 表示。
/// `SMAppService` backing 只保留给旧安装迁移和休眠路径。
enum HelperServiceState: Equatable, Sendable {
    case legacy
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
    case unsupported
    case error(String)

    var allowsXPC: Bool { self == .enabled }
}

protocol SMAppServiceBacking: AnyObject {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

protocol HelperServiceManaging: AnyObject {
    var state: HelperServiceState { get }
    var lastError: String? { get }
    var hasRegisteredService: Bool { get }
    func register() throws
    func unregister() throws
    func openSystemSettings()
}

final class RealSMAppServiceBacking: SMAppServiceBacking {
    private let service = SMAppService.daemon(plistName: HelperProtocol.daemonPlistName)

    var status: SMAppService.Status { service.status }

    func register() throws {
        try service.register()
    }

    func unregister() throws {
        try service.unregister()
    }
}

/// app 对系统 daemon 生命周期的唯一入口。
final class SMAppHelperServiceManager: HelperServiceManaging, @unchecked Sendable {
    static let shared = SMAppHelperServiceManager()

    private let backing: any SMAppServiceBacking
    private let legacyPlistPath: String
    private let legacySocketPath: String
    private let localHelperPath: String
    private let openSettings: () -> Void
    private let errorLock = NSLock()
    private var lastErrorStorage: String?
    private var registrationPendingStorage = false

    init(
        backing: any SMAppServiceBacking = RealSMAppServiceBacking(),
        legacyPlistPath: String = HelperProtocol.plistPath,
        legacySocketPath: String = HelperProtocol.socketPath,
        localHelperPath: String = HelperProtocol.helperBinaryPath,
        openSettings: @escaping () -> Void = {
            SMAppService.openSystemSettingsLoginItems()
        }
    ) {
        self.backing = backing
        self.legacyPlistPath = legacyPlistPath
        self.legacySocketPath = legacySocketPath
        self.localHelperPath = localHelperPath
        self.openSettings = openSettings
    }

    var state: HelperServiceState {
        if let lastError { return .error(lastError) }
        // 新本机安装使用固定 helper 路径和 LaunchDaemon plist。
        // 旧安装只有 plist/socket，没有固定 helper。
        if FileManager.default.fileExists(atPath: legacyPlistPath) {
            return FileManager.default.fileExists(atPath: localHelperPath) ? .enabled : .legacy
        }
        if FileManager.default.fileExists(atPath: legacySocketPath) { return .legacy }
        switch backing.status {
        case .enabled:
            clearRegistrationPending()
            return .enabled
        case .requiresApproval:
            clearRegistrationPending()
            return .requiresApproval
        case .notFound:
            return .notFound
        case .notRegistered:
            if registrationPending { return .requiresApproval }
            return .notRegistered
        @unknown default:
            return .unsupported
        }
    }

    var lastError: String? {
        errorLock.withLock { lastErrorStorage }
    }

    var hasRegisteredService: Bool {
        backing.status == .enabled || backing.status == .requiresApproval
    }

    func register() throws {
        setLastError(nil)
        do {
            try backing.register()
            errorLock.withLock { registrationPendingStorage = true }
        } catch {
            setLastError(error.localizedDescription)
            throw HelperServiceError.registration(error)
        }
    }

    func unregister() throws {
        setLastError(nil)
        do {
            try backing.unregister()
            errorLock.withLock { registrationPendingStorage = false }
        } catch {
            setLastError(error.localizedDescription)
            throw HelperServiceError.unregistration(error)
        }
    }

    func openSystemSettings() {
        openSettings()
    }

    private func setLastError(_ value: String?) {
        errorLock.withLock { lastErrorStorage = value }
    }

    private var registrationPending: Bool {
        errorLock.withLock { registrationPendingStorage }
    }

    private func clearRegistrationPending() {
        errorLock.withLock { registrationPendingStorage = false }
    }
}

enum HelperServiceError: LocalizedError {
    case registration(Error)
    case unregistration(Error)

    var errorDescription: String? {
        switch self {
        case .registration(let error):
            "Cannot register CovioHelper: \(error.localizedDescription)"
        case .unregistration(let error):
            "Cannot unregister CovioHelper: \(error.localizedDescription)"
        }
    }
}
