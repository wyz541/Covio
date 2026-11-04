import XCTest
@testable import Covio

final class FanControlRuntimeTests: XCTestCase {
    func testManualConfigurationWritesClampedTargetAndShutdownReleases() {
        let reader = FakeFanReader()
        let writer = FakeFanWriter()
        let runtime = makeRuntime(reader: reader, writer: writer)

        let configureReply = runtime.handle(request(
            HelperWire.shared.COMMAND_FAN_CONTROL_CONFIGURE,
            payload: MonitorFanConfiguration(
                enabled: true,
                mode: .manual,
                manualRPM: ["0": 9_000],
                manualModes: ["0": .manual]
            ).helperPayload()
        ))

        XCTAssertEqual(configureReply?.ok, true)
        XCTAssertEqual(writer.targets[0], 4_800)
        XCTAssertEqual(writer.holdCalls, 1)
        XCTAssertEqual(status(runtime)["active"], "true")

        runtime.shutdown()

        XCTAssertEqual(writer.releaseAllCalls, 1)
        XCTAssertEqual(writer.holdingCount, 0)
        XCTAssertEqual(status(runtime)["state"], "system")
    }

    func testExpiredLeaseRestoresSystemControl() {
        let reader = FakeFanReader()
        let writer = FakeFanWriter()
        let clock = FakeFanClock()
        let runtime = makeRuntime(reader: reader, writer: writer, clock: clock)

        _ = runtime.handle(request(
            HelperWire.shared.COMMAND_FAN_CONTROL_CONFIGURE,
            payload: manualConfiguration(rpm: 2_400).helperPayload()
        ))
        clock.advance(seconds: 20.1)
        runtime.driveControlCycle()

        XCTAssertEqual(writer.releaseAllCalls, 1)
        XCTAssertEqual(writer.holdingCount, 0)
        XCTAssertEqual(status(runtime)["state"], "system")
        XCTAssertEqual(status(runtime)["active"], "false")
    }

    func testThreeWriteFailuresRestoreSystemControlAndExposeError() {
        let reader = FakeFanReader()
        let writer = FakeFanWriter()
        writer.writeError = FakeFanError.writeFailed
        let runtime = makeRuntime(reader: reader, writer: writer)

        _ = runtime.handle(request(
            HelperWire.shared.COMMAND_FAN_CONTROL_CONFIGURE,
            payload: manualConfiguration(rpm: 2_400).helperPayload()
        ))
        runtime.driveControlCycle()
        runtime.driveControlCycle()

        let result = status(runtime)
        XCTAssertEqual(writer.releaseAllCalls, 1)
        XCTAssertEqual(writer.holdingCount, 0)
        XCTAssertEqual(result["state"], "error")
        XCTAssertEqual(result["active"], "false")
        XCTAssertEqual(result["error"], FakeFanError.writeFailed.description)
    }

    func testCurveTemperatureUsesHysteresisBeforeDropping() {
        let reader = FakeFanReader()
        let writer = FakeFanWriter()
        let runtime = makeRuntime(reader: reader, writer: writer)
        let configuration = MonitorFanConfiguration(
            enabled: true,
            mode: .curve,
            selectedSensorKeys: ["TCMz"],
            curves: [
                "0": [
                    MonitorFanCurvePoint(temperature: 40, rpm: 1_200),
                    MonitorFanCurvePoint(temperature: 100, rpm: 4_800),
                ],
            ]
        )

        _ = runtime.handle(request(
            HelperWire.shared.COMMAND_FAN_CONTROL_CONFIGURE,
            payload: configuration.helperPayload()
        ))
        XCTAssertEqual(status(runtime)["controlTemperature"], "70.00")

        reader.snapshot = snapshot(temperature: 69)
        runtime.driveControlCycle()
        XCTAssertEqual(status(runtime)["controlTemperature"], "70.00")

        reader.snapshot = snapshot(temperature: 68.4)
        runtime.driveControlCycle()
        XCTAssertEqual(status(runtime)["controlTemperature"], "68.40")
    }

