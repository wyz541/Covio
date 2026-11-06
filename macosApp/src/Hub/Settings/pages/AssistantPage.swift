import SwiftUI

/// 助手设置。
///
/// 对话、本地模型与外部 Agent 服务属于同一个功能，所以放在同一分节。
/// 工作台顶栏不再显示助手页签。
struct AssistantPage: View {
    let runtime: AppRuntime

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MacTheme.space6) {
                HStack(spacing: MacTheme.space2) {
                    Spacer(minLength: 0)
                    AgentHeadingActions(agent: runtime.agent, language: runtime.language)
                }

                AgentTabView(
                    agent: runtime.agent,
                    language: runtime.language,
                    modelSetup: runtime.modelSetup
                )
                .settingsRowAnchor(SettingsRowID.assistantChat)

                LocalModelPackagesCard(runtime: runtime)
                    .settingsRowAnchor(SettingsRowID.assistantModel)

                AgentExternalServiceCard(runtime: runtime)
                    .settingsRowAnchor(SettingsRowID.assistantExternalAgent)
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, MacTheme.space6)
            .padding(.vertical, MacTheme.space5)
        }
    }
}
