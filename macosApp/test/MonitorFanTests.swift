import XCTest
@testable import Covio

final class MonitorFanTests: XCTestCase {
    func testAdvancedSettingsExpandForCovioModes() {
        XCTAssertFalse(MonitorFanPolicy.expandsAdvanced(for: .automatic))
        XCTAssertTrue(MonitorFanPolicy.expandsAdvanced(for: .curve))
        XCTAssertTrue(MonitorFanPolicy.expandsAdvanced(for: .manual))
    }

    @MainActor
    func testGlobalHelperStatusMapsToFanAvailability() {
        XCTAssertEqual(MonitorFanControlModel.helperAvailability(for: .match), .ready)
        XCTAssertEqual(MonitorFanControlModel.helperAvailability(for: .missing), .missing)
        XCTAssertEqual(MonitorFanControlModel.helperAvailability(for: .outdated), .outdated)
        XCTAssertEqual(MonitorFanControlModel.helperAvailability(for: .identityMismatch), .outdated)
        XCTAssertEqual(MonitorFanControlModel.helperAvailability(for: .untrusted), .unavailable)
        XCTAssertEqual(MonitorFanControlModel.helperAvailability(for: nil), .unavailable)
    }

    func testCurveClampsAtFanLimits() {
        XCTAssertEqual(
            MonitorFanCurve.target(
                temperature: 50,
                startCelsius: 60,
                fullCelsius: 90,
                minimumRPM: 1_500,
                maximumRPM: 5_000
            ),
            1_500
        )
        XCTAssertEqual(
            MonitorFanCurve.target(
                temperature: 100,
                startCelsius: 60,
                fullCelsius: 90,
                minimumRPM: 1_500,
                maximumRPM: 5_000
            ),
            5_000
        )
    }

    func testCurveInterpolatesLinearly() {
        XCTAssertEqual(
            MonitorFanCurve.target(
                temperature: 75,
                startCelsius: 60,
                fullCelsius: 90,
                minimumRPM: 1_500,
                maximumRPM: 5_500
            ),
            3_500,
            accuracy: 0.001
        )
    }

    func testMultiPointCurveInterpolatesBetweenNearestPoints() {
        let points = [
            MonitorFanCurvePoint(temperature: 40, rpm: 1_200),
            MonitorFanCurvePoint(temperature: 65, rpm: 2_400),
            MonitorFanCurvePoint(temperature: 85, rpm: 4_800),
        ]

        XCTAssertEqual(
            MonitorFanCurve.target(
                points: points,
                temperature: 75,
                minimumRPM: 1_200,
                maximumRPM: 5_800
            ),
            3_600,
            accuracy: 0.001
        )
        XCTAssertEqual(
            MonitorFanCurve.target(
                points: points,
                temperature: 30,
                minimumRPM: 1_200,
                maximumRPM: 5_800
            ),
            1_200
        )
        XCTAssertEqual(
            MonitorFanCurve.target(
                points: points,
                temperature: 100,
                minimumRPM: 1_200,
                maximumRPM: 5_800
            ),
            4_800
        )
    }

    func testHysteresisPreventsSmallTemperatureDrops() {
        XCTAssertEqual(
            MonitorFanCurve.heldTemperature(current: 68.7, previous: 70),
            70,
            accuracy: 0.001
        )
        XCTAssertEqual(
            MonitorFanCurve.heldTemperature(current: 68.4, previous: 70),
            68.4,
            accuracy: 0.001
        )
        XCTAssertEqual(
            MonitorFanCurve.heldTemperature(current: 72, previous: 70),
            72,
            accuracy: 0.001
        )
    }

    func testConfigurationNormalizesCurveAndManualRPM() {
        let value = MonitorFanConfiguration(
            enabled: true,
            mode: .manual,
            startCelsius: 20,
            fullCelsius: 21,
            selectedSensorKeys: ["TCMz", "TCMz"],
            manualRPM: ["0": 900, "1": 9_000]
        ).normalized(
            fanMinimums: [0: 1_200],
            fanMaximums: [0: 5_000, 1: 6_000]
        )

        XCTAssertEqual(value.startCelsius, 35)
        XCTAssertEqual(value.fullCelsius, 40)
        XCTAssertEqual(value.selectedSensorKeys, ["TCMz"])
        XCTAssertEqual(value.manualRPM["0"], 1_200)
        XCTAssertEqual(value.manualRPM["1"], 6_000)
    }

    func testManualModesNormalizeAndDefaultToManual() {
        let value = MonitorFanConfiguration(
            mode: .manual,
            manualModes: [
                "0": .automatic,
                "1": .curve,
                "bad": .manual,
            ]
        ).normalized(fanMinimums: [0: 1_200, 1: 1_500])

        XCTAssertEqual(value.manualModes, ["0": .automatic, "1": .manual])
        XCTAssertEqual(value.controlMode(for: 0), .automatic)
        XCTAssertEqual(value.controlMode(for: 1), .manual)
        XCTAssertEqual(value.controlMode(for: 2), .manual)
    }

    func testCurveModeIgnoresPerFanManualModes() {
        let value = MonitorFanConfiguration(
            mode: .curve,
            manualModes: ["0": .automatic, "1": .manual]
        )

        XCTAssertEqual(value.controlMode(for: 0), .curve)
        XCTAssertEqual(value.controlMode(for: 1), .curve)
    }

    func testEachFanUsesItsOwnCurve() {
        let configuration = MonitorFanConfiguration(
            curves: [
                "0": [
                    MonitorFanCurvePoint(temperature: 40, rpm: 1_200),
                    MonitorFanCurvePoint(temperature: 90, rpm: 5_000),
                ],
                "1": [
                    MonitorFanCurvePoint(temperature: 40, rpm: 1_500),
                    MonitorFanCurvePoint(temperature: 90, rpm: 6_000),
                ],
            ]
        )

        XCTAssertEqual(
            configuration.target(
                fanIndex: 0,
                temperature: 65,
                minimumRPM: 1_200,
                maximumRPM: 5_000
            ),
            3_100,
            accuracy: 0.001
        )
        XCTAssertEqual(
            configuration.target(
                fanIndex: 1,
                temperature: 65,
                minimumRPM: 1_500,
                maximumRPM: 6_000
            ),
            3_750,
            accuracy: 0.001
        )
    }

