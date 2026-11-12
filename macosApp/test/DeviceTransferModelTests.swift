import XCTest
@testable import Covio

@MainActor
final class DeviceTransferModelTests: XCTestCase {
    func testBootstrapLoadsDeviceAndTransferState() async {
        let client = FakeDeviceTransferClient()
        let model = DeviceTransferModel(client: client)

        await model.bootstrap()

        XCTAssertTrue(model.isReady)
        XCTAssertEqual(model.localDevice?.displayName, "Test Mac")
        XCTAssertEqual(model.devices.map(\.displayName), ["Test iPhone"])
        XCTAssertTrue(model.listenerActive)
        XCTAssertEqual(model.transfers.map(\.transferId), ["transfer-1"])
    }

    func testPairingFlowCarriesOfferResponseAndConfirmation() async {
        let client = FakeDeviceTransferClient()
        let model = DeviceTransferModel(client: client)
        await model.bootstrap()

        await model.beginPairing()
        XCTAssertEqual(model.pairingOfferQR, "offer-qr")

        await model.completePairing(responsePayload: "response-qr")
        XCTAssertEqual(model.confirmationCode, "123456")
        XCTAssertNil(model.pairingOfferQR)

        await model.confirmPairing()

        XCTAssertNil(model.confirmationCode)
        XCTAssertEqual(model.devices.map(\.displayName), ["Test iPhone", "Paired Windows"])
    }

    func testPairingResponderAcceptsOfferAndConfirms() async {
        let client = FakeDeviceTransferClient()
        let model = DeviceTransferModel(client: client)
        await model.bootstrap()

        await model.acceptPairingOffer("offer-from-phone")
        XCTAssertEqual(model.pairingResponseQR, "response-from-mac")
        XCTAssertEqual(model.confirmationCode, "654321")

        await model.confirmPairing()
        let lastResponder = await client.lastResponderValue()
        XCTAssertEqual(lastResponder, true)
        XCTAssertNil(model.pairingResponseQR)
    }

    func testNativeTransferErrorKeepsStableCode() async {
        let client = FakeDeviceTransferClient()
        await client.setSendError(.native(code: 3009, message: "disk full"))
        let model = DeviceTransferModel(client: client)
        await model.bootstrap()
        model.selectFile(URL(fileURLWithPath: "/tmp/report.txt"))

        await model.sendSelectedFile()

        XCTAssertEqual(model.errorMessage, "disk full [3009]")
    }
}

private actor FakeDeviceTransferClient: DeviceTransferClient {
    private var sendError: DeviceTransferNativeError?
    private var responder = false
    private let device = DeviceTransferDevice(
        deviceId: "phone-1",
        displayName: "Test iPhone",
        publicKey: "phone-key",
        pairedAtMs: 1,
        lastSeenMs: 2,
        online: true,
        systemName: "iOS",
        systemVersion: "27.0",
        capabilities: ["file.transfer"]
    )
    private let paired = DeviceTransferPairedDevice(
        deviceId: "phone-1",
        displayName: "Test iPhone",
        publicKey: "phone-key",
        pairedAtMs: 1,
        lastSeenMs: 2
    )

    func setSendError(_ error: DeviceTransferNativeError?) {
        sendError = error
    }

    func lastResponderValue() -> Bool {
        responder
    }

    func bootstrap(_ payload: DeviceTransferBootstrapPayload) async throws -> DeviceTransferBootstrapResponse {
        DeviceTransferBootstrapResponse(
            identity: DeviceTransferIdentity(
                deviceId: "mac-1",
                displayName: "Test Mac",
                publicKey: "mac-key"
            ),
            localDevice: DeviceTransferLocalProfile(
                displayName: "Test Mac",
                systemName: "macOS",
                systemVersion: "27.0",
                model: "MacBookPro18,2",
                capabilities: payload.capabilities
            ),
            devices: [device],
            status: try await status()
        )
    }

    func devices() async throws -> DeviceTransferDevicesResponse {
        DeviceTransferDevicesResponse(devices: [device])
    }

    func status() async throws -> DeviceTransferStatus {
        DeviceTransferStatus(
            lifecycle: "foreground",
            listenerActive: true,
            listenerError: nil,
            pendingIncomingTransferId: nil,
            transfers: [transfer]
        )
    }

    func beginPairing() async throws -> DeviceTransferPairingBegin {
        DeviceTransferPairingBegin(qrPayload: "offer-qr", expiresAtMs: 100)
    }

    func acceptPairingOffer(_ qrPayload: String) async throws -> DeviceTransferPairingAccepted {
        DeviceTransferPairingAccepted(
            responsePayload: "response-from-mac",
            confirmationCode: "654321",
            remoteDevice: paired,
            remoteCapabilities: ["file.transfer"],
            remoteSystemName: "iOS",
            remoteSystemVersion: "27.0"
        )
    }

    func completePairing(_ responsePayload: String) async throws -> DeviceTransferPairingCompleted {
        DeviceTransferPairingCompleted(
            confirmationCode: "123456",
            remoteDevice: paired
        )
    }

    func confirmPairing(code: String, responder: Bool) async throws -> DeviceTransferPairingConfirmed {
        self.responder = responder
        let windows = DeviceTransferDevice(
            deviceId: "windows-1",
            displayName: "Paired Windows",
            publicKey: "windows-key",
            pairedAtMs: 3,
            lastSeenMs: 4,
            online: true,
            systemName: "Windows",
            systemVersion: "11",
            capabilities: ["file.transfer"]
        )
        return DeviceTransferPairingConfirmed(device: paired, devices: [device, windows])
    }

    func cancelPairing() async throws -> DeviceTransferPairingCancelled {
        DeviceTransferPairingCancelled(cancelled: true)
    }

    func startListening(destinationPath: String) async throws -> DeviceTransferListenResponse {
        DeviceTransferListenResponse(listenerActive: true)
    }

    func send(sourcePath: String, peerDeviceId: String) async throws -> DeviceTransferItem {
        if let sendError {
            throw sendError
        }
        return transfer
    }

    func transferCommand(_ command: String, transferId: String) async throws -> DeviceTransferItem {
        transfer
    }

    private var transfer: DeviceTransferItem {
        DeviceTransferItem(
            transferId: "transfer-1",
            direction: "receive",
            peerDeviceId: "phone-1",
            state: "completed",
            fileName: "report.txt",
            totalBytes: 10,
            durableBytes: 10,
            progressPercent: 100,
            errorCode: nil,
            errorMessage: nil,
            finalPath: "/tmp/report.txt",
            updatedAtMs: 5
        )
    }
}
