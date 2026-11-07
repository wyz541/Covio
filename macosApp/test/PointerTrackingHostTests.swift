import AppKit
import SwiftUI
import XCTest
@testable import Covio

/// 指针进出宿主的回报。
///
/// 热区与挂帘面板都靠这两个回调驱动：热区报告进入才展开挂帘（需求 R2），
/// 面板报告离开才排收起计时。跟踪区的 owner 是宿主自己，所以这两个方法
/// 必须真的被覆写，光挂 tracking area 是不够的。
@MainActor
final class PointerTrackingHostTests: XCTestCase {
    private func makeHost() -> PointerTrackingHost<Color> {
        PointerTrackingHost(rootView: .clear)
    }

    private func makeBareView() -> PointerTrackingView {
        PointerTrackingView(frame: .zero)
    }

    private func event() throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .mouseMoved,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 0,
                clickCount: 0,
                pressure: 0
            )
        )
    }

    /// 指针进入要报到。
    func testEnteringReportsThePointer() throws {
        let host = makeHost()
        var entered = 0
        host.onPointerEnter = { entered += 1 }

        host.mouseEntered(with: try event())

        XCTAssertEqual(entered, 1, "指针进入没有报到，热区打不开挂帘")
    }

    /// 指针离开要报到。
    func testExitingReportsThePointer() throws {
        let host = makeHost()
        var exited = 0
        host.onPointerExit = { exited += 1 }

        host.mouseExited(with: try event())

        XCTAssertEqual(exited, 1, "指针离开没有报到，挂帘不会排收起计时")
    }

    /// 没挂回调时进出不能崩。
    func testNoCallbacksIsHarmless() throws {
        let host = makeHost()
        host.mouseEntered(with: try event())
        host.mouseExited(with: try event())
    }

    /// 空白热区只使用 AppKit 视图，不创建 SwiftUI hosting view。
    func testTheBareViewDoesNotCreateAHostingView() throws {
        let view = makeBareView()
        var entered = 0
        view.onPointerEnter = { entered += 1 }

        XCTAssertTrue(view.subviews.isEmpty)
        view.mouseEntered(with: try event())
        XCTAssertEqual(entered, 1)
    }

    /// 跟踪区按窗口可见矩形铺满，进出都能覆盖到。
    func testTheTrackingAreaCoversTheWholeHost() {
        let host = makeHost()
        host.frame = CGRect(x: 0, y: 0, width: 186, height: 32)
        host.updateTrackingAreas()

        let areas = host.trackingAreas
        XCTAssertEqual(areas.count, 1, "宿主应该只挂一个跟踪区")
        XCTAssertTrue(
            areas[0].options.contains(.inVisibleRect),
            "用 .inVisibleRect 才能跟着窗口尺寸走，不用手工重算"
        )
    }
}
