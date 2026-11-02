import XCTest
import kmpDomain
@testable import Covio

/// 设置项的目录表。
///
/// 目录表是搜索的唯一数据源。表里的锚点必须与页面上的
/// `.settingsRowAnchor(_:)` 一一对应，否则跳转会滚到一个不存在的位置。
@MainActor
final class SettingsCatalogTests: XCTestCase {
    /// 锚点全表唯一。重复的锚点会让 `ScrollViewReader` 滚错行。
    func testRowIDsAreUnique() {
        let ids = SettingsCatalog.entries.map(\.rowID)
        XCTAssertEqual(Set(ids).count, ids.count, "有重复的行锚点")
    }

    /// 每个分节都有可搜的设置项。
    func testEverySectionHasRows() {
        for section in SettingsSection.allCases {
            XCTAssertFalse(
                SettingsCatalog.entries.filter { $0.section == section }.isEmpty,
                "\(section.rawValue) 没有任何设置项"
            )
        }
    }

    /// 目录表里的分节覆盖六个分节，且顺序与 `SettingsSection.allCases` 一致。
    func testSectionOrderFollowsTheSectionList() {
        var seen: [SettingsSection] = []
        for entry in SettingsCatalog.entries where seen.last != entry.section {
            if !seen.contains(entry.section) { seen.append(entry.section) }
        }
        XCTAssertEqual(seen, SettingsSection.allCases)
    }

    /// 每条都有合同键的标题，中英都不为空。
    func testEveryEntryHasCopy() {
        for entry in SettingsCatalog.entries {
            XCTAssertNotNil(entry.title.key, "\(entry.rowID) 的标题没有合同键")
            XCTAssertFalse(entry.title.en.isEmpty, "\(entry.rowID) 缺英文标题")
            XCTAssertFalse(entry.title.zhHans.isEmpty, "\(entry.rowID) 缺中文标题")
            XCTAssertFalse(entry.keywords.isEmpty, "\(entry.rowID) 没有关键词")
        }
    }

    /// 锚点常量与目录表里的值一致。
    ///
    /// 页面引用的是常量，目录表写的是字符串。两边不一致时跳转会失效。
    func testAnchorConstantsMatchTheCatalog() {
        let constants: [String] = [
            SettingsRowID.overviewMaster,
            SettingsRowID.batteryEnabled,
            SettingsRowID.batteryCapacity,
            SettingsRowID.batteryTime,
            SettingsRowID.idlePrevent,
            SettingsRowID.idleCharging,
            SettingsRowID.idleCancel,
            SettingsRowID.clipboardEnabled,
            SettingsRowID.clipboardHotKeys,
            SettingsRowID.assistantChat,
            SettingsRowID.assistantModel,
            SettingsRowID.assistantExternalAgent,
            SettingsRowID.generalDarkWake,
            SettingsRowID.generalSleepMode,
            SettingsRowID.generalLanguage,
            SettingsRowID.generalLogin,
            SettingsRowID.generalNotifications,
            SettingsRowID.generalUpdates,
            SettingsRowID.generalVersion,
            SettingsRowID.generalLogs,
            SettingsRowID.generalReset,
        ]
        XCTAssertEqual(Set(constants), Set(SettingsCatalog.entries.map(\.rowID)))
    }
}

/// 搜索索引。
@MainActor
final class SettingsSearchIndexTests: XCTestCase {
    func testEmptyQueryReturnsNothing() {
        XCTAssertTrue(SettingsSearchIndex.search("", language: .simplifiedChinese).isEmpty)
        XCTAssertTrue(SettingsSearchIndex.search("   ", language: .english).isEmpty)
    }

    /// 命中标题。
    func testMatchesTheTitle() {
        let hits = SettingsSearchIndex.search("hibernate", language: .english)
        XCTAssertTrue(hits.contains { $0.rowID == SettingsRowID.generalSleepMode })
    }

    /// 中文标题也能搜到。
    func testMatchesTheChineseTitle() {
        let hits = SettingsSearchIndex.search("休眠", language: .simplifiedChinese)
        XCTAssertTrue(hits.contains { $0.rowID == SettingsRowID.generalSleepMode })
    }

