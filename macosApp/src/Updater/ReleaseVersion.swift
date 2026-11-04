import Foundation

/// Covio 的 Semantic Versioning 2.0.0 版本。
///
/// 发布版本不使用 build metadata。构建号、渠道和 Git commit 是独立身份字段。
struct ReleaseVersion: Comparable, Equatable, Sendable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int
    let prerelease: [String]
    let buildMetadata: [String]

    var baseVersion: String { "\(major).\(minor).\(patch)" }
    var isStable: Bool { prerelease.isEmpty }

    var description: String {
        var value = baseVersion
        if !prerelease.isEmpty {
            value += "-" + prerelease.joined(separator: ".")
        }
        if !buildMetadata.isEmpty {
            value += "+" + buildMetadata.joined(separator: ".")
        }
        return value
    }

    init?(_ value: String) {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = Self.pattern.firstMatch(in: text, range: range),
              match.range == range,
              let majorText = Self.group(1, match, text),
              let minorText = Self.group(2, match, text),
              let patchText = Self.group(3, match, text),
              let major = Int(majorText),
              let minor = Int(minorText),
              let patch = Int(patchText)
        else {
            return nil
        }
        let prerelease = Self.group(4, match, text)?.split(
            separator: ".",
            omittingEmptySubsequences: false
        ).map(String.init) ?? []
        guard !prerelease.contains(where: {
            $0.allSatisfy(\.isNumber) && $0.count > 1 && $0.hasPrefix("0")
        }) else {
            return nil
        }
        let buildMetadata = Self.group(5, match, text)?.split(
            separator: ".",
            omittingEmptySubsequences: false
        ).map(String.init) ?? []
        self.init(
            major: major,
            minor: minor,
            patch: patch,
            prerelease: prerelease,
            buildMetadata: buildMetadata
        )
    }

    init(major: Int, minor: Int, patch: Int, prerelease: [String] = [], buildMetadata: [String] = []) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
        self.buildMetadata = buildMetadata
    }

    func isInternalBuild(_ buildNumber: Int) -> Bool {
        buildMetadata.isEmpty
            && prerelease == ["internal", String(buildNumber)]
            && (1...9_999).contains(buildNumber)
    }

    static func < (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        if lhs.prerelease.isEmpty && rhs.prerelease.isEmpty { return false }
        if lhs.prerelease.isEmpty { return false }
        if rhs.prerelease.isEmpty { return true }

        for index in 0..<max(lhs.prerelease.count, rhs.prerelease.count) {
            guard index < lhs.prerelease.count else { return true }
            guard index < rhs.prerelease.count else { return false }
            let left = lhs.prerelease[index]
            let right = rhs.prerelease[index]
            if left == right { continue }
            let leftNumeric = left.allSatisfy(\.isNumber)
            let rightNumeric = right.allSatisfy(\.isNumber)
            if leftNumeric && rightNumeric {
                if left.count != right.count { return left.count < right.count }
                return left < right
            }
            if leftNumeric != rightNumeric { return leftNumeric }
            return left < right
        }
        return false
    }

    private static let pattern = try! NSRegularExpression(
        pattern: #"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$"#
    )

    private static func group(_ index: Int, _ match: NSTextCheckingResult, _ text: String) -> String? {
        let range = match.range(at: index)
        guard range.location != NSNotFound, let value = Range(range, in: text) else {
            return nil
        }
        return String(text[value])
    }
}
