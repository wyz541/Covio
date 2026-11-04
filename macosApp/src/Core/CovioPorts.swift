import Foundation

protocol StateListener: AnyObject {
    func onState(state: AppState)
}

protocol PowerSource: AnyObject {
    func read() -> BatteryStatus?
    func subscribe(listener_: @escaping () -> Void)
    func stop()
}

protocol PowerObservationSource: AnyObject {
    func read() -> PowerObservation
    func subscribe(listener_: @escaping () -> Void)
    func stop()
}

protocol LidSensor: AnyObject {
    func read() -> LidState
    func subscribe(listener: @escaping (LidState) -> Void)
    func stop()
}

protocol IdleSensor: AnyObject {
    func idleSeconds() -> Int64
}

protocol SleepController: AnyObject {
    func sleep()
    func displaySleep()
    func applyIdleSleepPrevention(prevention: IdleSleepPrevention) -> IdleSleepAssertionResult
    func readIdleSleepPrevention() -> IdleSleepPrevention
    func systemIdleSleepTimeoutSeconds() -> Int64?
}

protocol SleepWatcher: AnyObject {
    func subscribe(listener__: @escaping (SleepEvent) -> Void)
    func stop()
}

protocol WakeLogReader: AnyObject {
    func read() -> WakeLogSnapshot?
}

protocol PrivilegedOps: AnyObject {
    func isInstalled() -> Bool
    func status() -> HelperStatus
    func helperVersion() -> String?
    func install() -> Bool
    func uninstall() -> Bool
    func setDisableSleep(disabled: Bool) -> Bool
    func lidLeaseStatus() -> LidLeaseStatus
    func hibernateMode() -> Int32?
    func setHibernateMode(mode: Int32) -> Bool
}

protocol LoginItem: AnyObject {
    func isEnabled() -> Bool
    func enable() -> Bool
    func disable() -> Bool
}

protocol UpdateChecker: AnyObject {
    func latestRelease() -> UpdateInfo?
}

protocol Notifier: AnyObject {
    func notify(title: String, subtitle: String, message: String, releaseUrl: String?)
}

protocol AppLogger: AnyObject {
    func info(message: String)
    func warn(message: String, error: Error?)
    func error(message: String, error: Error?)
    func logFile() -> String
}

protocol ConfigChanged: AnyObject {
    func onChanged(config: AppConfig)
}

extension Notifier {
    func notify(title: String, subtitle: String = "", message: String = "", releaseUrl: String? = nil) {
        notify(title: title, subtitle: subtitle, message: message, releaseUrl: releaseUrl)
    }
}

extension AppLogger {
    func warn(message: String) { warn(message: message, error: nil) }
    func error(message: String) { error(message: message, error: nil) }
}
