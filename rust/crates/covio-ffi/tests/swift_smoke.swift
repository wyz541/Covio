import CovioFFI
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func errorText(_ error: CovioError) -> String {
    guard let data = error.message.data, error.message.len > 0 else {
        return "status \(error.code)"
    }
    return String(decoding: UnsafeBufferPointer(start: data, count: error.message.len), as: UTF8.self)
}

func dispatch(_ handle: OpaquePointer, _ json: String) -> Int32 {
    let bytes = Array(json.utf8)
    var output = CovioOwnedBytes(data: nil, len: 0, capacity: 0)
    var error = CovioError(code: 0, message: CovioOwnedBytes(data: nil, len: 0, capacity: 0))
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
    if status != 0 {
        let message = errorText(error)
        covio_error_free(&error)
        fail("dispatch failed: \(message)")
    }
    covio_owned_bytes_free(&output)
    return Int32(status)
}

guard covio_ffi_abi_version() == 2 else {
    fail("unexpected ABI version")
}
guard covio_bridge_protocol_version() == 1 else {
    fail("unexpected bridge protocol version")
}

var createError = CovioError(code: 0, message: CovioOwnedBytes(data: nil, len: 0, capacity: 0))
guard let handle = covio_handle_create(1, 0, 0, nil, nil, &createError) else {
    fail("handle create failed: \(errorText(createError))")
}
defer {
    covio_handle_release(handle)
    covio_error_free(&createError)
}

_ = dispatch(
    handle,
    #"{"kind":"request","body":{"protocol_version":1,"request_id":"swift-1","generation":1,"command":"settings.load","deadline":null,"payload":{}}}"#
)
guard covio_handle_active_request_count(handle) == 1 else {
    fail("request was not tracked")
}

let requestID = Array("swift-1".utf8)
var cancelError = CovioError(code: 0, message: CovioOwnedBytes(data: nil, len: 0, capacity: 0))
let cancelStatus = requestID.withUnsafeBufferPointer { buffer in
    covio_handle_cancel(handle, buffer.baseAddress, buffer.count, 0, 50, &cancelError)
}
guard cancelStatus == 0 else {
    fail("cancel failed: \(errorText(cancelError))")
}
guard covio_handle_active_request_count(handle) == 0 else {
    fail("request was not cancelled")
}

var shutdownError = CovioError(code: 0, message: CovioOwnedBytes(data: nil, len: 0, capacity: 0))
let shutdownStatus = covio_handle_shutdown(handle, true, false, 0, 50, &shutdownError)
guard shutdownStatus == 0, covio_handle_lifecycle(handle) == 2 else {
    fail("shutdown failed: \(errorText(shutdownError))")
}

var capabilityError = CovioError(code: 0, message: CovioOwnedBytes(data: nil, len: 0, capacity: 0))
guard covio_capability_status(0, &capabilityError) == 0 else {
    fail("filesystem capability unavailable: \(errorText(capabilityError))")
}
guard covio_capability_status(4, &capabilityError) == 12 else {
    fail("unwired power capability did not return unavailable")
}

if ProcessInfo.processInfo.environment["COVIO_RUN_REAL_KEYCHAIN_TESTS"] == "1" {
    let smokeRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("covio-ffi-smoke-\(UUID().uuidString)")
        .path
    let dataRoot = Array(smokeRoot.utf8)
    let keychainService = Array("com.wyz.covio.agent.ffi.swift-smoke.\(UUID().uuidString)".utf8)
    let keychainKey = Array("mcp-bearer-token".utf8)
    let keychainValue = Array("swift-value".utf8)
    var keychainError = CovioError(code: 0, message: CovioOwnedBytes(data: nil, len: 0, capacity: 0))
    let deleteStatus = dataRoot.withUnsafeBufferPointer { root in
        keychainService.withUnsafeBufferPointer { service in
            keychainKey.withUnsafeBufferPointer { key in
                covio_agent_token_delete(
                    root.baseAddress,
                    root.count,
                    service.baseAddress,
                    service.count,
                    key.baseAddress,
                    key.count,
                    &keychainError
                )
            }
        }
    }
    guard deleteStatus == 0 else {
        fail("stale keychain delete failed: \(errorText(keychainError))")
    }
    let writeStatus = dataRoot.withUnsafeBufferPointer { root in
        keychainService.withUnsafeBufferPointer { service in
            keychainKey.withUnsafeBufferPointer { key in
                keychainValue.withUnsafeBufferPointer { value in
                    covio_agent_token_write(
                        root.baseAddress,
                        root.count,
                        service.baseAddress,
                        service.count,
                        key.baseAddress,
                        key.count,
                        value.baseAddress,
                        value.count,
                        &keychainError
                    )
                }
            }
        }
    }
    guard writeStatus == 0 else {
        fail("keychain write failed: \(errorText(keychainError))")
    }
    var keychainOutput = CovioOwnedBytes(data: nil, len: 0, capacity: 0)
    let readStatus = dataRoot.withUnsafeBufferPointer { root in
        keychainService.withUnsafeBufferPointer { service in
            keychainKey.withUnsafeBufferPointer { key in
                covio_agent_token_read(
                    root.baseAddress,
                    root.count,
                    service.baseAddress,
                    service.count,
                    key.baseAddress,
                    key.count,
                    &keychainOutput,
                    &keychainError
                )
            }
        }
    }
    guard readStatus == 0,
          let outputData = keychainOutput.data,
          String(decoding: UnsafeBufferPointer(start: outputData, count: keychainOutput.len), as: UTF8.self) == "swift-value"
    else {
        fail("keychain read failed: \(errorText(keychainError))")
    }
    covio_owned_bytes_free(&keychainOutput)
    let cleanupStatus = dataRoot.withUnsafeBufferPointer { root in
        keychainService.withUnsafeBufferPointer { service in
            keychainKey.withUnsafeBufferPointer { key in
                covio_agent_token_delete(
                    root.baseAddress,
                    root.count,
                    service.baseAddress,
                    service.count,
                    key.baseAddress,
                    key.count,
                    &keychainError
                )
            }
        }
    }
    guard cleanupStatus == 0 else {
        fail("keychain cleanup failed: \(errorText(keychainError))")
    }
    let resetStatus = dataRoot.withUnsafeBufferPointer { root in
        covio_agent_token_reset(root.baseAddress, root.count, &keychainError)
    }
    guard resetStatus == 0 else {
        fail("credential vault reset failed: \(errorText(keychainError))")
    }
    try? FileManager.default.removeItem(atPath: smokeRoot)
    covio_error_free(&keychainError)
} else {
    print("Covio C ABI keychain checks skipped: requires a signed macOS host")
}
covio_error_free(&cancelError)
covio_error_free(&shutdownError)
covio_error_free(&capabilityError)

print("Covio C ABI Swift smoke passed")
