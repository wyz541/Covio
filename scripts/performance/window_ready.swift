import ApplicationServices
import CoreGraphics
import Darwin
import Foundation

/// 状态项在 Accessibility 树里属于应用的 extras menu bar。
/// CGWindowList 看不到部分菜单栏窗口，因此先查 AX，再回退到窗口列表。
func menuBarItemIsReady(pid: pid_t) -> Bool {
    let application = AXUIElementCreateApplication(pid)
    var rawMenuBar: CFTypeRef?
    guard AXUIElementCopyAttributeValue(
        application,
        "AXExtrasMenuBar" as CFString,
        &rawMenuBar
    ) == .success,
        let menuBar = rawMenuBar as! AXUIElement?,
        var rawChildren: CFTypeRef? = nil,
        AXUIElementCopyAttributeValue(
            menuBar,
            kAXChildrenAttribute as CFString,
            &rawChildren
        ) == .success,
        let children = rawChildren as? [AXUIElement]
    else {
        return false
    }
    for child in children {
        var rawRole: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            child,
            kAXRoleAttribute as CFString,
            &rawRole
        ) == .success,
            let role = rawRole as? String
        else {
            continue
        }
        if role == "AXMenuBarItem" {
            return true
        }
    }
    return false
}

func windowIsReady(pid: pid_t) -> Bool {
    let windows = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly],
        kCGNullWindowID
    ) as? [[String: Any]] ?? []
    return windows.contains(where: {
        ($0[kCGWindowOwnerPID as String] as? Int32) == pid
    })
}

func waitForReady(pid: pid_t, seconds: Double) -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if windowIsReady(pid: pid) || menuBarItemIsReady(pid: pid) {
            return true
        }
        usleep(20_000)
    }
    return false
}

if CommandLine.arguments.count >= 2 && CommandLine.arguments[1] == "--serve" {
    // 先初始化 Accessibility 连接，避免把 helper 启动成本算进 app 的启动时间。
    _ = AXIsProcessTrusted()
    _ = menuBarItemIsReady(pid: getpid())
    print("warm")
    fflush(stdout)
    while let line = readLine(strippingNewline: true) {
        let pieces = line.split(separator: " ")
        guard pieces.count >= 2,
              let pid = Int32(pieces[0]),
              let seconds = Double(pieces[1])
        else {
            print("error")
            fflush(stdout)
            continue
        }
        print(waitForReady(pid: pid, seconds: seconds) ? "ready" : "timeout")
        fflush(stdout)
    }
    exit(0)
}

guard CommandLine.arguments.count >= 2,
      let pid = Int32(CommandLine.arguments[1])
else {
    exit(2)
}
let seconds = CommandLine.arguments.count >= 3
    ? Double(CommandLine.arguments[2]) ?? 30
    : 30
exit(waitForReady(pid: pid, seconds: seconds) ? 0 : 1)