    func testCurveNormalizationSortsDeduplicatesAndClamps() {
        let configuration = MonitorFanConfiguration(
            startCelsius: 58,
            fullCelsius: 86,
            curves: [
                "0": [
                    MonitorFanCurvePoint(temperature: 90, rpm: 9_000),
                    MonitorFanCurvePoint(temperature: 20, rpm: 200),
                    MonitorFanCurvePoint(temperature: 70, rpm: 2_505),
                    MonitorFanCurvePoint(temperature: 70, rpm: 2_600),
                ],
            ]
        ).normalized(
            fanMinimums: [0: 1_200],
            fanMaximums: [0: 5_000]
        )

        XCTAssertEqual(configuration.curves["0"]?.map(\.temperature), [40, 70, 90])
        XCTAssertEqual(configuration.curves["0"]?.map(\.rpm), [1_200, 2_600, 5_000])
    }

    func testCurveNormalizationKeepsBothEndpointsWhenReducingPointCount() {
        let points = (0..<12).map { index in
            MonitorFanCurvePoint(
                temperature: 40 + Double(index * 5),
                rpm: 1_200 + Double(index * 300)
            )
        }

        let normalized = MonitorFanCurve.normalized(
            points,
            minimumRPM: 1_200,
            maximumRPM: 5_800
        )

        XCTAssertEqual(normalized.count, MonitorFanPolicy.maximumCurvePointCount)
        XCTAssertEqual(normalized.first?.temperature, 40)
        XCTAssertEqual(normalized.last?.temperature, 95)
    }

