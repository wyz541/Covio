import XCTest
import kmpDomain
@testable import Covio

/// 生成的合同常量与合同本身是否一致。
///
/// `ContractCopy.swift` 与 `ContractTokens.swift` 由
/// `scripts/generate-contract-constants.py` 从 `docs/covio-design-contract.json` 生成。
/// 这里读同一份合同逐条比对，所以改了合同而忘了重跑脚本时测试会失败。
final class ContractConstantsTests: XCTestCase {
    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private func contract() throws -> [String: Any] {
        let url = Self.repoRoot.appendingPathComponent("docs/covio-design-contract.json")
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func copySection() throws -> [String: [String: String]] {
        try XCTUnwrap(try contract()["copy"] as? [String: [String: String]])
    }

    /// 每条生成的文案都要与合同一致，且键名在合同里存在。
    func testEveryGeneratedCopyMatchesTheContract() throws {
        let contract = try copySection()
        XCTAssertFalse(ContractCopy.all.isEmpty, "一条文案都没生成")

        for entry in ContractCopy.all {
            let key = try XCTUnwrap(entry.key, "生成的条目必须带合同键")
            guard let expected = contract[key] else {
                XCTFail("合同里没有键 \(key)")
                continue
            }
            XCTAssertEqual(entry.en, expected["en"], "\(key) 的英文文案与合同不一致")
            XCTAssertEqual(entry.zhHans, expected["zh-Hans"], "\(key) 的中文文案与合同不一致")
        }
    }

    /// 生成的条数要与合同一致。少一条说明生成器漏了。
    func testGeneratedCopyCoversTheWholeContract() throws {
        let contract = try copySection()
        let generated = Set(ContractCopy.all.compactMap(\.key))
        let missing = Set(contract.keys).subtracting(generated)
        XCTAssertTrue(missing.isEmpty, "这些键没有生成：\(missing.sorted())")
    }

    /// 颜色令牌逐条比对。`token/art/*` 是插图色，生成器不导出。
    func testEveryGeneratedColorMatchesTheContract() throws {
        let tokens = try XCTUnwrap(try contract()["tokens"] as? [String: [String: Any]])
        let expected = tokens.filter { !$0.key.hasPrefix("token/art/") && $0.value["type"] as? String == "color" }
        XCTAssertEqual(ContractColors.all.count, expected.count, "颜色条数与合同不一致")

        for token in ContractColors.all {
            guard let source = expected[token.key] else {
                XCTFail("合同里没有颜色 \(token.key)")
                continue
            }
            XCTAssertEqual(token.lightHex, source["light"] as? String, "\(token.key) 的浅色值不一致")
            XCTAssertEqual(token.darkHex, source["dark"] as? String, "\(token.key) 的深色值不一致")
        }
    }

    /// 尺寸令牌逐条比对。
    func testEveryGeneratedDimensionMatchesTheContract() throws {
        let tokens = try XCTUnwrap(try contract()["tokens"] as? [String: [String: Any]])
        let expected = tokens.filter { !$0.key.hasPrefix("token/art/") && $0.value["type"] as? String == "dimension" }
        XCTAssertEqual(ContractDimensions.all.count, expected.count, "尺寸条数与合同不一致")

        for (key, value) in ContractDimensions.all {
            guard let source = expected[key], let light = source["light"] as? Double else {
                XCTFail("合同里没有尺寸 \(key)")
                continue
            }
            XCTAssertEqual(Double(value), light, accuracy: 0.0001, "\(key) 的值不一致")
        }
    }

    /// 动效令牌逐条比对。合同里写毫秒，Swift 里是秒。
    func testEveryGeneratedMotionMatchesTheContract() throws {
        let tokens = try XCTUnwrap(try contract()["tokens"] as? [String: [String: Any]])
        let expected = tokens.filter { $0.value["type"] as? String == "duration" }
        XCTAssertFalse(expected.isEmpty, "合同里一条动效令牌都没有")
        XCTAssertEqual(ContractMotion.all.count, expected.count, "动效条数与合同不一致")

        for token in ContractMotion.all {
            guard let source = expected[token.key] else {
                XCTFail("合同里没有动效 \(token.key)")
                continue
            }
            let ms = try XCTUnwrap(source["durationMs"] as? Double, "\(token.key) 缺 durationMs")
            XCTAssertEqual(token.seconds, ms / 1000, accuracy: 0.0001, "\(token.key) 的时长不一致")
            XCTAssertEqual(token.minSeconds, (source["minMs"] as? Double ?? 0) / 1000, accuracy: 0.0001)
            XCTAssertEqual(token.maxSeconds, (source["maxMs"] as? Double ?? 0) / 1000, accuracy: 0.0001)
            XCTAssertEqual(token.curve, source["curve"] as? String, "\(token.key) 的曲线描述不一致")

            let reduced = (source["reducedMotionMs"] as? Double).map { $0 / 1000 }
            XCTAssertEqual(token.reducedSeconds, reduced, "\(token.key) 的减弱动态时长不一致")
        }
    }

    /// `HubMotion` 的取值必须来自合同，不能各写一份。
    ///
    /// 合同加动效令牌之前，`HubMotion` 是这些数字的唯一落点。
    /// 现在权威在合同，这里逐条比对，防止两边漂移。
    func testHubMotionComesFromTheContract() {
        XCTAssertEqual(HubMotion.expand, ContractMotion.tokenMotionHubExpand.seconds)
        XCTAssertEqual(HubMotion.collapse, ContractMotion.tokenMotionHubCollapse.seconds)
        XCTAssertEqual(HubMotion.tabSwitch, ContractMotion.tokenMotionTabSwitch.seconds)
        XCTAssertEqual(HubMotion.screenshotCapture, ContractMotion.tokenMotionScreenshotCapture.seconds)
        XCTAssertEqual(HubMotion.screenshotCopy, ContractMotion.tokenMotionScreenshotCopy.seconds)
        XCTAssertEqual(HubMotion.fileFocusSwitch, ContractMotion.tokenMotionFileFocusSwitch.seconds)
        XCTAssertEqual(
            HubMotion.fileFocusSwitchReduced,
            ContractMotion.tokenMotionFileFocusSwitch.reducedSeconds
        )
        XCTAssertEqual(HubMotion.transferStart, ContractMotion.tokenMotionTransferStart.seconds)
        XCTAssertEqual(HubMotion.transferComplete, ContractMotion.tokenMotionTransferComplete.seconds)
        XCTAssertEqual(HubMotion.errorAppear, ContractMotion.tokenMotionErrorAppear.seconds)
        XCTAssertEqual(HubMotion.reducedMotion, ContractMotion.tokenMotionReducedMotion.seconds)
        XCTAssertEqual(HubMotion.pointerExitCollapseDelay, ContractMotion.tokenMotionPointerExitCollapse.seconds)
    }

    /// 范围与减弱动态时长要自洽。写反了会让动画时长变成负数。
    func testMotionRangesAreOrdered() {
        for token in ContractMotion.all {
            XCTAssertLessThanOrEqual(token.minSeconds, token.seconds, "\(token.key) 的下限高于取值")
            XCTAssertLessThanOrEqual(token.seconds, token.maxSeconds, "\(token.key) 的取值高于上限")
            XCTAssertGreaterThan(token.seconds, 0, "\(token.key) 的时长必须为正")
            if let reduced = token.reducedSeconds {
                XCTAssertLessThanOrEqual(reduced, token.seconds, "\(token.key) 的减弱动态时长更长")
            }
        }
    }

    /// 合同里 `token/art/*` 不该被导出成 Swift 常量。
    /// 那些是插图装饰色，界面不该直接用。
    func testDecorativeArtTokensAreNotExported() {
        for token in ContractColors.all {
            XCTAssertFalse(token.key.hasPrefix("token/art/"), "装饰色不该导出：\(token.key)")
        }
    }

    /// macOS 的每个组件都要有 Swift 落点。
    ///
    /// schema 表达不了「macOS 下 `swiftMapping` 必填」，所以在这里拦一道。
    /// 同一份检查也在 `scripts/validate-contract.py` 里。
    func testEveryComponentHasASwiftMapping() throws {
        let components = try XCTUnwrap(try contract()["components"] as? [String: [String: Any]])
        XCTAssertFalse(components.isEmpty)

        for (key, component) in components {
            let mapping = component["swiftMapping"] as? [String: String]
            XCTAssertNotNil(mapping, "\(key) 没有 swiftMapping")
            XCTAssertFalse(mapping?["target"]?.isEmpty ?? true, "\(key) 的 Swift 落点是空的")
            XCTAssertFalse(mapping?["behavior"]?.isEmpty ?? true, "\(key) 的 Swift 行为说明是空的")
        }
    }

    /// 每条平台映射都要有 Swift 目标，且与组件的落点一致。
    func testPlatformMappingCarriesTheSwiftTarget() throws {
        let contract = try self.contract()
        let platform = try XCTUnwrap(contract["platformMapping"] as? [String: [String: String]])
        let components = try XCTUnwrap(contract["components"] as? [String: [String: Any]])
        XCTAssertFalse(platform.isEmpty)

        for (key, entry) in platform {
            let target = entry["swiftRuntimeTarget"]
            XCTAssertFalse(target?.isEmpty ?? true, "\(key) 没有 swiftRuntimeTarget")

            // platform/component/x 的落点必须与 component/x 的 swiftMapping 一致。
            guard key.hasPrefix("platform/component/") else { continue }
            let componentKey = String(key.dropFirst("platform/".count))
            let expected = (components[componentKey]?["swiftMapping"] as? [String: String])?["target"]
            XCTAssertEqual(target, expected, "\(key) 的落点与 \(componentKey) 不一致")
        }
    }

    /// 第三版文件区的组件、尺寸、状态、文案和动效必须在合同里。
    func testUnifiedFileAreaContractCarriesTheThirdPreview() throws {
        let components = try XCTUnwrap(try contract()["components"] as? [String: [String: Any]])
        let componentKeys = [
            "component/file-area",
            "component/file-focus-card",
            "component/file-quiet-tile",
            "component/file-filter-menu",
            "component/file-empty-state",
            "component/file-context-menu",
        ]
        for key in componentKeys {
            XCTAssertNotNil(components[key], "合同缺少 \(key)")
        }

        let focusSize = try XCTUnwrap(components["component/file-focus-card"]?["nativeSize"] as? [String: NSNumber])
        XCTAssertEqual(focusSize["width"]?.doubleValue, 912)
        XCTAssertEqual(focusSize["height"]?.doubleValue, 176)

        let tileSize = try XCTUnwrap(components["component/file-quiet-tile"]?["nativeSize"] as? [String: NSNumber])
        XCTAssertEqual(tileSize["width"]?.doubleValue, 217.5)
        XCTAssertEqual(tileSize["height"]?.doubleValue, 146)

        let fileAreaStates = try XCTUnwrap(components["component/file-area"]?["states"] as? [String])
        XCTAssertTrue(fileAreaStates.contains("state/component/file-area/default"))
        XCTAssertTrue(fileAreaStates.contains("state/component/file-area/empty"))
        XCTAssertTrue(fileAreaStates.contains("state/component/file-area/no-match"))

        let copy = try copySection()
        let copyKeys = [
            "copy/hub/files/filter/all",
            "copy/hub/files/filter/screenshots",
            "copy/hub/files/filter/files",
            "copy/hub/files/filter/text",
            "copy/hub/files/filter/transfers",
            "copy/hub/files/empty/title",
            "copy/hub/files/no-match/title",
            "copy/hub/files/kind/image",
            "copy/hub/files/kind/pdf",
            "copy/hub/files/kind/audio",
            "copy/hub/files/error/copy",
            "copy/hub/files/error/connection",
            "copy/hub/files/action/dismiss",
            "copy/hub/files/state/waiting",
            "copy/hub/files/state/transferring",
            "copy/hub/files/state/transfer-cancelled",
        ]
        for key in copyKeys {
            XCTAssertNotNil(copy[key], "合同缺少 \(key)")
        }

        let tokens = try XCTUnwrap(try contract()["tokens"] as? [String: [String: Any]])
        let focusSwitch = try XCTUnwrap(tokens["token/motion/file-focus-switch"])
        XCTAssertEqual((focusSwitch["durationMs"] as? NSNumber)?.doubleValue, 120)
        XCTAssertEqual((focusSwitch["reducedMotionMs"] as? NSNumber)?.doubleValue, 80)
    }

    /// 状态机的 Swift 映射表要指向真实存在的文件。
    func testSwiftStateMappingPointsAtRealFiles() throws {
        let states = try XCTUnwrap(try contract()["states"] as? [String: Any])
        let mapping = try XCTUnwrap(states["swiftRuntimeMapping"] as? [String: [String: String]])

        for (key, entry) in mapping {
            let path = try XCTUnwrap(entry["path"], "\(key) 没有 path")
            let url = Self.repoRoot.appendingPathComponent(path)
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: url.path),
                "\(key) 指向的文件不存在：\(path)"
            )
            XCTAssertFalse(entry["target"]?.isEmpty ?? true, "\(key) 没有 target")
        }
    }

    /// 合同声明已落地的接口，实现文件要真的在。
    func testImplementedKotlinInterfacesExist() throws {
        let metadata = try XCTUnwrap(try contract()["metadata"] as? [String: Any])
        let interfaces = try XCTUnwrap(metadata["kotlinInterfaces"] as? [[String: String]])
        XCTAssertEqual(interfaces.count, 4, "接口数量被改动了")

        for entry in interfaces {
            let name = try XCTUnwrap(entry["name"])
            XCTAssertEqual(entry["status"], "implemented", "\(name) 还没落地")
            let path = try XCTUnwrap(entry["path"], "\(name) 没有 path")
            let url = Self.repoRoot.appendingPathComponent(path)
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: url.path),
                "\(name) 的实现文件不存在：\(path)"
            )
        }
    }

    /// Kotlin 侧的合同读取器要能在 SwiftUI 宿主里跑起来。
    ///
    /// 这一条同时验证 `macosArm64` framework 的导出：数据类、枚举、
    /// 以及 `object` 的 `.shared` 写法。跑通了说明共享层的合同模型可用。
    func testKotlinContractReaderReadsTheShippedContract() throws {
        let path = Self.repoRoot.appendingPathComponent("docs/covio-design-contract.json").path
        let result = DesignContractReader.shared.readFile(path: path)

        let errorText = result.errors.map { $0.describe() }.joined(separator: "; ")
        XCTAssertTrue(result.isValid, "合同校验失败：\(errorText)")

        let contract = try XCTUnwrap(result.contract)
        XCTAssertEqual(contract.components.count, 30)
        XCTAssertEqual(contract.platformMappings.count, 33)
        XCTAssertEqual(contract.motionTokens.count, 11)
        XCTAssertEqual(contract.entry(key: "copy/app/name")?.en, "Covio")

        // 枚举导出成类，所以用 `==` 比较，不写 `switch`。
        XCTAssertTrue(result.errors.isEmpty)
        let warningText = result.warnings.map { $0.describe() }.joined(separator: "; ")
        XCTAssertTrue(result.warnings.isEmpty, "真合同不该有告警：\(warningText)")
    }

    /// 读不到的合同要变成诊断，不能抛异常跨到 Swift 终止进程。
    func testKotlinContractReaderReportsAMissingFile() {
        let result = DesignContractReader.shared.readFile(path: "/tmp/covio-没有这个合同.json")

        XCTAssertFalse(result.isValid)
        XCTAssertNil(result.contract)
        XCTAssertEqual(result.errors.count, 1)
        XCTAssertEqual(result.errors.first?.severity, DesignContractSeverity.error)
        XCTAssertEqual(result.errors.first?.path, "/tmp/covio-没有这个合同.json")
    }
}

