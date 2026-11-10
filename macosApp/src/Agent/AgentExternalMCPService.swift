import Foundation
import Network
import Observation
import Security

enum AgentExternalTokenError: Error, LocalizedError {
    case randomGenerationFailed
    case keychain(CovioCoreError)

    var errorDescription: String? {
        switch self {
        case .randomGenerationFailed: "Could not generate an external Agent token."
        case .keychain(let error): error.localizedDescription
        }
    }
}

struct AgentExternalTokenStore: Sendable {
    let service: String
    let account: String

    init(
        service: String = "com.wyz.covio.agent.external",
        account: String = "mcp-bearer-token"
    ) {
        self.service = service
        self.account = account
    }

    func loadOrCreate() throws -> String {
        if let existing = try load() { return existing }
        let token = try generateToken()
        try save(token)
        return token
    }

    func rotate() throws -> String {
        let token = try generateToken()
        try save(token)
        return token
    }

    private func load() throws -> String? {
        do {
            guard let token = try CovioAgentTokenKeychain.read(service: service, key: account),
                  !token.isEmpty
            else { return nil }
            return token
        } catch let error as CovioCoreError {
            throw AgentExternalTokenError.keychain(error)
        }
    }

    private func save(_ token: String) throws {
        do {
            try CovioAgentTokenKeychain.write(service: service, key: account, value: token)
        } catch let error as CovioCoreError {
            throw AgentExternalTokenError.keychain(error)
        }
    }

    func delete() throws {
        do {
            try CovioAgentTokenKeychain.delete(service: service, key: account)
        } catch let error as CovioCoreError {
            throw AgentExternalTokenError.keychain(error)
        }
    }

    private func generateToken() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw AgentExternalTokenError.randomGenerationFailed
        }
        return Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

struct AgentExternalServicePreferences: Sendable {
    static let enabledKey = "covio.agent.external.enabled"
    static let standard = AgentExternalServicePreferences()
    static let disabled = AgentExternalServicePreferences(overrideEnabled: false)

    private let suiteName: String?
    private let overrideEnabled: Bool?

    init(suiteName: String? = nil, overrideEnabled: Bool? = nil) {
        self.suiteName = suiteName
        self.overrideEnabled = overrideEnabled
    }

    func isEnabled() -> Bool {
        overrideEnabled ?? defaults?.bool(forKey: Self.enabledKey) ?? false
    }

    func setEnabled(_ enabled: Bool) {
        guard overrideEnabled == nil else { return }
        defaults?.set(enabled, forKey: Self.enabledKey)
    }

    private var defaults: UserDefaults? {
        suiteName.map(UserDefaults.init(suiteName:)) ?? .standard
    }
}

@MainActor
final class AgentExternalPendingBridge {
    var onPendingActionChanged: (@MainActor () async -> Void)?

    func notify() async {
        await onPendingActionChanged?()
    }
}

@MainActor
@Observable
final class AgentExternalMCPService {
    private struct ConnectionState {
        let connection: NWConnection
        var buffer = Data()
    }

