//! Generated JNI entry points and native registration.

use crate::session::{JniSession, SessionError};
use covio_ffi::CovioStatusCode;
use jni::objects::{JByteArray, JObject, JValue};
use jni::sys::{
    JNI_VERSION_1_8, JNIEnv as RawJniEnv, JavaVM as RawJavaVm, jboolean, jbyteArray, jclass, jint,
    jlong, jobject,
};
use jni::{JNIEnv, JavaVM, NativeMethod};
use std::collections::HashMap;
use std::ffi::c_void;
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::sync::atomic::{AtomicI64, Ordering};
use std::sync::{Arc, Mutex, OnceLock};

const NATIVE_CLASS: &str = "com/wyz/covio/bridge/CovioNative";

static SESSIONS: OnceLock<Mutex<HashMap<i64, Arc<JniSession>>>> = OnceLock::new();
static NEXT_HANDLE: AtomicI64 = AtomicI64::new(1);

fn sessions() -> &'static Mutex<HashMap<i64, Arc<JniSession>>> {
    SESSIONS.get_or_init(|| Mutex::new(HashMap::new()))
}

fn insert_session(session: Arc<JniSession>) -> i64 {
    let handle = NEXT_HANDLE.fetch_add(1, Ordering::Relaxed).max(1);
    if let Ok(mut values) = sessions().lock() {
        values.insert(handle, session);
    }
    handle
}

fn session(handle: i64) -> Result<Arc<JniSession>, SessionError> {
    sessions()
        .lock()
        .map_err(|_| SessionError {
            status: CovioStatusCode::Internal as u32,
            message: "session registry lock failed".to_owned(),
        })?
        .get(&handle)
        .cloned()
        .ok_or(SessionError {
            status: CovioStatusCode::InvalidArgument as u32,
            message: "invalid JNI session handle".to_owned(),
        })
}

fn remove_session(handle: i64) -> Option<Arc<JniSession>> {
    sessions().lock().ok()?.remove(&handle)
}

fn jni_env(raw: RawJniEnv) -> Result<JNIEnv<'static>, SessionError> {
    unsafe { JNIEnv::from_raw(raw as *mut RawJniEnv) }.map_err(|_| SessionError {
        status: CovioStatusCode::Internal as u32,
        message: "JNI environment could not be read".to_owned(),
    })
}

fn read_bytes(env: &mut JNIEnv, value: jbyteArray) -> Result<Vec<u8>, SessionError> {
    if value.is_null() {
        return Err(SessionError {
            status: CovioStatusCode::InvalidArgument as u32,
            message: "byte array is null".to_owned(),
        });
    }
    let value = unsafe { JByteArray::from_raw(value) };
    env.convert_byte_array(value).map_err(|_| SessionError {
        status: CovioStatusCode::InvalidArgument as u32,
        message: "byte array could not be read".to_owned(),
    })
}

fn set_bytes(env: &mut JNIEnv, output: jobject, bytes: &[u8]) -> Result<(), SessionError> {
    if output.is_null() {
        return Err(SessionError {
            status: CovioStatusCode::InvalidArgument as u32,
            message: "byte output is null".to_owned(),
        });
    }
    let array = env.byte_array_from_slice(bytes).map_err(|_| SessionError {
        status: CovioStatusCode::Internal as u32,
        message: "byte array allocation failed".to_owned(),
    })?;
    let array_object = JObject::from(array);
    env.set_field(
        unsafe { JObject::from_raw(output) },
        "bytes",
        "[B",
        JValue::Object(&array_object),
    )
    .map_err(|_| SessionError {
        status: CovioStatusCode::Internal as u32,
        message: "byte output could not be written".to_owned(),
    })
}

fn clear_bytes(env: &mut JNIEnv, output: jobject) {
    if output.is_null() {
        return;
    }
    let output = unsafe { JObject::from_raw(output) };
    let _ = env.set_field(&output, "bytes", "[B", JValue::Object(&JObject::null()));
}