/// 十六进制色值的解析。`MacTheme` 用它把合同的值转成颜色。
final class MacThemeTests: XCTestCase {
    /// 六位是 `RRGGBB`，不带透明度。
    func testSixDigitHexIsOpaque() {
        let color = MacTheme.nsColor(hex: "#4656A4")
        XCTAssertEqual(color.redComponent, 0x46 / 255.0, accuracy: 0.001)
        XCTAssertEqual(color.greenComponent, 0x56 / 255.0, accuracy: 0.001)
        XCTAssertEqual(color.blueComponent, 0xA4 / 255.0, accuracy: 0.001)
        XCTAssertEqual(color.alphaComponent, 1, accuracy: 0.001)
    }

    /// 八位是 `RRGGBBAA`，与 CSS 一致。合同里的半透明令牌都是这个形式。
    func testEightDigitHexCarriesAlpha() {
        let color = MacTheme.nsColor(hex: "#0000002E")
        XCTAssertEqual(color.alphaComponent, 0x2E / 255.0, accuracy: 0.001)
        XCTAssertEqual(color.redComponent, 0, accuracy: 0.001)
    }

    /// 认不出的值返回洋红色，好让错误一眼可见。
    func testBadHexIsObvious() {
        XCTAssertEqual(MacTheme.nsColor(hex: "not a color"), .magenta)
        XCTAssertEqual(MacTheme.nsColor(hex: "#12345"), .magenta)
        XCTAssertEqual(MacTheme.nsColor(hex: ""), .magenta)
    }

