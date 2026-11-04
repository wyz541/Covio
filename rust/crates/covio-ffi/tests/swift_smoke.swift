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

guard covio_ffi_abi_version() == 1 else {
    fail("unexpected ABI version")
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
covio_error_free(&cancelError)
covio_error_free(&shutdownError)
covio_error_free(&capabilityError)

print("Covio C ABI Swift smoke passed")