    private let gateway: AgentServiceGateway
    private let auditStore: any AgentExternalAuditStoring
    private let sessions: AgentMCPSessionStore
    private let httpHandler: AgentMCPHTTPHandler
    private let bridge: AgentExternalPendingBridge
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: ConnectionState] = [:]
    private var cleanupTimer: Timer?

    let token: String
    private(set) var port: UInt16?
    private(set) var lastError: String?

    init(
        gateway: AgentServiceGateway,
        auditStore: any AgentExternalAuditStoring,
        token: String,
        sessionStore: AgentMCPSessionStore = AgentMCPSessionStore()
    ) {
        self.gateway = gateway
        self.auditStore = auditStore
        self.token = token
        self.sessions = sessionStore
        let bridge = AgentExternalPendingBridge()
        self.bridge = bridge
        let router = AgentMCPRouter(gateway: gateway)
        self.httpHandler = AgentMCPHTTPHandler(
            router: router,
            gateway: gateway,
            sessions: sessionStore,
            bearerToken: token,
            onPendingActionChanged: {
                await bridge.notify()
            }
        )
    }

    var endpointURL: URL? {
        guard let port else { return nil }
        return URL(string: "http://127.0.0.1:\(port)/mcp")
    }

    func setOnPendingActionChanged(_ action: (@MainActor () async -> Void)?) {
        bridge.onPendingActionChanged = action
    }

    nonisolated static func listenerParameters() -> NWParameters {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        return parameters
    }

    func start() {
        guard listener == nil else { return }
        lastError = nil
        let parameters = Self.listenerParameters()
        do {
            let listener = try NWListener(using: parameters)
            self.listener = listener
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    self?.handleListenerState(state)
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.accept(connection)
                }
            }
            listener.start(queue: .main)
            cleanupTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
                Task { @MainActor [weak self] in
                    await self?.expireSessions()
                }
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func stop() {
        cleanupTimer?.invalidate()
        cleanupTimer = nil
        listener?.cancel()
        listener = nil
        port = nil
        for state in connections.values {
            state.connection.cancel()
        }
        connections.removeAll()
        Task {
            let ids = await sessions.removeAll()
            for id in ids {
                await gateway.cancelPending(source: .external(id))
            }
        }
    }

    func recordExternalAudit(_ audit: AgentToolAudit) async {
        guard let sessionID = audit.source.externalSessionID else { return }
        let record = AgentExternalAuditRecord(
            id: audit.id,
            sessionID: sessionID,
            toolName: audit.toolName,
            risk: audit.risk,
            status: audit.status,
            detail: audit.detail,
            errorCode: audit.errorCode,
            durationMilliseconds: audit.durationMilliseconds,
            createdAtEpochMilliseconds: audit.createdAtEpochMilliseconds
        )
        try? await auditStore.recordExternalAudit(record)
    }

    private func expireSessions() async {
        let ids = await sessions.expireIdle()
        for id in ids {
            await gateway.cancelPending(source: .external(id))
        }
    }

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            port = listener?.port?.rawValue
            lastError = nil
        case .failed(let error):
            lastError = error.localizedDescription
            stop()
        case .cancelled:
            port = nil
        default:
            break
        }
    }

    private func accept(_ connection: NWConnection) {
        guard listener != nil else {
            connection.cancel()
            return
        }
        let key = ObjectIdentifier(connection)
        connections[key] = ConnectionState(connection: connection)
        connection.stateUpdateHandler = { [weak self] state in
            if case .failed = state {
                Task { @MainActor in self?.close(key) }
            }
        }
        connection.start(queue: .main)
        receive(key)
    }

    private func receive(_ key: ObjectIdentifier) {
        guard var state = connections[key] else { return }
        state.connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 64 * 1_024
        ) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self, var current = self.connections[key] else { return }
                if let data, !data.isEmpty {
                    current.buffer.append(data)
                    self.connections[key] = current
                }
                if error != nil {
                    self.close(key)
                    return
                }
                switch AgentHTTPRequestParser.parse(current.buffer) {
                case .request(let request):
                    await self.respond(to: request, connection: current.connection, key: key)
                case .failure(let status, let message):
                    let response = AgentHTTPResponse(
                        status: status,
                        headers: ["content-type": "text/plain; charset=utf-8"],
                        body: Data(message.utf8)
                    )
                    self.send(response, on: current.connection, closeAfter: true, key: key)
                case .incomplete:
                    if isComplete {
                        self.close(key)
                    } else {
                        self.receive(key)
                    }
                }
            }
        }
    }

    private func respond(
        to request: AgentHTTPRequest,
        connection: NWConnection,
        key: ObjectIdentifier
    ) async {
        guard let port else {
            let response = AgentHTTPResponse(status: 503)
            send(response, on: connection, closeAfter: true, key: key)
            return
        }
        let response = await httpHandler.handle(request, localPort: port)
        send(response, on: connection, closeAfter: true, key: key)
    }

    private func send(
        _ response: AgentHTTPResponse,
        on connection: NWConnection,
        closeAfter: Bool,
        key: ObjectIdentifier
    ) {
        var headers = response.headers
        headers["content-length"] = "\(response.body.count)"
        headers["connection"] = "close"
        var text = "HTTP/1.1 \(response.status) \(Self.reason(for: response.status))\r\n"
        for (name, value) in headers.sorted(by: { $0.key < $1.key }) {
            text += "\(name): \(value)\r\n"
        }
        text += "\r\n"
        var data = Data(text.utf8)
        data.append(response.body)
        connection.send(content: data, completion: .contentProcessed { [weak self] _ in
            Task { @MainActor in
                if closeAfter { self?.close(key) }
            }
        })
    }

    private func close(_ key: ObjectIdentifier) {
        guard let state = connections.removeValue(forKey: key) else { return }
        state.connection.cancel()
    }

    private static func reason(for status: Int) -> String {
        switch status {
        case 200: "OK"
        case 202: "Accepted"
        case 204: "No Content"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 403: "Forbidden"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        case 406: "Not Acceptable"
        case 413: "Content Too Large"
        case 415: "Unsupported Media Type"
        case 429: "Too Many Requests"
        case 431: "Request Header Fields Too Large"
        case 503: "Service Unavailable"
        default: "Error"
        }
    }
}