    /// 每个合同里的色值都要能解析。解析失败会变成洋红色。
    func testEveryContractColorParses() {
        for token in ContractColors.all {
            for hex in [token.lightHex, token.darkHex] {
                XCTAssertNotEqual(
                    MacTheme.nsColor(hex: hex),
                    .magenta,
                    "\(token.key) 的色值 \(hex) 解析失败"
                )
            }
        }
    }
}

/// 设置页的六个分节。
final class SettingsSectionTests: XCTestCase {
    /// 分节数量与顺序来自合同的 `copy/nav/*`。
    func testSectionsMatchTheContractNavOrder() {
        XCTAssertEqual(
            SettingsSection.allCases.map(\.rawValue),
            ["overview", "battery", "idle", "clipboard", "assistant", "general"]
        )
    }

    /// 每节都要有自己的导航名、页标题与页说明，且都来自合同。
    func testEachSectionHasContractCopy() {
        for section in SettingsSection.allCases {
            XCTAssertNotNil(section.navTitle.key, "\(section.rawValue) 的导航名没有合同键")
            XCTAssertNotNil(section.pageTitle.key, "\(section.rawValue) 的页标题没有合同键")
            XCTAssertNotNil(section.pageSummary.key, "\(section.rawValue) 的页说明没有合同键")
            XCTAssertFalse(section.navTitle.en.isEmpty)
            XCTAssertFalse(section.pageTitle.zhHans.isEmpty)
        }
    }

