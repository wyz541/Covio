import AppKit
import SwiftUI

struct AgentTabView: View {
    @Bindable var agent: AgentChatRuntime
    let language: AppLanguage
    let modelSetup: ModelSetupRuntime?

    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    init(
        agent: AgentChatRuntime,
        language: AppLanguage,
        modelSetup: ModelSetupRuntime? = nil
    ) {
        _agent = Bindable(agent)
        self.language = language
        self.modelSetup = modelSetup
    }

    var body: some View {
        Group {
            if let modelSetup,
               !modelSetup.isAIReady || !modelSetup.activeModelSupportsAgent
            {
                ModelSetupInlineCard(
                    model: modelSetup,
                    language: language,
                    purpose: .agent
                )
            } else {
                chatBody
            }
        }
        .frame(height: HubMetrics.agentBodyHeight, alignment: .top)
        .task { await modelSetup?.refresh() }
        .onAppear { agent.language = language }
        .onChange(of: language) { _, next in agent.language = next }
    }

    private var chatBody: some View {
        VStack(spacing: MacTheme.space2) {
            transcript
            if let pending = agent.pendingAction {
                confirmationCard(pending)
            }
            composer
            if let error = agent.errorText {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(MacTheme.errorText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(error)
            }
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: MacTheme.space2) {
                    localBadge
                    if agent.messages.isEmpty {
                        emptyState
                    } else {
                        ForEach(agent.messages) { message in
                            messageView(message)
                        }
                        if agent.stage == .thinking || agent.stage == .executing {
                            thinkingRow
                        }
                        if !agent.toolAudits.isEmpty {
                            auditSection
                        }
                        Color.clear.frame(height: 1).id(Self.bottomID)
                    }
                }
                .padding(MacTheme.space3)
            }
            .background(
                MacTheme.material,
                in: RoundedRectangle(cornerRadius: HubMetrics.bentoCardRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: HubMetrics.bentoCardRadius, style: .continuous)
                    .strokeBorder(MacTheme.divider, lineWidth: 1)
            )
            .settingsAwareGlassSurface(cornerRadius: HubMetrics.bentoCardRadius)
            .onChange(of: agent.messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.16)) {
                    proxy.scrollTo(Self.bottomID, anchor: .bottom)
                }
            }
            .onChange(of: agent.messages.last?.text) { _, _ in
                proxy.scrollTo(Self.bottomID, anchor: .bottom)
            }
        }
        .frame(height: HubMetrics.agentTranscriptHeight)
    }

    private var localBadge: some View {
        HStack(spacing: MacTheme.space1) {
            Circle()
                .fill(MacTheme.successText)
                .frame(width: 6, height: 6)
            Text(localStatusText)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(MacTheme.textSecondary)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var localStatusText: String {
        let offline = ContractCopy.copyAgentOffline.text(for: language)
        guard modelSetup?.isAIReady == true else { return offline }
        return "\(offline) · \(ContractCopy.copyModelSetupStateReady.text(for: language))"
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: MacTheme.space2) {
            Text(ContractCopy.copyAgentEmptyTitle.text(for: language))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(MacTheme.textPrimary)
            Text(ContractCopy.copyAgentEmptyBody.text(for: language))
                .font(.system(size: 12))
                .foregroundStyle(MacTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, MacTheme.space4)
    }

    private func messageView(_ message: AgentChatMessage) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 80) }
            VStack(alignment: .leading, spacing: MacTheme.space1) {
                Text(roleName(message.role))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(MacTheme.textSecondary)
                Text(message.text)
                    .font(.system(size: 12))
                    .foregroundStyle(message.role == .service ? MacTheme.textSecondary : MacTheme.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(message.text)
            }
            .padding(.horizontal, MacTheme.space3)
            .padding(.vertical, MacTheme.space2)
            .background(
                bubbleColor(message.role),
                in: RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
            )
            if message.role != .user { Spacer(minLength: 80) }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    private var thinkingRow: some View {
        HStack(spacing: MacTheme.space1) {
            ProgressView()
                .controlSize(.small)
            Text(ContractCopy.copyAgentThinking.text(for: language))
                .font(.system(size: 11))
                .foregroundStyle(MacTheme.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var auditSection: some View {
        VStack(alignment: .leading, spacing: MacTheme.space1) {
            Divider()
            ForEach(Array(agent.toolAudits.suffix(6))) { audit in
                HStack(spacing: MacTheme.space1) {
                    Text(audit.toolName)
                        .font(.system(size: 9, design: .monospaced))
                    Text("· \(audit.risk.rawValue)")
                        .font(.system(size: 9))
                        .foregroundStyle(MacTheme.textSecondary)
                    Spacer(minLength: MacTheme.space1)
                    Text(audit.status.rawValue)
                        .font(.system(size: 9, weight: .medium))
                    if let duration = audit.durationMilliseconds {
                        Text("\(duration) ms")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(MacTheme.textSecondary)
                    }
                    if let code = audit.errorCode?.rawValue {
                        Text(code)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(MacTheme.errorText)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.top, MacTheme.space1)
    }

    private func confirmationCard(_ pending: AgentPendingAction) -> some View {
        HStack(spacing: MacTheme.space3) {
            VStack(alignment: .leading, spacing: MacTheme.space1) {
                Text("\(pending.toolName) · \(pending.risk.rawValue)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MacTheme.textPrimary)
                Text(pendingSummary(pending))
                    .font(.system(size: 11))
                    .foregroundStyle(MacTheme.textSecondary)
                if let preview = pending.textPreview, !preview.isEmpty {
                    Text(preview)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(MacTheme.textPrimary)
                        .lineLimit(5)
                        .textSelection(.enabled)
                        .padding(MacTheme.space2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            MacTheme.material,
                            in: RoundedRectangle(
                                cornerRadius: MacTheme.controlRadius,
                                style: .continuous
                            )
                        )
                }
                Text(ContractCopy.copyAgentConfirmBody.text(for: language))
                    .font(.system(size: 10))
                    .foregroundStyle(MacTheme.textSecondary)
            }
            Spacer(minLength: MacTheme.space2)
            Button(ContractCopy.copyAgentCancel.text(for: language)) {
                agent.cancelPendingAction()
            }
            .buttonStyle(.plain)
            .disabled(agent.stage != .awaitingConfirmation)
            Button(ContractCopy.copyAgentConfirm.text(for: language)) {
                agent.confirmPendingAction()
            }
            .buttonStyle(.borderedProminent)
            .tint(MacTheme.accent)
            .disabled(agent.stage != .awaitingConfirmation)
        }
        .padding(MacTheme.space3)
        .background(
            MacTheme.elevated,
            in: RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                .strokeBorder(MacTheme.warningText.opacity(0.45), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: MacTheme.space2) {
            if !agent.attachments.isEmpty {
                attachmentStrip
            }

            HStack(spacing: MacTheme.space2) {
                Button(action: chooseAttachments) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(MacTheme.textSecondary)
                .disabled(agent.isBusy || agent.pendingAction != nil)
                .accessibilityLabel(ContractCopy.copyAgentAttachFiles.text(for: language))
                .help(ContractCopy.copyAgentAttachFiles.text(for: language))

                TextField(
                    ContractCopy.copyAgentPlaceholder.text(for: language),
                    text: $draft,
                    axis: .vertical
                )
                .lineLimit(1...3)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($inputFocused)
                .onSubmit(send)
                .disabled(agent.isBusy || agent.pendingAction != nil)
                .padding(.horizontal, MacTheme.space3)
                .frame(minHeight: HubMetrics.agentComposerHeight)
                .background(
                    MacTheme.elevated,
                    in: RoundedRectangle(cornerRadius: MacTheme.controlRadius, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: MacTheme.controlRadius, style: .continuous)
                        .strokeBorder(MacTheme.divider, lineWidth: 1)
                )

                if agent.stage == .executing {
                    HStack(spacing: MacTheme.space1) {
                        ProgressView()
                            .controlSize(.small)
                        Text(ContractCopy.copyAgentThinking.text(for: language))
                            .font(.system(size: 10))
                            .foregroundStyle(MacTheme.textSecondary)
                    }
                } else if agent.isBusy {
                    Button(ContractCopy.copyAgentStop.text(for: language)) {
                        agent.stop()
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint(ContractCopy.copyAgentStop.text(for: language))
                } else {
                    Button(ContractCopy.copyAgentSend.text(for: language), action: send)
                        .buttonStyle(.borderedProminent)
                        .tint(MacTheme.accent)
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || agent.pendingAction != nil)
                }
            }
        }
    }

    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: MacTheme.space1) {
                ForEach(agent.attachments) { file in
                    HStack(spacing: MacTheme.space1) {
                        Image(systemName: "doc")
                            .font(.system(size: 9))
                        Text(file.displayName)
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                        Button {
                            agent.removeAttachment(file.id)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .semibold))
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)
                        .disabled(agent.isBusy || agent.pendingAction != nil)
                        .accessibilityLabel(ContractCopy.copyAgentRemoveAttachment.text(for: language))
                        .accessibilityValue(file.displayName)
                    }
                    .foregroundStyle(MacTheme.textSecondary)
                    .padding(.horizontal, MacTheme.space2)
                    .frame(height: 28)
                    .background(
                        MacTheme.elevated,
                        in: Capsule(style: .continuous)
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(MacTheme.divider, lineWidth: 1)
                    )
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func chooseAttachments() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.resolvesAliases = false
        panel.prompt = ContractCopy.copyAgentAttachFiles.text(for: language)
        guard panel.runModal() == .OK else { return }
        agent.attachFiles(panel.urls)
    }

    private func send() {
        let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        draft = ""
        agent.send(value)
        inputFocused = true
    }

    private func roleName(_ role: AgentChatRole) -> String {
        switch role {
        case .user: ContractCopy.copyAgentYou.text(for: language)
        case .assistant: ContractCopy.copyAgentName.text(for: language)
        case .service: ContractCopy.copyAgentOffline.text(for: language)
        }
    }

    private func bubbleColor(_ role: AgentChatRole) -> Color {
        switch role {
        case .user: MacTheme.accent.opacity(0.18)
        case .assistant: Color.primary.opacity(0.07)
        case .service: MacTheme.successText.opacity(0.10)
        }
    }

    private func pendingSummary(_ pending: AgentPendingAction) -> String {
        if let count = pending.characterCount {
            return String(
                format: ContractCopy.copyAgentCopyCharacters.text(for: language),
                count
            )
        }
        return pending.summary
    }

    private static let bottomID = "agent-bottom"
}

struct AgentHeadingActions: View {
    let agent: AgentChatRuntime
    let language: AppLanguage

    @State private var confirmClearAll = false

    var body: some View {
        HStack(spacing: MacTheme.space2) {
            Button(ContractCopy.copyAgentClear.text(for: language)) {
                agent.clear()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .disabled(agent.isBusy || (agent.messages.isEmpty && agent.attachments.isEmpty))
            .accessibilityLabel(ContractCopy.copyAgentClear.text(for: language))

            Button {
                confirmClearAll = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(MacTheme.textSecondary)
            .disabled(agent.isBusy || agent.messages.isEmpty)
            .accessibilityLabel(ContractCopy.copyAgentHistoryClearAll.text(for: language))
            .alert(
                ContractCopy.copyAgentHistoryClearTitle.text(for: language),
                isPresented: $confirmClearAll
            ) {
                Button(ContractCopy.copyAgentCancel.text(for: language), role: .cancel) {}
                Button(ContractCopy.copyAgentHistoryClearAll.text(for: language), role: .destructive) {
                    agent.clearAllHistory()
                }
            } message: {
                Text(ContractCopy.copyAgentHistoryClearBody.text(for: language))
            }
        }
    }
}
