import SwiftUI

/// 首页的 bento 网格。合同 `component/bento-grid`，`nativeSize` 是 912 × 420。
///
/// 四列，行高 96 点，间距 12 点。卡片的位置由模型保存，视图只负责画。
///
/// 编辑模式里卡片可拖动、可缩放、可删除。
/// 拖动时显示目标格；占用或越界时不放置。
struct BentoGrid: View {
    let widgets: [WidgetInstance]
    let isEditing: Bool
    let language: AppLanguage
    let runtime: AppRuntime?
    /// 把一块组件放到指定网格位置。
    let onMove: (String, Int, Int) -> Void
    /// 改一块卡片的档位。
    let onResize: (String, WidgetSize) -> Void
    let onDelete: (String) -> Void

    /// 正在拖动的卡片 id 与累计位移。
    @State private var draggingID: String?
    @State private var dragOffset: CGSize = .zero
    @State private var dropCandidate: BentoDropCandidate?
    /// 正在缩放的卡片 id 与起始档位。
    @State private var resizingID: String?
    @State private var resizeBase: WidgetSize = .small

    private var spots: [BentoSpot] { BentoPacker.pack(widgets, columns: HubMetrics.bentoColumns) }
    private var rows: Int { BentoPacker.rows(spots) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let dropCandidate {
                dropTarget(dropCandidate)
            }
            ForEach(spots, id: \.id) { spot in
                card(for: spot)
            }
        }
        .frame(
            width: HubMetrics.contentColumnWidth,
            height: HubMetrics.bentoGridHeight(rows: rows),
            alignment: .topLeading
        )
    }

    // MARK: - 一块卡片

    private func card(for spot: BentoSpot) -> some View {
        let isDragging = draggingID == spot.id
        return BentoWidgetCard(
            spot: spot,
            title: WidgetCatalog.descriptor(for: spot.kind, language: language).title,
            detail: WidgetDetail.text(
                for: spot.kind,
                runtime: runtime,
                language: language
            ),
            tint: WidgetCatalog.descriptor(for: spot.kind, language: language).tint,
            isEditing: isEditing,
            isDragging: isDragging,
            language: language,
            onMoveDirection: { direction in move(spot, by: direction) },
            onDelete: { onDelete(spot.id) },
            onResize: { translation in resize(spot, translation: translation) },
            onResizeEnded: { endResize(spot) }
        )
        .focusable(isEditing)
        .onKeyPress(.leftArrow) {
            guard isEditing else { return .ignored }
            move(spot, by: .left)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            guard isEditing else { return .ignored }
            move(spot, by: .right)
            return .handled
        }
        .onKeyPress(.upArrow) {
            guard isEditing else { return .ignored }
            move(spot, by: .up)
            return .handled
        }
        .onKeyPress(.downArrow) {
            guard isEditing else { return .ignored }
            move(spot, by: .down)
            return .handled
        }
        .offset(
            x: CGFloat(spot.column) * HubMetrics.bentoColumnStep + (isDragging ? dragOffset.width : 0),
            y: CGFloat(spot.row) * HubMetrics.bentoRowStep + (isDragging ? dragOffset.height : 0)
        )
        .zIndex(isDragging ? 2 : 1)
        .gesture(isEditing ? dragGesture(for: spot) : nil)
    }

    // MARK: - 拖动放置

    private func dragGesture(for spot: BentoSpot) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                if draggingID != spot.id {
                    draggingID = spot.id
                    dragOffset = .zero
                }
                dragOffset = value.translation
                dropCandidate = candidate(for: spot, translation: value.translation)
            }
            .onEnded { _ in
                guard draggingID == spot.id else { return }
                if let dropCandidate, dropCandidate.isValid {
                    onMove(spot.id, dropCandidate.column, dropCandidate.row)
                }
                draggingID = nil
                dragOffset = .zero
                dropCandidate = nil
            }
    }

    private func candidate(for spot: BentoSpot, translation: CGSize) -> BentoDropCandidate {
        let width = min(spot.size.gridColumns, HubMetrics.bentoColumns)
        let rawColumn = Int(
            ((CGFloat(spot.column) * HubMetrics.bentoColumnStep + translation.width)
                / HubMetrics.bentoColumnStep).rounded()
        )
        let rawRow = Int(
            ((CGFloat(spot.row) * HubMetrics.bentoRowStep + translation.height)
                / HubMetrics.bentoRowStep).rounded()
        )
        let column = rawColumn.clamped(to: 0...(HubMetrics.bentoColumns - width))
        let row = rawRow.clamped(to: 0...max(0, rows - spot.size.gridRows))
        let inBounds = column == rawColumn && row == rawRow
        let available = BentoPacker.canPlace(
            id: spot.id,
            size: spot.size,
            column: column,
            row: row,
            among: spots,
            columns: HubMetrics.bentoColumns,
            maximumRows: rows
        )
        return BentoDropCandidate(
            size: spot.size,
            column: column,
            row: row,
            isValid: inBounds && available
        )
    }

    private func dropTarget(_ candidate: BentoDropCandidate) -> some View {
        let color = candidate.isValid ? MacTheme.accent : MacTheme.errorText
        return RoundedRectangle(cornerRadius: HubMetrics.bentoCardRadius, style: .continuous)
            .fill(color.opacity(0.1))
            .overlay {
                RoundedRectangle(cornerRadius: HubMetrics.bentoCardRadius, style: .continuous)
                    .strokeBorder(
                        color,
                        style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                    )
            }
            .frame(
                width: HubMetrics.bentoCardWidth(columns: candidate.size.gridColumns),
                height: HubMetrics.bentoCardHeight(rows: candidate.size.gridRows)
            )
            .offset(
                x: CGFloat(candidate.column) * HubMetrics.bentoColumnStep,
                y: CGFloat(candidate.row) * HubMetrics.bentoRowStep
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .zIndex(3)
    }

    private func move(_ spot: BentoSpot, by direction: BentoMoveDirection) {
        let column = spot.column + direction.columnDelta
        let row = spot.row + direction.rowDelta
        guard BentoPacker.canPlace(
            id: spot.id,
            size: spot.size,
            column: column,
            row: row,
            among: spots,
            columns: HubMetrics.bentoColumns,
            maximumRows: rows
        ) else { return }
        onMove(spot.id, column, row)
    }

    // MARK: - 缩放改档

    private func resize(_ spot: BentoSpot, translation: CGSize) {
        if resizingID != spot.id {
            resizingID = spot.id
            resizeBase = spot.size
        }

        let size = BentoPacker.resized(from: resizeBase, translation: translation)
        guard size.key != spot.size.key else { return }
        onResize(spot.id, size)
    }

    /// 松手就忘掉起点档位。
    ///
    /// 不忘记的话，第二次拖同一块会先跳回第一次的起点：
    /// 位移从零重新计，而基准还是上一轮那个旧档位。
    private func endResize(_ spot: BentoSpot) {
        guard resizingID == spot.id else { return }
        resizingID = nil
    }
}

private struct BentoDropCandidate {
    let size: WidgetSize
    let column: Int
    let row: Int
    let isValid: Bool
}

extension Comparable {
    /// 夹到区间里。缩放时算出来的列数与行数可能越界。
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