    /// 页面对应的内容高度。
    ///
    /// 面板高度是各段之和，所以这里比的是内容高度，不是某一页的绝对高度。
    /// 面板窗口的高度直接由它决定，改小了会把页面底部裁掉。
    func testEachPageContentHeightIsTheSumOfItsParts() {
        for tab in HubTab.allCases {
            let page = HubPage.pane(tab)
            XCTAssertEqual(
                HubMetrics.contentHeight(for: page),
                HubMetrics.plateTopInset + HubMetrics.plateStackHeight(for: page),
                "\(tab.rawValue) 的面板高度不等于内容层加上顶部的缝"
            )
            let actionRow = tab.hasInlineActions
                ? HubMetrics.pageActionHeight + HubMetrics.pageActionGap
                : 0
            XCTAssertEqual(
                HubMetrics.pageContentHeight(for: page),
                actionRow + HubMetrics.bodyHeight(for: page),
                "\(tab.rawValue) 的页内容高度不等于页操作行加主体"
            )
        }

        // 文件区按合同固定为 538 点；其余页仍按各自内容计算。
        XCTAssertEqual(HubMetrics.bodyHeight(for: .pane(.files)), HubMetrics.filesBodyHeight)
        XCTAssertEqual(HubMetrics.filesBodyHeight, FileAreaMetrics.areaHeight)
        XCTAssertGreaterThan(HubMetrics.filesBodyHeight, HubMetrics.clipboardBodyHeight)
        XCTAssertGreaterThan(HubMetrics.filesBodyHeight, HubMetrics.settingsBodyHeight)
        XCTAssertGreaterThan(HubMetrics.filesBodyHeight, HubMetrics.placeholderBodyHeight)

        // 还没落地的页签用占位高度。
        for tab in [HubTab.now, .board] {
            XCTAssertEqual(
                HubMetrics.bodyHeight(for: .pane(tab)),
                HubMetrics.placeholderBodyHeight,
                "\(tab.rawValue) 应该用占位高度"
            )
        }
    }