    /// Helper 不是用户设置；助手与模型现在是设置项。
    func testHelperIsNotAUserFacingSettingAndAssistantIs() {
        XCTAssertTrue(SettingsSearchIndex.search("helper", language: .english).isEmpty)
        XCTAssertTrue(SettingsSearchIndex.search("privileged", language: .english).isEmpty)
        XCTAssertTrue(
            SettingsSearchIndex.search("助手", language: .simplifiedChinese)
                .contains { $0.rowID == SettingsRowID.assistantChat }
        )
    }

    /// 模型与外部服务跳转时进入助手分节。
    func testAssistantSettingsStayInTheAssistantSection() {
        for rowID in [SettingsRowID.assistantModel, SettingsRowID.assistantExternalAgent] {
            let hit = SettingsCatalog.entries.first { $0.rowID == rowID }
            XCTAssertEqual(hit?.section, .assistant)
        }
    }

    /// 命中关键词。关键词里同时有中文与英文，两种界面语言都能用。
    func testMatchesKeywordsInBothLanguages() {
        let english = SettingsSearchIndex.search("hibernatemode", language: .english)
        let chinese = SettingsSearchIndex.search("hibernatemode", language: .simplifiedChinese)
        XCTAssertFalse(english.isEmpty, "关键词没有命中")
        XCTAssertEqual(english.map(\.rowID), chinese.map(\.rowID))
    }

    /// 不区分大小写。
    func testIgnoresCase() {
        let lower = SettingsSearchIndex.search("language", language: .english)
        let upper = SettingsSearchIndex.search("LANGUAGE", language: .english)
        XCTAssertEqual(lower.map(\.rowID), upper.map(\.rowID))
        XCTAssertFalse(lower.isEmpty)
    }

    /// 用英文查中文界面也能查到。
    func testMatchesTheOtherLanguage() {
        let hits = SettingsSearchIndex.search("clipboard", language: .simplifiedChinese)
        XCTAssertTrue(hits.contains { $0.rowID == SettingsRowID.clipboardEnabled })
    }

    /// 没有命中时返回空列表。
    func testUnknownQueryReturnsNothing() {
        XCTAssertTrue(SettingsSearchIndex.search("zzzz-not-a-setting", language: .english).isEmpty)
    }

    /// 结果按分节顺序返回。
    func testResultsFollowTheSectionOrder() {
        // 「电池」命中电池节的标题与阈值设置。
        let hits = SettingsSearchIndex.search("电池", language: .simplifiedChinese)
        XCTAssertGreaterThan(hits.count, 1)

        let order = SettingsSection.allCases
        let indices = hits.compactMap { order.firstIndex(of: $0.section) }
        XCTAssertEqual(indices, indices.sorted(), "结果没有按分节顺序返回")
    }

    /// 结果数量有上限。
    func testResultsAreCapped() {
        // 空字符串之外，几乎能命中全部的关键词。
        let hits = SettingsSearchIndex.search("e", language: .english)
        XCTAssertLessThanOrEqual(hits.count, SettingsSearchIndex.maxResults)
    }

    /// 命中带着所属分节，跳转时直接用它。
    func testHitCarriesTheSection() {
        let hits = SettingsSearchIndex.search("hibernate", language: .english)
        XCTAssertFalse(hits.isEmpty)
        for hit in hits {
            XCTAssertEqual(hit.section, hit.entry.section)
            XCTAssertEqual(hit.id, hit.rowID)
        }
    }
}

