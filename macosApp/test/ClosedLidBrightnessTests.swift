import CoreGraphics
import XCTest
@testable import Covio

@MainActor
final class ClosedLidBrightnessTests: XCTestCase {
    func testCloseJournalsThenZerosAndOpenRestores() {
        let events = EventLog()
        let backend = FakeClosedLidBrightnessBackend(events: events, brightness: 0.6)
        let store = FakeClosedLidBrightnessRecoveryStore(events: events)
        let controller = ClosedLidZeroBrightnessController(backend: backend, store: store)

        controller.start()
        let closed = controller.evaluate(
            enabled: true,
            sessionActive: true,
            lidState: .closed,
            externalDisplayCount: 0
        )

        XCTAssertTrue(closed.privateBrightnessActive)
        XCTAssertFalse(closed.fallbackToPublicDisplayOff)
        XCTAssertEqual(backend.brightness, 0)
        XCTAssertEqual(store.record?.brightness, 0.6)
        XCTAssertEqual(events.values, ["journal-save", "brightness-0.0"])

        let opened = controller.evaluate(
            enabled: true,
            sessionActive: false,
            lidState: .open,
            externalDisplayCount: 0
        )

        XCTAssertFalse(opened.privateBrightnessActive)
        XCTAssertEqual(backend.brightness, 0.6, accuracy: 0.001)
        XCTAssertNil(store.record)
        XCTAssertEqual(controller.phase, .ready)
    }

    func testCachedDisplayIsUsedAfterThePanelLeavesTheDisplayList() {
        let backend = FakeClosedLidBrightnessBackend(brightness: 0.5)
        let store = FakeClosedLidBrightnessRecoveryStore()
        let controller = ClosedLidZeroBrightnessController(backend: backend, store: store)
        controller.start()
        backend.lookupDisplayID = nil

        let result = controller.evaluate(
            enabled: true,
            sessionActive: true,
            lidState: .closed,
            externalDisplayCount: 0
        )

        XCTAssertTrue(result.privateBrightnessActive)
        XCTAssertEqual(backend.setValues, [0])
        XCTAssertEqual(store.record?.displayID, backend.fixedDisplayID)
    }

    func testInactiveDisplayWritesNothingAndFallsBack() {
        let backend = FakeClosedLidBrightnessBackend(brightness: 0.5)
        backend.displayIsActive = false
        let store = FakeClosedLidBrightnessRecoveryStore()
        let controller = ClosedLidZeroBrightnessController(backend: backend, store: store)
        controller.start()

        let result = controller.evaluate(
            enabled: true,
            sessionActive: true,
            lidState: .closed,
            externalDisplayCount: 0
        )

        XCTAssertFalse(result.privateBrightnessActive)
        XCTAssertTrue(result.fallbackToPublicDisplayOff)
        XCTAssertTrue(backend.setValues.isEmpty)
        XCTAssertNil(store.record)
        XCTAssertEqual(controller.phase, .failed)
        XCTAssertTrue(controller.lastError?.contains("active=0") == true)
    }

    func testDisplayBecomingAsleepAfterZeroRestoresAndFallsBack() {
        let backend = FakeClosedLidBrightnessBackend(brightness: 0.5)
        backend.asleepAfterZero = true
        let store = FakeClosedLidBrightnessRecoveryStore()
        let controller = ClosedLidZeroBrightnessController(backend: backend, store: store)
        controller.start()

        let result = controller.evaluate(
            enabled: true,
            sessionActive: true,
            lidState: .closed,
            externalDisplayCount: 0
        )

        XCTAssertFalse(result.privateBrightnessActive)
        XCTAssertTrue(result.fallbackToPublicDisplayOff)
        XCTAssertEqual(backend.setValues, [0, 0.5])
        XCTAssertEqual(backend.brightness, 0.5, accuracy: 0.001)
        XCTAssertNil(store.record)
        XCTAssertEqual(controller.phase, .failed)
        XCTAssertTrue(controller.lastError?.contains("asleep=1") == true)
    }

    func testUnknownLidWritesNothing() {
        let backend = FakeClosedLidBrightnessBackend(brightness: 0.5)
        let store = FakeClosedLidBrightnessRecoveryStore()
        let controller = ClosedLidZeroBrightnessController(backend: backend, store: store)
        controller.start()

        let result = controller.evaluate(
            enabled: true,
            sessionActive: true,
            lidState: .unknown,
            externalDisplayCount: 0
        )

        XCTAssertFalse(result.privateBrightnessActive)
        XCTAssertFalse(result.fallbackToPublicDisplayOff)
        XCTAssertTrue(backend.setValues.isEmpty)
        XCTAssertNil(store.record)
    }