fn set_error(env: &mut JNIEnv, output: jobject, error: &SessionError) {
    if output.is_null() {
        return;
    }
    let output = unsafe { JObject::from_raw(output) };
    let _ = env.set_field(&output, "code", "I", JValue::Int(error.status as jint));
    if let Ok(message) = env.new_string(&error.message) {
        let message = JObject::from(message);
        let _ = env.set_field(
            &output,
            "message",
            "Ljava/lang/String;",
            JValue::Object(&message),
        );
    }
}

fn clear_error(env: &mut JNIEnv, output: jobject) {
    if output.is_null() {
        return;
    }
    let output = unsafe { JObject::from_raw(output) };
    let _ = env.set_field(&output, "code", "I", JValue::Int(0));
    if let Ok(message) = env.new_string("") {
        let message = JObject::from(message);
        let _ = env.set_field(
            &output,
            "message",
            "Ljava/lang/String;",
            JValue::Object(&message),
        );
    }
}

fn finish_status(env: &mut JNIEnv, error_out: jobject, result: Result<(), SessionError>) -> jint {
    match result {
        Ok(()) => {
            clear_error(env, error_out);
            CovioStatusCode::Ok as jint
        }
        Err(error) => {
            set_error(env, error_out, &error);
            error.status as jint
        }
    }
}

fn panic_error(message: &str) -> SessionError {
    SessionError {
        status: CovioStatusCode::Panic as u32,
        message: message.to_owned(),
    }
}