/// 行的锚点是否真的挂在视图上。
///
/// 目录表里有、页面上没挂锚点的行，搜索会跳到不存在的位置。
/// `ScrollViewReader.scrollTo` 找不到目标时什么都不做，也不报错，
/// 所以这类缺陷在界面上表现为「搜得到，点了没反应」。
///
/// 电池页的容量阈值与剩余时间阈值就这样漏过一次。见 ADR-001 实测 34。
///
/// 这个套件读源码文本，不构建视图。名字与值的对应关系由
/// `SettingsCatalogTests.testAnchorConstantsMatchTheCatalog` 负责，
/// 两条断言合起来覆盖「每个目录项都有锚点」。
final class SettingsRowAnchorCoverageTests: XCTestCase {
    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    /// 页面上出现的锚点名，即 `.settingsRowAnchor(SettingsRowID.x)` 里的 `x`。
    private static let anchorMarker = ".settingsRowAnchor(SettingsRowID."
    /// `SettingsRowID` 里的常量声明前缀。
    private static let declarationMarker = "static let "

    /// 声明了却没有挂到任何视图上的锚点。
    func testEveryDeclaredRowIDIsAnchoredInAView() throws {
        let declared = try declaredRowIDNames()
        let anchored = try anchoredRowIDNames()

        XCTAssertGreaterThan(declared.count, 15, "没读到 SettingsRowID 的声明")
        XCTAssertFalse(anchored.isEmpty, "没读到任何锚点")

        let missing = declared.subtracting(anchored).sorted()
        XCTAssertTrue(
            missing.isEmpty,
            "这些锚点没有挂在视图上，搜索会跳到不存在的位置：\(missing)"
        )
    }

    /// 扫描范围包含页面与复用行件。路径算错时这条会失败，
    /// 而不是让上一条在空集合上白过。
    func testScanSeesTheSettingsViews() throws {
        let files = try sourceFiles()
            .map { $0.path.replacingOccurrences(of: Self.repoRoot.path + "/", with: "") }
        XCTAssertTrue(files.contains("macosApp/src/Hub/Settings/pages/BatteryPage.swift"))
        XCTAssertTrue(files.contains("macosApp/src/Hub/Settings/SettingsRows.swift"))
        XCTAssertTrue(files.contains("macosApp/src/Hub/Settings/SettingsCatalog.swift"))
    }

    /// 目录表里的锚点一定来自 `SettingsRowID`。
    ///
    /// 目录项直接写字符串时 `declaredRowIDNames()` 读不到它，锚点也就不用挂。
    func testCatalogRowIDsAreDeclaredConstants() {
        let declared = SettingsCatalog.entries.map(\.rowID)
        XCTAssertEqual(Set(declared).count, declared.count, "有重复的行锚点")
        for rowID in declared {
            XCTAssertFalse(rowID.isEmpty)
            XCTAssertTrue(
                rowID.contains("."),
                "\(rowID) 不像锚点常量，检查 SettingsCatalog"
            )
        }
    }

    private func sourceFiles() throws -> [URL] {
        let root = Self.repoRoot.appendingPathComponent("macosApp/src")
        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        )
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    /// 标记之后紧跟的标识符。扫描用的是纯文本，不引入正则。
    private func names(after marker: String, in text: Substring) -> Set<String> {
        var names: Set<String> = []
        var search = text
        while let range = search.range(of: marker) {
            let rest = search[range.upperBound...]
            let name = rest.prefix { $0.isLetter || $0.isNumber || $0 == "_" }
            if !name.isEmpty { names.insert(String(name)) }
            search = rest
        }
        return names
    }

    private func declaredRowIDNames() throws -> Set<String> {
        let url = Self.repoRoot.appendingPathComponent("macosApp/src/Hub/Settings/SettingsCatalog.swift")
        let text = try String(contentsOf: url, encoding: .utf8)
        // 只读 `enum SettingsRowID` 那一段，避免把目录表里的别的常量算进来。
        let section = try XCTUnwrap(text.range(of: "enum SettingsRowID"))
        let body = text[section.lowerBound...]
        // 顶层枚举的收尾大括号在第 0 列，这是结束位置。
        let end = body.range(of: "\n}")?.lowerBound ?? body.endIndex
        return names(after: Self.declarationMarker, in: body[..<end])
    }

    private func anchoredRowIDNames() throws -> Set<String> {
        var found: Set<String> = []
        for url in try sourceFiles() {
            let text = try String(contentsOf: url, encoding: .utf8)
            found.formUnion(names(after: Self.anchorMarker, in: text[...]))
        }
        return found
    }
}
