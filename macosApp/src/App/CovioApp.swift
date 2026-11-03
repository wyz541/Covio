import SwiftUI
import kmpDomain

/// 应用入口。
///
/// 三条维护命令在 SwiftUI 起来之前分流，它们都不需要界面：
/// - `--helper`：特权 helper 本体，由 LaunchDaemon 以 root 启动。
/// - `--install-helper` / `--uninstall-helper`：迁移脚本用它走真实的安装路径，
///   而不是在脚本里重抄一遍安装步骤。
/// - `--helper-version`：问 helper 自己的版本号，迁移脚本用它判断是否 OUTDATED。
/// - Debug 构建另有充电命令，用来验证 helper 的原始回复。
///
/// Hub 是 NSPanel，由 `AppDelegate` 与 `NotchShellController` 管理。
/// 这里不提供任何窗口。`Settings` 场景是让 `App` 协议有一个非空 `Scene` 的最小写法。
@main
enum CovioMain {
    static func main() async {
        let arguments = CommandLine.arguments

        if arguments.contains(HelperProtocol.helperArgument) {
            exit(HelperServer.run())
        }
        if arguments.contains(MaintenanceCommand.installHelper) {
            exit(HelperInstaller.install(executablePath: executablePath, logger: log) ? 0 : 1)
        }
        if arguments.contains(MaintenanceCommand.uninstallHelper) {
            exit(HelperInstaller.uninstall(logger: log) ? 0 : 1)
        }
        if arguments.contains(MaintenanceCommand.helperVersion) {
            exit(printHelperVersion())
        }
        if arguments.contains(MaintenanceCommand.helperProtocolVersion) {
            exit(printHelperProtocolVersion())
        }
        if arguments.contains(MaintenanceCommand.printReleaseIdentity) {
            exit(printReleaseIdentity())
        }
        if arguments.contains(MaintenanceCommand.prepareInstallTransaction) {
            exit(prepareInstallTransaction())
        }
        if arguments.contains(MaintenanceCommand.installLegacyHelperAsRoot) {
            exit(installLegacyHelperAsRoot(arguments))
        }
        if arguments.contains(MaintenanceCommand.registerInstallTransactionHelper) {
            exit(registerInstallTransactionHelper())
        }
        if arguments.contains(MaintenanceCommand.installUpdaterAsRoot) {
            exit(UpdaterInstaller.installForInstallTransactionAsRoot(logger: log) ? 0 : 1)
        }
        if arguments.contains(MaintenanceCommand.installUpdaterEngineAsRoot) {
            exit(UpdaterInstaller.installForAutomaticUpdateAsRoot(logger: log) ? 0 : 1)
        }
        if arguments.contains(MaintenanceCommand.verifyInstallTransaction) {
            exit(verifyInstallTransaction())
        }
#if DEBUG
        if handleChargeLimitMaintenance(arguments) {
            return
        }
        if handleFanControlMaintenance(arguments) {
            return
        }
#endif
        if arguments.contains(MaintenanceCommand.verifyModelDownload) {
            guard let path = ProcessInfo.processInfo.environment["COVIO_MODEL_DOWNLOAD_ACCEPTANCE_PATH"],
                  !path.isEmpty
            else {
                log("Set COVIO_MODEL_DOWNLOAD_ACCEPTANCE_PATH to a result file.")
                exit(1)
            }
            exit(
                await ModelDownloadAcceptanceVerifier.run(
                    outputURL: URL(fileURLWithPath: path)
                )
            )
        }
        CovioApp.main()
    }

    /// 当前可执行文件的绝对路径。它会写进 LaunchDaemon plist。
    private static var executablePath: String {
        Bundle.main.executablePath ?? CommandLine.arguments.first ?? ""
    }

    /// 诊断信息写 stderr，stdout 留给 `--helper-version` 的结果。
    private static func log(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }

