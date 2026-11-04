#ifndef COVIO_FFI_H
#define COVIO_FFI_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define COVIO_FFI_ABI_VERSION 1u

typedef struct CovioHandle CovioHandle;
typedef struct CovioAppHandle CovioAppHandle;
typedef struct CovioEngineHandle CovioEngineHandle;

typedef enum CovioStatusCode {
    COVIO_STATUS_OK = 0,
    COVIO_STATUS_INVALID_ARGUMENT = 1,
    COVIO_STATUS_INVALID_UTF8 = 2,
    COVIO_STATUS_PAYLOAD_TOO_LARGE = 3,
    COVIO_STATUS_MALFORMED_MESSAGE = 4,
    COVIO_STATUS_PROTOCOL_VERSION = 5,
    COVIO_STATUS_STALE_GENERATION = 6,
    COVIO_STATUS_STALE_REVISION = 7,
    COVIO_STATUS_INVALID_REVISION = 8,
    COVIO_STATUS_DEADLINE_EXCEEDED = 9,
    COVIO_STATUS_CANCELLED = 10,
    COVIO_STATUS_SHUTTING_DOWN = 11,
    COVIO_STATUS_UNSUPPORTED = 12,
    COVIO_STATUS_NOT_FOUND = 13,
    COVIO_STATUS_CONFLICT = 14,
    COVIO_STATUS_IO = 15,
    COVIO_STATUS_INTERNAL = 16,
    COVIO_STATUS_PANIC = 17,
} CovioStatusCode;

typedef enum CovioLifecycle {
    COVIO_LIFECYCLE_RUNNING = 0,
    COVIO_LIFECYCLE_DRAINING = 1,
    COVIO_LIFECYCLE_STOPPED = 2,
} CovioLifecycle;

typedef enum CovioCapability {
    COVIO_CAPABILITY_FILESYSTEM = 0,
    COVIO_CAPABILITY_PROCESS = 1,
    COVIO_CAPABILITY_SOCKET = 2,
    COVIO_CAPABILITY_NOTIFICATION = 3,
    COVIO_CAPABILITY_POWER = 4,
    COVIO_CAPABILITY_UPDATE = 5,
    COVIO_CAPABILITY_SECURE_STORAGE = 6,
} CovioCapability;

typedef struct CovioOwnedBytes {
    uint8_t *data;
    size_t len;
    size_t capacity;
} CovioOwnedBytes;

typedef struct CovioError {
    uint32_t code;
    CovioOwnedBytes message;
} CovioError;

typedef void (*CovioEventCallback)(
    void *context,
    const uint8_t *data,
    size_t len
);

typedef CovioOwnedBytes (*CovioEngineCallback)(
    void *context,
    const uint8_t *request,
    size_t request_len,
    CovioError *error
);

CovioAppHandle *covio_app_create(
    const uint8_t *data_root,
    size_t data_root_len,
    CovioError *error
);

CovioAppHandle *covio_app_create_with_paths(
    const uint8_t *config_path,
    size_t config_len,
    const uint8_t *shelf_path,
    size_t shelf_len,
    const uint8_t *clipboard_path,
    size_t clipboard_len,
    const uint8_t *workspace_path,
    size_t workspace_len,
    CovioError *error
);

void covio_app_release(CovioAppHandle *handle);

uint32_t covio_app_call(
    CovioAppHandle *handle,
    const uint8_t *command,
    size_t command_len,
    const uint8_t *payload,
    size_t payload_len,
    int64_t now_epoch_seconds,
    CovioOwnedBytes *out_data,
    CovioError *error
);

CovioEngineHandle *covio_engine_create(
    const uint8_t *config_json,
    size_t config_len,
    CovioEngineCallback callback,
    void *context,
    CovioError *error
);

void covio_engine_release(CovioEngineHandle *handle);

uint32_t covio_engine_call(
    CovioEngineHandle *handle,
    const uint8_t *command,
    size_t command_len,
    const uint8_t *payload_json,
    size_t payload_len,
    int64_t now_epoch_seconds,
    CovioOwnedBytes *out_data,
    CovioError *error
);

CovioOwnedBytes covio_owned_bytes_copy(const uint8_t *data, size_t len);

uint32_t covio_ffi_abi_version(void);

/* One handle is single-threaded. Host callbacks must not re-enter the handle. */
CovioHandle *covio_handle_create(
    uint64_t generation,
    uint64_t revision,
    uint32_t max_control_bytes,
    CovioEventCallback callback,
    void *context,
    CovioError *error
);

void covio_handle_release(CovioHandle *handle);

uint32_t covio_handle_dispatch(
    CovioHandle *handle,
    const uint8_t *message,
    size_t message_len,
    uint64_t now_unix_millis,
    CovioOwnedBytes *out_message,
    CovioError *error
);

uint32_t covio_handle_cancel(
    CovioHandle *handle,
    const uint8_t *request_id,
    size_t request_id_len,
    uint32_t reason,
    uint64_t now_unix_millis,
    CovioError *error
);

uint32_t covio_handle_shutdown(
    CovioHandle *handle,
    bool immediate,
    bool has_deadline,
    uint64_t deadline_unix_millis,
    uint64_t now_unix_millis,
    CovioError *error
);

uint32_t covio_handle_lifecycle(const CovioHandle *handle);
uint64_t covio_handle_active_request_count(const CovioHandle *handle);

uint32_t covio_keychain_read(
    const uint8_t *key,
    size_t key_len,
    CovioOwnedBytes *out_value,
    CovioError *error
);

uint32_t covio_keychain_write(
    const uint8_t *key,
    size_t key_len,
    const uint8_t *value,
    size_t value_len,
    CovioError *error
);

uint32_t covio_keychain_delete(
    const uint8_t *key,
    size_t key_len,
    CovioError *error
);

uint32_t covio_capability_status(uint32_t capability, CovioError *error);

void covio_owned_bytes_free(CovioOwnedBytes *bytes);
void covio_error_free(CovioError *error);

#ifdef __cplusplus
}
#endif

#endif
