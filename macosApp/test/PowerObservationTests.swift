import XCTest
@testable import Covio

/// 电源观察端口的导出与映射测试。
///
/// 策略本身由 Kotlin 测试覆盖。
/// 这里只守 Swift 系统 API 到共享模型的第一层转换。
final class PowerObservationTests: XCTestCase {
    func testBatteryPercentDoesNotInventUnknownValues() {
        XCTAssertNil(MacPowerSource.batteryPercent(current: nil, maximum: 100))
        XCTAssertNil(MacPowerSource.batteryPercent(current: 50, maximum: nil))
        XCTAssertNil(MacPowerSource.batteryPercent(current: 50, maximum: 0))
        XCTAssertEqual(MacPowerSource.batteryPercent(current: 50, maximum: 100), 50)
        XCTAssertEqual(MacPowerSource.batteryPercent(current: 150, maximum: 100), 100)
    }

    func testProviderTypeMappingDistinguishesAdapterAndBattery() {
        XCTAssertEqual(MacPowerObservationSource.mapProviderType("AC Power"), .acPower)
        XCTAssertEqual(MacPowerObservationSource.mapProviderType("Battery Power"), .discharging)
        XCTAssertEqual(MacPowerObservationSource.mapProviderType("Off Line"), .unknown)
        XCTAssertEqual(MacPowerObservationSource.mapProviderType(""), .unknown)
    }

    func testChargingStateOverridesTheGenericAdapterState() {
        XCTAssertEqual(
            MacPowerObservationSource.resolvePowerState(provider: .acPower, battery: .charging),
            .charging
        )
        XCTAssertEqual(
            MacPowerObservationSource.resolvePowerState(provider: .acPower, battery: .charged),
            .charged
        )
        XCTAssertEqual(
            MacPowerObservationSource.resolvePowerState(provider: .acPower, battery: .unknown),
            .acPower
        )
        XCTAssertEqual(
            MacPowerObservationSource.resolvePowerState(provider: .unknown, battery: .discharging),
            .discharging
        )
    }

    func testThermalStateMappingHasNoImplicitNormalFallback() {
        XCTAssertEqual(MacPowerObservationSource.mapThermalState(.nominal), .nominal)
        XCTAssertEqual(MacPowerObservationSource.mapThermalState(.fair), .fair)
        XCTAssertEqual(MacPowerObservationSource.mapThermalState(.serious), .serious)
        XCTAssertEqual(MacPowerObservationSource.mapThermalState(.critical), .critical)
    }

    /// 真机读值必须满足范围约束，缺失值也必须保留为 nil。
    func testLiveObservationKeepsMissingValuesNullable() {
        let observation = MacPowerObservationSource().read()

        if let percent = observation.batteryPercent?.int32Value {
            XCTAssertTrue((0...100).contains(percent))
        }
        if let count = observation.externalDisplayCount?.int32Value {
            XCTAssertGreaterThanOrEqual(count, 0)
        }
        if observation.batteryPercent != nil {
            XCTAssertNotEqual(observation.hasBattery?.boolValue, false)
        }
    }
}
