import CoreGraphics
import Foundation
import os

enum ClosedLidZeroBrightnessPhase: Equatable, Sendable {
    case disabled
    case ready
    case active
    case failed

    var isActive: Bool { self == .active }
}

struct ClosedLidBrightnessEvaluation: Equatable, Sendable {
    let privateBrightnessActive: Bool
    let fallbackToPublicDisplayOff: Bool
    let error: String?
}

/// Coordinates the opt-in private brightness path.
///
/// The controller writes the recovery record before it sets brightness to
/// zero. Every failure attempts a restore. A failed restore keeps the record
/// for the next launch or a manual retry.
@MainActor
final class ClosedLidZeroBrightnessController {
    static let readbackTolerance: Float = 0.02
    static let restoreRetryIntervalSeconds: Int64 = 30

    private let backend: ClosedLidBrightnessBackend
    private let store: ClosedLidBrightnessRecoveryStoring
    private let nowEpochSeconds: () -> Int64
    private let logger = Logger(subsystem: CovioRuntimeConstants.APP_ID, category: "ClosedLidDisplay")

    private(set) var phase: ClosedLidZeroBrightnessPhase = .disabled
    private(set) var lastError: String?
    private(set) var activeDisplayID: CGDirectDisplayID?
    private var recoveryRecord: ClosedLidBrightnessRecoveryRecord?
    private var cachedDisplayID: CGDirectDisplayID?
    private var started = false
    private var privateBrightnessApplied = false
    private var privateAttemptFailed = false
    private var restoreBlockedUntilEpochSeconds: Int64 = 0

    var availability: ClosedLidBrightnessAvailability { backend.availability }

    init(
        backend: ClosedLidBrightnessBackend,
        store: ClosedLidBrightnessRecoveryStoring,
        nowEpochSeconds: @escaping () -> Int64 = {
            Int64(Date().timeIntervalSince1970)
        }
    ) {
        self.backend = backend
        self.store = store
        self.nowEpochSeconds = nowEpochSeconds
        if let live = backend.builtInDisplayID() {
            cachedDisplayID = live
        }
    }

    func start() {
        guard !started else { return }
        started = true
        refreshCachedDisplay()
        if let pending = store.load() {
            recoveryRecord = pending
            cachedDisplayID = backend.builtInDisplayID() ?? pending.displayID
            _ = restorePending(force: true)
        } else {
            phase = backend.availability.isAvailable ? .ready : .failed
            lastError = backend.availability.reason
        }
    }

    func evaluate(
        enabled: Bool,
        sessionActive: Bool,
        lidState: LidState,
        externalDisplayCount: Int?
    ) -> ClosedLidBrightnessEvaluation {
        if !started { start() }
        refreshCachedDisplay()

        let wantsPrivatePath = enabled && sessionActive
        guard wantsPrivatePath else {
            guard restorePending(force: false) else {
                return evaluation(active: false, fallback: false, error: lastError)
            }
            privateAttemptFailed = false
            phase = enabled && backend.availability.isAvailable ? .ready : .disabled
            if !enabled { lastError = nil }
            return evaluation(active: false, fallback: false)
        }

        guard backend.availability.isAvailable else {
            guard restorePending(force: false) else {
                return evaluation(active: false, fallback: lidState == .closed, error: lastError)
            }
            return fail(
                backend.availability.reason ?? "Private brightness API unavailable",
                fallback: lidState == .closed
            )
        }

        guard externalDisplayCount == 0 else {
            guard restorePending(force: false) else {
                return evaluation(active: false, fallback: lidState == .closed, error: lastError)
            }
            let reason = externalDisplayCount == nil
                ? "External display state is unknown"
                : "An external display is connected"
            return fail(reason, fallback: lidState == .closed)
        }

        switch lidState {
        case .open:
            guard restorePending(force: false) else {
                return evaluation(active: false, fallback: false, error: lastError)
            }
            privateAttemptFailed = false
            phase = .ready
            lastError = nil
            return evaluation(active: false, fallback: false)
        case .unknown:
            guard restorePending(force: false) else {
                return evaluation(active: false, fallback: false, error: lastError)
            }
            return fail("Lid state is unknown", fallback: false)
        case .closed:
            break
        default:
            guard restorePending(force: false) else {
                return evaluation(active: false, fallback: false, error: lastError)
            }
            return fail("Lid state is unknown", fallback: false)
        }

        if privateBrightnessApplied,
           let record = recoveryRecord,
           (record.displayID == cachedDisplayID || cachedDisplayID == nil) {
            let state = backend.displayState(displayID: record.displayID)
            guard state.allowsCapture else {
                let restored = restorePending(force: true)
                privateAttemptFailed = true
                logger.error("Closed-lid display lost capture capability: \(state.diagnosticDescription, privacy: .public)")
                return fail(
                    restored
                        ? "Built-in display is not drawable: \(state.diagnosticDescription)"
                        : "Built-in display is not drawable and brightness restore failed: \(state.diagnosticDescription)",
                    fallback: true
                )
            }
            activeDisplayID = record.displayID
            phase = .active
            lastError = nil
            return evaluation(active: true, fallback: false)
        }

        if recoveryRecord != nil, !restorePending(force: false) {
            return evaluation(active: false, fallback: true, error: lastError)
        }

        guard let displayID = cachedDisplayID else {
            privateAttemptFailed = true
            return fail("No built-in display is available", fallback: true)
        }

        let now = nowEpochSeconds()
        if privateAttemptFailed {
            return evaluation(active: false, fallback: true, error: lastError)
        }

        do {
            let before = backend.displayState(displayID: displayID)
            guard before.allowsCapture else {
                privateAttemptFailed = true
                logger.error("Closed-lid display is not drawable: \(before.diagnosticDescription, privacy: .public)")
                return fail(
                    "Built-in display is not drawable: \(before.diagnosticDescription)",
                    fallback: true
                )
            }
            let original = try backend.readBrightness(displayID: displayID)
            let record = ClosedLidBrightnessRecoveryRecord(
                displayID: displayID,
                brightness: original,
                lidState: "closed",
                updatedAtEpochSeconds: nowEpochSeconds()
            )
            guard store.save(record) else {
                privateAttemptFailed = true
                return fail("Could not save the brightness recovery record", fallback: true)
            }
            recoveryRecord = record
            activeDisplayID = displayID

            try backend.setBrightness(0, displayID: displayID)
            let actual = try backend.readBrightness(displayID: displayID)
            guard abs(actual) <= Self.readbackTolerance else {
                let restored = restorePending(force: true)
                privateAttemptFailed = true
                return fail(
                    restored
                        ? "Brightness readback did not reach zero (\(actual))"
                        : "Brightness readback did not reach zero (\(actual)); restore also failed",
                    fallback: true
                )
            }

            let after = backend.displayState(displayID: displayID)
            guard after.allowsCapture else {
                let restored = restorePending(force: true)
                privateAttemptFailed = true
                logger.error("Closed-lid display became unavailable after brightness zero: \(after.diagnosticDescription, privacy: .public)")
                return fail(
                    restored
                        ? "Built-in display became unavailable after brightness zero: \(after.diagnosticDescription)"
                        : "Built-in display became unavailable and brightness restore failed: \(after.diagnosticDescription)",
                    fallback: true
                )
            }

            phase = .active
            privateBrightnessApplied = true
            privateAttemptFailed = false
            lastError = nil
            logger.info("Closed-lid display is drawable at zero brightness: \(after.diagnosticDescription, privacy: .public)")
            return evaluation(active: true, fallback: false)
        } catch {
            let message = error.localizedDescription
            let restored = restorePending(force: true)
            privateAttemptFailed = true
            return fail(
                restored ? message : "\(message); brightness restore also failed",
                fallback: true
            )
        }
    }

