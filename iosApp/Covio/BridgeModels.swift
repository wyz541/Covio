import Foundation

struct EmptyPayload: Encodable, Sendable {}

struct DeviceIdentity: Codable, Sendable {
    let deviceId: String
    let displayName: String
    let publicKey: String
}

struct LocalDeviceProfile: Codable, Sendable {
    let displayName: String
    let systemName: String
    let systemVersion: String
    let model: String
    let capabilities: [String]
}

struct PairedDeviceRecord: Codable, Identifiable, Sendable {
    let deviceId: String
    let displayName: String
    let publicKey: String
    let pairedAtMs: Int64
    let lastSeenMs: Int64

    var id: String { deviceId }
}

struct DeviceView: Codable, Identifiable, Sendable {
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

struct TransferView: Codable, Identifiable, Sendable {
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

struct MobileStatus: Codable, Sendable {
    let lifecycle: String
    let listenerActive: Bool
    let listenerError: String?
    let pendingIncomingTransferId: String?
    let transfers: [TransferView]
}

struct BootstrapResponse: Codable, Sendable {
    let identity: DeviceIdentity
    let localDevice: LocalDeviceProfile
    let devices: [DeviceView]
    let status: MobileStatus
}

struct DevicesResponse: Codable, Sendable {
    let devices: [DeviceView]
}

struct PairingBeginResponse: Codable, Sendable {
    let qrPayload: String
    let expiresAtMs: Int64
}

struct PairingAcceptResponse: Codable, Sendable {
    let responsePayload: String
    let confirmationCode: String
    let remoteDevice: PairedDeviceRecord
    let remoteCapabilities: [String]
    let remoteSystemName: String
    let remoteSystemVersion: String
}

struct PairingCompleteResponse: Codable, Sendable {
    let confirmationCode: String
    let remoteDevice: PairedDeviceRecord
}

struct PairingConfirmResponse: Codable, Sendable {
    let device: PairedDeviceRecord
    let devices: [DeviceView]
}

struct StatusResponse: Codable, Sendable {
    let lifecycle: String
    let listenerActive: Bool
    let listenerError: String?
    let pendingIncomingTransferId: String?
    let transfers: [TransferView]
}
