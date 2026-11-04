import XCTest
@testable import Covio

/// bento 网格的装箱算法。
///
/// 显式位置来自配置，自动位置按组件顺序算出来。
/// 它错了的后果是卡片重叠、位置乱跳或旧配置无法迁移。
final class BentoPackerTests: XCTestCase {
    private func widget(_ id: String, _ size: WidgetSize) -> WidgetInstance {
        WidgetInstance(id: id, kind: id, size: size, settings: [:], column: -1, row: -1)
    }

    private func widget(_ id: String, _ size: WidgetSize, column: Int32, row: Int32) -> WidgetInstance {
        WidgetInstance(
            id: id,
            kind: id,
            size: size,
            settings: [:],
            column: column,
            row: row
        )
    }

    // MARK: - 基本摆放

    /// 小块从左往右填满一行。
    func testSmallWidgetsFillARowLeftToRight() {
        let spots = BentoPacker.pack(
            (0..<4).map { widget("w\($0)", .small) },
            columns: 4
        )
        XCTAssertEqual(spots.map(\.column), [0, 1, 2, 3])
        XCTAssertEqual(spots.map(\.row), [0, 0, 0, 0])
    }

    /// 宽块占两列，第二块接着放。
    func testWideWidgetsTakeTwoColumns() {
        let spots = BentoPacker.pack(
            [widget("a", .wide), widget("b", .wide)],
            columns: 4
        )
        XCTAssertEqual(spots.map(\.column), [0, 2])
        XCTAssertEqual(spots.map(\.row), [0, 0])
    }

    /// 一行放不下时换下一行。
    func testWidgetsWrapToTheNextRow() {
        let spots = BentoPacker.pack(
            [widget("a", .wide), widget("b", .wide), widget("c", .wide)],
            columns: 4
        )
        XCTAssertEqual(spots.map(\.row), [0, 0, 1])
        XCTAssertEqual(spots.last?.column, 0)
    }

    /// 高块占两行，后面的块绕开它。
    func testTallWidgetsBlockTheRowBelow() {
        let spots = BentoPacker.pack(
            [widget("tall", .tall), widget("a", .small), widget("b", .small)],
            columns: 4
        )
        XCTAssertEqual(spots[0].column, 0)
        XCTAssertEqual(spots[0].row, 0)
        XCTAssertEqual(spots[1].column, 1)
        XCTAssertEqual(spots[1].row, 0)
        XCTAssertEqual(spots[2].column, 2)
        XCTAssertEqual(spots[2].row, 0)
    }

    /// 大块占两列两行。
    func testLargeWidgetsTakeTwoColumnsAndTwoRows() {
        let spots = BentoPacker.pack([widget("big", .large)], columns: 4)
        XCTAssertEqual(spots.count, 1)
        XCTAssertEqual(BentoPacker.rows(spots), 2)
    }

    /// 显式位置保留下方与中间的空格，不按列表顺序重排。
    func testExplicitPositionsKeepEmptyCells() {
        let spots = BentoPacker.pack(
            [
                widget("top", .small),
                widget("lower", .small, column: 2, row: 3),
            ],
            columns: 4
        )

        XCTAssertEqual(spots[0].column, 0)
        XCTAssertEqual(spots[0].row, 0)
        XCTAssertEqual(spots[1].column, 2)
        XCTAssertEqual(spots[1].row, 3)
        XCTAssertEqual(BentoPacker.rows(spots), 4)
    }

    /// 自动摆放会避开先保留的显式位置。
    func testAutomaticWidgetsPackAroundExplicitPositions() {
        let spots = BentoPacker.pack(
            [
                widget("fixed", .small, column: 2, row: 0),
                widget("automatic", .small),
            ],
            columns: 4
        )

        XCTAssertEqual(spots[0].column, 2)
        XCTAssertEqual(spots[0].row, 0)
        XCTAssertEqual(spots[1].column, 0)
        XCTAssertEqual(spots[1].row, 0)
    }

    /// 两块卡片写了同一格时，先出现的一块保留位置，后一块自动落位。
    func testOverlappingExplicitPositionsFallBackToAutomaticPacking() {
        let spots = BentoPacker.pack(
            [
                widget("first", .small, column: 0, row: 0),
                widget("second", .small, column: 0, row: 0),
            ],
            columns: 4
        )

        XCTAssertEqual(spots[0].column, 0)
        XCTAssertEqual(spots[0].row, 0)
        XCTAssertEqual(spots[1].column, 1)
        XCTAssertEqual(spots[1].row, 0)
    }

