import CovioFFI
import XCTest
@testable import Covio

final class CovioBridgeTests: XCTestCase {
    func testBootstrapJSONMatchesSwiftModels() throws {
        let json = """
        {
          "identity": {"deviceId":"sha256:device","displayName":"iPhone","publicKey":"abc"},
          "localDevice": {"displayName":"iPhone","systemName":"iOS","systemVersion":"26.1","model":"iPhone","capabilities":["file.transfer"]},
          "devices": [],
          "status": {"lifecycle":"foreground","listenerActive":false,"listenerError":null,"pendingIncomingTransferId":null,"transfers":[]}
        }
        """
        let response = try JSONDecoder().decode(BootstrapResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.identity.deviceId, "sha256:device")
        XCTAssertEqual(response.localDevice.systemVersion, "26.1")
    }

    func testMobileBridgeRoundTrip() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("covio-ios-bridge-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let bridge = try CovioBridge(dataRoot: root)
        let response: StatusResponse = try await bridge.call("mobile.status")
        XCTAssertEqual(response.lifecycle, "foreground")
        XCTAssertTrue(response.transfers.isEmpty)
    }

    func testNativeErrorIsTyped() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("covio-ios-error-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let bridge = try CovioBridge(dataRoot: root)
        do {
            let _: StatusResponse = try await bridge.call("mobile.unknown")
            XCTFail("unknown command should fail")
        } catch let CovioBridgeError.native(code, _) {
            XCTAssertEqual(code, 1)
        }
    }
}

final class CovioABIContractTests: XCTestCase {
    func testDispatchCancellationAndShutdown() throws {
        XCTAssertEqual(covio_ffi_abi_version(), 2)
        XCTAssertEqual(covio_bridge_protocol_version(), 1)

        var error = emptyError()
        guard let handle = covio_handle_create(
            1,
            0,
            0,
            nil,
            nil,
            &error
        ) else {
            XCTFail("handle creation failed: \(errorText(error))")
            return
        }
        defer { covio_handle_release(handle) }

        let request = """
        {"kind":"request","body":{"protocol_version":1,"request_id":"ios-test","generation":1,"command":"settings.load","deadline":null,"payload":{}}}
        """
        XCTAssertEqual(dispatch(handle: handle, json: request), 0)
        XCTAssertEqual(covio_handle_active_request_count(handle), 1)

        let requestId = Array("ios-test".utf8)
        var cancelError = emptyError()
        let cancelStatus = requestId.withUnsafeBufferPointer { buffer in
            covio_handle_cancel(handle, buffer.baseAddress, buffer.count, 0, 50, &cancelError)
        }
        XCTAssertEqual(cancelStatus, 0)
        XCTAssertEqual(covio_handle_active_request_count(handle), 0)
        covio_error_free(&cancelError)

        var shutdownError = emptyError()
        let shutdownStatus = covio_handle_shutdown(handle, true, false, 0, 50, &shutdownError)
        XCTAssertEqual(shutdownStatus, 0)
        XCTAssertEqual(covio_handle_lifecycle(handle), 2)
        covio_error_free(&shutdownError)
    }

    private func dispatch(handle: OpaquePointer, json: String) -> UInt32 {
        let bytes = Array(json.utf8)
        var output = emptyBytes()
        var error = emptyError()
        let status = bytes.withUnsafeBufferPointer { buffer in
            covio_handle_dispatch(
                handle,
                buffer.baseAddress,
                buffer.count,
                50,
                &output,
                &error
            )
        }
        covio_owned_bytes_free(&output)
        covio_error_free(&error)
        return status
    }

    private func errorText(_ error: CovioError) -> String {
        guard let pointer = error.message.data, error.message.len > 0 else {
            return "status \(error.code)"
        }
        return String(
            decoding: UnsafeBufferPointer(start: pointer, count: error.message.len),
            as: UTF8.self
        )
    }

    private func emptyBytes() -> CovioOwnedBytes {
        CovioOwnedBytes(data: nil, len: 0, capacity: 0)
    }

    private func emptyError() -> CovioError {
        CovioError(code: 0, message: emptyBytes())
    }
}
