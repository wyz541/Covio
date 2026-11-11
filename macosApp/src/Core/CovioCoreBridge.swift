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

    static func emptyBytes() -> CovioOwnedBytes {
        CovioOwnedBytes(data: nil, len: 0, capacity: 0)
    }

    static func emptyError() -> CovioError {
        CovioError(code: 0, message: emptyBytes())
    }

    static func error(_ error: CovioError) -> CovioCoreError {
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

/// Purpose-limited Agent token access through the Rust platform adapter.
enum CovioAgentTokenKeychain {
    static func read(service: String, key: String) throws -> String? {
        let dataRootBytes = Array(CovioCoreDefaults.applicationSupportRoot.utf8)
        let serviceBytes = Array(service.utf8)
        let keyBytes = Array(key.utf8)
        var output = CovioCoreClient.emptyBytes()
        var error = CovioCoreClient.emptyError()
        let status = dataRootBytes.withUnsafeBufferPointer { dataRootBuffer in
            serviceBytes.withUnsafeBufferPointer { serviceBuffer in
                keyBytes.withUnsafeBufferPointer { keyBuffer in
                    covio_agent_token_read(
                        dataRootBuffer.baseAddress,
                        dataRootBuffer.count,
                        serviceBuffer.baseAddress,
                        serviceBuffer.count,
                        keyBuffer.baseAddress,
                        keyBuffer.count,
                        &output,
                        &error
                    )
                }
            }
        }
        defer {
            covio_owned_bytes_free(&output)
            covio_error_free(&error)
        }
        if status == UInt32(COVIO_STATUS_NOT_FOUND.rawValue) {
            return nil
        }
        guard status == UInt32(COVIO_STATUS_OK.rawValue) else {
            throw CovioCoreClient.error(error)
        }
        guard output.len > 0 else { return "" }
        guard let data = output.data else {
            throw CovioCoreError(code: UInt32(COVIO_STATUS_INTERNAL.rawValue), message: "Keychain returned no data.")
        }
        let value = Data(bytes: data, count: output.len)
        guard let string = String(data: value, encoding: .utf8) else {
            throw CovioCoreError(code: UInt32(COVIO_STATUS_INVALID_UTF8.rawValue), message: "Keychain value is not UTF-8.")
        }
        return string
    }

    static func write(service: String, key: String, value: String) throws {
        let dataRootBytes = Array(CovioCoreDefaults.applicationSupportRoot.utf8)
        let serviceBytes = Array(service.utf8)
        let keyBytes = Array(key.utf8)
        let valueBytes = Array(value.utf8)
        var error = CovioCoreClient.emptyError()
        let status = dataRootBytes.withUnsafeBufferPointer { dataRootBuffer in
            serviceBytes.withUnsafeBufferPointer { serviceBuffer in
                keyBytes.withUnsafeBufferPointer { keyBuffer in
                    valueBytes.withUnsafeBufferPointer { valueBuffer in
                        covio_agent_token_write(
                            dataRootBuffer.baseAddress,
                            dataRootBuffer.count,
                            serviceBuffer.baseAddress,
                            serviceBuffer.count,
                            keyBuffer.baseAddress,
                            keyBuffer.count,
                            valueBuffer.baseAddress,
                            valueBuffer.count,
                            &error
                        )
                    }
                }
            }
        }
        defer { covio_error_free(&error) }
        guard status == UInt32(COVIO_STATUS_OK.rawValue) else {
            throw CovioCoreClient.error(error)
        }
    }

    static func delete(service: String, key: String) throws {
        let dataRootBytes = Array(CovioCoreDefaults.applicationSupportRoot.utf8)
        let serviceBytes = Array(service.utf8)
        let keyBytes = Array(key.utf8)
        var error = CovioCoreClient.emptyError()
        let status = dataRootBytes.withUnsafeBufferPointer { dataRootBuffer in
            serviceBytes.withUnsafeBufferPointer { serviceBuffer in
                keyBytes.withUnsafeBufferPointer { keyBuffer in
                    covio_agent_token_delete(
                        dataRootBuffer.baseAddress,
                        dataRootBuffer.count,
                        serviceBuffer.baseAddress,
                        serviceBuffer.count,
                        keyBuffer.baseAddress,
                        keyBuffer.count,
                        &error
                    )
                }
            }
        }
        defer { covio_error_free(&error) }
        guard status == UInt32(COVIO_STATUS_OK.rawValue) else {
            throw CovioCoreClient.error(error)
        }
    }

    static func reset() throws {
        let dataRootBytes = Array(CovioCoreDefaults.applicationSupportRoot.utf8)
        var error = CovioCoreClient.emptyError()
        let status = dataRootBytes.withUnsafeBufferPointer { dataRootBuffer in
            covio_agent_token_reset(
                dataRootBuffer.baseAddress,
                dataRootBuffer.count,
                &error
            )
        }
        defer { covio_error_free(&error) }
        guard status == UInt32(COVIO_STATUS_OK.rawValue) else {
            throw CovioCoreClient.error(error)
        }
    }
}

enum CovioCoreDefaults {
    static var applicationSupportRoot: String {
#if DEBUG
        if let override = ProcessInfo.processInfo.environment["COVIO_APPLICATION_SUPPORT_ROOT"],
           !override.isEmpty
        {
            return override
        }
#endif
        return FileManager.default.urls(
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
