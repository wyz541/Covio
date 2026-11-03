import Foundation

final class CovioUpdaterClient {
    private let paths: UpdaterPaths
    private var connection: NSXPCConnection?

    init(paths: UpdaterPaths = UpdaterPaths()) {
        self.paths = paths
    }

    func getStatus(completion: @escaping (Result<UpdaterStatus, Error>) -> Void) {
        guard let proxy = proxy(error: completion) else { return }
        proxy.getStatus { data in
            completion(Self.decode(UpdaterStatus.self, from: data))
        }
    }

    func checkNow(
        completion: @escaping (Result<UpdaterOperationResult, Error>) -> Void
    ) {
        guard let proxy = proxy(error: completion) else { return }
        proxy.checkNow { data in
            completion(Self.decode(UpdaterOperationResult.self, from: data))
        }
    }

    func installAvailable(
        completion: @escaping (Result<UpdaterOperationResult, Error>) -> Void
    ) {
        guard let proxy = proxy(error: completion) else { return }
        proxy.installAvailable { data in
            completion(Self.decode(UpdaterOperationResult.self, from: data))
        }
    }

    func setAutomaticUpdates(
        _ enabled: Bool,
        completion: @escaping (Result<UpdaterOperationResult, Error>) -> Void
    ) {
        guard let proxy = proxy(error: completion) else { return }
        proxy.setAutomaticUpdates(enabled) { data in
            completion(Self.decode(UpdaterOperationResult.self, from: data))
        }
    }

    func restartApp(
        completion: @escaping (Result<UpdaterOperationResult, Error>) -> Void
    ) {
        guard let proxy = proxy(error: completion) else { return }
        proxy.restartApp { data in
            completion(Self.decode(UpdaterOperationResult.self, from: data))
        }
    }

    func invalidate() {
        connection?.invalidate()
        connection = nil
    }

    private func proxy<T>(
        error completion: @escaping (Result<T, Error>) -> Void
    ) -> CovioUpdaterXPCProtocol? {
        guard let connection = connection ?? makeConnection(),
              let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
                  completion(.failure(error))
              }) as? CovioUpdaterXPCProtocol
        else {
            completion(.failure(CovioUpdaterClientError.unavailable))
            return nil
        }
        return proxy
    }

    private func makeConnection() -> NSXPCConnection? {
        guard let requirement = try? String(
            contentsOf: paths.updaterRequirement,
            encoding: .utf8
        ) else {
            return nil
        }
        let trimmed = requirement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let connection = NSXPCConnection(
            machServiceName: UpdaterContract.machServiceName,
            options: .privileged
        )
        connection.remoteObjectInterface = NSXPCInterface(
            with: CovioUpdaterXPCProtocol.self
        )
        connection.setCodeSigningRequirement(trimmed)
        connection.interruptionHandler = { [weak self, weak connection] in
            guard connection === self?.connection else { return }
            self?.connection = nil
        }
        connection.invalidationHandler = { [weak self, weak connection] in
            guard connection === self?.connection else { return }
            self?.connection = nil
        }
        connection.resume()
        self.connection = connection
        return connection
    }

    private static func decode<T: Decodable>(
        _ type: T.Type,
        from data: Data
    ) -> Result<T, Error> {
        do {
            return .success(try JSONDecoder().decode(type, from: data))
        } catch {
            return .failure(CovioUpdaterClientError.invalidResponse)
        }
    }
}

enum CovioUpdaterClientError: Error, Equatable, LocalizedError {
    case unavailable
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .unavailable: "CovioUpdater is not available"
        case .invalidResponse: "CovioUpdater returned an invalid response"
        }
    }
}