    /// 首页高度跟着网格行数走，不跟页签走。
    func testTheHomeHeightFollowsTheGridRows() {
        XCTAssertEqual(
            HubMetrics.bodyHeight(for: .home(rows: 0)),
            HubMetrics.emptyHomeHeight,
            "零行时应该用空态高度"
        )
        for rows in 1...4 {
            XCTAssertEqual(
                HubMetrics.bodyHeight(for: .home(rows: rows)),
                HubMetrics.bentoGridHeight(rows: rows),
                "\(rows) 行的首页高度不等于网格高度"
            )
        }
    }

    /// 面板必须盖得住顶栏与内容列。
    ///
    /// 编辑模式多一条提示条，也要盖得住。
    func testThePanelCoversTheTabBarAndThePageOnEveryPage() {
        for tab in HubTab.allCases {
            let page = HubPage.pane(tab)
            for editing in [false, true] {
                let plates = HubMetrics.plateStackHeight(for: page, editing: editing)
                let needed = HubMetrics.tabBarHeight
                    + HubMetrics.navigationContentGap
                    + HubMetrics.panelPadding * 2
                    + (editing ? HubMetrics.editBannerHeight + HubMetrics.pageGap : 0)
                    + HubMetrics.pageContentHeight(for: page)
                XCTAssertGreaterThanOrEqual(
                    plates,
                    needed,
                    "\(tab.rawValue) 编辑模式 \(editing) 的板高盖不住顶栏加页内容"
                )
            }
        }
    }
}