    /// 打印 helper 自己报告的应用版本号。
    ///
    /// 退出码：0 成功，1 连不上 helper。
    /// 版本是否等于本版由调用方比较，脚本里比更清楚。
    private static func printHelperVersion() -> Int32 {
        guard let version = HelperClient().version() else {
            log("Helper did not report a version")
            return 1
        }
        print(version)
        return 0
    }

    /// 打印 helper 自己报告的协议版本号。
    private static func printHelperProtocolVersion() -> Int32 {
        guard let protocolVersion = HelperClient().versionInfo()?.protocolVersion else {
            log("Helper did not report a protocol version")
            return 1
        }
        print(protocolVersion)
        return 0
    }

    private static func printReleaseIdentity() -> Int32 {
        guard let identity = HelperReleaseIdentitySource.expectedAppIdentity else {
            log("The bundled release identity is unavailable")
            return 1
        }
        return printJSON(identityObject(identity)) ? 0 : 1
    }

    private static func prepareInstallTransaction() -> Int32 {
        let client = HelperClient()
        guard HelperReleaseInspector.inspect(client: client) == .match else {
            log("The running helper does not match the installed app")
            return 1
        }
        guard client.prepareInstallTransaction() else {
            log("The helper did not restore privileged state for the install transaction")
            return 1
        }
        return 0
    }

    private static func registerInstallTransactionHelper() -> Int32 {
        switch HelperInstaller.registerForInstallTransaction(logger: log) {
        case .enabled, .requiresApproval:
            return 0
        case .failed(let message):
            log(message)
            return 1
        }
    }

    private static func installLegacyHelperAsRoot(_ arguments: [String]) -> Int32 {
        guard getuid() == 0 else {
            log("The Legacy helper install command requires root")
            return 1
        }
        guard let index = arguments.firstIndex(of: MaintenanceCommand.installLegacyHelperAsRoot),
              arguments.indices.contains(index + 1),
              !arguments[index + 1].isEmpty
        else {
            log("The Legacy helper install command requires a uid")
            return 1
        }
        let uid = arguments[index + 1]
        return HelperInstaller.installForInstallTransactionAsRoot(uid: uid, logger: log) ? 0 : 1
    }

    private static func verifyInstallTransaction() -> Int32 {
        let client = HelperClient()
        let status = HelperReleaseInspector.inspect(client: client)
        var value: [String: String] = ["status": statusName(status)]
        if let identity = HelperReleaseIdentitySource.expectedAppIdentity {
            value.merge(identityObject(identity)) { _, new in new }
        }
        guard printJSON(value) else { return 1 }
        return status == .match ? 0 : 1
    }

    private static func identityObject(_ identity: HelperReleaseIdentity) -> [String: String] {
        [
            "releaseId": identity.releaseId,
            "clientVersion": identity.clientVersion,
            "productVersion": identity.productVersion,
            "buildNumber": identity.buildNumber,
            "gitCommit": identity.gitCommit,
            "protocolVersion": identity.protocolVersion,
            "helperSHA256": identity.helperSHA256,
            "channel": identity.channel,
        ]
    }

    private static func statusName(_ status: HelperStatus) -> String {
        switch status {
        case .match: "MATCH"
        case .missing: "MISSING"
        case .outdated: "OUTDATED"
        case .identityMismatch: "IDENTITY_MISMATCH"
        case .untrusted: "UNTRUSTED"
        default: "UNKNOWN"
        }
    }

    private static func printJSON(_ value: [String: String]) -> Bool {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8)
        else {
            log("Cannot encode the release identity")
            return false
        }
        print(text)
        return true
    }

