import Foundation
import SwiftUI
import UIKit

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var isReady = false
    @Published private(set) var identity: DeviceIdentity?
    @Published private(set) var localDevice: LocalDeviceProfile?
    @Published private(set) var devices: [DeviceView] = []
    @Published private(set) var transfers: [TransferView] = []
    @Published private(set) var pendingIncoming: TransferView?
    @Published private(set) var listenerActive = false
    @Published private(set) var listenerError: String?
    @Published private(set) var lifecycle = "foreground"
    @Published var selectedFile: URL?
    @Published var selectedPeerId: String?
    @Published var errorMessage: String?

    @Published private(set) var pairingRole: PairingRole = .initiator
    @Published private(set) var pairingOfferQR: String?
    @Published private(set) var pairingResponseQR: String?
    @Published private(set) var confirmationCode: String?

    private var bridge: CovioBridge?
    private var pollTask: Task<Void, Never>?
    private var lastPendingTransferId: String?
    private var previousTransferStates: [String: String] = [:]
    private var isBootstrapping = false

    enum PairingRole: String, Sendable {
        case initiator
        case responder
    }

    func bootstrap() async {
        guard !isReady, !isBootstrapping else { return }
        isBootstrapping = true
        defer { isBootstrapping = false }
        do {
            let root = try FileAccess.applicationSupportRoot()
            let bridge = try CovioBridge(dataRoot: root)
            self.bridge = bridge
            let device = UIDevice.current
            let payload = BootstrapPayload(
                displayName: device.name,
                systemName: device.covioSystemName,
                systemVersion: device.covioSystemVersion,
                model: device.model,
                capabilities: [
                    "file.transfer",
                    "file.picker",
                    "share.sheet",
                    "notification",
                    "keychain.identity",
                    "background.resume"
                ]
            )
            let response: BootstrapResponse = try await bridge.call(
                "mobile.bootstrap",
                payload: bridge.encode(payload)
            )
            identity = response.identity
            localDevice = response.localDevice
            devices = response.devices
            apply(status: StatusResponse(
                lifecycle: response.status.lifecycle,
                listenerActive: response.status.listenerActive,
                listenerError: response.status.listenerError,
                pendingIncomingTransferId: response.status.pendingIncomingTransferId,
                transfers: response.status.transfers
            ))
            selectedPeerId = devices.first?.deviceId
            isReady = true
            await LocalNotifications.requestAuthorization()
            startPolling()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectFile(_ result: Result<[URL], any Error>) async {
        do {
            guard let url = try result.get().first else { return }
            selectedFile = try FileAccess.prepareSourceFile(url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func sendSelectedFile() async {
        guard let bridge, let selectedFile else { return }
        guard let peerId = selectedPeerId else {
            errorMessage = "Pair a device before sending a file."
            return
        }
        do {
            let payload = SendPayload(
                sourcePath: selectedFile.path,
                peerDeviceId: peerId
            )
            let _: TransferView = try await bridge.call(
                "mobile.transfer.send",
                payload: bridge.encode(payload)
            )
            await refreshStatus()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startReceiving() async {
        guard let bridge else { return }
        do {
            let destination = try FileAccess.receivedDirectory()
            let payload = ListenPayload(destinationPath: destination.path)
            let _: ListenResponse = try await bridge.call(
                "mobile.transfer.listen",
                payload: bridge.encode(payload)
            )
            await refreshStatus()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func acceptIncoming(_ transfer: TransferView) async {
        await transferCommand(
            "mobile.transfer.accept",
            transferId: transfer.transferId
        )
    }

    func rejectIncoming(_ transfer: TransferView) async {
        await transferCommand(
            "mobile.transfer.reject",
            transferId: transfer.transferId
        )
    }

    func resume(_ transfer: TransferView) async {
        await transferCommand(
            "mobile.transfer.resume",
            transferId: transfer.transferId
        )
    }

    func cancel(_ transfer: TransferView) async {
        await transferCommand(
            "mobile.transfer.cancel",
            transferId: transfer.transferId
        )
    }

    func scenePhaseChanged(_ phase: ScenePhase) async {
        guard let bridge, isReady else { return }
        do {
            switch phase {
            case .active:
                let _: ForegroundResponse = try await bridge.call(
                    "mobile.lifecycle.foreground"
                )
                await refreshStatus()
            case .background:
                let response: StatusResponse = try await bridge.call(
                    "mobile.lifecycle.background"
                )
                apply(status: response)
            case .inactive:
                break
            @unknown default:
                break
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func beginPairing() async {
        guard let bridge else { return }
        do {
            let response: PairingBeginResponse = try await bridge.call(
                "mobile.pairing.begin"
            )
            pairingRole = .initiator
            pairingOfferQR = response.qrPayload
            pairingResponseQR = nil
            confirmationCode = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func acceptPairingOffer(_ qrPayload: String) async {
        guard let bridge else { return }
        do {
            let payload = PairingAcceptPayload(qrPayload: qrPayload)
            let response: PairingAcceptResponse = try await bridge.call(
                "mobile.pairing.acceptOffer",
                payload: bridge.encode(payload)
            )
            pairingRole = .responder
            pairingOfferQR = nil
            pairingResponseQR = response.responsePayload
            confirmationCode = response.confirmationCode
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func completePairingWithResponse(_ responsePayload: String) async {
        guard let bridge else { return }
        do {
            let payload = PairingResponsePayload(responsePayload: responsePayload)
            let response: PairingCompleteResponse = try await bridge.call(
                "mobile.pairing.completeInitiator",
                payload: bridge.encode(payload)
            )
            pairingRole = .initiator
            pairingResponseQR = nil
            confirmationCode = response.confirmationCode
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func confirmPairing() async {
        guard let bridge, let confirmationCode else { return }
        do {
            let payload = PairingConfirmPayload(confirmationCode: confirmationCode)
            let command = pairingRole == .initiator
                ? "mobile.pairing.confirmInitiator"
                : "mobile.pairing.confirmResponder"
            let response: PairingConfirmResponse = try await bridge.call(
                command,
                payload: bridge.encode(payload)
            )
            devices = response.devices
            if selectedPeerId == nil {
                selectedPeerId = devices.first?.deviceId
            }
            resetPairing()
            await LocalNotifications.send(
                title: "Device paired",
                body: response.device.displayName
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cancelPairing() async {
        guard let bridge else { return }
        do {
            let _: PairingCancelResponse = try await bridge.call(
                "mobile.pairing.cancel"
            )
            resetPairing()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resetPairing() {
        pairingOfferQR = nil
        pairingResponseQR = nil
        confirmationCode = nil
    }

    func refreshDevices() async {
        guard let bridge else { return }
        do {
            let response: DevicesResponse = try await bridge.call(
                "mobile.devices.list"
            )
            devices = response.devices
            if selectedPeerId == nil {
                selectedPeerId = devices.first?.deviceId
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func transferCommand(_ command: String, transferId: String) async {
        guard let bridge else { return }
        do {
            let payload = TransferCommandPayload(transferId: transferId)
            let _: TransferView = try await bridge.call(
                command,
                payload: bridge.encode(payload)
            )
            await refreshStatus()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { @MainActor [weak self] in
            var ticks = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                await self?.refreshStatus()
                ticks += 1
                if ticks.isMultiple(of: 10) {
                    await self?.refreshDevices()
                }
            }
        }
    }

    private func refreshStatus() async {
        guard let bridge else { return }
        do {
            let response: StatusResponse = try await bridge.call(
                "mobile.status"
            )
            apply(status: response)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func apply(status: StatusResponse) {
        lifecycle = status.lifecycle
        listenerActive = status.listenerActive
        listenerError = status.listenerError
        transfers = status.transfers
        for transfer in status.transfers
        where transfer.state == "completed"
            && previousTransferStates[transfer.transferId] != "completed" {
            Task {
                await LocalNotifications.send(
                    title: "Transfer complete",
                    body: transfer.fileName ?? "A file transfer completed."
                )
            }
        }
        previousTransferStates = Dictionary(
            uniqueKeysWithValues: status.transfers.map { ($0.transferId, $0.state) }
        )
        pendingIncoming = status.transfers.first {
            $0.transferId == status.pendingIncomingTransferId
        }
        if let pendingIncoming,
           pendingIncoming.transferId != lastPendingTransferId {
            lastPendingTransferId = pendingIncoming.transferId
            Task {
                await LocalNotifications.send(
                    title: "Incoming file",
                    body: pendingIncoming.fileName ?? "A paired device sent a file."
                )
            }
        }
        if status.pendingIncomingTransferId == nil {
            lastPendingTransferId = nil
        }
    }
}

private struct BootstrapPayload: Encodable {
    let displayName: String
    let systemName: String
    let systemVersion: String
    let model: String
    let capabilities: [String]
}

private struct SendPayload: Encodable { let sourcePath: String; let peerDeviceId: String }
private struct ListenPayload: Encodable { let destinationPath: String }
private struct ListenResponse: Decodable { let listenerActive: Bool }
private struct TransferCommandPayload: Encodable { let transferId: String }
private struct PairingAcceptPayload: Encodable { let qrPayload: String }
private struct PairingResponsePayload: Encodable { let responsePayload: String }
private struct PairingConfirmPayload: Encodable { let confirmationCode: String }
private struct PairingCancelResponse: Decodable { let cancelled: Bool }
private struct ForegroundResponse: Decodable {
    let status: MobileStatus
    let resumedTransferIds: [String]
}