    func testConfigurationRoundTripsPerFanCurves() throws {
        let original = MonitorFanConfiguration(
            enabled: true,
            mode: .curve,
            manualModes: ["0": .automatic, "1": .manual],
            syncFans: true,
            curves: [
                "0": [
                    MonitorFanCurvePoint(temperature: 45, rpm: 1_200),
                    MonitorFanCurvePoint(temperature: 78, rpm: 3_900),
                    MonitorFanCurvePoint(temperature: 92, rpm: 5_800),
                ],
            ]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MonitorFanConfiguration.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    func testLegacyConfigurationWithoutCurvesUsesTwoPointFallback() throws {
        let data = Data(
            """
            {"enabled":true,"mode":"automatic","startCelsius":58,"fullCelsius":86,
             "selectedSensorKeys":["TCMz"],"manualRPM":{}}
            """.utf8
        )
        let configuration = try JSONDecoder().decode(MonitorFanConfiguration.self, from: data)

        XCTAssertEqual(configuration.mode, .curve)
        XCTAssertTrue(configuration.manualModes.isEmpty)
        XCTAssertFalse(configuration.syncFans)
        XCTAssertTrue(configuration.curves.isEmpty)
        XCTAssertEqual(
            configuration.curvePoints(for: 0, minimumRPM: 1_200, maximumRPM: 5_800),
            [
                MonitorFanCurvePoint(temperature: 58, rpm: 1_200),
                MonitorFanCurvePoint(temperature: 86, rpm: 5_800),
            ]
        )
    }

    func testHelperPayloadRoundTripsPerFanCurves() throws {
        let payload = MonitorFanConfiguration(
            enabled: true,
            mode: .curve,
            curves: [
                "0": [
                    MonitorFanCurvePoint(temperature: 45, rpm: 1_200),
                    MonitorFanCurvePoint(temperature: 92, rpm: 5_800),
                ],
                "1": [
                    MonitorFanCurvePoint(temperature: 50, rpm: 1_300),
                    MonitorFanCurvePoint(temperature: 96, rpm: 6_000),
                ],
            ]
        ).helperPayload()
        let curveText = try XCTUnwrap(payload["curves"])
        let decoded = try JSONDecoder().decode(
            [String: [MonitorFanCurvePoint]].self,
            from: Data(curveText.utf8)
        )

        XCTAssertEqual(decoded["0"]?.first?.temperature, 45)
        XCTAssertEqual(decoded["1"]?.last?.rpm, 6_000)
    }

    func testHelperPayloadRoundTripsManualModes() throws {
        let payload = MonitorFanConfiguration(
            enabled: true,
            mode: .manual,
            manualModes: ["0": .automatic, "1": .manual]
        ).helperPayload()
        let modeText = try XCTUnwrap(payload["manualModes"])
        let decoded = try JSONDecoder().decode(
            [String: MonitorFanMode].self,
            from: Data(modeText.utf8)
        )

        XCTAssertEqual(decoded, ["0": .automatic, "1": .manual])
    }

    func testSystemAutomaticAndCurveUseDifferentHelperModes() {
        let automatic = MonitorFanConfiguration(
            enabled: true,
            mode: .automatic
        ).helperPayload()
        let curve = MonitorFanConfiguration(
            enabled: true,
            mode: .curve
        ).helperPayload()

        XCTAssertEqual(automatic["mode"], "auto")
        XCTAssertEqual(curve["mode"], "curve")
    }

    func testDisabledLegacyAutomaticConfigurationStaysSystemControlled() throws {
        let data = Data(#"{"enabled":false,"mode":"automatic"}"#.utf8)
        let configuration = try JSONDecoder().decode(MonitorFanConfiguration.self, from: data)

        XCTAssertEqual(configuration.mode, .automatic)
    }

    func testSynchronizedManualRPMUsesEachFanRange() {
        let units = [
            MonitorFanReading.Unit(
                index: 0,
                rpm: 3_500,
                minimumRPM: 1_200,
                maximumRPM: 5_800,
                targetRPM: 3_500,
                mode: 1
            ),
            MonitorFanReading.Unit(
                index: 1,
                rpm: 3_650,
                minimumRPM: 1_300,
                maximumRPM: 6_000,
                targetRPM: 3_650,
                mode: 1
            ),
        ]

        let targets = MonitorFanSpeedSync.targets(
            sourceFanIndex: 0,
            rpm: 3_500,
            units: units
        )

        XCTAssertEqual(targets, [0: 3_500, 1: 3_650])
    }

    @MainActor
    func testManualModeSwitchSynchronizesWhenEnabled() {
        let reading = MonitorFanReading(
            temperatures: [.init(key: "TCMz", celsius: 65)],
            units: [
                .init(index: 0, rpm: 2_200, minimumRPM: 1_200, maximumRPM: 5_000, targetRPM: 2_200, mode: 1),
                .init(index: 1, rpm: 2_300, minimumRPM: 1_300, maximumRPM: 6_000, targetRPM: 2_300, mode: 1),
            ]
        )
        let configuration = MonitorFanConfiguration(
            enabled: true,
            mode: .manual,
            manualModes: ["0": .manual, "1": .manual],
            syncFans: true
        )
        let model = MonitorFanControlModel(
            previewConfiguration: configuration,
            availability: .ready
        )

        model.setManualMode(.automatic, fanIndex: 0, reading: reading)

        XCTAssertEqual(model.manualMode(for: 0), .automatic)
        XCTAssertEqual(model.manualMode(for: 1), .automatic)

        var independentConfiguration = configuration
        independentConfiguration.syncFans = false
        let independent = MonitorFanControlModel(
            previewConfiguration: independentConfiguration,
            availability: .ready
        )
        independent.setManualMode(.automatic, fanIndex: 0, reading: reading)

        XCTAssertEqual(independent.manualMode(for: 0), .automatic)
        XCTAssertEqual(independent.manualMode(for: 1), .manual)
    }

    @MainActor
    func testManualRPMWriteUsesThreeHundredMillisecondDebounce() async {
        let reading = MonitorFanReading(
            temperatures: [.init(key: "TCMz", celsius: 65)],
            units: [
                .init(index: 0, rpm: 2_200, minimumRPM: 1_200, maximumRPM: 5_000, targetRPM: 2_200, mode: 1),
                .init(index: 1, rpm: 2_300, minimumRPM: 1_300, maximumRPM: 6_000, targetRPM: 2_300, mode: 1),
            ]
        )
        let model = MonitorFanControlModel(
            previewConfiguration: MonitorFanConfiguration(
                enabled: true,
                mode: .manual,
                manualRPM: ["0": 2_200, "1": 2_300],
                manualModes: ["0": .manual, "1": .manual]
            ),
            availability: .ready
        )

        model.setManualRPM(2_400, fanIndex: 0, reading: reading)
        XCTAssertTrue(model.hasPendingManualWrite)
        try? await Task.sleep(for: .milliseconds(150))
        model.setManualRPM(2_600, fanIndex: 0, reading: reading)
        try? await Task.sleep(for: .milliseconds(250))
        XCTAssertTrue(model.hasPendingManualWrite)
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(model.hasPendingManualWrite)
        XCTAssertEqual(model.configuration.manualRPM["0"], 2_600)
    }

    @MainActor
    func testSingleFanFullSpeedOnlyChangesOneFanWhenSyncIsOff() {
        let reading = MonitorFanReading(
            temperatures: [.init(key: "TCMz", celsius: 65)],
            units: [
                .init(index: 0, rpm: 2_200, minimumRPM: 1_200, maximumRPM: 5_800, targetRPM: 2_200, mode: 1),
                .init(index: 1, rpm: 2_300, minimumRPM: 1_300, maximumRPM: 6_000, targetRPM: 2_300, mode: 1),
            ]
        )
        let model = MonitorFanControlModel(
            previewConfiguration: MonitorFanConfiguration(
                enabled: true,
                mode: .manual,
                manualRPM: ["0": 2_200, "1": 2_300],
                manualModes: ["0": .automatic, "1": .automatic],
                syncFans: false
            ),
            availability: .ready
        )

        model.boostFan(1, reading: reading)

        XCTAssertEqual(model.configuration.mode, .manual)
        XCTAssertEqual(model.configuration.manualRPM["0"], 2_200)
        XCTAssertEqual(model.configuration.manualRPM["1"], 6_000)
        XCTAssertEqual(model.manualMode(for: 0), .automatic)
        XCTAssertEqual(model.manualMode(for: 1), .manual)
    }

    @MainActor
    func testSingleFanFullSpeedSynchronizesWhenEnabled() {
        let reading = MonitorFanReading(
            temperatures: [.init(key: "TCMz", celsius: 65)],
            units: [
                .init(index: 0, rpm: 2_200, minimumRPM: 1_200, maximumRPM: 5_800, targetRPM: 2_200, mode: 1),
                .init(index: 1, rpm: 2_300, minimumRPM: 1_300, maximumRPM: 6_000, targetRPM: 2_300, mode: 1),
            ]
        )
        let model = MonitorFanControlModel(
            previewConfiguration: MonitorFanConfiguration(
                enabled: true,
                mode: .manual,
                manualRPM: ["0": 2_200, "1": 2_300],
                manualModes: ["0": .automatic, "1": .manual],
                syncFans: true
            ),
            availability: .ready
        )

        model.boostFan(1, reading: reading)

        XCTAssertEqual(model.configuration.manualRPM, ["0": 5_800, "1": 6_000])
        XCTAssertEqual(model.manualMode(for: 0), .manual)
        XCTAssertEqual(model.manualMode(for: 1), .manual)
    }

    @MainActor
    func testAllFansFullSpeedUsesEachMaximum() {
        let reading = MonitorFanReading(
            temperatures: [.init(key: "TCMz", celsius: 65)],
            units: [
                .init(index: 0, rpm: 2_200, minimumRPM: 1_200, maximumRPM: 5_800, targetRPM: 2_200, mode: 1),
                .init(index: 1, rpm: 2_300, minimumRPM: 1_300, maximumRPM: 6_000, targetRPM: 2_300, mode: 1),
            ]
        )
        let model = MonitorFanControlModel(
            previewConfiguration: MonitorFanConfiguration(enabled: false, mode: .automatic),
            availability: .ready
        )

        model.boostAllFans(reading: reading)

        XCTAssertTrue(model.configuration.enabled)
        XCTAssertEqual(model.configuration.mode, .manual)
        XCTAssertEqual(model.configuration.manualRPM, ["0": 5_800, "1": 6_000])
        XCTAssertEqual(model.manualMode(for: 0), .manual)
        XCTAssertEqual(model.manualMode(for: 1), .manual)
    }

    @MainActor
    func testRestoreAutoCurveLeavesManualMode() {
        let reading = MonitorFanReading(
            temperatures: [.init(key: "TCMz", celsius: 65)],
            units: [
                .init(index: 0, rpm: 2_200, minimumRPM: 1_200, maximumRPM: 5_800, targetRPM: 2_200, mode: 1),
            ]
        )
        let model = MonitorFanControlModel(
            previewConfiguration: MonitorFanConfiguration(
                enabled: true,
                mode: .manual,
                manualRPM: ["0": 5_800],
                manualModes: ["0": .manual]
            ),
            availability: .ready
        )

        model.restoreAutoCurve(reading: reading)

        XCTAssertTrue(model.configuration.enabled)
        XCTAssertEqual(model.configuration.mode, .curve)
    }

    func testControlTemperatureUsesSelectedSensors() {
        let reading = MonitorFanReading(
            temperatures: [
                .init(key: "TCMz", celsius: 72),
                .init(key: "TG0D", celsius: 64),
                .init(key: "TB0T", celsius: 38),
            ],
            units: []
        )

        XCTAssertEqual(
            reading.controlTemperature(selectedKeys: ["TCMz"]),
            72
        )
        XCTAssertEqual(
            reading.controlTemperature(selectedKeys: ["TG0D", "TB0T"]),
            64
        )
        XCTAssertEqual(
            reading.controlTemperature(selectedKeys: []),
            72
        )
    }

    func testMonitorHistoryTracksTheFanSeries() {
        let reading = MonitorFanReading(
            temperatures: [.init(key: "TCMz", celsius: 72)],
            units: [
                .init(
                    index: 0,
                    rpm: 2_200,
                    minimumRPM: 1_200,
                    maximumRPM: 5_000,
                    targetRPM: 2_100,
                    mode: 1
                ),
                .init(
                    index: 1,
                    rpm: 2_600,
                    minimumRPM: 1_200,
                    maximumRPM: 5_500,
                    targetRPM: 2_500,
                    mode: 1
                ),
            ]
        )
        let snapshot = MonitorSnapshot(
            cpu: nil,
            gpu: nil,
            memory: nil,
            disk: nil,
            network: nil,
            battery: nil,
            power: nil,
            display: nil,
            fan: reading,
            thermal: .nominal,
            sampledAt: Date()
        )
        var history = MonitorHistory(capacity: 2)
        history.append(snapshot, fanControlTemperature: 68)
        history.append(snapshot)

        XCTAssertEqual(history.fanTemperature, [68, 72])
        XCTAssertEqual(history.fanRPM, [2_600, 2_600])
    }

    func testHelperPayloadUsesStableFieldNames() {
        let payload = MonitorFanConfiguration(
            enabled: true,
            mode: .manual,
            startCelsius: 58,
            fullCelsius: 86,
            selectedSensorKeys: ["TCMz", "TG0D"],
            manualRPM: ["1": 2_400, "0": 2_200]
        ).helperPayload()

        XCTAssertEqual(payload["enabled"], "true")
        XCTAssertEqual(payload["mode"], "manual")
        XCTAssertEqual(payload["start"], "58")
        XCTAssertEqual(payload["full"], "86")
        XCTAssertEqual(payload["sensors"], "TCMz,TG0D")
        XCTAssertEqual(payload["manualRPM"], "0:2200,1:2400")
    }

    func testTemperatureSourceMappingUsesPlatformSpecificGPUKeys() {
        let sensors = [
            SMCTemperatureReading(key: "TCMz", celsius: 65),
            SMCTemperatureReading(key: "Tp01", celsius: 60),
            SMCTemperatureReading(key: "Tg0D", celsius: 48),
            SMCTemperatureReading(key: "TG0D", celsius: 33),
            SMCTemperatureReading(key: "TB0T", celsius: 31.2),
            SMCTemperatureReading(key: "TB2T", celsius: 31.4),
        ]

        let appleSilicon = SMCFanReader.temperatureSourceReadings(
            for: sensors,
            appleSilicon: true
        )
        XCTAssertEqual(appleSilicon[.cpu], 65)
        XCTAssertEqual(appleSilicon[.gpu], 48)
        XCTAssertEqual(appleSilicon[.battery], 31.4)

        let intel = SMCFanReader.temperatureSourceReadings(
            for: sensors,
            appleSilicon: false
        )
        XCTAssertEqual(intel[.cpu], 65)
        XCTAssertEqual(intel[.gpu], 33)
        XCTAssertEqual(intel[.battery], 31.4)
    }

    func testTemperatureNameLibraryCoversAll64ExplicitKeys() {
        let expected: Set<String> = [
            "TCMz", "TCMb", "TCMc", "TC0P", "TC0D", "TC0E", "TC0F", "TC0H",
            "TC0C", "TC1C", "TC2C", "TC3C", "TC4C", "TC5C", "TC6C", "TC7C",
            "TC8C", "TCSA", "TG0P", "TG0D", "TG0H", "TG1D", "TG1P", "Tm0P",
            "TM0P", "TM0A", "TM0B", "TMVR", "TN0D", "TN1D", "TS0P", "TB0T",
            "TB1T", "TB2T", "TB3T", "TP0P", "TP1P", "TPCD", "TAOL", "TaLP",
            "TA0P", "TA1P", "TaSP", "Ts0S", "Ts1S", "Ts0P", "Ts1P", "TCXC",
            "TH0P", "TH0a", "TH0b", "TH1a", "TH1b", "TH0x", "TW0P", "TL0P",
            "TI0P", "TI1P", "TD0P", "TDRD", "TD3P", "TO0P", "TVEP", "TVM0",
        ]

        XCTAssertEqual(SMCTemperatureName.knownKeys, expected)
        for key in expected {
            XCTAssertFalse(
                SMCTemperatureName.displayName(for: key, language: .simplifiedChinese).isEmpty
            )
            XCTAssertFalse(
                SMCTemperatureName.displayName(for: key, language: .english).isEmpty
            )
        }
        XCTAssertEqual(
            SMCTemperatureName.displayName(for: "TCSA", language: .simplifiedChinese),
            "CPU 系统代理"
        )
        XCTAssertEqual(
            SMCTemperatureName.displayName(for: "TH0x", language: .english),
            "Exhaust e"
        )
        XCTAssertEqual(
            SMCTemperatureName.displayName(for: "TCZZ", language: .english),
            "CPU ZZ"
        )
        XCTAssertEqual(
            SMCTemperatureName.displayName(for: "ZZZZ", language: .simplifiedChinese),
            "ZZZZ"
        )
    }

    func testTemperatureNameFilterMatchesNameAndKey() {
        XCTAssertTrue(
            SMCTemperatureName.matches("TC1C", query: "core 1")
        )
        XCTAssertTrue(
            SMCTemperatureName.matches("TB2T", query: "电池 3")
        )
        XCTAssertTrue(
            SMCTemperatureName.matches("TB2T", query: "battery 3")
        )
        XCTAssertTrue(
            SMCTemperatureName.matches("TD3P", query: "td3p")
        )
        XCTAssertFalse(
            SMCTemperatureName.matches("TC1C", query: "battery")
        )
        XCTAssertTrue(
            SMCTemperatureName.matches("ZZZZ", query: "zzzz")
        )
    }

    func testFanTargetFormatAlwaysIncludesRPM() {
        XCTAssertEqual(MonitorFanFormat.targetRPM(3_500), "3500 RPM")
        XCTAssertEqual(MonitorFanFormat.targetRPM(nil), "—")
    }

    func testTemperatureRulePercentUsesFivePercentSteps() {
        XCTAssertEqual(MonitorFanPolicy.rulePercentStep, 5)
        XCTAssertEqual(MonitorFanTemperatureRule.snappedPercent(33), 35)
        XCTAssertEqual(MonitorFanTemperatureRule.snappedPercent(42), 40)
        XCTAssertEqual(MonitorFanTemperatureRule.snappedPercent(98), 100)
    }

    func testFanPreviewUsesRealMacHardwareRanges() {
        let units = MonitorFanPreviewFixtures.reading.units

        XCTAssertEqual(units[0].minimumRPM, 1_499)
        XCTAssertEqual(units[0].maximumRPM, 5_348)
        XCTAssertEqual(units[1].minimumRPM, 1_499)
        XCTAssertEqual(units[1].maximumRPM, 5_776)
    }

    func testFanMaximumValidationRejectsInvalidRanges() {
        XCTAssertEqual(SMCFanReader.validFanMaximum(5_348, minimum: 1_500), 5_348)
        XCTAssertNil(SMCFanReader.validFanMaximum(nil, minimum: 1_500))
        XCTAssertNil(SMCFanReader.validFanMaximum(1_500, minimum: 1_500))
        XCTAssertNil(SMCFanReader.validFanMaximum(15_001, minimum: 1_500))
    }

    func testTemperatureRuleInterpolatesAndClampsPercent() {
        let points = [
            MonitorFanTemperatureRulePoint(celsius: 32, fanPercent: 30),
            MonitorFanTemperatureRulePoint(celsius: 34, fanPercent: 50),
        ]

        XCTAssertEqual(
            MonitorFanTemperatureRule.targetPercent(points: points, temperature: 32),
            30
        )
        XCTAssertEqual(
            MonitorFanTemperatureRule.targetPercent(points: points, temperature: 33),
            40,
            accuracy: 0.001
        )
        XCTAssertEqual(
            MonitorFanTemperatureRule.targetPercent(points: points, temperature: 40),
            50
        )
        XCTAssertEqual(
            MonitorFanTemperatureRule.targetPercent(points: points, temperature: 20),
            30
        )
    }

    func testTemperatureRuleNormalizationSortsSpacesAndClamps() {
        let normalized = MonitorFanTemperatureRule.normalized([
            .init(celsius: 34, fanPercent: 50),
            .init(celsius: 31.5, fanPercent: 30),
            .init(celsius: 33, fanPercent: 40),
            .init(celsius: 110, fanPercent: 120),
        ])

        XCTAssertEqual(normalized.map(\.celsius), [32, 34, 105])
        XCTAssertEqual(normalized.map(\.fanPercent), [30, 50, 100])
    }

    func testDenseTemperatureRuleHasNoInvalidSliderRange() {
        let points = [
            MonitorFanTemperatureRulePoint(celsius: 32, fanPercent: 30),
            MonitorFanTemperatureRulePoint(celsius: 34, fanPercent: 40),
            MonitorFanTemperatureRulePoint(celsius: 36, fanPercent: 50),
        ]
        let range = MonitorFanTemperatureRule.editableTemperatureRange(
            index: 1,
            points: points
        )

        XCTAssertEqual(range.lowerBound, 34)
        XCTAssertEqual(range.upperBound, 34)
    }

    func testConfigurationNormalizesTemperatureRules() {
        let configuration = MonitorFanConfiguration(
            temperatureRules: [
                "battery": [
                    .init(celsius: 32, fanPercent: 30),
                    .init(celsius: 34, fanPercent: 50),
                ],
                "gpu": [
                    .init(celsius: 60, fanPercent: 30),
                ],
                "unknown": [
                    .init(celsius: 40, fanPercent: 20),
                    .init(celsius: 50, fanPercent: 30),
                ],
            ]
        ).normalized()

        XCTAssertEqual(Array(configuration.temperatureRules.keys), ["battery"])
        XCTAssertTrue(configuration.hasTemperatureRules(for: .battery))
        XCTAssertFalse(configuration.hasTemperatureRules(for: .gpu))
    }

    func testTemperatureRulePercentMapsToFanMaximum() {
        XCTAssertEqual(
            MonitorFanPercent.rpm(percent: 30, minimumRPM: 1499, maximumRPM: 5348),
            1604.4,
            accuracy: 0.001
        )
        XCTAssertEqual(
            MonitorFanPercent.rpm(percent: 50, minimumRPM: 1499, maximumRPM: 5776),
            2888,
            accuracy: 0.001
        )
        XCTAssertEqual(
            MonitorFanPercent.rpm(percent: 60, minimumRPM: 1499, maximumRPM: 5348),
            3208.8,
            accuracy: 0.001
        )
        XCTAssertEqual(
            MonitorFanPercent.rpm(percent: 20, minimumRPM: 1499, maximumRPM: 5348),
            1499,
            accuracy: 0.001
        )
        XCTAssertEqual(
            MonitorFanPercent.rpm(percent: 100, minimumRPM: 1499, maximumRPM: 5348),
            5348,
            accuracy: 0.001
        )
    }

    func testHelperPayloadRoundTripsTemperatureRules() throws {
        let payload = MonitorFanConfiguration(
            enabled: true,
            mode: .curve,
            temperatureRules: [
                "battery": [
                    .init(celsius: 32, fanPercent: 30),
                    .init(celsius: 34, fanPercent: 50),
                ],
            ]
        ).helperPayload()
        let text = try XCTUnwrap(payload["temperatureRules"])
        let decoded = try JSONDecoder().decode(
            [String: [MonitorFanTemperatureRulePoint]].self,
            from: Data(text.utf8)
        )

        XCTAssertEqual(decoded["battery"]?.map(\.celsius), [32, 34])
        XCTAssertEqual(decoded["battery"]?.map(\.fanPercent), [30, 50])
    }

    func testTemperatureSourceDefaultsMatchBatteryWorkflow() {
        XCTAssertEqual(
            MonitorFanTemperatureRule.defaultPoints(for: .battery).map(\.celsius),
            [30, 32, 34]
        )
        XCTAssertEqual(
            MonitorFanTemperatureRule.defaultPoints(for: .battery).map(\.fanPercent),
            [0, 40, 60]
        )
        XCTAssertEqual(
            MonitorFanTemperatureRule.defaultPoints(for: .cpu).map(\.celsius),
            [60, 80]
        )
        XCTAssertEqual(
            MonitorFanTemperatureRule.defaultPoints(for: .gpu).map(\.celsius),
            [40, 60]
        )
    }

    func testLegacyBatteryDefaultMigratesToThreePointRule() throws {
        let json = #"""
        {
          "enabled": true,
          "mode": "curve",
          "temperatureRules": {
            "battery": [
              { "celsius": 32, "fanPercent": 30 },
              { "celsius": 34, "fanPercent": 40 }
            ]
          }
        }
        """#
        let configuration = try JSONDecoder().decode(
            MonitorFanConfiguration.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(
            configuration.temperatureRules["battery"]?.map(\.celsius),
            [30, 32, 34]
        )
        XCTAssertEqual(
            configuration.temperatureRules["battery"]?.map(\.fanPercent),
            [0, 40, 60]
        )
    }

    func testNewBatteryDefaultUsesMinimumBelowFirstPoint() {
        let points = MonitorFanTemperatureRule.defaultPoints(for: .battery)

        XCTAssertEqual(
            MonitorFanTemperatureRule.targetPercent(points: points, temperature: 27.6),
            0
        )
        XCTAssertEqual(
            MonitorFanTemperatureRule.targetPercent(points: points, temperature: 30),
            0
        )
        XCTAssertEqual(
            MonitorFanTemperatureRule.targetPercent(points: points, temperature: 32),
            40
        )
        XCTAssertEqual(
            MonitorFanTemperatureRule.targetPercent(points: points, temperature: 34),
            60
        )
    }

    func testFanRpmSummaryShowsMinimumTargetAndMaximum() {
        let fan0 = MonitorFanReading.Unit(
            index: 0,
            rpm: 2_600,
            minimumRPM: 1_499,
            maximumRPM: 5_348,
            targetRPM: 2_654,
            mode: 1
        )
        let fan1 = MonitorFanReading.Unit(
            index: 1,
            rpm: 2_800,
            minimumRPM: 1_499,
            maximumRPM: 5_776,
            targetRPM: 2_782,
            mode: 1
        )

        let minimum = MonitorFanRpmScale.summary(for: fan0, percent: 0)
        XCTAssertEqual(minimum.minimumRPM, 1_499)
        XCTAssertEqual(minimum.targetRPM, 1_499)
        XCTAssertEqual(minimum.maximumRPM, 5_348)

        let fan0Forty = MonitorFanRpmScale.summary(for: fan0, percent: 40)
        XCTAssertEqual(fan0Forty.minimumRPM, 1_499)
        XCTAssertEqual(fan0Forty.targetRPM, 2_139.2, accuracy: 0.001)
        XCTAssertEqual(fan0Forty.maximumRPM, 5_348)

        let fan1Forty = MonitorFanRpmScale.summary(for: fan1, percent: 40)
        XCTAssertEqual(fan1Forty.minimumRPM, 1_499)
        XCTAssertEqual(fan1Forty.targetRPM, 2_310.4, accuracy: 0.001)
        XCTAssertEqual(fan1Forty.maximumRPM, 5_776)

        let fan1Sixty = MonitorFanRpmScale.summary(for: fan1, percent: 60)
        XCTAssertEqual(fan1Sixty.minimumRPM, 1_499)
        XCTAssertEqual(fan1Sixty.targetRPM, 3_465.6, accuracy: 0.001)
        XCTAssertEqual(fan1Sixty.maximumRPM, 5_776)
    }

    func testControlTemperatureUsesOnlyEnabledRuleSources() {
        let reading = MonitorFanReading(
            temperatures: [
                .init(key: "TCMz", celsius: 72),
                .init(key: "Tg0D", celsius: 64),
                .init(key: "TB0T", celsius: 34),
            ],
            units: []
        )
        let legacy = MonitorFanConfiguration(selectedSensorKeys: ["TCMz"])
        let battery = MonitorFanConfiguration(
            selectedSensorKeys: ["TCMz"],
            temperatureRules: ["battery": MonitorFanTemperatureRule.defaultPoints(for: .battery)]
        )
        let unavailable = MonitorFanConfiguration(
            temperatureRules: ["gpu": MonitorFanTemperatureRule.defaultPoints(for: .gpu)]
        )

        XCTAssertEqual(legacy.controlTemperature(in: reading), 72)
        XCTAssertEqual(battery.controlTemperature(in: reading), 34)
        XCTAssertNil(
            unavailable.controlTemperature(in: MonitorFanReading(
                temperatures: [.init(key: "TCMz", celsius: 72)],
                units: []
            ))
        )
    }

    func testMergedTemperatureRuleUsesHighestSourceRequest() {
        let configuration = MonitorFanConfiguration(
            temperatureRules: [
                "battery": MonitorFanTemperatureRule.defaultPoints(for: .battery),
                "cpu": MonitorFanTemperatureRule.defaultPoints(for: .cpu),
            ]
        )

        XCTAssertEqual(
            configuration.mergedTargetPercent(sourceTemperatures: [
                .battery: 33,
                .cpu: 70,
            ]),
            50
        )
        XCTAssertEqual(
            configuration.mergedTargetPercent(sourceTemperatures: [.battery: 34]),
            60
        )
        XCTAssertNil(
            configuration.mergedTargetPercent(sourceTemperatures: [.gpu: 70])
        )
    }

    @MainActor
    func testTemperatureRuleEditsPersistAcrossModelReloads() {
        let suiteName = "MonitorFanTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let reading = MonitorFanReading(
            temperatures: [.init(key: "TB0T", celsius: 33)],
            units: [
                .init(index: 0, rpm: 2_000, minimumRPM: 1_200, maximumRPM: 5_800, targetRPM: 2_000, mode: 1),
            ]
        )
        let model = MonitorFanControlModel(defaults: defaults)

        model.setTemperatureSource(.battery, enabled: true, reading: reading)
        XCTAssertEqual(
            model.configuration.temperatureRules["battery"]?.map(\.celsius),
            [30, 32, 34]
        )

        model.setTemperatureRulePoints(
            [
                .init(celsius: 31, fanPercent: 25),
                .init(celsius: 35, fanPercent: 55),
            ],
            source: .battery,
            reading: reading,
            applyImmediately: true
        )

        let reloaded = MonitorFanControlModel(defaults: defaults)
        XCTAssertEqual(
            reloaded.configuration.temperatureRules["battery"],
            [
                .init(celsius: 31, fanPercent: 25),
                .init(celsius: 35, fanPercent: 55),
            ]
        )

        reloaded.setTemperatureSource(.battery, enabled: false, reading: reading)
        XCTAssertNil(reloaded.configuration.temperatureRules["battery"])
    }

    func testBatteryCurveOverridesAdapterAndFallsBackPerFan() {
        let adapter0 = [
            MonitorFanCurvePoint(temperature: 40, rpm: 1_200),
            MonitorFanCurvePoint(temperature: 90, rpm: 5_000),
        ]
        let adapter1 = [
            MonitorFanCurvePoint(temperature: 45, rpm: 1_300),
            MonitorFanCurvePoint(temperature: 95, rpm: 6_000),
        ]
        let battery0 = [
            MonitorFanCurvePoint(temperature: 50, rpm: 1_500),
            MonitorFanCurvePoint(temperature: 85, rpm: 4_800),
        ]
        let configuration = MonitorFanConfiguration(
            powerSource: .battery,
            curves: ["0": adapter0, "1": adapter1],
            batteryCurves: ["0": battery0]
        )

        XCTAssertEqual(
            configuration.curvePoints(for: 0, minimumRPM: 1_200, maximumRPM: 5_000),
            battery0
        )
        XCTAssertEqual(
            configuration.curvePoints(for: 1, minimumRPM: 1_300, maximumRPM: 6_000),
            adapter1
        )
        XCTAssertEqual(configuration.effectiveCurveSource(for: 0), .battery)
        XCTAssertEqual(configuration.effectiveCurveSource(for: 1), .adapter)
    }

    func testBatteryHelperPayloadMergesBatteryCurveOverAdapterFallback() throws {
        let adapter0 = [
            MonitorFanCurvePoint(temperature: 40, rpm: 1_200),
            MonitorFanCurvePoint(temperature: 90, rpm: 5_000),
        ]
        let adapter1 = [
            MonitorFanCurvePoint(temperature: 45, rpm: 1_300),
            MonitorFanCurvePoint(temperature: 95, rpm: 6_000),
        ]
        let battery0 = [
            MonitorFanCurvePoint(temperature: 50, rpm: 1_500),
            MonitorFanCurvePoint(temperature: 85, rpm: 4_800),
        ]
        let configuration = MonitorFanConfiguration(
            enabled: true,
            mode: .curve,
            powerSource: .battery,
            curves: ["0": adapter0, "1": adapter1],
            batteryCurves: ["0": battery0]
        )
        let text = try XCTUnwrap(configuration.helperPayload()["curves"])
        let decoded = try JSONDecoder().decode(
            [String: [MonitorFanCurvePoint]].self,
            from: Data(text.utf8)
        )

        XCTAssertEqual(decoded["0"], battery0)
        XCTAssertEqual(decoded["1"], adapter1)

        var adapterConfiguration = configuration
        adapterConfiguration.powerSource = .adapter
        let adapterText = try XCTUnwrap(adapterConfiguration.helperPayload()["curves"])
        let adapterDecoded = try JSONDecoder().decode(
            [String: [MonitorFanCurvePoint]].self,
            from: Data(adapterText.utf8)
        )

        XCTAssertEqual(adapterDecoded["0"], adapter0)
        XCTAssertEqual(adapterDecoded["1"], adapter1)
    }

    func testPowerCurvesRoundTripAndLegacyConfigurationUsesAdapter() throws {
        let original = MonitorFanConfiguration(
            enabled: true,
            mode: .curve,
            powerSource: .battery,
            curves: [
                "0": [
                    .init(temperature: 40, rpm: 1_200),
                    .init(temperature: 90, rpm: 5_000),
                ],
            ],
            batteryCurves: [
                "0": [
                    .init(temperature: 50, rpm: 1_500),
                    .init(temperature: 85, rpm: 4_800),
                ],
            ]
        )
        let decoded = try JSONDecoder().decode(
            MonitorFanConfiguration.self,
            from: JSONEncoder().encode(original)
        )
        let legacy = try JSONDecoder().decode(
            MonitorFanConfiguration.self,
            from: Data(#"{"enabled":true,"mode":"curve"}"#.utf8)
        )

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(legacy.powerSource, .adapter)
        XCTAssertTrue(legacy.batteryCurves.isEmpty)
    }

    @MainActor
    func testCopyAdapterCurvesToBatteryCopiesCustomAndFallbackCurves() {
        let reading = MonitorFanReading(
            temperatures: [.init(key: "TCMz", celsius: 65)],
            units: [
                .init(index: 0, rpm: 2_200, minimumRPM: 1_200, maximumRPM: 5_000, targetRPM: 2_200, mode: 1),
                .init(index: 1, rpm: 2_300, minimumRPM: 1_300, maximumRPM: 6_000, targetRPM: 2_300, mode: 1),
            ]
        )
        let custom = [
            MonitorFanCurvePoint(temperature: 45, rpm: 1_400),
            MonitorFanCurvePoint(temperature: 90, rpm: 4_900),
        ]
        let model = MonitorFanControlModel(
            previewConfiguration: MonitorFanConfiguration(
                startCelsius: 58,
                fullCelsius: 86,
                curves: ["0": custom]
            ),
            availability: .ready
        )

        model.copyAdapterCurvesToBattery(reading: reading)

        XCTAssertEqual(model.configuration.batteryCurves["0"], custom)
        XCTAssertEqual(
            model.configuration.batteryCurves["1"],
            [
                .init(temperature: 58, rpm: 1_300),
                .init(temperature: 86, rpm: 6_000),
            ]
        )
    }

    @MainActor
    func testCurveEditsTargetTheSelectedPowerSource() {
        let reading = MonitorFanReading(
            temperatures: [.init(key: "TCMz", celsius: 65)],
            units: [
                .init(index: 0, rpm: 2_200, minimumRPM: 1_200, maximumRPM: 5_000, targetRPM: 2_200, mode: 1),
            ]
        )
        let adapter = [
            MonitorFanCurvePoint(temperature: 45, rpm: 1_400),
            MonitorFanCurvePoint(temperature: 90, rpm: 4_900),
        ]
        let battery = [
            MonitorFanCurvePoint(temperature: 50, rpm: 1_600),
            MonitorFanCurvePoint(temperature: 88, rpm: 4_700),
        ]
        let model = MonitorFanControlModel(
            previewConfiguration: MonitorFanConfiguration(curves: ["0": adapter]),
            availability: .ready
        )

        model.setCurve(fanIndex: 0, points: battery, source: .battery, reading: reading)

        XCTAssertEqual(model.configuration.curves["0"], adapter)
        XCTAssertEqual(model.configuration.batteryCurves["0"], battery)

        model.clearCurve(fanIndex: 0, source: .battery, reading: reading)

        XCTAssertEqual(model.configuration.curves["0"], adapter)
        XCTAssertNil(model.configuration.batteryCurves["0"])
    }

    @MainActor
    func testPowerSourceSelectionPersists() {
        let suiteName = "MonitorFanTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let reading = MonitorFanReading(
            temperatures: [.init(key: "TCMz", celsius: 65)],
            units: [
                .init(index: 0, rpm: 2_200, minimumRPM: 1_200, maximumRPM: 5_000, targetRPM: 2_200, mode: 1),
            ]
        )
        let model = MonitorFanControlModel(defaults: defaults)

        model.updatePowerSource(.battery, reading: reading)

        XCTAssertEqual(model.configuration.powerSource, .battery)
        XCTAssertEqual(MonitorFanControlModel(defaults: defaults).configuration.powerSource, .battery)
    }

    func testSnapshotMapsPowerSupplyToFanCurveSource() {
        func snapshot(_ supply: MonitorSnapshot.Power.Supply) -> MonitorSnapshot {
            MonitorSnapshot(
                cpu: nil,
                gpu: nil,
                memory: nil,
                disk: nil,
                network: nil,
                battery: nil,
                power: MonitorSnapshot.Power(
                    supply: supply,
                    hasBattery: true,
                    batteryPercent: 70,
                    temperatureCelsius: 30,
                    watts: 20,
                    averageWatts: 18,
                    remainingSeconds: nil,
                    chargePowerWatts: nil,
                    timeToFullSeconds: nil,
                    batteryHealthPercent: 90,
                    topApps: [],
                    events: [],
                    batteryDataAvailable: true,
                    powerDataAvailable: true,
                    energyDataAvailable: true
                ),
                display: nil,
                fan: nil,
                thermal: .nominal,
                sampledAt: Date()
            )
        }

        XCTAssertEqual(snapshot(.adapter).fanPowerSource, .adapter)
        XCTAssertEqual(snapshot(.charging).fanPowerSource, .adapter)
        XCTAssertEqual(snapshot(.battery).fanPowerSource, .battery)
    }
}
