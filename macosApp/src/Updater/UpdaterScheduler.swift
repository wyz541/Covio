import Darwin
import Foundation

final class UpdaterScheduler: @unchecked Sendable {
    static let defaultInterval: TimeInterval = 6 * 60 * 60
    static let defaultInitialDelay: TimeInterval = 15

    private let coordinator: UpdaterCoordinator
    private let paths: UpdaterPaths
    private let interval: TimeInterval
    private let initialDelay: TimeInterval
    private let preferences: UpdaterPreferenceStore
    private let queue = DispatchQueue(label: "com.wyz.covio.updater.scheduler")
    private var timer: DispatchSourceTimer?

    init(
        coordinator: UpdaterCoordinator,
        paths: UpdaterPaths,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.coordinator = coordinator
        self.paths = paths
        preferences = UpdaterPreferenceStore(paths: paths)
        interval = Self.seconds(
            environment["COVIO_UPDATER_CHECK_INTERVAL_SECONDS"],
            fallback: Self.defaultInterval,
            minimum: 60
        )
        initialDelay = Self.seconds(
            environment["COVIO_UPDATER_INITIAL_CHECK_DELAY_SECONDS"],
            fallback: Self.defaultInitialDelay,
            minimum: 1
        )
    }

    func start(
        completion: @escaping @Sendable (UpdaterOperationResult) -> Void
    ) {
        queue.async { [weak self] in
            guard let self, self.timer == nil else { return }
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(
                deadline: .now() + self.initialDelay,
                repeating: self.interval,
                leeway: .seconds(30)
            )
            timer.setEventHandler { [weak self] in
                self?.runAutomaticUpdate(completion: completion)
            }
            self.timer = timer
            timer.resume()
        }
    }

    func cancel() {
        queue.sync {
            timer?.cancel()
            timer = nil
        }
    }

    static func consoleUID(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> uid_t? {
        if let value = environment["COVIO_UPDATER_CONSOLE_UID"] {
            guard let raw = UInt32(value), raw > 0 else { return nil }
            return uid_t(raw)
        }
        guard let attributes = try? FileManager.default.attributesOfItem(
            atPath: "/dev/console"
        ), let owner = (attributes[.ownerAccountID] as? NSNumber)?.uint32Value,
              owner > 0
        else {
            return nil
        }
        return uid_t(owner)
    }

    private func runAutomaticUpdate(
        completion: @escaping @Sendable (UpdaterOperationResult) -> Void
    ) {
        guard let uid = Self.consoleUID(),
              preferences.isAutomaticUpdateEnabled(for: uid)
        else {
            return
        }
        coordinator.checkAndInstall(completion: completion)
    }

    private static func seconds(
        _ value: String?,
        fallback: TimeInterval,
        minimum: TimeInterval
    ) -> TimeInterval {
        guard let value, let parsed = TimeInterval(value), parsed >= minimum else {
            return fallback
        }
        return parsed
    }
}
