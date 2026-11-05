import Foundation

enum UpdaterContract {
    static let defaultMachServiceName = "com.wyz.covio.updater.xpc"

    static var machServiceName: String {
        let override = ProcessInfo.processInfo.environment["COVIO_UPDATER_XPC_SERVICE_NAME"] ?? ""
        return override.isEmpty ? defaultMachServiceName : override
    }
    static let launchDaemonLabel = "com.wyz.covio.updater"
    static let protocolVersion = 1
    static let launcherIdentifier = "com.wyz.covio.updater.launcher"
    static let engineIdentifier = "com.wyz.covio.updater"
}
