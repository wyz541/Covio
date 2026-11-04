import Foundation

/// 特权 helper 的安装契约：路径、命令行参数与命令白名单。
///
/// 权威在 Rust-core helper contract。这里只读兼容常量，不另抄一份业务规则。
///
/// 协议本身（编解码、校验、回复构造）在 Rust core。
/// 调用点直接用 `HelperWire.shared`，见 `HelperServer` 与 `HelperClient`。
///
/// `HelperContractMirrorTests` 会检查 Swift 镜像与发布身份一致。
enum HelperProtocol {
    static var protocolVersion: String { CovioHelperContract.HELPER_PROTOCOL_VERSION }

    /// 以 helper 身份启动的命令行参数。
    static var helperArgument: String { CovioHelperContract.HELPER_ARGUMENT }
    static var helperExecutableName: String { CovioHelperContract.HELPER_EXECUTABLE_NAME }
    static var helperExecutableBundlePath: String { CovioHelperContract.HELPER_EXECUTABLE_BUNDLE_PATH }
    static var helperBinaryPath: String { CovioHelperContract.HELPER_BINARY_PATH }
    static var daemonPlistName: String { CovioHelperContract.HELPER_DAEMON_PLIST_NAME }
    static var xpcServiceName: String { CovioHelperContract.HELPER_XPC_SERVICE_NAME }

    static var socketPath: String { CovioHelperContract.HELPER_SOCKET_PATH }
    static var helperDirectory: String { CovioHelperContract.HELPER_DIRECTORY }
    static var chargeLimitStatePath: String { CovioHelperContract.HELPER_CHARGE_LIMIT_STATE_PATH }
    static var chargeLimitRuntimePath: String { CovioHelperContract.HELPER_CHARGE_LIMIT_RUNTIME_PATH }
    static var allowedUidPath: String { CovioHelperContract.HELPER_ALLOWED_UID_PATH }
    static var clientRequirementPath: String { CovioHelperContract.HELPER_CLIENT_REQUIREMENT_PATH }
    static var versionPath: String { CovioHelperContract.HELPER_VERSION_PATH }
    static var appPathFile: String { CovioHelperContract.HELPER_APP_PATH_FILE }
    static var sleepOwnerPath: String { CovioHelperContract.HELPER_SLEEP_OWNER_PATH }
    static var sleepOwnerValue: String { CovioHelperContract.HELPER_SLEEP_OWNER_VALUE }
    static var leaseDurationSeconds: Int64 { CovioHelperContract.HELPER_LEASE_DURATION_SECONDS }
    static var leaseRenewSeconds: Int64 { CovioHelperContract.HELPER_LEASE_RENEW_SECONDS }
    static var logPath: String { CovioHelperContract.HELPER_LOG_PATH }
    static var plistPath: String { CovioHelperContract.HELPER_PLIST_PATH }
    static var launchDaemonLabel: String { CovioHelperContract.HELPER_LAUNCH_DAEMON_LABEL }

    static var allowedCommands: Set<String> { CovioHelperContract.HELPER_ALLOWED_COMMANDS }

    /// 允许的休眠模式。镜像 Rust-core 白名单，避免两处规则漂移。
    static var supportedHibernateModes: Set<Int> {
        Set(CovioRuntimeConstants.SUPPORTED_HIBERNATE_MODES.map { Int($0.intValue) })
    }
}
