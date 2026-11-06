import CoreGraphics
import Foundation

guard CommandLine.arguments.count >= 2,
      let pid = Int32(CommandLine.arguments[1])
else {
    exit(2)
}

let seconds = CommandLine.arguments.count >= 3
    ? Double(CommandLine.arguments[2]) ?? 30
    : 30
let deadline = Date().addingTimeInterval(seconds)
while Date() < deadline {
    let windows = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly],
        kCGNullWindowID
    ) as? [[String: Any]] ?? []
    if windows.contains(where: {
        ($0[kCGWindowOwnerPID as String] as? Int32) == pid
    }) {
        exit(0)
    }
    usleep(20_000)
}
exit(1)
