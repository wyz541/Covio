import Foundation

/// 网格上的一个格子。
struct BentoCell: Hashable {
    let column: Int
    let row: Int
}

/// 网格上落好位置的一块组件。
///
/// 显式位置来自配置；没有显式位置时由装箱算出来。
struct BentoSpot: Equatable {
    let id: String
    let kind: String
    let size: WidgetSize
    let column: Int
    let row: Int
    /// 在配置里的序号。没有显式位置的组件按它自动摆放。
    let order: Int
}

/// 键盘与无障碍移动卡片的方向。
enum BentoMoveDirection {
    case left
    case right
    case up
    case down

    var columnDelta: Int {
        switch self {
        case .left: -1
        case .right: 1
        case .up, .down: 0
        }
    }

    var rowDelta: Int {
        switch self {
        case .up: -1
        case .down: 1
        case .left, .right: 0
        }
    }
}

/// 组件卡片的装箱。
///
/// 纯函数，不碰视图，也不碰模型。
///
/// 先保留所有合法的显式位置，再按顺序自动摆放其余组件。
/// 显式位置可以留下空位；没有显式位置时保持原来的紧凑布局。
enum BentoPacker {
    /// 坏配置里的行号上限。正常 24 块组件远到不了这里。
    static let maximumRow = 128

    /// 把组件按顺序摆进网格。
    ///
    /// 宽度超过列数的组件按列数收窄，不然找不到位置会一直往下加行。
    static func pack(_ widgets: [WidgetInstance], columns: Int) -> [BentoSpot] {
        guard columns > 0 else { return [] }

        var explicitPositions: [Int: (column: Int, row: Int)] = [:]
        var occupied: Set<BentoCell> = []

        for (order, widget) in widgets.enumerated() {
            guard widget.column >= 0, widget.row >= 0 else { continue }
            let widgetColumn = Int(widget.column)
            let widgetRow = Int(widget.row)
            let width = min(widget.size.gridColumns, columns)
            let height = widget.size.gridRows
            guard widgetColumn + width <= columns,
                  widgetRow + height <= maximumRow
            else { continue }
            let cells = cells(
                column: widgetColumn,
                row: widgetRow,
                width: width,
                height: height
            )
            guard occupied.isDisjoint(with: cells) else { continue }
            explicitPositions[order] = (widgetColumn, widgetRow)
            occupied.formUnion(cells)
        }

        var spots = Array<BentoSpot?>(repeating: nil, count: widgets.count)
        for (order, widget) in widgets.enumerated() {
            let width = min(widget.size.gridColumns, columns)
            let height = widget.size.gridRows
            let position = explicitPositions[order] ?? firstAvailable(
                width: width,
                height: height,
                columns: columns,
                occupied: &occupied
            )
            guard let position else { continue }
            spots[order] = BentoSpot(
                id: widget.id,
                kind: widget.kind,
                size: widget.size,
                column: position.column,
                row: position.row,
                order: order
            )
        }

        return spots.compactMap { $0 }
    }

    /// 把当前自动布局落成显式坐标。
    static func materialized(_ widgets: [WidgetInstance], columns: Int) -> [WidgetInstance] {
        let spots = pack(widgets, columns: columns)
        let spotsByOrder = Dictionary(uniqueKeysWithValues: spots.map { ($0.order, $0) })
        return widgets.enumerated().map { order, widget in
            guard let spot = spotsByOrder[order] else { return widget }
            return widget.withGridFrame(
                size: spot.size,
                column: Int32(spot.column),
                row: Int32(spot.row)
            )
        }
    }

    /// 目标区域是否可以放下这张卡片。
    static func canPlace(
        id: String,
        size: WidgetSize,
        column: Int,
        row: Int,
        among spots: [BentoSpot],
        columns: Int,
        maximumRows: Int
    ) -> Bool {
        guard columns > 0 else { return false }
        let width = min(size.gridColumns, columns)
        let height = size.gridRows
        let rowLimit = min(maximumRows, maximumRow)
        guard column >= 0,
              row >= 0,
              column + width <= columns,
              row + height <= rowLimit
        else { return false }

        let proposed = cells(column: column, row: row, width: width, height: height)
        let occupied = spots
            .filter { $0.id != id }
            .flatMap { spot in
                cells(
                    column: spot.column,
                    row: spot.row,
                    width: min(spot.size.gridColumns, columns),
                    height: spot.size.gridRows
                )
            }
        return proposed.isDisjoint(with: occupied)
    }

    /// 网格一共几行。
    static func rows(_ spots: [BentoSpot]) -> Int {
        spots.map { $0.row + $0.size.gridRows }.max() ?? 0
    }

    private static func firstAvailable(
        width: Int,
        height: Int,
        columns: Int,
        occupied: inout Set<BentoCell>
    ) -> (column: Int, row: Int)? {
        guard width <= columns else { return nil }
        for row in 0...(maximumRow - height) {
            for column in 0...(columns - width) {
                let proposed = cells(column: column, row: row, width: width, height: height)
                guard occupied.isDisjoint(with: proposed) else { continue }
                occupied.formUnion(proposed)
                return (column, row)
            }
        }
        return nil
    }

    private static func cells(
        column: Int,
        row: Int,
        width: Int,
        height: Int
    ) -> Set<BentoCell> {
        var result: Set<BentoCell> = []
        for offsetY in 0..<height {
            for offsetX in 0..<width {
                result.insert(BentoCell(column: column + offsetX, row: row + offsetY))
            }
        }
        return result
    }

    /// 列数与行数换成档位。与打样 `sizeOf` 一致。
    static func size(columns: Int, rows: Int) -> WidgetSize {
        if columns >= 2, rows >= 2 { return .large }
        if columns >= 2 { return .wide }
        if rows >= 2 { return .tall }
        return .small
    }

    /// 缩放手柄拖了多远，换成新档位。
    ///
    /// 从 `base` 算，不从当前档位算：一次拖动里 `onChanged` 会连着来很多次，
    /// 每次都拿当前档位累加会自己滚起来。`base` 是这一次拖动开始时的档位，
    /// 松手后由调用方清掉。
    ///
    /// 上限是最大档跨的列与行，不是网格的列数：四档里最宽最高的就是「大」。
    /// 网格比这还窄时由 `pack` 收窄。
    static func resized(from base: WidgetSize, translation: CGSize) -> WidgetSize {
        let width = HubMetrics.bentoCardWidth(columns: base.gridColumns) + translation.width
        let height = HubMetrics.bentoCardHeight(rows: base.gridRows) + translation.height
        return size(
            columns: Int((width / HubMetrics.bentoColumnStep).rounded())
                .clamped(to: 1...WidgetSize.large.gridColumns),
            rows: Int((height / HubMetrics.bentoRowStep).rounded())
                .clamped(to: 1...WidgetSize.large.gridRows)
        )
    }
}

extension WidgetSize {
    /// 占几列。小 1，宽 2，高 1，大 2。
    var gridColumns: Int {
        switch key {
        case "wide", "large": 2
        default: 1
        }
    }

    /// 占几行。小 1，宽 1，高 2，大 2。
    var gridRows: Int {
        switch key {
        case "tall", "large": 2
        default: 1
        }
    }

    /// 按序列化键找档位。认不出的键回退到模型给的兜底档。
    static func from(key: String) -> WidgetSize {
        WidgetSize.entries.first { $0.key == key } ?? WidgetSize.companion.FALLBACK
    }
}
