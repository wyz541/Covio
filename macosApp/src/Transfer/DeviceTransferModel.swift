import Darwin
import Foundation

@MainActor
final class DeviceTransferModel: ObservableObject {
    enum PairingRole: Sendable {
        case initiator
        case responder
    }

    @Published private(set) var isReady = false
    @Published private(set) var identity: DeviceTransferIdentity?
    @Published private(set) var localDevice: DeviceTransferLocalProfile?
    @Published private(set) var devices: [DeviceTransferDevice] = []
    @Published private(set) var transfers: [DeviceTransferItem] = []
    @Published private(set) var listenerActive = false
    @Published private(set) var listenerError: String?
    @Published private(set) var pairingRole: PairingRole = .initiator
    @Published private(set) var pairingOfferQR: String?
    @Published private(set) var pairingResponseQR: String?
    @Published private(set) var confirmationCode: String?
    @Published private(set) var receiveDirectory: URL?
    private var pendingIncomingTransferId: String?
    @Published var selectedFile: URL?
    @Published var selectedPeerId: String?
    @Published var errorMessage: String?

    private var client: (any DeviceTransferClient)?
    private var pollTask: Task<Void, Never>?
    private var bootstrapping = false

    var pendingIncoming: DeviceTransferItem? {
        guard let pendingIncomingTransferId else { return nil }
        return transfers.first { $0.transferId == pendingIncomingTransferId }
    }

    init(client: (any DeviceTransferClient)? = nil) {
        self.client = client
    }

    deinit {
        pollTask?.cancel()
    }

    func bootstrap() async {
        guard !isReady, !bootstrapping else { return }
        bootstrapping = true
        defer { bootstrapping = false }
        do {
            AppPaths.ensureSupportDirectory()
            let resolvedClient: any DeviceTransferClient
            if let client {
                resolvedClient = client
            } else {
                resolvedClient = try RustDeviceTransferClient(dataRoot: AppPaths.supportDirectory)
                client = resolvedClient
            }
            let response = try await resolvedClient.bootstrap(Self.bootstrapPayload())
            identity = response.identity
            localDevice = response.localDevice
            devices = response.devices
            apply(response.status)
            selectedPeerId = devices.first?.deviceId
            isReady = true
            startPolling()
        } catch {
            present(error)
        }
    }

    func selectFile(_ url: URL) {
        selectedFile = url
    }

    func sendSelectedFile() async {
        guard let client, let selectedFile else { return }
        guard let selectedPeerId else {
            errorMessage = "Pair a device before sending a file."
            return
        }
        do {
            _ = try await client.send(
                sourcePath: selectedFile.path,
                peerDeviceId: selectedPeerId
            )
            await refreshStatus()
        } catch {
            present(error)
        }
    }

    func startReceiving() async {
        guard let client else { return }
        do {
            let directory = try Self.makeReceiveDirectory()
            receiveDirectory = directory
            _ = try await client.startListening(destinationPath: directory.path)
            await refreshStatus()
        } catch {
            present(error)
        }
    }

    func acceptIncoming(_ transfer: DeviceTransferItem) async {
        await transferCommand("mobile.transfer.accept", transfer: transfer)
    }

    func rejectIncoming(_ transfer: DeviceTransferItem) async {
        await transferCommand("mobile.transfer.reject", transfer: transfer)
    }

    func pause(_ transfer: DeviceTransferItem) async {
        await transferCommand("mobile.transfer.pause", transfer: transfer)
    }

    func resume(_ transfer: DeviceTransferItem) async {
        await transferCommand("mobile.transfer.resume", transfer: transfer)
    }

    func cancel(_ transfer: DeviceTransferItem) async {
        await transferCommand("mobile.transfer.cancel", transfer: transfer)
    }

    func beginPairing() async {
        guard let client else { return }
        do {
            let response = try await client.beginPairing()
            pairingRole = .initiator
            pairingOfferQR = response.qrPayload
            pairingResponseQR = nil
            confirmationCode = nil
        } catch {
            present(error)
        }
    }

