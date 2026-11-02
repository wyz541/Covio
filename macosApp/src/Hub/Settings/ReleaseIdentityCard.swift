import Foundation
import SwiftUI

/// 设置页只读版本身份。客户端版本是主值，发布元数据分开显示。
struct ReleaseIdentityDisplay: Equatable {
    let clientVersion: String
    let channel: String
    let buildNumber: String
    let gitShortSHA: String
    let helperProtocolVersion: String

    init(
        clientVersion: String = GeneratedReleaseIdentity.clientVersion,
        channel: String = GeneratedReleaseIdentity.channel,
        buildNumber: Int = GeneratedReleaseIdentity.buildNumber,
        gitCommit: String,
        helperProtocolVersion: Int = GeneratedReleaseIdentity.helperProtocolVersion
    ) {
        self.clientVersion = clientVersion
        self.channel = channel
        self.buildNumber = String(buildNumber)
        self.gitShortSHA = Self.shortSHA(gitCommit)
        self.helperProtocolVersion = String(helperProtocolVersion)
    }

    static func live(bundle: Bundle = .main) -> ReleaseIdentityDisplay {
        let gitCommit = (bundle.object(forInfoDictionaryKey: "CovioGitCommit") as? String)
            ?? "development"
        return ReleaseIdentityDisplay(gitCommit: gitCommit)
    }

    private static func shortSHA(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "development" }
        return String(trimmed.prefix(12))
    }
}

struct ReleaseIdentityCard: View {
    let runtime: AppRuntime

    private var display: ReleaseIdentityDisplay {
        ReleaseIdentityDisplay.live()
    }

    var body: some View {
        MacCard {
            MacSectionTitle(text: ContractCopy.copyGeneralVersionTitle.text(for: runtime.language))
            HStack(alignment: .firstTextBaseline, spacing: MacTheme.space3) {
                Text(ContractCopy.copyGeneralVersionClient.text(for: runtime.language))
                    .font(.system(size: 12))
                    .foregroundStyle(MacTheme.textSecondary)
                Spacer(minLength: MacTheme.space2)
                Text(display.clientVersion)
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .foregroundStyle(MacTheme.textPrimary)
                    .monospacedDigit()
                    .textSelection(.enabled)
            }
            Divider()
                .overlay(MacTheme.divider)
            Grid(alignment: .leading, horizontalSpacing: MacTheme.space6, verticalSpacing: MacTheme.space2) {
                ReleaseIdentityFact(
                    label: ContractCopy.copyGeneralVersionChannel.text(for: runtime.language),
                    value: display.channel
                )
                ReleaseIdentityFact(
                    label: ContractCopy.copyGeneralVersionBuild.text(for: runtime.language),
                    value: display.buildNumber
                )
                ReleaseIdentityFact(
                    label: ContractCopy.copyGeneralVersionGit.text(for: runtime.language),
                    value: display.gitShortSHA,
                    monospaced: true
                )
                ReleaseIdentityFact(
                    label: ContractCopy.copyGeneralVersionHelper.text(for: runtime.language),
                    value: display.helperProtocolVersion,
                    monospaced: true
                )
            }
        }
    }
}

private struct ReleaseIdentityFact: View {
    let label: String
    let value: String
    var monospaced = false

    var body: some View {
        GridRow {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(MacTheme.textSecondary)
            Text(value)
                .font(.system(size: 12, weight: .medium, design: monospaced ? .monospaced : .default))
                .foregroundStyle(MacTheme.textPrimary)
                .textSelection(.enabled)
        }
    }
}