    /// 显式布局落盘前会把自动位置一起写出来。
    func testMaterializingAssignsEveryPosition() {
        let widgets = [widget("fixed", .small, column: 2, row: 1), widget("automatic", .small)]
        let materialized = BentoPacker.materialized(widgets, columns: 4)

        XCTAssertEqual(materialized[0].column, 2)
        XCTAssertEqual(materialized[0].row, 1)
        XCTAssertEqual(materialized[1].column, 0)
        XCTAssertEqual(materialized[1].row, 0)
    }

    /// 目标位置必须可放、在边界内，并且不压到别的卡片。
    func testCanPlaceRejectsCollisionsAndOutOfBounds() {
        let spots = BentoPacker.pack(
            [
                widget("left", .small, column: 0, row: 0),
                widget("right", .small, column: 3, row: 0),
            ],
            columns: 4
        )

        XCTAssertTrue(
            BentoPacker.canPlace(
                id: "new", size: .small, column: 1, row: 0,
                among: spots, columns: 4, maximumRows: 1
            )
        )
        XCTAssertFalse(
            BentoPacker.canPlace(
                id: "new", size: .small, column: 0, row: 0,
                among: spots, columns: 4, maximumRows: 1
            )
        )
        XCTAssertFalse(
            BentoPacker.canPlace(
                id: "new", size: .small, column: 4, row: 0,
                among: spots, columns: 4, maximumRows: 1
            )
        )
        XCTAssertFalse(
            BentoPacker.canPlace(
                id: "new", size: .small, column: 1, row: 1,
                among: spots, columns: 4, maximumRows: 1
            )
        )
        XCTAssertTrue(
            BentoPacker.canPlace(
                id: "left", size: .small, column: 0, row: 0,
                among: spots, columns: 4, maximumRows: 1
            )
        )
    }

    // MARK: - 不重叠

    /// 任意一组组件装箱后都不重叠。重叠是布局里最难看的一种错。
    func testNoTwoWidgetsOverlap() {
        let widgets = [
            widget("a", .wide), widget("b", .small), widget("c", .tall),
            widget("d", .large), widget("e", .small), widget("f", .wide),
            widget("g", .small), widget("h", .tall), widget("i", .small),
        ]
        let spots = BentoPacker.pack(widgets, columns: 4)

        var taken: Set<BentoCell> = []
        for spot in spots {
            for offsetY in 0..<spot.size.gridRows {
                for offsetX in 0..<spot.size.gridColumns {
                    let cell = BentoCell(column: spot.column + offsetX, row: spot.row + offsetY)
                    XCTAssertTrue(taken.insert(cell).inserted, "\(spot.id) 与别的卡片重叠在 \(cell)")
                }
            }
        }
    }

    /// 装箱不丢组件，顺序也不变。顺序就是用户存的顺序。
    func testEveryWidgetKeepsItsOrder() {
        let widgets = [widget("a", .large), widget("b", .small), widget("c", .wide)]
        let spots = BentoPacker.pack(widgets, columns: 4)
        XCTAssertEqual(spots.map(\.id), ["a", "b", "c"])
        XCTAssertEqual(spots.map(\.order), [0, 1, 2])
    }

    /// 同样的输入永远给同样的输出。位置不落盘，重算时不能跳。
    func testPackingIsDeterministic() {
        let widgets = [widget("a", .wide), widget("b", .tall), widget("c", .small)]
        let first = BentoPacker.pack(widgets, columns: 4)
        let second = BentoPacker.pack(widgets, columns: 4)
        XCTAssertEqual(first, second)
    }

    // MARK: - 边界

    /// 列数为零时返回空，不崩。
    func testZeroColumnsPacksNothing() {
        XCTAssertTrue(BentoPacker.pack([widget("a", .small)], columns: 0).isEmpty)
    }

    /// 组件比网格还宽时按列数收窄，不会一直往下加行。
    func testAnOverwideWidgetIsClampedToTheColumnCount() {
        let spots = BentoPacker.pack([widget("a", .large)], columns: 1)
        XCTAssertEqual(spots.count, 1)
        XCTAssertEqual(spots[0].column, 0)
        XCTAssertEqual(spots[0].row, 0)
        XCTAssertEqual(BentoPacker.rows(spots), 2)
    }

    /// 空列表没有行。
    func testNoWidgetsMeansNoRows() {
        XCTAssertEqual(BentoPacker.rows([]), 0)
        XCTAssertTrue(BentoPacker.pack([], columns: 4).isEmpty)
    }

    // MARK: - 档位