    func testTemperatureRulesUseWidestFanRequest() throws {
        let reader = FakeFanReader()
        let writer = FakeFanWriter()
        let runtime = makeRuntime(reader: reader, writer: writer)
        reader.snapshot = SMCFanReadingSnapshot(
            temperatures: [
                SMCTemperatureReading(key: "TCMz", celsius: 70),
                SMCTemperatureReading(key: "Tg0D", celsius: 50),
                SMCTemperatureReading(key: "TB0T", celsius: 32),
            ],
            fans: [
                SMCFanReading(
                    index: 0,
                    rpm: 1_000,
                    minimumRPM: 1_000,
                    maximumRPM: 5_000,
                    targetRPM: 0,
                    mode: 0
                ),
                SMCFanReading(
                    index: 1,
                    rpm: 1_200,
                    minimumRPM: 1_200,
                    maximumRPM: 6_000,
                    targetRPM: 0,
                    mode: 0
                ),
            ]
        )
        let configuration = MonitorFanConfiguration(
            enabled: true,
            mode: .curve,
            temperatureRules: [
                "cpu": [
                    .init(celsius: 60, fanPercent: 20),
                    .init(celsius: 80, fanPercent: 60),
                ],
                "gpu": [
                    .init(celsius: 40, fanPercent: 10),
                    .init(celsius: 60, fanPercent: 30),
                ],
                "battery": [
                    .init(celsius: 32, fanPercent: 30),
                    .init(celsius: 34, fanPercent: 50),
                ],
            ]
        )

        let reply = runtime.handle(request(
            HelperWire.shared.COMMAND_FAN_CONTROL_CONFIGURE,
            payload: configuration.helperPayload()
        ))

        XCTAssertEqual(reply?.ok, true)
        XCTAssertEqual(writer.targets[0], 2_000)
        XCTAssertEqual(writer.targets[1], 2_400)
        let sourceText = try XCTUnwrap(status(runtime)["sourceTemperatures"])
        let sourceValues = try JSONDecoder().decode(
            [String: Double].self,
            from: Data(sourceText.utf8)
        )
        XCTAssertEqual(sourceValues["cpu"], 70)
        XCTAssertEqual(sourceValues["gpu"], 50)
        XCTAssertEqual(sourceValues["battery"], 32)
    }

    func testTemperatureRulesFailOverToAnAvailableSource() {
        let reader = FakeFanReader()
        let writer = FakeFanWriter()
        let runtime = makeRuntime(reader: reader, writer: writer)
        reader.snapshot = SMCFanReadingSnapshot(
            temperatures: [
                SMCTemperatureReading(key: "TA0P", celsius: 25),
                SMCTemperatureReading(key: "TB0T", celsius: 32),
            ],
            fans: [
                SMCFanReading(
                    index: 0,
                    rpm: 1_000,
                    minimumRPM: 1_000,
                    maximumRPM: 5_000,
                    targetRPM: 0,
                    mode: 0
                ),
            ]
        )
        let configuration = MonitorFanConfiguration(
            enabled: true,
            mode: .curve,
            temperatureRules: [
                "gpu": [
                    .init(celsius: 40, fanPercent: 10),
                    .init(celsius: 60, fanPercent: 30),
                ],
                "battery": [
                    .init(celsius: 32, fanPercent: 30),
                    .init(celsius: 34, fanPercent: 50),
                ],
            ]
        )

        _ = runtime.handle(request(
            HelperWire.shared.COMMAND_FAN_CONTROL_CONFIGURE,
            payload: configuration.helperPayload()
        ))

        XCTAssertEqual(writer.targets[0], 1_500)
        XCTAssertEqual(status(runtime)["active"], "true")
    }

    func testTemperatureRulesRestoreWhenEveryConfiguredSourceIsMissing() {
        let reader = FakeFanReader()
        let writer = FakeFanWriter()
        let runtime = makeRuntime(reader: reader, writer: writer)
        reader.snapshot = snapshot(temperature: 25, key: "TA0P")
        let configuration = MonitorFanConfiguration(
            enabled: true,
            mode: .curve,
            temperatureRules: [
                "battery": [
                    .init(celsius: 32, fanPercent: 30),
                    .init(celsius: 34, fanPercent: 50),
                ],
            ]
        )

        _ = runtime.handle(request(
            HelperWire.shared.COMMAND_FAN_CONTROL_CONFIGURE,
            payload: configuration.helperPayload()
        ))
        runtime.driveControlCycle()
        runtime.driveControlCycle()

        XCTAssertEqual(writer.releaseAllCalls, 1)
        XCTAssertEqual(status(runtime)["state"], "error")
        XCTAssertEqual(status(runtime)["active"], "false")
    }