    func testExternalDisplayWritesNothing() {
        let backend = FakeClosedLidBrightnessBackend(brightness: 0.5)
        let store = FakeClosedLidBrightnessRecoveryStore()
        let controller = ClosedLidZeroBrightnessController(backend: backend, store: store)
        controller.start()

        let result = controller.evaluate(
            enabled: true,
            sessionActive: true,
            lidState: .closed,
            externalDisplayCount: 1
        )

        XCTAssertFalse(result.privateBrightnessActive)
        XCTAssertTrue(result.fallbackToPublicDisplayOff)
        XCTAssertTrue(backend.setValues.isEmpty)
    }

    func testUnavailableBackendNeverWrites() {
        let backend = FakeClosedLidBrightnessBackend(brightness: 0.5)
        backend.availability = .unavailable("unmeasured macOS")
        let controller = ClosedLidZeroBrightnessController(
            backend: backend,
            store: FakeClosedLidBrightnessRecoveryStore()
        )
        controller.start()

        let result = controller.evaluate(
            enabled: true,
            sessionActive: true,
            lidState: .closed,
            externalDisplayCount: 0
        )

        XCTAssertFalse(result.privateBrightnessActive)
        XCTAssertTrue(result.fallbackToPublicDisplayOff)
        XCTAssertTrue(backend.setValues.isEmpty)
        XCTAssertEqual(controller.phase, .failed)
    }

    func testWriteFailureRestoresTheOriginalBrightness() {
        let backend = FakeClosedLidBrightnessBackend(brightness: 0.6)
        backend.failingSetValues = [0]
        let store = FakeClosedLidBrightnessRecoveryStore()
        let controller = ClosedLidZeroBrightnessController(backend: backend, store: store)
        controller.start()

        let result = controller.evaluate(
            enabled: true,
            sessionActive: true,
            lidState: .closed,
            externalDisplayCount: 0
        )

        XCTAssertFalse(result.privateBrightnessActive)
        XCTAssertTrue(result.fallbackToPublicDisplayOff)
        XCTAssertEqual(backend.brightness, 0.6, accuracy: 0.001)
        XCTAssertEqual(backend.setValues, [0, 0.6])
        XCTAssertNil(store.record)
    }

    func testFailedPrivateAttemptWaitsForANewLidCycle() {
        let backend = FakeClosedLidBrightnessBackend(brightness: 0.6)
        backend.failingSetValues = [0]
        let controller = ClosedLidZeroBrightnessController(
            backend: backend,
            store: FakeClosedLidBrightnessRecoveryStore()
        )
        controller.start()

        _ = controller.evaluate(
            enabled: true,
            sessionActive: true,
            lidState: .closed,
            externalDisplayCount: 0
        )
        XCTAssertEqual(backend.setValues, [0, 0.6])

        let retried = controller.evaluate(
            enabled: true,
            sessionActive: true,
            lidState: .closed,
            externalDisplayCount: 0
        )
        XCTAssertTrue(retried.fallbackToPublicDisplayOff)
        XCTAssertEqual(backend.setValues, [0, 0.6])

        let opened = controller.evaluate(
            enabled: true,
            sessionActive: false,
            lidState: .open,
            externalDisplayCount: 0
        )
        XCTAssertFalse(opened.privateBrightnessActive)

        _ = controller.evaluate(
            enabled: true,
            sessionActive: true,
            lidState: .closed,
            externalDisplayCount: 0
        )
        XCTAssertEqual(backend.setValues, [0, 0.6, 0, 0.6])
    }

    func testReadbackMismatchRestoresAndFallsBack() {
        let backend = FakeClosedLidBrightnessBackend(brightness: 0.6)
        backend.readbackAfterZero = 0.5
        let store = FakeClosedLidBrightnessRecoveryStore()
        let controller = ClosedLidZeroBrightnessController(backend: backend, store: store)
        controller.start()

        let result = controller.evaluate(
            enabled: true,
            sessionActive: true,
            lidState: .closed,
            externalDisplayCount: 0
        )

        XCTAssertFalse(result.privateBrightnessActive)
        XCTAssertTrue(result.fallbackToPublicDisplayOff)
        XCTAssertEqual(backend.brightness, 0.6, accuracy: 0.001)
        XCTAssertNil(store.record)
    }

    func testRecoveryJournalFailurePreventsTheZeroWrite() {
        let backend = FakeClosedLidBrightnessBackend(brightness: 0.6)
        let store = FakeClosedLidBrightnessRecoveryStore()
        store.saveSucceeds = false
        let controller = ClosedLidZeroBrightnessController(backend: backend, store: store)
        controller.start()

        let result = controller.evaluate(
            enabled: true,
            sessionActive: true,
            lidState: .closed,
            externalDisplayCount: 0
        )

        XCTAssertFalse(result.privateBrightnessActive)
        XCTAssertTrue(result.fallbackToPublicDisplayOff)
        XCTAssertTrue(backend.setValues.isEmpty)
    }