/// 设置页的格式化。纯函数，与 Compose 版逐字对齐。
final class SettingsFormatTests: XCTestCase {
    /// 时长的中文写法。
    func testChineseDuration() {
        XCTAssertEqual(SettingsFormat.duration(seconds: 300, language: .simplifiedChinese), "5分")
        XCTAssertEqual(SettingsFormat.duration(seconds: 3_600, language: .simplifiedChinese), "1小时0分")
        XCTAssertEqual(SettingsFormat.duration(seconds: 5_400, language: .simplifiedChinese), "1小时30分")
        XCTAssertEqual(SettingsFormat.duration(seconds: 86_400, language: .simplifiedChinese), "24小时0分")
    }

    /// 时长的英文写法。
    func testEnglishDuration() {
        XCTAssertEqual(SettingsFormat.duration(seconds: 300, language: .english), "5m")
        XCTAssertEqual(SettingsFormat.duration(seconds: 3_600, language: .english), "1h 0m")
        XCTAssertEqual(SettingsFormat.duration(seconds: 5_400, language: .english), "1h 30m")
        XCTAssertEqual(SettingsFormat.duration(seconds: 86_400, language: .english), "24h 0m")
    }

    /// 三种休眠模式都要有名字，且随语言变化。
    func testSleepModeLabelsCoverEverySupportedMode() {
        for mode in ModelsKt.SUPPORTED_HIBERNATE_MODES {
            let english = SettingsFormat.sleepModeLabel(mode.int32Value, language: .english)
            let chinese = SettingsFormat.sleepModeLabel(mode.int32Value, language: .simplifiedChinese)
            XCTAssertFalse(english.isEmpty)
            XCTAssertFalse(chinese.isEmpty)
            XCTAssertNotEqual(english, chinese, "模式 \(mode) 的中英文名字一样")
        }
    }

    /// 时间用系统时区渲染，格式与 Compose 版一致。
    func testWakeTimeUsesTheDocumentedFormat() {
        let text = SettingsFormat.wakeTime(epochSeconds: 1_700_000_000)
        XCTAssertEqual(text.count, 19, "格式应为 yyyy-MM-dd HH:mm:ss：\(text)")
        XCTAssertEqual(text.filter { $0 == "-" }.count, 2)
        XCTAssertEqual(text.filter { $0 == ":" }.count, 2)
    }

    /// 实际语言码与 Kotlin 的 `AppLanguage` 一致，空偏好回落到系统语言。
    func testLanguageCodesMatchKotlin() {
        XCTAssertEqual(AppLanguage.english.rawValue, "en")
        XCTAssertEqual(AppLanguage.simplifiedChinese.rawValue, "zh-CN")
        XCTAssertEqual(AppLanguagePreference.system.rawValue, "")
        XCTAssertEqual(AppLanguagePreference.english.rawValue, "en")
        XCTAssertEqual(AppLanguagePreference.simplifiedChinese.rawValue, "zh-CN")
        XCTAssertEqual(AppLanguagePreference.fromCode(nil), .system)
        XCTAssertEqual(AppLanguagePreference.fromCode(""), .system)
        XCTAssertEqual(AppLanguagePreference.fromCode("system"), .system)
        XCTAssertEqual(AppLanguagePreference.fromCode("zh"), .simplifiedChinese)
        XCTAssertEqual(AppLanguagePreference.fromCode("zh-Hans-CN"), .simplifiedChinese)
        XCTAssertEqual(AppLanguagePreference.fromCode("en-US"), .english)
        XCTAssertEqual(AppLanguage.fromCode("en"), .english)
        XCTAssertEqual(AppLanguage.fromCode("zh-CN"), .simplifiedChinese)
        XCTAssertEqual(AppLanguage.fromCode(nil), CopyLocale.language)
        XCTAssertEqual(AppLanguage.fromCode("fr"), CopyLocale.language)
    }

    /// 首期只支持中英文，其他系统语言显示英文。
    func testSystemLanguageFallsBackToEnglish() {
        XCTAssertEqual(
            CopyLocale.language(preferredLanguages: ["zh-Hans-CN", "en-US"]),
            .simplifiedChinese
        )
        XCTAssertEqual(CopyLocale.language(preferredLanguages: ["en-US"]), .english)
        XCTAssertEqual(CopyLocale.language(preferredLanguages: ["fr-FR"]), .english)
        XCTAssertEqual(CopyLocale.language(preferredLanguages: []), .english)
    }
}
