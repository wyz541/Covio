#ifndef COVIO_FFI_H
#define COVIO_FFI_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "covio_bridge.generated.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct CovioAppHandle CovioAppHandle;
typedef struct CovioEngineHandle CovioEngineHandle;

typedef enum CovioCapability {
    COVIO_CAPABILITY_FILESYSTEM = 0,
    COVIO_CAPABILITY_PROCESS = 1,
    COVIO_CAPABILITY_SOCKET = 2,
    COVIO_CAPABILITY_NOTIFICATION = 3,
    COVIO_CAPABILITY_POWER = 4,
    COVIO_CAPABILITY_UPDATE = 5,
    COVIO_CAPABILITY_SECURE_STORAGE = 6,
} CovioCapability;

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

/* Bridge handles are single-threaded. Host callbacks must not re-enter them. */

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

uint32_t covio_keychain_read_with_service(
    const uint8_t *service,
    size_t service_len,
    const uint8_t *key,
    size_t key_len,
    CovioOwnedBytes *out_value,
    CovioError *error
);

uint32_t covio_keychain_write_with_service(
    const uint8_t *service,
    size_t service_len,
    const uint8_t *key,
    size_t key_len,
    const uint8_t *value,
    size_t value_len,
    CovioError *error
);

uint32_t covio_keychain_delete_with_service(
    const uint8_t *service,
    size_t service_len,
    const uint8_t *key,
    size_t key_len,
    CovioError *error
);

uint32_t covio_capability_status(uint32_t capability, CovioError *error);

#ifdef __cplusplus
}
#endif

#endif