    func testStartupRestoresAPersistedRecord() {
        let backend = FakeClosedLidBrightnessBackend(brightness: 0)
        let store = FakeClosedLidBrightnessRecoveryStore(
            record: ClosedLidBrightnessRecoveryRecord(
                displayID: 7,
                brightness: 0.42,
                lidState: "closed",
                updatedAtEpochSeconds: 900
            )
        )
        let controller = ClosedLidZeroBrightnessController(backend: backend, store: store)

        controller.start()

        XCTAssertEqual(backend.brightness, 0.42, accuracy: 0.001)
        XCTAssertNil(store.record)
        XCTAssertEqual(controller.phase, .ready)
    }

    func testFailedRestoreIsRateLimitedInsteadOfRetryingEveryRefresh() {
        var now: Int64 = 1_000
        let backend = FakeClosedLidBrightnessBackend(brightness: 0)
        backend.failAllSets = true
        let store = FakeClosedLidBrightnessRecoveryStore(
            record: ClosedLidBrightnessRecoveryRecord(
                displayID: 7,
                brightness: 0.42,
                lidState: "closed",
                updatedAtEpochSeconds: 900
            )
        )
        let controller = ClosedLidZeroBrightnessController(
            backend: backend,
            store: store,
            nowEpochSeconds: { now }
        )

        controller.start()
        XCTAssertEqual(backend.setValues.count, 1)

        _ = controller.evaluate(
            enabled: false,
            sessionActive: false,
            lidState: .open,
            externalDisplayCount: 0
        )
        XCTAssertEqual(backend.setValues.count, 1)

        now += ClosedLidZeroBrightnessController.restoreRetryIntervalSeconds
        _ = controller.evaluate(
            enabled: false,
            sessionActive: false,
            lidState: .open,
            externalDisplayCount: 0
        )
        XCTAssertEqual(backend.setValues.count, 2)
        XCTAssertNotNil(store.record)
    }

    func testRapidCloseOpenCyclesAlwaysRestore() {
        let backend = FakeClosedLidBrightnessBackend(brightness: 0.6)
        let store = FakeClosedLidBrightnessRecoveryStore()
        let controller = ClosedLidZeroBrightnessController(backend: backend, store: store)
        controller.start()

        for _ in 0 ..< 4 {
            let closed = controller.evaluate(
                enabled: true,
                sessionActive: true,
                lidState: .closed,
                externalDisplayCount: 0
            )
            XCTAssertTrue(closed.privateBrightnessActive)
            XCTAssertEqual(backend.brightness, 0)

            let opened = controller.evaluate(
                enabled: true,
                sessionActive: false,
                lidState: .open,
                externalDisplayCount: 0
            )
            XCTAssertFalse(opened.privateBrightnessActive)
            XCTAssertEqual(backend.brightness, 0.6, accuracy: 0.001)
        }

        XCTAssertNil(store.record)
    }

    func testDisablingTheExperimentRestoresWhileTheLidIsStillClosed() {
        let backend = FakeClosedLidBrightnessBackend(brightness: 0.6)
        let store = FakeClosedLidBrightnessRecoveryStore()
        let controller = ClosedLidZeroBrightnessController(backend: backend, store: store)
        controller.start()
        _ = controller.evaluate(
            enabled: true,
            sessionActive: true,
            lidState: .closed,
            externalDisplayCount: 0
        )

        _ = controller.evaluate(
            enabled: false,
            sessionActive: true,
            lidState: .closed,
            externalDisplayCount: 0
        )

        XCTAssertEqual(backend.brightness, 0.6, accuracy: 0.001)
        XCTAssertNil(store.record)
        XCTAssertEqual(controller.phase, .disabled)
    }

    func testControllerStopRestoresTheOriginalBrightness() {
        let backend = FakeClosedLidBrightnessBackend(brightness: 0.6)
        let store = FakeClosedLidBrightnessRecoveryStore()
        let controller = ClosedLidZeroBrightnessController(backend: backend, store: store)
        controller.start()
        _ = controller.evaluate(
            enabled: true,
            sessionActive: true,
            lidState: .closed,
            externalDisplayCount: 0
        )

        controller.stop()

        XCTAssertEqual(backend.brightness, 0.6, accuracy: 0.001)
        XCTAssertNil(store.record)
        XCTAssertEqual(controller.phase, .disabled)
    }