    @MainActor
    func testHelperStatusErrorIsVisibleWithoutACommandMessage() {
        let model = MonitorFanControlModel(
            previewConfiguration: .defaultValue,
            availability: .ready,
            helperStatus: FanControlHelperStatus(
                active: false,
                mode: "system",
                controlTemperature: nil,
                leaseRemainingSeconds: 0,
                error: "Fan control write failed"
            )
        )

        XCTAssertEqual(model.visibleErrorMessage, "Fan control write failed")
    }

    private func makeRuntime(
        reader: FakeFanReader,
        writer: FakeFanWriter,
        clock: FakeFanClock = FakeFanClock()
    ) -> FanControlRuntime {
        FanControlRuntime(
            now: clock.now,
            schedulesTimer: false,
            hardwareFactory: {
                FanControlHardware(reader: reader, writer: writer)
            }
        )
    }

    private func manualConfiguration(rpm: Double) -> MonitorFanConfiguration {
        MonitorFanConfiguration(
            enabled: true,
            mode: .manual,
            manualRPM: ["0": rpm],
            manualModes: ["0": .manual]
        )
    }

    private func request(
        _ command: String,
        payload: [String: String] = [:]
    ) -> HelperRequest {
        HelperRequest(
            version: HelperProtocol.protocolVersion,
            requestId: UUID().uuidString,
            command: command,
            payload: payload
        )
    }

    private func status(_ runtime: FanControlRuntime) -> [String: String] {
        let reply = runtime.handle(request(HelperWire.shared.COMMAND_FAN_CONTROL_STATUS))
        XCTAssertEqual(reply?.ok, true)
        return reply?.result ?? [:]
    }

    private func snapshot(
        temperature: Double,
        key: String = "TCMz"
    ) -> SMCFanReadingSnapshot {
        SMCFanReadingSnapshot(
            temperatures: [SMCTemperatureReading(key: key, celsius: temperature)],
            fans: [
                SMCFanReading(
                    index: 0,
                    rpm: 1_200,
                    minimumRPM: 1_200,
                    maximumRPM: 4_800,
                    targetRPM: 0,
                    mode: 0
                ),
            ]
        )
    }
}

private enum FakeFanError: Error, CustomStringConvertible {
    case writeFailed

    var description: String { "Fan control write failed" }
}

private final class FakeFanClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date(timeIntervalSince1970: 1_000)

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func advance(seconds: TimeInterval) {
        lock.lock()
        value = value.addingTimeInterval(seconds)
        lock.unlock()
    }
}

private final class FakeFanReader: FanControlTemperatureReading, @unchecked Sendable {
    var snapshot = SMCFanReadingSnapshot(
        temperatures: [SMCTemperatureReading(key: "TCMz", celsius: 70)],
        fans: [
            SMCFanReading(
                index: 0,
                rpm: 1_200,
                minimumRPM: 1_200,
                maximumRPM: 4_800,
                targetRPM: 0,
                mode: 0
            ),
        ]
    )

    func read(sensorKeys: Set<String>?) -> SMCFanReadingSnapshot {
        snapshot
    }
}

private final class FakeFanWriter: FanControlFanWriting, @unchecked Sendable {
    private(set) var heldFans: Set<Int> = []
    private(set) var targets: [Int: Double] = [:]
    private(set) var holdCalls = 0
    private(set) var releaseAllCalls = 0
    var writeError: Error?

    var holdingCount: Int { heldFans.count }

    func isHolding(_ index: Int) -> Bool {
        heldFans.contains(index)
    }

    func hold(_ index: Int) throws {
        holdCalls += 1
        heldFans.insert(index)
    }

    func ensureHeld(_ index: Int) throws {
        heldFans.insert(index)
    }

    func writeTarget(_ index: Int, rpm: Double) throws {
        if let writeError { throw writeError }
        targets[index] = rpm
    }

    func release(_ index: Int) throws {
        heldFans.remove(index)
    }

    func releaseAll() throws {
        releaseAllCalls += 1
        heldFans.removeAll()
    }
}
