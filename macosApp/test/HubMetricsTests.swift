import SwiftUI
import XCTest
import kmpDomain
@testable import Covio

/// Hub 面板的几何。
///
/// 面板由悬浮顶栏与内容列组成。内容列延伸到顶栏背后，并自带内边距。
/// 页签提供页面标识；内容列只给需要页面动作的工作区保留操作行。
/// 这里的每一条都在核对「加法有没有漏项」，因为漏项的后果是内容被裁掉，
/// 而裁掉的部分在测试里看不出来。
@MainActor
final class HubMetricsTests: XCTestCase {
    /// 内容列宽度等于面板宽度减去两边内边距。
    func testTheContentColumnFitsInsideThePanel() {
        XCTAssertEqual(
            HubMetrics.contentColumnWidth,
            HubMetrics.panelWidth - HubMetrics.panelPadding * 2
        )
        XCTAssertGreaterThan(HubMetrics.contentColumnWidth, 0)
        // 晾衣线的卡片按这个宽度排布，太窄就放不下。
        XCTAssertGreaterThan(HubMetrics.contentColumnWidth, 600)
    }

    /// 顶栏放得下四件：首页入口、搜索框、页签区、动作按钮。
    ///
    /// 页签区占剩下的宽度，所以固定件的和必须小于内容列宽度。
    func testTheTabBarLeavesRoomForTheTabStrip() {
        let used = HubMetrics.tabBarFixedWidth + HubMetrics.tabBarHPadding * 2
        XCTAssertLessThan(used, HubMetrics.panelWidth)
        XCTAssertGreaterThan(HubMetrics.panelWidth - used, 200)
    }

    /// 顶栏高度放得下最高的一件，并且与合同里的 46 点一致。
    func testTheTabBarIsTallerThanItsItems() {
        let tallest = max(
            HubMetrics.tabHeight,
            HubMetrics.homeEntryHeight,
            HubMetrics.searchFieldHeight
        )
        XCTAssertGreaterThan(HubMetrics.tabBarHeight, tallest)
    }

    /// 页面自然板高等于顶栏、内容顶部留白、内容列内边距与页内容之和。
    func testTheNaturalPlateStackHeightIsTheSumOfItsParts() {
        for page in Self.allPages {
            let expected = HubMetrics.tabBarHeight
                + HubMetrics.navigationContentGap
                + HubMetrics.panelPadding * 2
                + HubMetrics.pageContentHeight(for: page)
            XCTAssertEqual(HubMetrics.naturalPlateStackHeight(for: page), expected)
        }
    }

    /// 首屏内容在导航层下方开始。内容仍可滚动到导航层背后。
    func testTheContentStartsBelowTheNavigationLayer() {
        XCTAssertEqual(
            HubMetrics.contentTopPadding,
            HubMetrics.tabBarHeight
                + HubMetrics.navigationContentGap
                + HubMetrics.panelPadding
        )
        XCTAssertGreaterThan(HubMetrics.contentTopPadding, HubMetrics.tabBarHeight)
    }

    /// 页面自然高度加上顶栏与菜单栏之间的缝。这个值不决定窗口尺寸。
    func testTheNaturalContentHeightAddsTheGapAboveThePlates() {
        for page in Self.allPages {
            XCTAssertEqual(
                HubMetrics.naturalContentHeight(for: page),
                HubMetrics.plateTopInset + HubMetrics.naturalPlateStackHeight(for: page)
            )
        }
    }

    /// 编辑模式在内容列顶部多一条提示条，提示条下面留一段间距。
    func testEditingAddsTheBannerAndItsGap() {
        for page in Self.allPages {
            XCTAssertEqual(
                HubMetrics.naturalContentHeight(for: page, editing: true),
                HubMetrics.naturalContentHeight(for: page)
                    + HubMetrics.editBannerHeight
                    + HubMetrics.pageGap
            )
        }
    }

    /// 首选外壳高度来自合同，并覆盖监控页当前的三行卡片布局。
    func testThePreferredShellHeightCoversTheMonitorPage() {
        XCTAssertEqual(
            HubMetrics.preferredShellContentHeight,
            ContractDimensions.tokenSizeWorkbenchShellHeight
        )
        XCTAssertGreaterThanOrEqual(
            HubMetrics.preferredShellContentHeight,
            HubMetrics.naturalContentHeight(for: .pane(.devices))
        )
    }

    /// 外壳高度只由屏幕决定。大屏取首选值，小屏收缩到可用高度。
    func testTheShellHeightDependsOnTheScreenOnly() {
        XCTAssertEqual(
            HubMetrics.shellContentHeight(screenHeight: 1_117, safeAreaTop: 32),
            HubMetrics.preferredShellContentHeight
        )
        XCTAssertEqual(
            HubMetrics.shellContentHeight(screenHeight: 768, safeAreaTop: 0),
            HubMetrics.hubMaxHeight(screenHeight: 768)
        )
        XCTAssertEqual(
            HubMetrics.shellPlateStackHeight(screenHeight: 768, safeAreaTop: 0),
            HubMetrics.hubMaxHeight(screenHeight: 768) - HubMetrics.plateTopInset
        )
    }