    /// 列数与行数换成档位。与打样 `sizeOf` 一致。
    func testSizeFromColumnsAndRows() {
        XCTAssertEqual(BentoPacker.size(columns: 1, rows: 1), .small)
        XCTAssertEqual(BentoPacker.size(columns: 2, rows: 1), .wide)
        XCTAssertEqual(BentoPacker.size(columns: 1, rows: 2), .tall)
        XCTAssertEqual(BentoPacker.size(columns: 2, rows: 2), .large)
        // 超出上限也按最大档算。
        XCTAssertEqual(BentoPacker.size(columns: 4, rows: 3), .large)
    }

    /// 四档各占几列几行。
    func testGridSpansMatchTheFourSizes() {
        XCTAssertEqual(WidgetSize.small.gridColumns, 1)
        XCTAssertEqual(WidgetSize.small.gridRows, 1)
        XCTAssertEqual(WidgetSize.wide.gridColumns, 2)
        XCTAssertEqual(WidgetSize.wide.gridRows, 1)
        XCTAssertEqual(WidgetSize.tall.gridColumns, 1)
        XCTAssertEqual(WidgetSize.tall.gridRows, 2)
        XCTAssertEqual(WidgetSize.large.gridColumns, 2)
        XCTAssertEqual(WidgetSize.large.gridRows, 2)
    }

    /// 档位与列行数互转是同一件事，来回一趟不变。
    func testSizeRoundTripsThroughItsSpan() {
        for size in [WidgetSize.small, .wide, .tall, .large] {
            XCTAssertEqual(
                BentoPacker.size(columns: size.gridColumns, rows: size.gridRows).key,
                size.key
            )
        }
    }

    /// 按序列化键找回档位。认不出的键回退到模型给的兜底档，不崩。
    func testSizeLookupFallsBackForAnUnknownKey() {
        XCTAssertEqual(WidgetSize.from(key: "wide").key, "wide")
        XCTAssertEqual(WidgetSize.from(key: "nonsense").key, WidgetSize.companion.FALLBACK.key)
    }

    // MARK: - 缩放手柄

    /// 没拖动就保持原档位。
    func testResizingByNothingKeepsTheSize() {
        for size in [WidgetSize.small, .wide, .tall, .large] {
            XCTAssertEqual(resized(from: size, by: .zero).key, size.key)
        }
    }

    /// 往右拖过一列就把档位加宽。
    func testDraggingRightWidensTheCard() {
        XCTAssertEqual(resized(from: .small, by: CGSize(width: HubMetrics.bentoColumnStep, height: 0)), .wide)
    }

    /// 往下拖过一行就加高。
    func testDraggingDownHeightensTheCard() {
        XCTAssertEqual(resized(from: .small, by: CGSize(width: 0, height: HubMetrics.bentoRowStep)), .tall)
    }

    /// 拖过头夹到最大档。四档里最大的是「大」，占两列两行。
    func testDraggingTooFarStopsAtTheLargestSize() {
        XCTAssertEqual(resized(from: .small, by: CGSize(width: 9_999, height: 9_999)), .large)
    }

    /// 往回收缩夹到一格，不会算出零列零行。
    func testDraggingBackwardsStopsAtOneCell() {
        let size = resized(from: .large, by: CGSize(width: -9_999, height: -9_999))
        XCTAssertEqual(size.gridColumns, 1)
        XCTAssertEqual(size.gridRows, 1)
    }

    /// 基准是这次拖动开始时的档位，不是当前档位。
    ///
    /// 一次拖动里 `onChanged` 连着来，位移是从起点累计的。
    /// 若拿当前档位当基准，第二次 `onChanged` 会在第一次的结果上再加一遍，卡片自己滚起来。
    func testTheTranslationIsMeasuredFromTheBaseNotTheCurrentSize() {
        let half = CGSize(width: HubMetrics.bentoColumnStep / 2, height: 0)
        // 从「小」出发拖半格，还在第一列。
        XCTAssertEqual(resized(from: .small, by: half), .small)
        // 从「宽」出发拖同样半格，仍在第二列，不会跳到第三列。
        XCTAssertEqual(resized(from: .wide, by: half), .wide)
    }

    /// 往右下一起拖，一次到「大」。
    func testDraggingRightAndDownTogetherGivesTheLargestCard() {
        let diagonal = CGSize(width: HubMetrics.bentoColumnStep, height: HubMetrics.bentoRowStep)
        XCTAssertEqual(resized(from: .small, by: diagonal), .large)
    }

    /// 缩放手柄的换算。
    private func resized(from base: WidgetSize, by translation: CGSize) -> WidgetSize {
        BentoPacker.resized(from: base, translation: translation)
    }
}