#if DEBUG
    /// Debug 构建的硬件验证入口。命令仍由 helper 校验客户端签名和参数范围。
    private static func handleChargeLimitMaintenance(_ arguments: [String]) -> Bool {
        if arguments.contains(DebugChargeCommand.helperStatus) {
            exit(printHelperStatus())
        }
        if arguments.contains(DebugChargeCommand.status) {
            exit(printChargeLimitReply(
                command: HelperWire.shared.COMMAND_CHARGE_LIMIT_STATUS,
                timeoutMillis: 3_000
            ))
        }
        if arguments.contains(DebugChargeCommand.restore) {
            exit(printChargeLimitReply(
                command: HelperWire.shared.COMMAND_CHARGE_LIMIT_RESTORE,
                timeoutMillis: 20_000
            ))
        }
        if let index = arguments.firstIndex(of: DebugChargeCommand.configure) {
            guard arguments.indices.contains(index + 1),
                  let percent = Int(arguments[index + 1])
            else {
                log("Charge limit percent is missing or invalid")
                exit(1)
            }
            let activeDischarge = arguments.indices.contains(index + 2)
                ? arguments[index + 2].lowercased()
                : "false"
            guard activeDischarge == "true" || activeDischarge == "false" else {
                log("Active discharge value must be true or false")
                exit(1)
            }
            exit(printChargeLimitReply(
                command: HelperWire.shared.COMMAND_CHARGE_LIMIT_CONFIGURE,
                payload: [
                    "percent": String(percent),
                    "activeDischarge": activeDischarge,
                ],
                timeoutMillis: 20_000,
                requiresMatchedHelper: true
            ))
        }
        return false
    }

    /// Debug 构建的风扇维护入口。配置写入要求完整身份握手；恢复始终允许。
    private static func handleFanControlMaintenance(_ arguments: [String]) -> Bool {
        if arguments.contains(DebugFanCommand.status) {
            let status = HelperClient().fanControlStatus()
            exit(printFanControlStatus(status))
        }
        if arguments.contains(DebugFanCommand.configureMinimum) {
            let client = HelperClient()
            let status = HelperReleaseInspector.inspect(client: client)
            guard status == .match else {
                log("Privileged write rejected by the helper release handshake: \(status)")
                exit(1)
            }
            let result = client.configureFanControl(
                MonitorFanConfiguration(enabled: true, mode: .manual)
            )
            let value: [String: String] = [
                "ok": result.ok ? "true" : "false",
                "message": result.message ?? "",
                "status": result.status.map(fanControlStatusText) ?? "unknown",
            ]
            guard printJSON(value) else { exit(1) }
            exit(result.ok ? 0 : 1)
        }
        if arguments.contains(DebugFanCommand.restore) {
            let result = HelperClient().restoreFanControl()
            let value: [String: String] = [
                "ok": result.ok ? "true" : "false",
                "message": result.message ?? "",
                "status": result.status.map(fanControlStatusText) ?? "unknown",
            ]
            guard printJSON(value) else { exit(1) }
            exit(result.ok ? 0 : 1)
        }
        return false
    }

    private static func printFanControlStatus(_ status: FanControlHelperStatus?) -> Int32 {
        guard let status else {
            log("Helper did not report fan control status")
            return 1
        }
        guard printJSON(["status": fanControlStatusText(status)]) else { return 1 }
        return 0
    }

    private static func fanControlStatusText(_ status: FanControlHelperStatus) -> String {
        var parts: [String] = [
            "active=\(status.active)",
            "mode=\(status.mode)",
            "leaseRemainingSeconds=\(status.leaseRemainingSeconds)",
        ]
        if let controlTemperature = status.controlTemperature {
            parts.append("controlTemperature=\(controlTemperature)")
        } else {
            parts.append("controlTemperature=nil")
        }
        parts.append("error=\(status.error ?? "")")
        return parts.joined(separator: ",")
    }

    private static func printChargeLimitReply(
        command: String,
        payload: [String: String] = [:],
        timeoutMillis: Int? = nil,
        requiresMatchedHelper: Bool = false
    ) -> Int32 {
        let client = HelperClient()
        if requiresMatchedHelper {
            let status = HelperReleaseInspector.inspect(client: client)
            guard status == .match else {
                log("Privileged write rejected by the helper release handshake: \(status)")
                return 1
            }
        }
        guard let reply = client.request(
            command: command,
            payload: payload,
            timeoutMillis: timeoutMillis
        ) else {
            log("Helper did not reply to \(command)")
            return 1
        }
        print(HelperWire.shared.encodeReply(reply: reply))
        return reply.ok ? 0 : 1
    }

    private static func printHelperStatus() -> Int32 {
        let exists = FileManager.default.fileExists(atPath: HelperProtocol.socketPath)
        let client = HelperClient()
        let probe = client.versionProbe()
        let identity = probe.flatMap { HelperReleaseHandshake.shared.parse(result: $0.result) }
        let ops = MacPrivilegedOps(
            logger: FileAppLogger(),
            executablePath: executablePath,
            client: client
        )
        let status = ops.status()
        print("socket=\(HelperProtocol.socketPath)")
        print("exists=\(exists)")
        print("version=\(identity?.clientVersion ?? probe?.result["version"] ?? "nil")")
        print("productVersion=\(identity?.productVersion ?? "nil")")
        print("buildNumber=\(identity?.buildNumber ?? "nil")")
        print("gitCommit=\(identity?.gitCommit ?? "nil")")
        print("releaseId=\(identity?.releaseId ?? "nil")")
        print("protocol=\(identity?.protocolVersion ?? probe?.result["protocolVersion"] ?? "nil")")
        print("helperSHA256=\(identity?.helperSHA256 ?? "nil")")
        print("opsStatus=\(status)")
        return status == .match ? 0 : 1
    }
