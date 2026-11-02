import AppKit
import kmpDomain

/// 菜单栏状态项。它是 Covio 唯一的菜单栏入口。
///
/// macOS 决定状态项的位置，并把它和其他菜单栏图标排在一起。
/// 状态项图形由 `CovioStatusIcon` 提供，是预渲染的玻璃吊卡图标。
///
/// 行为来自设计合同 `component/tray-icon.swiftMapping`：左键开合挂帘，右键开菜单。
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let shell: NotchShellController
    /// 运行时。菜单里的命令直接调它，与设置页走同一批方法。
    private let runtime: AppRuntime?
    private let statusItem: NSStatusItem
    private(set) var menu = NSMenu()

    init(shell: NotchShellController, runtime: AppRuntime? = nil) {
        self.shell = shell
        self.runtime = runtime
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureButton()
        configureMenu()
        statusItem.isVisible = true
    }

    /// 状态项是否显示。
    var isVisible: Bool { statusItem.isVisible }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        let image = CovioStatusIcon.makeImage()
        button.image = image
        button.imagePosition = .imageOnly
        button.toolTip = ContractCopy.copyStatusItemDefault.text
        // 合同 `component/tray-icon` 的 accessibilityRules 要求交互目标不小于 24 点。
        button.setAccessibilityLabel(ContractCopy.copyStatusItemDefault.text)
        // 装了 `menu` 之后左键只会弹菜单。所以这里不装，改成自己接左右键。
        button.target = self
        button.action = #selector(handleClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func configureMenu() {
        menu.delegate = self
        menu.autoenablesItems = false

        let showItem = NSMenuItem(
            title: ContractCopy.copyHubFilesFilterScreenshots.text,
            action: #selector(showScreenshots),
            keyEquivalent: ""
        )
        showItem.target = self
        menu.addItem(showItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: ContractCopy.copyTrayActionSettings.text,
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: ContractCopy.copyTrayActionQuit.text,
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
    }

    func tearDown() {
        statusItem.menu = nil
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    // MARK: - 点击

    /// 左键开合挂帘，右键弹菜单。合同 `component/tray-icon.swiftMapping` 的写法。
    @objc private func handleClick() {
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true
        if wantsMenu {
            presentMenu()
        } else {
            shell.toggle()
        }
    }

    /// 弹出菜单。
    ///
    /// `performClick` 会一直跑到菜单关闭才返回，所以返回后马上摘掉 `menu` 是安全的。
    /// 不摘的话左键下次也会弹菜单。
    private func presentMenu() {
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    // MARK: - 菜单动作

    /// 打开文件工作区，并选中截图筛选。
    @objc private func showScreenshots() {
        shell.workbench.showFileArea(filter: .screenshots)
        shell.show()
    }

    @objc private func openSettings() {
        guard shell.workbench.openSettings() else { return }
        shell.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