    /// 首页没有页操作行，直接从网格开始。
    func testTheHomePageHasNoActionRow() {
        for rows in [0, 1, 4] {
            let page = HubPage.home(rows: rows)
            XCTAssertEqual(HubMetrics.pageContentHeight(for: page), HubMetrics.bodyHeight(for: page))
        }
    }

    /// 只有带页面动作的工作区多出操作行与间距。
    func testOnlyPanesWithActionsReserveAnActionRow() {
        for tab in HubTab.allCases {
            let actionRow = tab.hasInlineActions
                ? HubMetrics.pageActionHeight + HubMetrics.pageActionGap
                : 0
            XCTAssertEqual(
                HubMetrics.pageContentHeight(for: .pane(tab)),
                actionRow + HubMetrics.bodyHeight(for: .pane(tab))
            )
        }

        XCTAssertTrue(HubTab.agent.hasInlineActions)
        XCTAssertFalse(HubTab.clipboard.hasInlineActions)
        XCTAssertFalse(HubTab.files.hasInlineActions)
        XCTAssertFalse(HubTab.devices.hasInlineActions)
        XCTAssertFalse(HubTab.settings.hasInlineActions)
    }

    /// 每个页面的自然内容高度都比 0 大。零高度说明某一段漏算了。
    func testEveryPageHasAPositiveContentHeight() {
        for page in Self.allPages {
            XCTAssertGreaterThan(HubMetrics.naturalContentHeight(for: page), 0, "\(page) 的内容高度为 0")
        }
    }

    /// 四列网格加中间三条间距正好填满内容列。
    func testTheBentoColumnsFillTheContentColumn() {
        let span = HubMetrics.bentoColumnWidth * CGFloat(HubMetrics.bentoColumns)
            + HubMetrics.bentoGap * CGFloat(HubMetrics.bentoColumns - 1)
        XCTAssertEqual(span, HubMetrics.contentColumnWidth, accuracy: 0.001)
        XCTAssertGreaterThan(HubMetrics.bentoColumnWidth, 0)
    }

    /// 跨列的卡片宽度等于各列加中间的间距。跨行的卡片高度同理。
    func testAMultiSpanCardCountsTheGapsInBetween() {
        XCTAssertEqual(
            HubMetrics.bentoCardWidth(columns: 2),
            HubMetrics.bentoColumnWidth * 2 + HubMetrics.bentoGap
        )
        XCTAssertEqual(
            HubMetrics.bentoCardHeight(rows: 2),
            HubMetrics.bentoRowHeight * 2 + HubMetrics.bentoGap
        )
        // 跨一列一行就是单格。
        XCTAssertEqual(HubMetrics.bentoCardWidth(columns: 1), HubMetrics.bentoColumnWidth)
        XCTAssertEqual(HubMetrics.bentoCardHeight(rows: 1), HubMetrics.bentoRowHeight)
    }

    /// 网格高度等于各行加中间的间距。零行时是零。
    func testTheGridHeightCountsTheGapsInBetween() {
        XCTAssertEqual(HubMetrics.bentoGridHeight(rows: 0), 0)
        XCTAssertEqual(HubMetrics.bentoGridHeight(rows: 1), HubMetrics.bentoRowHeight)
        XCTAssertEqual(
            HubMetrics.bentoGridHeight(rows: 4),
            HubMetrics.bentoRowHeight * 4 + HubMetrics.bentoGap * 3
        )
    }

    /// 面板宽度不超过 Hub 的宽度上限：面板窗口按面板宽度居中，不会左右越界。
    func testThePanelWidthFitsTheHubWidth() {
        for screenWidth in [CGFloat(1_280), 1_440, 1_920, 2_560] {
            XCTAssertGreaterThanOrEqual(HubMetrics.hubWidth(screenWidth: screenWidth), HubMetrics.panelWidth)
        }
    }

    /// 剪切板页高按各段相加。
    ///
    /// 提示条可能出现也可能不出现，所以按它出现算。
    /// 这一页的高度常数以前少算过一段，结果底部按钮行被裁。
    /// 见 `docs/adr/adr-0001-macos-ui-swiftui.md` 实测 33。
    /// 文件页的同一条断言在 `WorkspaceTests`。
    func testTheClipboardPageHeightIsTheSumOfItsParts() {
        // 页自己的上下内边距没了：内边距现在由内容列统一给。
        let expected = ClipboardTabView.listHeight
            + ClipboardTabView.noticeGap
            + ClipboardTabView.noticeHeight
        XCTAssertEqual(
            HubMetrics.bodyHeight(for: .pane(.clipboard)),
            expected,
            "剪切板页的主体高不等于各段之和"
        )
        XCTAssertGreaterThan(
            HubMetrics.bodyHeight(for: .pane(.clipboard)),
            HubMetrics.placeholderBodyHeight
        )
    }

    /// 测试要遍历的全部页面。首页取零行、一行与默认行数三种。
    private static var allPages: [HubPage] {
        [.home(rows: 0), .home(rows: 1), .home(rows: HubMetrics.defaultHomeRows)]
            + HubTab.allCases.map { HubPage.pane($0) }
    }
}