    func testRecoveryRecordIsRetainedWhenClearFails() {
        let backend = FakeClosedLidBrightnessBackend(brightness: 0)
        let store = FakeClosedLidBrightnessRecoveryStore(
            record: ClosedLidBrightnessRecoveryRecord(
                displayID: 7,
                brightness: 0.42,
                lidState: "closed",
                updatedAtEpochSeconds: 900
            )
        )
        store.clearSucceeds = false
        let controller = ClosedLidZeroBrightnessController(backend: backend, store: store)

        controller.start()

        XCTAssertEqual(backend.brightness, 0.42, accuracy: 0.001)
        XCTAssertNotNil(store.record)
        XCTAssertEqual(controller.phase, .failed)
        XCTAssertNotNil(controller.lastError)
    }

    func testUnmeasuredMacOSRefusesToLoadPrivateSymbols() {
        let backend = DisplayServicesBrightnessBackend(osMajorVersion: 26)

        XCTAssertEqual(
            backend.availability,
            .unavailable("DisplayServices brightness is not verified on macOS 26")
        )
    }

    func testRecoveryStoreRoundTripsAndIgnoresInvalidRecords() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("covio-brightness-store-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("recovery.json")
        let store = JSONClosedLidBrightnessRecoveryStore(fileURL: url)
        let record = ClosedLidBrightnessRecoveryRecord(
            displayID: 7,
            brightness: 0.42,
            lidState: "closed",
            updatedAtEpochSeconds: 900
        )

        XCTAssertTrue(store.save(record))
        XCTAssertEqual(store.load(), record)
        XCTAssertTrue(store.clear())
        XCTAssertNil(store.load())

        try Data(#"{"displayID":0,"brightness":0.4,"lidState":"closed","updatedAtEpochSeconds":1}"#.utf8)
            .write(to: url)
        XCTAssertNil(store.load())
    }
}

final class EventLog {
    private(set) var values: [String] = []
    func append(_ value: String) { values.append(value) }
}

final class FakeClosedLidBrightnessBackend: ClosedLidBrightnessBackend {
    let fixedDisplayID: CGDirectDisplayID = 7
    var lookupDisplayID: CGDirectDisplayID? = 7
    var availability: ClosedLidBrightnessAvailability = .available
    var brightness: Float
    var failingSetValues: Set<Float> = []
    var failAllSets = false
    var readbackAfterZero: Float?
    var displayIsOnline = true
    var displayIsActive = true
    var displayIsAsleep = false
    var asleepAfterZero = false
    private(set) var setValues: [Float] = []
    private let events: EventLog?

    init(events: EventLog? = nil, brightness: Float) {
        self.events = events
        self.brightness = brightness
    }

    func builtInDisplayID() -> CGDirectDisplayID? { lookupDisplayID }

    func displayState(displayID: CGDirectDisplayID) -> ClosedLidDisplayState {
        ClosedLidDisplayState(
            displayID: displayID,
            isOnline: displayIsOnline,
            isActive: displayIsActive,
            isAsleep: displayIsAsleep
        )
    }

    func readBrightness(displayID: CGDirectDisplayID) throws -> Float {
        brightness
    }

    func setBrightness(_ brightness: Float, displayID: CGDirectDisplayID) throws {
        setValues.append(brightness)
        events?.append("brightness-\(brightness)")
        if failAllSets || failingSetValues.contains(brightness) {
            throw ClosedLidBrightnessBackendError.writeFailed(-1)
        }
        if brightness == 0, let readbackAfterZero {
            self.brightness = readbackAfterZero
        } else {
            self.brightness = brightness
        }
        if brightness == 0, asleepAfterZero {
            displayIsAsleep = true
        }
    }
}

final class FakeClosedLidBrightnessRecoveryStore: ClosedLidBrightnessRecoveryStoring {
    var record: ClosedLidBrightnessRecoveryRecord?
    var saveSucceeds = true
    var clearSucceeds = true
    private(set) var saveCalls = 0
    private(set) var clearCalls = 0
    private let events: EventLog?

    init(
        events: EventLog? = nil,
        record: ClosedLidBrightnessRecoveryRecord? = nil
    ) {
        self.events = events
        self.record = record
    }

    func load() -> ClosedLidBrightnessRecoveryRecord? { record }

    func save(_ record: ClosedLidBrightnessRecoveryRecord) -> Bool {
        saveCalls += 1
        guard saveSucceeds else { return false }
        events?.append("journal-save")
        self.record = record
        return true
    }

    func clear() -> Bool {
        clearCalls += 1
        guard clearSucceeds else { return false }
        record = nil
        return true
    }
}
