import Foundation

/// `CovioHelper` 命令行的运行入口。只启动 XPC listener，不暴露 legacy socket。
enum CovioHelperRuntime {
    static func run() -> Int32 {
        _ = HelperReleaseIdentitySource.daemonIdentity
        signal(SIGPIPE, SIG_IGN)

        let log = HelperLog()
        guard let clientRequirement = HelperSignature.mainAppRequirement() else {
            log.error("Cannot determine the Covio app code-signing requirement")
            return 1
        }

        let fanControlRuntime = FanControlRuntime(log: log)
        defer { fanControlRuntime.shutdown() }
        let leaseCoordinator = HelperLeaseCoordinator(log: log)
        HelperServer.resumeSharedChargeLimitRuntime(log: log)
        leaseCoordinator.restoreStaleState()

        let service = CovioHelperXPCService(
            log: log,
            leaseCoordinator: leaseCoordinator,
            fanControlRuntime: fanControlRuntime
        )
        let delegate = CovioHelperXPCDelegate(service: service)
        let listener = NSXPCListener(machServiceName: HelperProtocol.xpcServiceName)
        listener.delegate = delegate
        listener.setConnectionCodeSigningRequirement(clientRequirement)
        listener.resume()
        log.info("CovioHelper XPC listener started")

        var terminationSources: [DispatchSourceSignal] = []
        for number in [SIGTERM, SIGINT] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
            source.setEventHandler {
                HelperServer.prepareSharedChargeLimitForExit()
                fanControlRuntime.shutdown()
                exit(0)
            }
            source.resume()
            terminationSources.append(source)
        }

        while true {
            RunLoop.current.run(until: Date().addingTimeInterval(60))
        }
    }
}

private final class CovioHelperXPCDelegate: NSObject, NSXPCListenerDelegate {
    private let service: CovioHelperXPCService

    init(service: CovioHelperXPCService) {
        self.service = service
    }

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: CovioHelperXPCProtocol.self)
        connection.exportedObject = service
        connection.resume()
        return true
    }
}

private final class CovioHelperXPCService: NSObject, CovioHelperXPCProtocol {
    private let log: HelperLog
    private let leaseCoordinator: HelperLeaseCoordinator
    private let fanControlRuntime: FanControlRuntime

    init(
        log: HelperLog,
        leaseCoordinator: HelperLeaseCoordinator,
        fanControlRuntime: FanControlRuntime
    ) {
        self.log = log
        self.leaseCoordinator = leaseCoordinator
        self.fanControlRuntime = fanControlRuntime
    }

    func transact(_ requestLine: String, withReply reply: @escaping (String?) -> Void) {
        guard requestLine.utf8.count <= Int(HelperWire.shared.MAX_REQUEST_BYTES) else {
            let failure = HelperWire.shared.failure(
                requestId: "",
                message: "Request exceeds the size limit"
            )
            reply(HelperWire.shared.encodeReply(reply: failure))
            return
        }
        let response = HelperServer.process(
            line: requestLine,
            authorizePrivilegedCommand: { true },
            log: log,
            leaseCoordinator: leaseCoordinator,
            fanControlRuntime: fanControlRuntime
        )
        reply(HelperWire.shared.encodeReply(reply: response))
    }
}