    func acceptPairingOffer(_ payload: String) async {
        guard let client else { return }
        let payload = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !payload.isEmpty else {
            errorMessage = "Enter the pairing QR payload first."
            return
        }
        do {
            let response = try await client.acceptPairingOffer(payload)
            pairingRole = .responder
            pairingOfferQR = nil
            pairingResponseQR = response.responsePayload
            confirmationCode = response.confirmationCode
        } catch {
            present(error)
        }
    }

    func completePairing(responsePayload: String) async {
        guard let client else { return }
        let payload = responsePayload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !payload.isEmpty else {
            errorMessage = "Enter the response QR payload first."
            return
        }
        do {
            let response = try await client.completePairing(payload)
            pairingRole = .initiator
            pairingOfferQR = nil
            pairingResponseQR = nil
            confirmationCode = response.confirmationCode
        } catch {
            present(error)
        }
    }

    func confirmPairing() async {
        guard let client, let confirmationCode else { return }
        do {
            let response = try await client.confirmPairing(
                code: confirmationCode,
                responder: pairingRole == .responder
            )
            devices = response.devices
            if selectedPeerId == nil {
                selectedPeerId = devices.first?.deviceId
            }
            resetPairing()
        } catch {
            present(error)
        }
    }

    func cancelPairing() async {
        guard let client else { return }
        do {
            _ = try await client.cancelPairing()
            resetPairing()
        } catch {
            present(error)
        }
    }

    func resetPairing() {
        pairingOfferQR = nil
        pairingResponseQR = nil
        confirmationCode = nil
    }

    func refreshDevices() async {
        guard let client else { return }
        do {
            let response = try await client.devices()
            devices = response.devices
            if selectedPeerId == nil {
                selectedPeerId = devices.first?.deviceId
            }
        } catch {
            present(error)
        }
    }

    func refreshStatus() async {
        guard let client else { return }
        do {
            apply(try await client.status())
        } catch {
            present(error)
        }
    }

    func clearError() {
        errorMessage = nil
    }

    private func transferCommand(_ command: String, transfer: DeviceTransferItem) async {
        guard let client else { return }
        do {
            _ = try await client.transferCommand(command, transferId: transfer.transferId)
            await refreshStatus()
        } catch {
            present(error)
        }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { @MainActor [weak self] in
            var ticks = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self else { return }
                await refreshStatus()
                ticks += 1
                if ticks.isMultiple(of: 10) {
                    await refreshDevices()
                }
            }
        }
    }

    private func apply(_ status: DeviceTransferStatus) {
        listenerActive = status.listenerActive
        listenerError = status.listenerError
        pendingIncomingTransferId = status.pendingIncomingTransferId
        transfers = status.transfers
    }

    private func present(_ error: any Error) {
        if let native = error as? DeviceTransferNativeError {
            switch native {
            case let .native(code, message):
                errorMessage = "\(message) [\(code)]"
            default:
                errorMessage = native.localizedDescription
            }
            return
        }
        errorMessage = error.localizedDescription
    }

    private static func bootstrapPayload() -> DeviceTransferBootstrapPayload {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return DeviceTransferBootstrapPayload(
            displayName: previewDisplayName,
            systemName: "macOS",
            systemVersion: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            model: hardwareModel(),
            capabilities: [
                "file.transfer",
                "file.picker",
                "keychain.identity",
            ]
        )
    }

    private static var previewDisplayName: String {
        #if DEBUG
        if let name = ProcessInfo.processInfo.environment["COVIO_DEVICE_TRANSFER_DISPLAY_NAME"],
           !name.isEmpty
        {
            return name
        }
        #endif
        return Host.current().localizedName ?? "Mac"
    }

    private static func hardwareModel() -> String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 1 else {
            return "Mac"
        }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &bytes, &size, nil, 0) == 0 else {
            return "Mac"
        }
        let textBytes = bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: textBytes, as: UTF8.self)
    }

    private static func makeReceiveDirectory() throws -> URL {
        let directory = AppPaths.supportDirectory
            .appendingPathComponent("Transfer", isDirectory: true)
            .appendingPathComponent("Received", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }
}
