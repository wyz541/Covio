import Foundation

/// 通过 launchd Mach service 执行一次同步 RPC。
final class HelperXPCClient: @unchecked Sendable {
    private let serviceName: String
    private let lock = NSLock()
    private var connection: NSXPCConnection?

    init(serviceName: String) {
        self.serviceName = serviceName
    }

    deinit {
        invalidate()
    }

    func transact(_ requestLine: String, timeout: TimeInterval) -> HelperReply? {
        guard let proxy = remoteProxy() as? CovioHelperXPCProtocol else { return nil }
        let semaphore = DispatchSemaphore(value: 0)
        let result = OneShotXPCReply()
        proxy.transact(requestLine) { response in
            if result.complete(response) {
                semaphore.signal()
            }
        }
        guard semaphore.wait(timeout: .now() + timeout) == .success,
              let line = result.value
        else {
            invalidate()
            return nil
        }
        return HelperWire.shared.decodeReply(line: line)
    }

    private func remoteProxy() -> Any? {
        lock.lock()
        defer { lock.unlock() }
        if connection == nil {
            let newConnection = NSXPCConnection(machServiceName: serviceName, options: [])
            newConnection.remoteObjectInterface = NSXPCInterface(
                with: CovioHelperXPCProtocol.self
            )
            newConnection.invalidationHandler = { [weak self] in
                self?.invalidate()
            }
            newConnection.resume()
            connection = newConnection
        }
        return connection?.remoteObjectProxyWithErrorHandler { [weak self] _ in
            self?.invalidate()
        }
    }

    private func invalidate() {
        lock.lock()
        let current = connection
        connection = nil
        lock.unlock()
        current?.invalidate()
    }
}

private final class OneShotXPCReply: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false
    private var storedValue: String?

    var value: String? {
        lock.withLock { storedValue }
    }

    func complete(_ value: String?) -> Bool {
        lock.withLock {
            guard !completed else { return false }
            completed = true
            storedValue = value
            return true
        }
    }
}