    @discardableResult
    func restoreNow() -> Bool {
        restorePending(force: true)
    }

    func stop() {
        guard started else { return }
        let restored = restorePending(force: true)
        started = false
        if restored {
            phase = .disabled
        }
    }

    private func refreshCachedDisplay() {
        if let live = backend.builtInDisplayID() {
            cachedDisplayID = live
        }
    }

    @discardableResult
    private func restorePending(force: Bool) -> Bool {
        guard let record = recoveryRecord else {
            recoveryRecord = nil
            activeDisplayID = nil
            privateBrightnessApplied = false
            return true
        }
        let targetDisplayID = backend.builtInDisplayID() ?? record.displayID
        recoveryRecord = record
        cachedDisplayID = targetDisplayID
        activeDisplayID = targetDisplayID
        privateBrightnessApplied = false

        let now = nowEpochSeconds()
        guard force || now >= restoreBlockedUntilEpochSeconds else { return false }

        guard backend.availability.isAvailable else {
            restoreBlockedUntilEpochSeconds = now + Self.restoreRetryIntervalSeconds
            phase = .failed
            lastError = backend.availability.reason ?? "Private brightness API unavailable"
            return false
        }

        do {
            try backend.setBrightness(record.brightness, displayID: targetDisplayID)
            let actual = try backend.readBrightness(displayID: targetDisplayID)
            guard abs(actual - record.brightness) <= Self.readbackTolerance else {
                restoreBlockedUntilEpochSeconds = now + Self.restoreRetryIntervalSeconds
                phase = .failed
                lastError = "Brightness restore readback mismatch (\(actual))"
                return false
            }
            guard store.clear() else {
                restoreBlockedUntilEpochSeconds = now + Self.restoreRetryIntervalSeconds
                phase = .failed
                lastError = "Brightness was restored but the recovery record could not be cleared"
                return false
            }
            recoveryRecord = nil
            activeDisplayID = nil
            restoreBlockedUntilEpochSeconds = 0
            lastError = nil
            phase = backend.availability.isAvailable ? .ready : .disabled
            return true
        } catch {
            restoreBlockedUntilEpochSeconds = now + Self.restoreRetryIntervalSeconds
            phase = .failed
            lastError = error.localizedDescription
            return false
        }
    }

    private func fail(_ message: String, fallback: Bool) -> ClosedLidBrightnessEvaluation {
        phase = .failed
        lastError = message
        return evaluation(active: false, fallback: fallback, error: message)
    }

    private func evaluation(
        active: Bool,
        fallback: Bool,
        error: String? = nil
    ) -> ClosedLidBrightnessEvaluation {
        ClosedLidBrightnessEvaluation(
            privateBrightnessActive: active,
            fallbackToPublicDisplayOff: fallback,
            error: error
        )
    }
}
