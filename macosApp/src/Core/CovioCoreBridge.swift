import CovioFFI
import Foundation

struct CovioCoreError: Error, LocalizedError, Equatable, Sendable {
    let code: UInt32
    let message: String

    var errorDescription: String? { message }
}

/// Thread-safe owner of one Rust application-service handle.
final class CovioCoreClient: @unchecked Sendable {
    private let handle: OpaquePointer
    private let lock = NSLock()

    init(
        configPath: String,
        shelfPath: String,
        clipboardPath: String,
        workspacePath: String
    ) throws {
        var error = Self.emptyError()
        let config = Array(configPath.utf8)
        let shelf = Array(shelfPath.utf8)
        let clipboard = Array(clipboardPath.utf8)
        let workspace = Array(workspacePath.utf8)
        let created = config.withUnsafeBufferPointer { configBuffer in
            shelf.withUnsafeBufferPointer { shelfBuffer in
                clipboard.withUnsafeBufferPointer { clipboardBuffer in
                    workspace.withUnsafeBufferPointer { workspaceBuffer in
                        covio_app_create_with_paths(
                            configBuffer.baseAddress,
                            configBuffer.count,
                            shelfBuffer.baseAddress,
                            shelfBuffer.count,
                            clipboardBuffer.baseAddress,
                            clipboardBuffer.count,
                            workspaceBuffer.baseAddress,
                            workspaceBuffer.count,
                            &error
                        )
                    }
                }
            }
        }
        guard let created else {
            throw Self.error(error)
        }
        handle = created
    }

    init(applicationSupportRoot: String) throws {
        var error = Self.emptyError()
        let root = Array(applicationSupportRoot.utf8)
        let created = root.withUnsafeBufferPointer { buffer in
            covio_app_create(buffer.baseAddress, buffer.count, &error)
        }
        guard let created else {
            throw Self.error(error)
        }
        handle = created
    }

    deinit {
        covio_app_release(handle)
    }

    func call(
        _ command: String,
        payload: [String: Any] = [:],
        nowEpochSeconds: Int64 = Int64(Date().timeIntervalSince1970)
    ) throws -> Any {
        let commandBytes = Array(command.utf8)
        let payloadData = try JSONSerialization.data(withJSONObject: payload)
        var output = Self.emptyBytes()
        var error = Self.emptyError()

        lock.lock()
        defer { lock.unlock() }
        let status = commandBytes.withUnsafeBufferPointer { commandBuffer in
            payloadData.withUnsafeBytes { payloadBuffer in
                covio_app_call(
                    handle,
                    commandBuffer.baseAddress,
                    commandBuffer.count,
                    payloadBuffer.bindMemory(to: UInt8.self).baseAddress,
                    payloadData.count,
                    nowEpochSeconds,
                    &output,
                    &error
                )
            }
        }
        defer { covio_owned_bytes_free(&output) }
        guard status == 0 else {
            throw Self.error(error)
        }
        guard output.len > 0, let data = output.data else {
            return [:]
        }
        return try JSONSerialization.jsonObject(
            with: Data(bytes: data, count: output.len),
            options: [.fragmentsAllowed]
        )
    }

    func decode<T: Decodable>(
        _ type: T.Type,
        command: String,
        payload: [String: Any] = [:],
        nowEpochSeconds: Int64 = Int64(Date().timeIntervalSince1970)
    ) throws -> T {
        let value = try call(command, payload: payload, nowEpochSeconds: nowEpochSeconds)
        let data = try JSONSerialization.data(withJSONObject: value)
        return try JSONDecoder().decode(type, from: data)
    }

    private static func emptyBytes() -> CovioOwnedBytes {
        CovioOwnedBytes(data: nil, len: 0, capacity: 0)
    }

    private static func emptyError() -> CovioError {
        CovioError(code: 0, message: emptyBytes())
    }

    private static func error(_ error: CovioError) -> CovioCoreError {
        let message: String
        if let data = error.message.data, error.message.len > 0 {
            message = String(
                decoding: UnsafeBufferPointer(start: data, count: error.message.len),
                as: UTF8.self
            )
        } else {
            message = "Covio core request failed"
        }
        return CovioCoreError(code: error.code, message: message)
    }
}

enum CovioCoreDefaults {
    static var applicationSupportRoot: String {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first?.path ?? NSTemporaryDirectory()
    }

    static var configPath: String {
        URL(fileURLWithPath: applicationSupportRoot)
            .appendingPathComponent("com.wyz.covio/config.json").path
    }

    static var shelfPath: String {
        URL(fileURLWithPath: applicationSupportRoot)
            .appendingPathComponent("Covio/Screenshots/shelf.json").path
    }

    static var clipboardPath: String {
        URL(fileURLWithPath: applicationSupportRoot)
            .appendingPathComponent("Covio/Clipboard/clipboard.json").path
    }

    static var workspacePath: String {
        URL(fileURLWithPath: applicationSupportRoot)
            .appendingPathComponent("Covio/Workspace").path
    }
}

enum CovioCoreRuntime {
    static let shared: CovioCoreClient = {
        do {
            return try CovioCoreClient(applicationSupportRoot: CovioCoreDefaults.applicationSupportRoot)
        } catch {
            fatalError("Cannot create Covio Rust core handle: \(error)")
        }
    }()
}
