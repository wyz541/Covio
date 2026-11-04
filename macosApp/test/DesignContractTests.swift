import XCTest
@testable import Covio

/// 把 Swift 侧的常量与设计合同对起来。
///
/// - `docs/covio-design-contract.json` 给组件的 `nativeSize`、状态词汇、文案键与页签条目。
///
/// 动效时长与合同的比对在 `ContractConstantsTests`，这里不重复。
///
/// 这些断言的作用是：合同改了而代码没跟上时，测试会失败。
final class DesignContractTests: XCTestCase {
    // MARK: - 文件定位

    /// 仓库根目录。测试源在 `<root>/macosApp/test/`。
    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private func contractJSON() throws -> [String: Any] {
        let url = Self.repoRoot.appendingPathComponent("docs/covio-design-contract.json")
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - 页签

    /// 页签与 schema 2 的当前 `PaneKind` 一一对应。
    ///
    /// `PaneKind.SCREENSHOTS` 只为读取 schema 1 配置而保留，不再进入界面枚举。
    func testTabsMatchCurrentPaneKinds() throws {
        let copy = try XCTUnwrap(try contractJSON()["copy"] as? [String: Any])
        let currentKinds = PaneKind.entries.filter { $0.key != PaneKind.screenshots.key }
        XCTAssertEqual(HubTab.allCases.count, currentKinds.count, "页签数应等于当前 PaneKind 的取值数")

        for tab in HubTab.allCases {
            XCTAssertEqual(
                tab.paneKind.key,
                tab.rawValue,
                "\(tab.rawValue) 与 PaneKind 的键不一致"
            )
            XCTAssertNotNil(copy["copy/hub/tab/\(tab.rawValue)"], "合同缺少文案键 copy/hub/tab/\(tab.rawValue)")
            XCTAssertNotNil(
                copy["copy/hub/tab/\(tab.rawValue)/summary"],
                "合同缺少文案键 copy/hub/tab/\(tab.rawValue)/summary"
            )
        }

        XCTAssertEqual(
            HubTab.allCases.map(\.rawValue),
            ["now", "agent", "clipboard", "files", "devices", "settings", "board"]
        )
    }

    func testEveryTabHasTitleAndSummary() {
        for tab in HubTab.allCases {
            XCTAssertFalse(tab.title.en.isEmpty, "\(tab.rawValue) 缺英文标题")
            XCTAssertFalse(tab.title.zhHans.isEmpty, "\(tab.rawValue) 缺中文标题")
            XCTAssertFalse(tab.summary.en.isEmpty, "\(tab.rawValue) 缺英文说明")
            XCTAssertFalse(tab.summary.zhHans.isEmpty, "\(tab.rawValue) 缺中文说明")
            XCTAssertFalse(tab.glyph.isEmpty, "\(tab.rawValue) 缺图标")
        }
    }

    // MARK: - 组件尺寸

    private func nativeSize(_ key: String, in contract: [String: Any]) throws -> (Int, Int) {
        let components = try XCTUnwrap(contract["components"] as? [String: Any])
        let component = try XCTUnwrap(components[key] as? [String: Any], "合同缺少 \(key)")
        let size = try XCTUnwrap(component["nativeSize"] as? [String: Any], "\(key) 缺少 nativeSize")
        let width = try XCTUnwrap(size["width"] as? Int)
        let height = try XCTUnwrap(size["height"] as? Int)
        return (width, height)
    }

    /// 顶栏的尺寸。合同 `component/tab-bar` 的 `nativeSize` 是 960 × 46。
    ///
    /// 宽度等于面板宽度：顶栏横跨整个面板，内边距由顶栏自己留。
    func testTabBarSizeMatchesContract() throws {
        let (width, height) = try nativeSize("component/tab-bar", in: try contractJSON())
        XCTAssertEqual(HubMetrics.tabBarWidth, CGFloat(width))
        XCTAssertEqual(HubMetrics.tabBarHeight, CGFloat(height))
    }

    /// 页标题行。合同 `component/page-title` 的 `nativeSize` 是 912 × 24。
    ///
    /// 宽度等于内容列宽度，所以面板内边距一变这里就要跟着变。
    func testPageHeadingMatchesContract() throws {
        let (width, height) = try nativeSize("component/page-title", in: try contractJSON())
        XCTAssertEqual(HubMetrics.contentColumnWidth, CGFloat(width))
        XCTAssertEqual(HubMetrics.pageHeadingHeight, CGFloat(height))
    }

    /// bento 网格。合同 `component/bento-grid` 的 `nativeSize` 是 912 × 420。
    ///
    /// 高度等于四行加三条间距，所以这里同时钉住行高与间距。
    func testBentoGridMatchesContract() throws {
        let (width, height) = try nativeSize("component/bento-grid", in: try contractJSON())
        XCTAssertEqual(HubMetrics.contentColumnWidth, CGFloat(width))
        XCTAssertEqual(HubMetrics.bentoGridHeight(rows: HubMetrics.bentoColumns), CGFloat(height))
    }

    /// 组件卡。合同 `component/widget-card` 的 `nativeSize` 是 219 × 96。
    ///
    /// 一列一格，所以宽等于列宽，高等于行高。
    func testWidgetCardMatchesContract() throws {
        let (width, height) = try nativeSize("component/widget-card", in: try contractJSON())
        XCTAssertEqual(HubMetrics.bentoColumnWidth, CGFloat(width), accuracy: 0.001)
        XCTAssertEqual(HubMetrics.bentoRowHeight, CGFloat(height))
    }

    /// 合同给的是命中区，不是图形本身。
    func testTrayIconHitTargetMatchesContract() throws {
        let (width, height) = try nativeSize("component/tray-icon", in: try contractJSON())
        XCTAssertEqual(HubMetrics.trayIconHitTarget, CGFloat(width))
        XCTAssertEqual(HubMetrics.trayIconHitTarget, CGFloat(height))
    }

    /// 合同 `accessibilityRules` 的原文：不小于 24 点，主控件尽量 44 点。
    func testHitTargetRulesMatchContract() throws {
        let components = try XCTUnwrap(try contractJSON()["components"] as? [String: Any])
        let tabBar = try XCTUnwrap(components["component/tab-bar"] as? [String: Any])
        let rules = try XCTUnwrap(tabBar["accessibilityRules"] as? [String])
        let joined = rules.joined(separator: " ")

        XCTAssertTrue(joined.contains("at least 24 points"))
        XCTAssertTrue(joined.contains("44 points"))
        XCTAssertEqual(HubMetrics.minHitTarget, 24)
        XCTAssertEqual(HubMetrics.preferredHitTarget, 44)
    }

    // MARK: - 状态词汇

    func testHubStatesMatchContract() throws {
        let states = try XCTUnwrap(try contractJSON()["states"] as? [String: Any])
        let hub = try XCTUnwrap(states["menuBarAndNotchHub"] as? [String: Any])
        let entries = try XCTUnwrap(hub["hubStates"] as? [[String: Any]])

        let contractStates = entries.compactMap { $0["state"] as? String }
        XCTAssertEqual(HubState.allCases.map(\.rawValue), contractStates)

        // 每个状态的 copyKey 与 contractKey 都要与合同逐字一致。
        for entry in entries {
            let name = try XCTUnwrap(entry["state"] as? String)
            let state = try XCTUnwrap(HubState(rawValue: name))
            XCTAssertEqual(state.slug, entry["slug"] as? String, "\(name) 的 slug 不一致")
            XCTAssertEqual(state.copyKey, entry["copyKey"] as? String, "\(name) 的 copyKey 不一致")
            XCTAssertEqual(state.contractKey, entry["contractKey"] as? String, "\(name) 的 contractKey 不一致")
        }
    }

    /// 每个状态只能声明一种视觉来源。DEFAULT 使用 Covio 专属预渲染资源。
    @MainActor
    func testDefaultStatusItemUsesTheCovioAsset() throws {
        let states = try XCTUnwrap(try contractJSON()["states"] as? [String: Any])
        let hub = try XCTUnwrap(states["menuBarAndNotchHub"] as? [String: Any])
        let entries = try XCTUnwrap(hub["statusItemStates"] as? [[String: Any]])

        for entry in entries {
            let visualSourceCount = (entry["sfSymbol"] == nil ? 0 : 1)
                + (entry["renderer"] == nil ? 0 : 1)
                + (entry["assetName"] == nil ? 0 : 1)
            XCTAssertEqual(visualSourceCount, 1, "状态图标必须且只能声明一种视觉来源")
        }

        let defaultState = try XCTUnwrap(entries.first { $0["state"] as? String == "DEFAULT" })
        XCTAssertEqual(defaultState["assetName"] as? String, CovioStatusIcon.assetName)
        XCTAssertNil(defaultState["renderer"])
        XCTAssertNil(defaultState["sfSymbol"])
    }

    func testOutputStatesMatchContract() throws {
        let states = try XCTUnwrap(try contractJSON()["states"] as? [String: Any])
        let output = try XCTUnwrap(states["notchOutputHub"] as? [String: Any])
        let entries = try XCTUnwrap(output["states"] as? [[String: Any]])

        let contractStates = entries.compactMap { $0["name"] as? String }
        XCTAssertEqual(HubOutputState.allCases.map(\.rawValue), contractStates)

        for entry in entries {
            let name = try XCTUnwrap(entry["name"] as? String)
            let state = try XCTUnwrap(HubOutputState(rawValue: name))
            XCTAssertEqual(state.slug, entry["slug"] as? String, "\(name) 的 slug 不一致")
            XCTAssertEqual(state.copyKey, entry["copyKey"] as? String, "\(name) 的 copyKey 不一致")
            XCTAssertEqual(state.contractKey, entry["contractKey"] as? String, "\(name) 的 contractKey 不一致")
        }
    }

    /// 合同给的页签文案键必须真实存在。文案表在 `copy` 段。
    func testStateCopyKeysExistInContract() throws {
        let copy = try XCTUnwrap(try contractJSON()["copy"] as? [String: Any])
        for state in HubState.allCases {
            XCTAssertNotNil(copy[state.copyKey], "合同缺少文案键 \(state.copyKey)")
        }
        for state in HubOutputState.allCases {
            XCTAssertNotNil(copy[state.copyKey], "合同缺少文案键 \(state.copyKey)")
        }
    }

    /// 菜单栏用到的文案键也必须存在。
    func testStatusItemAndTrayCopyKeysExist() throws {
        let copy = try XCTUnwrap(try contractJSON()["copy"] as? [String: Any])
        for key in ["copy/status-item/default", "copy/tray/action/show-shelf",
                    "copy/tray/action/settings", "copy/tray/action/quit"] {
            XCTAssertNotNil(copy[key], "合同缺少文案键 \(key)")
        }
    }
}
