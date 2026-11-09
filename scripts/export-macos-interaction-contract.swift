#if os(Linux)
import Glibc
#else
import Darwin
#endif
import Foundation

private enum ExportError: Error, CustomStringConvertible {
    case missingValue(String)
    case staleOutput

    var description: String {
        switch self {
        case .missingValue(let flag):
            return "Missing value after \(flag)."
        case .staleOutput:
            return "The committed interaction contract is stale. Run this command without --check."
        }
    }
}

@main
struct ExportMacOSInteractionContract {
    static func main() {
        do {
            try run()
        } catch {
            FileHandle.standardError.write(Data("error: \(error)\n".utf8))
            exit(1)
        }
    }

    private static func run() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let output = try value(after: "--output", in: arguments)
            ?? "docs/macos-interaction-contract.json"
        let generated = try WorkbenchInteractionContract.current.encodedJSON()
        let outputURL = URL(fileURLWithPath: output)

        if arguments.contains("--check") {
            let committed = try Data(contentsOf: outputURL)
            guard committed == generated else { throw ExportError.staleOutput }
            print("macOS interaction contract is current: \(output)")
            return
        }

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try generated.write(to: outputURL, options: .atomic)
        print("wrote \(output)")
    }

    private static func value(after flag: String, in arguments: [String]) throws -> String? {
        guard let index = arguments.firstIndex(of: flag) else { return nil }
        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex else { throw ExportError.missingValue(flag) }
        return arguments[valueIndex]
    }
}
