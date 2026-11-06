import SwiftUI

/// Hub 面板内容的根。把控制器的状态接到 `HubView` 上。
///
/// 控制器用 `weak` 引用，避免"控制器 → 面板 → 内容视图 → 控制器"的循环持有。
struct HubContentRoot: View {
    weak var controller: NotchShellController?
    let initialGeometry: ScreenGeometry?
    let runtime: AppRuntime?

    var body: some View {
        if let controller, let geometry = controller.geometry ?? initialGeometry {
            HubView(
                geometry: geometry,
                isExpanded: controller.isExpanded,
                reduceMotion: controller.reduceMotion,
                hubState: controller.state,
                outputState: controller.outputState,
                workbench: controller.workbench,
                chrome: controller.chrome,
                runtime: runtime,
                popoverCoordinator: controller.popoverCoordinator,
                onOpenSettings: controller.onOpenSettings
            )
        } else {
            Color.clear
        }
    }
}
