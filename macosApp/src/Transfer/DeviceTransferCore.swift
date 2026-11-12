import CovioFFI
import Foundation

enum DeviceTransferNativeError: LocalizedError, Sendable, Equatable {
    case unavailable
    case native(code: UInt32, message: String)
    case malformedResponse

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "The native device-transfer session is not available."
        case let .native(_, message):
            message
        case .malformedResponse:
            "The native device-transfer response is malformed."
        }
    }
}

final class DeviceTransferNativeBridge: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.wyz.covio.device-transfer-bridge")
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
            throw DeviceTransferNativeError.malformedResponse
        }
    }

    func encode<Body: Encodable>(_ body: Body) throws -> Data {
        try JSONEncoder().encode(body)
    }

    private func perform(command: String, payload: Data) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                guard let handle else {
                    continuation.resume(throwing: DeviceTransferNativeError.unavailable)
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
    ) -> DeviceTransferNativeError {
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

struct DeviceTransferIdentity: Codable, Sendable {
    let deviceId: String
    let displayName: String
    let publicKey: String
}

struct DeviceTransferLocalProfile: Codable, Sendable {
    let displayName: String
    let systemName: String
    let systemVersion: String
    let model: String
    let capabilities: [String]
}

struct DeviceTransferPairedDevice: Codable, Identifiable, Sendable {
    let deviceId: String
    let displayName: String
    let publicKey: String
    let pairedAtMs: Int64
    let lastSeenMs: Int64

    var id: String { deviceId }
}

struct DeviceTransferDevice: Codable, Identifiable, Sendable {
    let deviceId: String
    let displayName: String
    let publicKey: String
    let pairedAtMs: Int64
    let lastSeenMs: Int64
    let online: Bool
    let systemName: String?
    let systemVersion: String?
    let capabilities: [String]

    var id: String { deviceId }
}

struct DeviceTransferItem: Codable, Identifiable, Sendable {
    let transferId: String
    let direction: String
    let peerDeviceId: String
    let state: String
    let fileName: String?
    let totalBytes: UInt64
    let durableBytes: UInt64
    let progressPercent: Int
    let errorCode: String?
    let errorMessage: String?
    let finalPath: String?
    let updatedAtMs: Int64

    var id: String { transferId }
}

struct DeviceTransferStatus: Codable, Sendable {
    let lifecycle: String
    let listenerActive: Bool
    let listenerError: String?
    let pendingIncomingTransferId: String?
    let transfers: [DeviceTransferItem]
}

struct DeviceTransferBootstrapResponse: Codable, Sendable {
    let identity: DeviceTransferIdentity
    let localDevice: DeviceTransferLocalProfile
    let devices: [DeviceTransferDevice]
    let status: DeviceTransferStatus
}

struct DeviceTransferDevicesResponse: Codable, Sendable {
    let devices: [DeviceTransferDevice]
}

struct DeviceTransferPairingBegin: Codable, Sendable {
    let qrPayload: String
    let expiresAtMs: Int64
}

struct DeviceTransferPairingAccepted: Codable, Sendable {
    let responsePayload: String
    let confirmationCode: String
    let remoteDevice: DeviceTransferPairedDevice
    let remoteCapabilities: [String]
    let remoteSystemName: String
    let remoteSystemVersion: String
}

struct DeviceTransferPairingCompleted: Codable, Sendable {
    let confirmationCode: String
    let remoteDevice: DeviceTransferPairedDevice
}

struct DeviceTransferPairingConfirmed: Codable, Sendable {
    let device: DeviceTransferPairedDevice
    let devices: [DeviceTransferDevice]
}

struct DeviceTransferPairingCancelled: Codable, Sendable {
    let cancelled: Bool
}

struct DeviceTransferListenResponse: Codable, Sendable {
    let listenerActive: Bool
}

struct DeviceTransferBootstrapPayload: Encodable, Sendable {
    let displayName: String
    let systemName: String
    let systemVersion: String
    let model: String
    let capabilities: [String]
}

protocol DeviceTransferClient: Sendable {
    func bootstrap(_ payload: DeviceTransferBootstrapPayload) async throws -> DeviceTransferBootstrapResponse
    func devices() async throws -> DeviceTransferDevicesResponse
    func status() async throws -> DeviceTransferStatus
    func beginPairing() async throws -> DeviceTransferPairingBegin
    func acceptPairingOffer(_ qrPayload: String) async throws -> DeviceTransferPairingAccepted
    func completePairing(_ responsePayload: String) async throws -> DeviceTransferPairingCompleted
    func confirmPairing(code: String, responder: Bool) async throws -> DeviceTransferPairingConfirmed
    func cancelPairing() async throws -> DeviceTransferPairingCancelled
    func startListening(destinationPath: String) async throws -> DeviceTransferListenResponse
    func send(sourcePath: String, peerDeviceId: String) async throws -> DeviceTransferItem
    func transferCommand(_ command: String, transferId: String) async throws -> DeviceTransferItem
}

final class RustDeviceTransferClient: DeviceTransferClient, @unchecked Sendable {
    private let bridge: DeviceTransferNativeBridge

    init(dataRoot: URL) throws {
        bridge = try DeviceTransferNativeBridge(dataRoot: dataRoot)
    }

    func bootstrap(_ payload: DeviceTransferBootstrapPayload) async throws -> DeviceTransferBootstrapResponse {
        try await bridge.call("mobile.bootstrap", payload: bridge.encode(payload))
    }

    func devices() async throws -> DeviceTransferDevicesResponse {
        try await bridge.call("mobile.devices.list")
    }

    func status() async throws -> DeviceTransferStatus {
        try await bridge.call("mobile.status")
    }

    func beginPairing() async throws -> DeviceTransferPairingBegin {
        try await bridge.call("mobile.pairing.begin")
    }

    func acceptPairingOffer(_ qrPayload: String) async throws -> DeviceTransferPairingAccepted {
        try await bridge.call(
            "mobile.pairing.acceptOffer",
            payload: bridge.encode(PairingOfferPayload(qrPayload: qrPayload))
        )
    }

    func completePairing(_ responsePayload: String) async throws -> DeviceTransferPairingCompleted {
        try await bridge.call(
            "mobile.pairing.completeInitiator",
            payload: bridge.encode(PairingResponsePayload(responsePayload: responsePayload))
        )
    }

    func confirmPairing(code: String, responder: Bool) async throws -> DeviceTransferPairingConfirmed {
        let command = responder
            ? "mobile.pairing.confirmResponder"
            : "mobile.pairing.confirmInitiator"
        return try await bridge.call(
            command,
            payload: bridge.encode(PairingConfirmationPayload(confirmationCode: code))
        )
    }

    func cancelPairing() async throws -> DeviceTransferPairingCancelled {
        try await bridge.call("mobile.pairing.cancel")
    }

    func startListening(destinationPath: String) async throws -> DeviceTransferListenResponse {
        try await bridge.call(
            "mobile.transfer.listen",
            payload: bridge.encode(ListenPayload(destinationPath: destinationPath))
        )
    }

    func send(sourcePath: String, peerDeviceId: String) async throws -> DeviceTransferItem {
        try await bridge.call(
            "mobile.transfer.send",
            payload: bridge.encode(SendPayload(sourcePath: sourcePath, peerDeviceId: peerDeviceId))
        )
    }

    func transferCommand(_ command: String, transferId: String) async throws -> DeviceTransferItem {
        try await bridge.call(
            command,
            payload: bridge.encode(TransferCommandPayload(transferId: transferId))
        )
    }
}

private struct PairingOfferPayload: Encodable {
    let qrPayload: String
}

private struct PairingResponsePayload: Encodable {
    let responsePayload: String
}

private struct PairingConfirmationPayload: Encodable {
    let confirmationCode: String
}

private struct ListenPayload: Encodable {
    let destinationPath: String
}

private struct SendPayload: Encodable {
    let sourcePath: String
    let peerDeviceId: String
}

private struct TransferCommandPayload: Encodable {
    let transferId: String
}
