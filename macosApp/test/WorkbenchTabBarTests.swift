import AppKit
import SwiftUI
import XCTest
import kmpDomain
@testable import Covio

/// 顶栏与编辑模式的形态。
///
/// 顶栏是打样里替代左栏导航条的那一条，编辑模式是打样里的 S6。
/// 这里守的是「页签上的字与把手、编辑提示条上的计数、动作词和搜索清空的落点」。
@MainActor
final class WorkbenchTabBarTests: XCTestCase {
    private func panes() -> [PaneItem] {
        let model = WorkbenchModel()
        return model.panes(language: CopyLocale.language)
    }

    /// 每条页签都有文字标题。导航不靠图标区分目的地。
    func testEveryPaneCarriesAReadableTitle() {
        for pane in panes() {
            XCTAssertFalse(pane.title.isEmpty, "\(pane.id) 没有标题")
        }
    }

    /// 默认页签的标题各不相同。只显示文字时，重复标题会让用户分不清目的地。
    func testDefaultPaneTitlesAreDistinct() {
        let titles = panes().map(\.title)
        XCTAssertEqual(Set(titles).count, titles.count, "有两个默认页签用了同一个标题")
    }

    /// 页签宽度固定。默认六个页签必须一次显示完，不能因标题宽度改变选中背景。
    func testDefaultTabsUseAFixedWidthThatFitsTheBar() {
        let count = panes().count

        XCTAssertEqual(HubMetrics.tabReorderStep, HubMetrics.tabWidth + HubMetrics.tabGap)
        XCTAssertLessThanOrEqual(
            HubMetrics.tabsWidth(count: count),
            HubMetrics.tabStripWidth,
            "默认页签不应该触发横向滚动"
        )
    }

    /// 右端动作的有无不能挪动左侧元素。
    ///
    /// 首页右端有「编辑」，工作区右端没有动作。空动作位曾经是一块吃满剩余宽度的
    /// `Color.clear`：工作区的内容贴左，首页的内容整行居中，切换页签时整条顶栏横移。
    /// 见 #514。三种情况用同一个目的地渲染，选中背景因此不影响比较。
    func testThePageActionDoesNotShiftTheLeadingContent() throws {
        let withoutAction = try leadingInkColumn(pageAction: nil)
        let withEdit = try leadingInkColumn(pageAction: ContractCopy.copyHubActionEdit)
        let withDone = try leadingInkColumn(
            pageAction: ContractCopy.copyHubActionDone,
            isEditing: true
        )

        XCTAssertEqual(withEdit, withoutAction, "有「编辑」按钮时，左侧元素横移了")
        XCTAssertEqual(withDone, withoutAction, "编辑模式的「完成」按钮让左侧元素横移了")
    }

