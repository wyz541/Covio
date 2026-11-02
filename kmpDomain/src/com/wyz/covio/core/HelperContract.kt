package com.wyz.covio.core

/**
 * 特权 helper 的安装契约：命令行参数、路径、协议版本与命令白名单。
 *
 * 放在共享模块里，因为有三处必须用同一份值：
 * - Compose 版的 `app/src/com/wyz/covio/app/helper/HelperProtocol.kt`
 * - SwiftUI 版的 `macosApp/src/Platform/HelperProtocol.swift`
 * - 安装脚本生成的 LaunchDaemon plist
 *
 * 抄三遍必然漂移。漂移的表现是「客户端发得出、服务端不认」，
 * 出错时很难定位。所以只留一份，两边都引用这里。
 *
 * 这些取值天生属于 macOS：LaunchDaemon 与服务端的 Unix 域 socket 都是 macOS 机制。
 * 第二个平台需要自己的特权服务时，再把这组常量拆进平台实现。
 */

/** 以 legacy socket helper 身份启动的命令行参数。 */
const val HELPER_ARGUMENT = "--helper"

/** XPC daemon 的可执行文件名。 */
const val HELPER_EXECUTABLE_NAME = "CovioHelper"

/** daemon 可执行文件相对 app bundle 根目录的位置。 */
const val HELPER_EXECUTABLE_BUNDLE_PATH = "Contents/MacOS/$HELPER_EXECUTABLE_NAME"

/** 休眠 SMAppService.daemon 路径使用的 plist 文件名。 */
const val HELPER_DAEMON_PLIST_NAME = "com.wyz.covio.helper.plist"

/** XPC Mach service 名称。 */
const val HELPER_XPC_SERVICE_NAME = "com.wyz.covio.helper.xpc"

/** 客户端与服务端协商的协议版本。改协议时必须同时改这里。 */
const val HELPER_PROTOCOL_VERSION = "10"

/** legacy helper 迁移路径监听的 Unix 域 socket。 */
const val HELPER_SOCKET_PATH = "/Library/Application Support/Covio/helper.sock"

/** helper 的安装目录。root 所有。 */
const val HELPER_DIRECTORY = "/Library/Application Support/Covio"

/** 固定 helper 二进制目录。root 所有。 */
const val HELPER_BINARY_DIRECTORY = "$HELPER_DIRECTORY/bin"

/** 本机 Legacy LaunchDaemon 使用的固定 helper 路径。 */
const val HELPER_BINARY_PATH = "$HELPER_BINARY_DIRECTORY/$HELPER_EXECUTABLE_NAME"

/** 充电上限状态目录。 */
const val HELPER_CHARGE_LIMIT_DIRECTORY = "$HELPER_DIRECTORY/charge-limit"

/** 保存原始 MCL 状态。卸载前必须确认此文件已经清除。 */
const val HELPER_CHARGE_LIMIT_STATE_PATH = "$HELPER_CHARGE_LIMIT_DIRECTORY/state.json"

/** 保存用户的持续充电意图。 */
const val HELPER_CHARGE_LIMIT_RUNTIME_PATH = "$HELPER_CHARGE_LIMIT_DIRECTORY/runtime.json"

/** 记录允许连接的 uid。安装时写入当前用户。 */
const val HELPER_ALLOWED_UID_PATH = "$HELPER_DIRECTORY/allowed_uid"

/** 记录允许执行充电控制命令的客户端代码签名 requirement。 */
const val HELPER_CLIENT_REQUIREMENT_PATH = "$HELPER_DIRECTORY/client-requirement"

/** 记录 helper 的版本。客户端用它判断是否需要重装。 */
const val HELPER_VERSION_PATH = "$HELPER_DIRECTORY/version"

/** 记录应用的位置。卸载时用。 */
const val HELPER_APP_PATH_FILE = "$HELPER_DIRECTORY/Covio.app"

/** 记录 Covio 是否拥有当前 `SleepDisabled`。只有 root helper 能写。 */
const val HELPER_SLEEP_OWNER_PATH = "$HELPER_DIRECTORY/sleep_owner"

/** 所有权 marker 的固定内容。 */
const val HELPER_SLEEP_OWNER_VALUE = "covio-sleep-disabled-v2"

/** helper 租约的有效期，单位秒。 */
const val HELPER_LEASE_DURATION_SECONDS = 60L

/** 应用续租间隔，单位秒。 */
const val HELPER_LEASE_RENEW_SECONDS = 15L

/** 租约 ID 的最大长度。 */
const val HELPER_LEASE_ID_MAX_LENGTH = 128

/** 同时有效的租约上限。用于限制异常客户端占用的内存。 */
const val HELPER_LEASE_MAX_ACTIVE = 16

/** helper 的日志。 */
const val HELPER_LOG_PATH = "$HELPER_DIRECTORY/helper.log"

/** 当前 Legacy LaunchDaemon 的 plist。 */
const val HELPER_PLIST_PATH = "/Library/LaunchDaemons/com.wyz.covio.helper.plist"

/** LaunchDaemon 的标签。 */
const val HELPER_LAUNCH_DAEMON_LABEL = "com.wyz.covio.helper"

/**
 * helper 接受的命令。
 *
 * 白名单而不是黑名单：新命令必须显式加进来，忘记加的表现是拒绝，
 * 而不是放行一条没想过的命令。
 */
val HELPER_ALLOWED_COMMANDS: Set<String> = setOf(
    "version",
    "setDisableSleep",
    "setHibernateMode",
    "chargeLimitStatus",
    "chargeLimitConfigure",
    "chargeLimitRestore",
    "lidLeaseAcquire",
    "lidLeaseRenew",
    "lidLeaseRelease",
    "lidLeaseStatus",
    "fanControlStatus",
    "fanControlConfigure",
    "fanControlKeepAlive",
    "fanControlRestore",
    "prepareInstallTransaction",
)
