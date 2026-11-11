import CovioFFI
import Foundation

enum CovioBridgeError: LocalizedError, Sendable {
    case unavailable
    case native(code: UInt32, message: String)
    case malformedResponse

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "The native session is not available."
        case let .native(_, message):
            return message
        case .malformedResponse:
            return "The native response is malformed."
        }
    }
}

final class CovioBridge: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.wyz.covio.mobile-bridge")
    private var handle: OpaquePointer?

    init(dataRoot: URL) throws {
        let path = Array(dataRoot.path.utf8)
        var error = Self.emptyError()
        handle = path.withUnsafeBufferPointer { buffer in
            covio_mobile_create(buffer.baseAddress, buffer.count, &error)
        }
        if handle == nil {
            throw Self.bridgeError(error)
        }
    }

    deinit {
        if let handle {
            covio_mobile_release(handle)
        }
    }

    func call<Response: Decodable & Sendable>(
        _ command: String,
        payload: Data = Data("{}".utf8)
    ) async throws -> Response {
        let data = try await perform(command: command, payload: payload)
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw CovioBridgeError.malformedResponse
        }
    }

    func encode<Body: Encodable>(_ body: Body) throws -> Data {
        try JSONEncoder().encode(body)
    }

    private func perform(command: String, payload: Data) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                guard let handle else {
                    continuation.resume(throwing: CovioBridgeError.unavailable)
                    return
                }
                var output = Self.emptyBytes()
                var error = Self.emptyError()
                let commandBytes = Array(command.utf8)
                let status = commandBytes.withUnsafeBufferPointer { commandBuffer in
                    payload.withUnsafeBytes { payloadBuffer in
                        covio_mobile_call(
                            handle,
                            commandBuffer.baseAddress,
                            commandBuffer.count,
                            payloadBuffer.bindMemory(to: UInt8.self).baseAddress,
                            payload.count,
                            Int64(Date().timeIntervalSince1970 * 1_000),
                            &output,
                            &error
                        )
                    }
                }
                if status != 0 {
                    continuation.resume(
                        throwing: Self.bridgeError(error, fallbackCode: status)
                    )
                    covio_owned_bytes_free(&output)
                    return
                }
                let data: Data
                if let pointer = output.data, output.len > 0 {
                    data = Data(bytes: pointer, count: output.len)
                } else {
                    data = Data("{}".utf8)
                }
                covio_owned_bytes_free(&output)
                covio_error_free(&error)
                continuation.resume(returning: data)
            }
        }
    }

    private static func bridgeError(
        _ error: CovioError,
        fallbackCode: UInt32? = nil
    ) -> CovioBridgeError {
        var value = error
        defer { covio_error_free(&value) }
        let message: String
        if let pointer = value.message.data, value.message.len > 0 {
            message = String(
                decoding: UnsafeBufferPointer(start: pointer, count: value.message.len),
                as: UTF8.self
            )
        } else {
            message = "Native operation failed."
        }
        return .native(code: fallbackCode ?? value.code, message: message)
    }

    private static func emptyBytes() -> CovioOwnedBytes {
        CovioOwnedBytes(data: nil, len: 0, capacity: 0)
    }

    private static func emptyError() -> CovioError {
        CovioError(code: 0, message: emptyBytes())
    }
}
