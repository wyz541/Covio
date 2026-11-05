import AppKit
import Foundation
@preconcurrency import UserNotifications

/// `Notifier` 端口的 macOS 实现。
///
/// 旧版使用 `NSUserNotification`，该 API 在 macOS 14 已废弃。
/// 当前实现使用 `UNUserNotificationCenter`。
///
/// `UNUserNotificationCenter` 需要用户授权，且应用必须已注册。
/// 未授权或注册失败时退回 `osascript`。
// 所有可变状态都由 `lock` 保护，所以可以跨线程传。
final class MacNotifier: NSObject, Notifier, @unchecked Sendable {
    private let logger: AppLogger
    private let notificationsEnabled: () -> Bool
    private let lock = NSLock()
    private var pendingReleaseUrl: String?

    init(logger: AppLogger, notificationsEnabled: @escaping () -> Bool) {
        self.logger = logger
        self.notificationsEnabled = notificationsEnabled
        super.init()
    }

    func notify(title: String, subtitle: String, message: String, releaseUrl: String?) {
        guard notificationsEnabled() else { return }
        lock.lock()
        pendingReleaseUrl = releaseUrl
        lock.unlock()
        // 通知的点击回调在 AppDelegate 里处理，见 `openPendingReleaseUrl()`。
        deliver(title: title, subtitle: subtitle, message: message)
    }

    /// 用户在通知上点了之后调用。打开待处理的下载页。
    ///
    /// 取出后立刻清空，所以连点两次只会打开一次。
    func openPendingReleaseUrl() {
        lock.lock()
        let url = pendingReleaseUrl
        pendingReleaseUrl = nil
        lock.unlock()
        guard let url, let target = URL(string: url) else { return }
        NSWorkspace.shared.open(target)
    }

    private func deliver(title: String, subtitle: String, message: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        if !subtitle.isEmpty { content.subtitle = subtitle }
        if !message.isEmpty { content.body = message }
        content.sound = nil

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { [weak self] granted, error in
            guard let self else { return }
            if let error {
                self.logger.warn(message: "Notification authorization failed", error: nil)
                _ = error
            }
            guard granted else {
                self.logger.warn(message: "Notifications are not authorized; using osascript fallback", error: nil)
                self.fallback(title: title, subtitle: subtitle, message: message)
                return
            }
            center.add(request) { addError in
                if addError != nil {
                    self.fallback(title: title, subtitle: subtitle, message: message)
                }
            }
        }
    }

    private func fallback(title: String, subtitle: String, message: String) {
        let text = [title, subtitle, message]
            .filter { !$0.isEmpty }
            .joined(separator: " - ")
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
        PmsetCommand.run(
            "-e",
            "display notification \"\(escaped)\" with title \"Covio\"",
            executable: "/usr/bin/osascript"
        )
    }
}