fn native_method(name: &str, signature: &str, function: *mut c_void) -> NativeMethod {
    NativeMethod {
        name: name.into(),
        sig: signature.into(),
        fn_ptr: function,
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "system" fn JNI_OnLoad(vm: *mut RawJavaVm, _reserved: *mut c_void) -> jint {
    let result = catch_unwind(AssertUnwindSafe(|| {
        let vm = unsafe { JavaVM::from_raw(vm) }
            .map_err(|_| panic_error("Java VM could not be opened"))?;
        let mut env = vm
            .attach_current_thread()
            .map_err(|_| panic_error("JNI environment could not attach"))?;
        let class = env
            .find_class(NATIVE_CLASS)
            .map_err(|_| panic_error("CovioNative class was not found"))?;
        let methods = [
            native_method(
                "nativeAbiVersion",
                "()I",
                covio_jni_abi_version as *mut c_void,
            ),
            native_method(
                "nativeProtocolVersion",
                "()I",
                covio_jni_protocol_version as *mut c_void,
            ),
            native_method(
                "nativeOpenSession",
                "(JJILcom/wyz/covio/bridge/NativeErrorBox;)J",
                covio_jni_handle_create as *mut c_void,
            ),
            native_method(
                "nativeConfigure",
                "(J[BLcom/wyz/covio/bridge/NativeErrorBox;)I",
                covio_jni_handle_configure as *mut c_void,
            ),
            native_method(
                "nativeRelease",
                "(J)V",
                covio_jni_handle_release as *mut c_void,
            ),
            native_method(
                "nativeDispatch",
                "(J[BJLcom/wyz/covio/bridge/ByteArrayBox;Lcom/wyz/covio/bridge/NativeErrorBox;)I",
                covio_jni_handle_dispatch as *mut c_void,
            ),
            native_method(
                "nativeCancel",
                "(J[BIJLcom/wyz/covio/bridge/NativeErrorBox;)I",
                covio_jni_handle_cancel as *mut c_void,
            ),
            native_method(
                "nativeShutdown",
                "(JZZJJLcom/wyz/covio/bridge/NativeErrorBox;)I",
                covio_jni_handle_shutdown as *mut c_void,
            ),
            native_method(
                "nativeNextEvent",
                "(JILcom/wyz/covio/bridge/ByteArrayBox;Lcom/wyz/covio/bridge/NativeErrorBox;)I",
                covio_jni_handle_next_event as *mut c_void,
            ),
            native_method(
                "nativeLifecycle",
                "(J)I",
                covio_jni_handle_lifecycle as *mut c_void,
            ),
            native_method(
                "nativeActiveRequestCount",
                "(J)J",
                covio_jni_handle_active_request_count as *mut c_void,
            ),
        ];
        env.register_native_methods(class, &methods)
            .map_err(|_| panic_error("JNI native methods could not be registered"))?;
        Ok::<(), SessionError>(())
    }));
    match result {
        Ok(Ok(())) => JNI_VERSION_1_8,
        _ => CovioStatusCode::Panic as jint,
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "system" fn covio_jni_abi_version(_env: RawJniEnv, _class: jclass) -> jint {
    covio_ffi::ABI_VERSION as jint
}

#[unsafe(no_mangle)]
pub unsafe extern "system" fn covio_jni_protocol_version(_env: RawJniEnv, _class: jclass) -> jint {
    covio_bridge::PROTOCOL_VERSION as jint
}

#[unsafe(no_mangle)]
pub unsafe extern "system" fn covio_jni_handle_create(
    env: RawJniEnv,
    _class: jclass,
    generation: jlong,
    revision: jlong,
    max_control_bytes: jint,
    error_out: jobject,
) -> jlong {
    let mut env = match jni_env(env) {
        Ok(env) => env,
        Err(_) => return 0,
    };
    let result = catch_unwind(AssertUnwindSafe(|| {
        if generation < 0 || revision < 0 {
            return Err(SessionError {
                status: CovioStatusCode::InvalidArgument as u32,
                message: "generation and revision must be non-negative".to_owned(),
            });
        }
        let size = if max_control_bytes <= 0 {
            covio_bridge::DEFAULT_MAX_CONTROL_BYTES as u32
        } else {
            max_control_bytes as u32
        };
        Ok(insert_session(Arc::new(JniSession::new(
            generation as u64,
            revision as u64,
            size,
        ))))
    }));
    match result {
        Ok(Ok(handle)) => {
            clear_error(&mut env, error_out);
            handle as jlong
        }
        Ok(Err(error)) => {
            set_error(&mut env, error_out, &error);
            0
        }
        Err(_) => {
            set_error(
                &mut env,
                error_out,
                &panic_error("JNI session creation panicked"),
            );
            0
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "system" fn covio_jni_handle_configure(
    env: RawJniEnv,
    _class: jclass,
    handle: jlong,
    config_json: jbyteArray,
    error_out: jobject,
) -> jint {
    let mut env = match jni_env(env) {
        Ok(env) => env,
        Err(error) => {
            return error.status as jint;
        }
    };
    let result = catch_unwind(AssertUnwindSafe(|| {
        let bytes = read_bytes(&mut env, config_json)?;
        session(handle)?.configure(&bytes)
    }));
    match result {
        Ok(result) => finish_status(&mut env, error_out, result),
        Err(_) => {
            let error = panic_error("JNI configure panicked");
            set_error(&mut env, error_out, &error);
            error.status as jint
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "system" fn covio_jni_handle_release(
    _env: RawJniEnv,
    _class: jclass,
    handle: jlong,
) {
    let _ = catch_unwind(AssertUnwindSafe(|| {
        if let Some(session) = remove_session(handle) {
            let _ = session.shutdown(true, false, 0, now_unix_millis());
            session.close();
        }
    }));
}

#[unsafe(no_mangle)]
pub unsafe extern "system" fn covio_jni_handle_dispatch(
    env: RawJniEnv,
    _class: jclass,
    handle: jlong,
    message: jbyteArray,
    now_unix_millis: jlong,
    out_message: jobject,
    error_out: jobject,
) -> jint {
    let mut env = match jni_env(env) {
        Ok(env) => env,
        Err(error) => {
            return error.status as jint;
        }
    };
    let result = catch_unwind(AssertUnwindSafe(|| {
        let bytes = read_bytes(&mut env, message)?;
        let response = session(handle)?.dispatch(&bytes, now_unix_millis.max(0) as u64)?;
        set_bytes(&mut env, out_message, &response)
    }));
    match result {
        Ok(result) => finish_status(&mut env, error_out, result),
        Err(_) => {
            let error = panic_error("JNI dispatch panicked");
            set_error(&mut env, error_out, &error);
            error.status as jint
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "system" fn covio_jni_handle_cancel(
    env: RawJniEnv,
    _class: jclass,
    handle: jlong,
    request_id: jbyteArray,
    reason: jint,
    now_unix_millis: jlong,
    error_out: jobject,
) -> jint {
    let mut env = match jni_env(env) {
        Ok(env) => env,
        Err(error) => {
            return error.status as jint;
        }
    };
    let result = catch_unwind(AssertUnwindSafe(|| {
        let bytes = read_bytes(&mut env, request_id)?;
        let request_id = std::str::from_utf8(&bytes).map_err(|_| SessionError {
            status: CovioStatusCode::InvalidUtf8 as u32,
            message: "request id is not UTF-8".to_owned(),
        })?;
        session(handle)?.cancel(
            request_id,
            reason.max(0) as u32,
            now_unix_millis.max(0) as u64,
        )
    }));
    match result {
        Ok(result) => finish_status(&mut env, error_out, result),
        Err(_) => {
            let error = panic_error("JNI cancel panicked");
            set_error(&mut env, error_out, &error);
            error.status as jint
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "system" fn covio_jni_handle_shutdown(
    env: RawJniEnv,
    _class: jclass,
    handle: jlong,
    immediate: jboolean,
    has_deadline: jboolean,
    deadline_unix_millis: jlong,
    now_unix_millis: jlong,
    error_out: jobject,
) -> jint {
    let mut env = match jni_env(env) {
        Ok(env) => env,
        Err(error) => {
            return error.status as jint;
        }
    };
    let result = catch_unwind(AssertUnwindSafe(|| {
        session(handle)?.shutdown(
            immediate != 0,
            has_deadline != 0,
            deadline_unix_millis.max(0) as u64,
            now_unix_millis.max(0) as u64,
        )
    }));
    match result {
        Ok(result) => finish_status(&mut env, error_out, result),
        Err(_) => {
            let error = panic_error("JNI shutdown panicked");
            set_error(&mut env, error_out, &error);
            error.status as jint
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "system" fn covio_jni_handle_next_event(
    env: RawJniEnv,
    _class: jclass,
    handle: jlong,
    timeout_ms: jint,
    out_message: jobject,
    error_out: jobject,
) -> jint {
    let mut env = match jni_env(env) {
        Ok(env) => env,
        Err(error) => {
            return error.status as jint;
        }
    };
    clear_bytes(&mut env, out_message);
    let result = catch_unwind(AssertUnwindSafe(|| {
        if let Some(event) = session(handle)?.next_event(timeout_ms.max(0) as u32)? {
            set_bytes(&mut env, out_message, &event)?;
        }
        Ok(())
    }));
    match result {
        Ok(result) => finish_status(&mut env, error_out, result),
        Err(_) => {
            let error = panic_error("JNI next event panicked");
            set_error(&mut env, error_out, &error);
            error.status as jint
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "system" fn covio_jni_handle_lifecycle(
    _env: RawJniEnv,
    _class: jclass,
    handle: jlong,
) -> jint {
    catch_unwind(AssertUnwindSafe(|| session(handle)?.lifecycle()))
        .ok()
        .and_then(Result::ok)
        .map(|value| value as jint)
        .unwrap_or(-1)
}

#[unsafe(no_mangle)]
pub unsafe extern "system" fn covio_jni_handle_active_request_count(
    _env: RawJniEnv,
    _class: jclass,
    handle: jlong,
) -> jlong {
    catch_unwind(AssertUnwindSafe(|| session(handle)?.active_request_count()))
        .ok()
        .and_then(Result::ok)
        .map(|value| value as jlong)
        .unwrap_or(-1)
}

fn now_unix_millis() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|duration| u64::try_from(duration.as_millis()).unwrap_or(u64::MAX))
        .unwrap_or(0)
}