    /// 按 1 倍比例渲染一条顶栏，返回最左一列有墨迹的像素横坐标。
    private func leadingInkColumn(
        pageAction: LocalizedCopy?,
        isEditing: Bool = false
    ) throws -> Int {
        let panes = panes()
        let bar = WorkbenchTabBar(
            panes: panes,
            destination: .pane(id: try XCTUnwrap(panes.first).id),
            isEditing: isEditing,
            searchPlaceholder: ContractCopy.copyNavSearchPlaceholder,
            searchText: .constant(""),
            language: .english,
            pageAction: pageAction,
            reduceMotion: true,
            onHome: {},
            onSelect: { _ in },
            onReorder: { _, _ in },
            onPageAction: {},
            onHover: { _, _ in }
        )
        let renderer = ImageRenderer(content: bar)
        renderer.scale = 1
        let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage, "顶栏没有渲染出图像"))
        for x in 0..<bitmap.pixelsWide {
            for y in 0..<bitmap.pixelsHigh
            where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 {
                return x
            }
        }
        XCTFail("顶栏渲染出来是空白的")
        return -1
    }

    /// 页签数量不超过模型的上限。
    func testTheTabCountStaysWithinTheModelLimit() {
        XCTAssertLessThanOrEqual(panes().count, Int(WorkbenchConfig.companion.MAX_PANES))
        XCTAssertLessThanOrEqual(panes().count, Int(WorkbenchConfig.companion.MAX_WIDGETS))
    }

    /// 编辑提示条上的计数来自配置：可见工作区数与组件数。
    func testTheEditBannerCountsComeFromTheConfig() {
        let model = WorkbenchModel()
        XCTAssertEqual(model.visiblePaneCount, model.panes(language: CopyLocale.language).count)
        XCTAssertEqual(model.homeWidgets.count, 6)
    }

    /// 页签标题必须使用视图传入的语言，不能回落到系统语言。
    func testPaneTitlesUseTheRequestedLanguage() {
        let model = WorkbenchModel()
        let english = model.panes(language: .english)
        let chinese = model.panes(language: .simplifiedChinese)
        let builtInTabs: [HubTab] = [.now, .agent, .clipboard, .files, .devices, .settings]

        XCTAssertEqual(english.map(\.title), builtInTabs.map { $0.title.text(for: .english) })
        XCTAssertEqual(chinese.map(\.title), builtInTabs.map { $0.title.text(for: .simplifiedChinese) })
    }

    /// 动作词和搜索清空文案都在合同里，且中英都有。
    func testTheNavigationCopyComesFromTheContract() {
        for copy in [
            ContractCopy.copyHubActionHome,
            ContractCopy.copyHubActionEdit,
            ContractCopy.copyHubActionDone,
            ContractCopy.copyHubSearchClear,
        ] {
            XCTAssertFalse(copy.en.isEmpty, "\(copy.key ?? "?") 缺英文")
            XCTAssertFalse(copy.zhHans.isEmpty, "\(copy.key ?? "?") 缺中文")
        }
    }

    /// 编辑提示条与空态的文案都在合同里。
    func testTheEditingCopyComesFromTheContract() {
        for copy in [
            ContractCopy.copyHubEditBanner,
            ContractCopy.copyHubHomeEmptyTitle,
            ContractCopy.copyHubHomeEmptyHint,
            ContractCopy.copyHubHomeEmptyHintEditing,
        ] {
            XCTAssertFalse(copy.en.isEmpty, "\(copy.key ?? "?") 缺英文")
            XCTAssertFalse(copy.zhHans.isEmpty, "\(copy.key ?? "?") 缺中文")
        }
    }

    /// 四个尺寸档都有标签。
    func testEverySizeHasALabel() {
        for size in [WidgetSize.small, .wide, .tall, .large] {
            let copy = WidgetCatalog.sizeLabel(size)
            XCTAssertFalse(copy.en.isEmpty, "\(size.key) 缺英文标签")
            XCTAssertFalse(copy.zhHans.isEmpty, "\(size.key) 缺中文标签")
        }
    }

    /// 六种内置组件都有标题与底色，底色取自合同。
    func testEveryBuiltInWidgetHasATitleAndATint() {
        let kinds = ["w-clock", "w-battery", "w-transfer", "w-actions", "w-shots", "w-devices"]
        var tints: Set<String> = []
        for kind in kinds {
            let descriptor = WidgetCatalog.descriptor(for: kind, language: .simplifiedChinese)
            XCTAssertNotEqual(descriptor.title, kind, "\(kind) 没有走目录表，落到了兜底")
            XCTAssertFalse(descriptor.title.isEmpty)
            XCTAssertTrue(descriptor.tint.key.hasPrefix("token/color/widget-tint-"), "\(kind) 的底色不是组件色")
            tints.insert(descriptor.tint.key)
        }
        XCTAssertEqual(tints.count, kinds.count, "有两块组件用了同一个底色")
    }

    /// 认不出的种类也要显示。丢掉就丢了用户排好的位置。
    func testAnUnknownWidgetKindStillRenders() {
        let descriptor = WidgetCatalog.descriptor(for: "w-future", language: .simplifiedChinese)
        XCTAssertEqual(descriptor.title, "w-future")
        XCTAssertFalse(descriptor.tint.key.isEmpty)
    }

    /// 组件标题与尺寸标签都在合同里。
    func testTheWidgetCopyComesFromTheContract() {
        for copy in [
            ContractCopy.copyHubWidgetClockTitle,
            ContractCopy.copyHubWidgetBatteryTitle,
            ContractCopy.copyHubWidgetTransferTitle,
            ContractCopy.copyHubWidgetActionsTitle,
            ContractCopy.copyHubWidgetShotsTitle,
            ContractCopy.copyHubWidgetDevicesTitle,
        ] {
            XCTAssertFalse(copy.en.isEmpty, "\(copy.key ?? "?") 缺英文")
            XCTAssertFalse(copy.zhHans.isEmpty, "\(copy.key ?? "?") 缺中文")
        }
    }
}