#endif
}

/// 迁移与排查用的命令行开关。只影响启动分流，不影响正常运行。
enum MaintenanceCommand {
    /// 安装特权 helper。会弹出管理员授权对话框。
    static let installHelper = "--install-helper"
    /// 卸载特权 helper。会弹出管理员授权对话框。
    static let uninstallHelper = "--uninstall-helper"
    /// 打印 helper 报告的应用版本号。
    static let helperVersion = "--helper-version"
    /// 打印 helper 报告的协议版本号。
    static let helperProtocolVersion = "--helper-protocol-version"
    /// 打印 app bundle 中 helper 的完整发布身份。
    static let printReleaseIdentity = "--print-release-identity"
    /// 升级前恢复风扇、充电上限和合盖租约。
    static let prepareInstallTransaction = "--prepare-install-transaction"
    /// PKG postinstall 以 root 安装固定路径 Legacy helper。
    static let installLegacyHelperAsRoot = "--install-legacy-helper-as-root"
    /// 事务交换 bundle 后替换 SMAppService 注册。
    static let registerInstallTransactionHelper = "--register-install-transaction-helper"
    /// PKG 事务以 root 安装独立 updater LauncherDaemon、engine 和指针。
    static let installUpdaterAsRoot = "--install-updater-as-root"
    /// 自动更新事务只替换 versioned updater engine 和指针。
    static let installUpdaterEngineAsRoot = "--install-updater-engine-as-root"
    /// 验证新 helper 与当前 app 的发布身份完全一致。
    static let verifyInstallTransaction = "--verify-install-transaction"
    /// 从真实模型源下载、暂停、重启恢复并验证损坏拒绝。
    static let verifyModelDownload = "--verify-model-download"
}

#if DEBUG
/// 只用于真机验证的调试命令。发布构建不包含这些入口。
enum DebugFanCommand {
    static let status = "--fan-control-status"
    static let configureMinimum = "--fan-control-configure-minimum"
    static let restore = "--fan-control-restore"
}

enum DebugChargeCommand {
    static let helperStatus = "--helper-status"
    static let status = "--charge-limit-status"
    static let configure = "--charge-limit-configure"
    static let restore = "--charge-limit-restore"
}
#endif

struct CovioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