/// 页签拖动排序的换算。
///
/// 一次拖动里 `onChanged` 连着来，位移是从起点累计的。
/// 这里守的是「每次只补新跨过的那几条」——把累计值重算一遍会让页签冲过头。
final class TabReorderStateTests: XCTestCase {
    private let step = HubMetrics.tabReorderStep

    /// 没拖动就不挪。
    func testNoTranslationMeansNoMove() {
        var state = TabReorderState(step: step)
        XCTAssertEqual(state.delta(forTranslation: 0), 0)
    }

    /// 不到一条的距离不算跨过。
    func testAShortDragDoesNotMove() {
        var state = TabReorderState(step: step)
        XCTAssertEqual(state.delta(forTranslation: step - 1), 0)
    }

    /// 跨过一条就补一条。
    func testCrossingOneStepMovesOne() {
        var state = TabReorderState(step: step)
        XCTAssertEqual(state.delta(forTranslation: step), 1)
    }

    /// 同一个位移连着报两次，第二次补零。这一条挡住的就是「冲过头」。
    func testRepeatingTheSameTranslationAddsNothing() {
        var state = TabReorderState(step: step)
        XCTAssertEqual(state.delta(forTranslation: step), 1)
        XCTAssertEqual(state.delta(forTranslation: step), 0)
    }

    /// 一路往右拖，每次只补新增的那一条。
    func testDraggingFurtherKeepsAddingOneAtATime() {
        var state = TabReorderState(step: step)
        XCTAssertEqual(state.delta(forTranslation: step), 1)
        XCTAssertEqual(state.delta(forTranslation: step * 2), 1)
        XCTAssertEqual(state.delta(forTranslation: step * 3), 1)
    }

    /// 拖回来是负数，页签往回挪。
    func testDraggingBackReturnsANegativeDelta() {
        var state = TabReorderState(step: step)
        XCTAssertEqual(state.delta(forTranslation: step * 2), 2)
        XCTAssertEqual(state.delta(forTranslation: step), -1)
        XCTAssertEqual(state.delta(forTranslation: 0), -1)
    }

    /// 松手之后从头计，下一次拖动不受上一次影响。
    func testResetForgetsThePreviousDrag() {
        var state = TabReorderState(step: step)
        XCTAssertEqual(state.delta(forTranslation: step * 3), 3)
        state.reset()
        XCTAssertEqual(state.delta(forTranslation: step * 3), 3)
    }

    /// 步长为零时不换算，也不除零。
    func testAZeroStepMovesNothing() {
        var state = TabReorderState(step: 0)
        XCTAssertEqual(state.delta(forTranslation: 999), 0)
    }
}

/// 首页卡片的副标题。
///
/// 有真实数据的用真实数据，没有的显示占位符，不编。
@MainActor
final class WidgetDetailTests: XCTestCase {
    /// 没有数据源的三块显示占位符。打样里它们是写死的假数据，不能照搬。
    func testWidgetsWithoutADataSourceShowThePlaceholder() {
        for kind in ["w-transfer", "w-actions", "w-devices"] {
            XCTAssertEqual(
                WidgetDetail.text(for: kind, runtime: nil, language: .simplifiedChinese),
                WidgetDetail.missing,
                "\(kind) 没有数据源，应该显示占位符"
            )
        }
    }

    /// 钟表块显示时间与星期。
    func testTheClockShowsTheTimeAndTheWeekday() {
        let text = WidgetDetail.text(for: "w-clock", runtime: nil, language: .simplifiedChinese)
        XCTAssertNotEqual(text, WidgetDetail.missing)
        XCTAssertTrue(text.contains("·"), "钟表块应该同时给时间与星期：\(text)")
    }

    /// 认不出的种类显示占位符。
    func testAnUnknownKindShowsThePlaceholder() {
        XCTAssertEqual(
            WidgetDetail.text(for: "w-future", runtime: nil, language: .english),
            WidgetDetail.missing
        )
    }
}
