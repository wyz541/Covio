import AppKit
import Foundation

protocol FileNamingExtracting: Sendable {
    func extract(candidateId: String, fileURL: URL) -> FileNamingExtractionResult
}

extension FileNamingContentExtractor: FileNamingExtracting {}

enum AutoNamingStage: Sendable, Equatable {
    case idle
    case analyzing
    case preview
    case applying
    case results
    case undoing
}

enum AutoNamingPreviewStatus: String, Sendable, Equatable {
    case ready
    case blocked
    case renamed
    case failed
    case undone
}

enum AutoNamingRisk: String, Sendable, Hashable {
    case scannedDocument
    case mixedContent
    case lowConfidence
    case conflict
    case fallbackModel
    case truncatedInput
    case promptInjection
    case fileChanged
}

enum AutoNamingPreviewError: Error, Sendable, Equatable {
    case busy
}

struct AutoNamingPlanSnapshot: Sendable, Equatable {
    let targetName: String?
    let confidence: Double
    let canApply: Bool
    let warnings: [String]
}

struct AutoNamingPreviewItem: Sendable, Equatable {
    let candidateId: String
    let sourceURL: URL
    let originalName: String
    let kind: FileNamingContentKind
    let targetName: String?
    let confidence: Double
    let evidence: [String]
    let warnings: [String]
    let risks: Set<AutoNamingRisk>
    var status: AutoNamingPreviewStatus
    var errorCode: String?
    let candidate: FileRenameCandidate?
    let modelMetrics: NamingModelMetrics?

    var canSelect: Bool {
        status == .ready && candidate != nil && targetName != nil
    }
}

@MainActor
@Observable
final class AutoNamingRuntime {
    private(set) var stage: AutoNamingStage = .idle
    private(set) var items: [AutoNamingPreviewItem] = []
    private(set) var selectedIDs: Set<String> = []
    private(set) var lastRunResult: FileRenameRunResult?
    private(set) var lastUndoResult: FileRenameRunResult?
    private(set) var errorMessage: LocalizedCopy?
    private(set) var infoMessage: LocalizedCopy?

    private let extractor: any FileNamingExtracting
    private var model: any NamingModelServing
    private let renameService: FileRenameService
    private let nowEpochSeconds: @Sendable () -> Int64
    private let makeRunID: @Sendable () -> String
    private var analysisTask: Task<[AutoNamingPreviewItem], Error>?
    private var suppressUndo = false

    init(
        extractor: any FileNamingExtracting = FileNamingContentExtractor(),
        model: any NamingModelServing = AutoNamingRuntime.makeDefaultModel(),
        renameService: FileRenameService = FileRenameService(),
        nowEpochSeconds: @escaping @Sendable () -> Int64 = {
            Int64(Date().timeIntervalSince1970)
        },
        makeRunID: @escaping @Sendable () -> String = { UUID().uuidString }
    ) {
        self.extractor = extractor
        self.model = model
        self.renameService = renameService
        self.nowEpochSeconds = nowEpochSeconds
        self.makeRunID = makeRunID
    }

    var busy: Bool {
        analysisTask != nil || stage == .analyzing || stage == .applying || stage == .undoing
    }

    func preheat() async throws -> NamingModelMetrics {
        try await model.preheat()
    }

    func prepareForModelSwitch() async -> Bool {
        guard !busy else { return false }
        await model.prepareForModelSwitch()
        return true
    }

    func replaceModel(_ next: any NamingModelServing) async -> Bool {
        guard !busy else { return false }
        await model.prepareForModelSwitch()
        model = next
        return true
    }

    func preview(
        urls: [URL],
        policy: FileNamingPolicy
    ) async throws -> [AutoNamingPreviewItem] {
        guard !busy else { throw AutoNamingPreviewError.busy }
        var seenPaths = Set<String>()
        let uniqueURLs = urls.filter {
            seenPaths.insert($0.standardizedFileURL.path).inserted
        }
        guard !uniqueURLs.isEmpty else { return [] }
        let snapshot = AutoNamingPolicySnapshot(policy)
        let extractor = extractor
        let model = model
        let task = Task.detached(priority: .userInitiated) {
            try await Self.buildPreviewItems(
                urls: uniqueURLs,
                policy: snapshot,
                extractor: extractor,
                model: model
            )
        }
        analysisTask = task
        defer { analysisTask = nil }
        return try await task.value
    }

    var canApply: Bool {
        stage == .preview && !selectedIDs.isEmpty
    }

    var canUndo: Bool {
        stage == .results && !suppressUndo && (lastRunResult?.successCount ?? 0) > 0
    }

    func analyze(urls: [URL], policy: FileNamingPolicy) async {
        guard !busy else { return }
        var seenPaths = Set<String>()
        let uniqueURLs = urls.filter {
            seenPaths.insert($0.standardizedFileURL.path).inserted
        }
        guard !uniqueURLs.isEmpty else {
            infoMessage = ContractCopy.copyAutoNamingNoticeNoFiles
            return
        }

        stage = .analyzing
        errorMessage = nil
        infoMessage = nil
        lastRunResult = nil
        lastUndoResult = nil
        suppressUndo = false
        items = []
        selectedIDs = []

        let policy = AutoNamingPolicySnapshot(policy)
        let extractor = extractor
        let model = model
        let task = Task.detached(priority: .userInitiated) {
            try await Self.buildPreviewItems(
                urls: uniqueURLs,
                policy: policy,
                extractor: extractor,
                model: model
            )
        }
        analysisTask = task

        do {
            let preview = try await task.value
            items = preview
            selectedIDs = Set(
                preview
                    .filter { $0.canSelect && !$0.risks.contains(.promptInjection) }
                    .map(\.candidateId)
            )
            stage = .preview
            if preview.isEmpty {
                infoMessage = ContractCopy.copyAutoNamingNoticeNoResults
            }
        } catch is CancellationError {
            stage = .idle
            infoMessage = ContractCopy.copyAutoNamingNoticeCancelled
        } catch {
            stage = .idle
            errorMessage = ContractCopy.copyAutoNamingErrorAnalysis
        }
        analysisTask = nil
    }

    func cancelAnalysis() {
        guard stage == .analyzing else { return }
        analysisTask?.cancel()
        Task { await model.cancel() }
        stage = .idle
        infoMessage = ContractCopy.copyAutoNamingNoticeCancelled
    }

    func toggleSelection(_ candidateId: String) {
        guard stage == .preview,
              let item = items.first(where: { $0.candidateId == candidateId }),
              item.canSelect
        else {
            return
        }
        if selectedIDs.contains(candidateId) {
            selectedIDs.remove(candidateId)
        } else {
            selectedIDs.insert(candidateId)
        }
    }

    func applySelected() async {
        guard stage == .preview else { return }
        let selected = items.filter { selectedIDs.contains($0.candidateId) && $0.canSelect }
        guard !selected.isEmpty else {
            infoMessage = ContractCopy.copyAutoNamingNoticeNoSelection
            return
        }

        let plan = FileRenamePlan(
            runId: makeRunID(),
            createdAtEpochSeconds: nowEpochSeconds(),
            items: selected.compactMap(\.candidate)
        )
        stage = .applying
        errorMessage = nil
        infoMessage = nil
        let renameService = self.renameService

        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try renameService.apply(plan)
            }.value
            lastRunResult = result
            suppressUndo = result.successCount == 0
            apply(result: result)
            stage = .results
            if result.failureCount == 0 {
                infoMessage = ContractCopy.copyAutoNamingNoticeApplied
            } else {
                infoMessage = ContractCopy.copyAutoNamingNoticePartialFailure
            }
            selectedIDs = []
        } catch let error as FileRenameError {
            stage = .preview
            markAllSelected(status: .failed, errorCode: error.code.rawValue)
            errorMessage = ContractCopy.copyAutoNamingErrorRename
        } catch {
            stage = .preview
            markAllSelected(status: .failed, errorCode: FileRenameErrorCode.renameFailed.rawValue)
            errorMessage = ContractCopy.copyAutoNamingErrorRename
        }
    }

    func undoLastRun() async {
        guard stage == .results, let run = lastRunResult, run.successCount > 0 else { return }
        stage = .undoing
        errorMessage = nil
        infoMessage = nil
        let renameService = self.renameService
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try renameService.undo(runId: run.runId)
            }.value
            lastUndoResult = result
            suppressUndo = result.failureCount == 0
            applyUndo(result: result)
            stage = .results
            infoMessage = result.failureCount == 0
                ? ContractCopy.copyAutoNamingNoticeUndone
                : ContractCopy.copyAutoNamingNoticePartialUndo
        } catch is FileRenameError {
            stage = .results
            errorMessage = ContractCopy.copyAutoNamingErrorUndo
            lastUndoResult = nil
        } catch {
            stage = .results
            errorMessage = ContractCopy.copyAutoNamingErrorUndo
            lastUndoResult = nil
        }
    }

    func reset() {
        guard !busy else { return }
        stage = .idle
        items = []
        selectedIDs = []
        lastRunResult = nil
        lastUndoResult = nil
        suppressUndo = false
        errorMessage = nil
        infoMessage = nil
    }

    func clearMessages() {
        errorMessage = nil
        infoMessage = nil
    }

    private func apply(result: FileRenameRunResult) {
        let byID = Dictionary(uniqueKeysWithValues: result.items.map { ($0.candidateId, $0) })
        items = items.map { item in
            guard let outcome = byID[item.candidateId] else { return item }
            var copy = item
            copy.status = outcome.status == .renamed ? .renamed : .failed
            copy.errorCode = outcome.error?.code.rawValue
            return copy
        }
    }

    private func applyUndo(result: FileRenameRunResult) {
        let byID = Dictionary(uniqueKeysWithValues: result.items.map { ($0.candidateId, $0) })
        items = items.map { item in
            guard let outcome = byID[item.candidateId] else { return item }
            var copy = item
            if outcome.status == .undone || outcome.status == .alreadyOriginal {
                copy.status = .undone
                copy.errorCode = nil
            } else {
                copy.errorCode = outcome.error?.code.rawValue
            }
            return copy
        }
    }

    private func markAllSelected(status: AutoNamingPreviewStatus, errorCode: String) {
        items = items.map { item in
            guard selectedIDs.contains(item.candidateId) else { return item }
            var copy = item
            copy.status = status
            copy.errorCode = errorCode
            return copy
        }
    }

    private static func buildPreviewItems(
        urls: [URL],
        policy: AutoNamingPolicySnapshot,
        extractor: any FileNamingExtracting,
        model: any NamingModelServing
    ) async throws -> [AutoNamingPreviewItem] {
        _ = try? await model.preheat()
        var results = Array<AutoNamingPreviewItem?>(repeating: nil, count: urls.count)
        var prepared: [PreparedPreview] = []

        do {
            for (index, url) in urls.enumerated() {
                try Task.checkCancellation()
                let candidateId = UUID().uuidString
                let result = extractor.extract(candidateId: candidateId, fileURL: url)
                switch result {
                case .failure(let failure):
                    results[index] = blockedItem(
                        candidateId: candidateId,
                        url: url,
                        kind: .unknown,
                        errorCode: failure.error.rawValue,
                        evidence: [],
                        warnings: [failure.error.rawValue]
                    )
                case .success(let extraction):
                    let request = NamingModelRequest(extraction: extraction, allowVision: policy.allowVision)
                    do {
                        let response = try await model.generate(request)
                        try Task.checkCancellation()
                        prepared.append(
                            PreparedPreview(
                                index: index,
                                url: url,
                                extraction: extraction,
                                response: response
                            )
                        )
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch let error as NamingModelError {
                        results[index] = blockedItem(
                            candidateId: candidateId,
                            url: url,
                            kind: extraction.kind,
                            errorCode: error.code.rawValue,
                            evidence: previewEvidence(extraction: extraction, response: nil),
                            warnings: extraction.warnings.map(\.rawValue)
                        )
                    } catch {
                        results[index] = blockedItem(
                            candidateId: candidateId,
                            url: url,
                            kind: extraction.kind,
                            errorCode: NamingModelErrorCode.generationFailed.rawValue,
                            evidence: previewEvidence(extraction: extraction, response: nil),
                            warnings: extraction.warnings.map(\.rawValue)
                        )
                    }
                }
            }

            let grouped = Dictionary(grouping: prepared) {
                $0.url.deletingLastPathComponent().standardizedFileURL.path
            }
            var nameCache: [String: Set<String>] = [:]
            let policyValue = policy.makePolicy()

            for (directoryPath, group) in grouped {
                try Task.checkCancellation()
                let names: Set<String>
                if let cached = nameCache[directoryPath] {
                    names = cached
                } else {
                    let loaded = Set(
                        (try? FileManager.default.contentsOfDirectory(atPath: directoryPath)) ?? []
                    )
                    nameCache[directoryPath] = loaded
                    names = loaded
                }

                let plans = FileNamingPlanner.shared.planBatch(
                    requests: group.map {
                        FileNamingRequest(
                            candidateId: $0.extraction.candidateId,
                            originalName: $0.url.lastPathComponent,
                            facts: $0.response.asNamingFacts()
                        )
                    },
                    policy: policyValue,
                    existingNames: names
                )

                for (preparedItem, plan) in zip(group, plans) {
                    let planSnapshot = AutoNamingPlanSnapshot(
                        targetName: plan.targetName,
                        confidence: plan.confidence,
                        canApply: plan.status == FileNamingPlanStatus.ready,
                        warnings: plan.warnings.map {
                            "\($0.code.name):\($0.detail)"
                        }
                    )
                    var candidate: FileRenameCandidate?
                    var errorCode: String?
                    if planSnapshot.canApply,
                       let targetName = planSnapshot.targetName,
                       targetName != preparedItem.url.lastPathComponent
                    {
                        do {
                            candidate = try FileRenameService.capture(
                                candidateId: preparedItem.extraction.candidateId,
                                sourceURL: preparedItem.url,
                                targetName: targetName
                            )
                        } catch let error as FileRenameError {
                            errorCode = error.code.rawValue
                        } catch {
                            errorCode = FileRenameErrorCode.fileChanged.rawValue
                        }
                    }
                    let status: AutoNamingPreviewStatus = candidate == nil ? .blocked : .ready
                    results[preparedItem.index] = AutoNamingPreviewItem(
                        candidateId: preparedItem.extraction.candidateId,
                        sourceURL: preparedItem.url,
                        originalName: preparedItem.url.lastPathComponent,
                        kind: preparedItem.extraction.kind,
                        targetName: planSnapshot.targetName,
                        confidence: planSnapshot.confidence,
                        evidence: previewEvidence(
                            extraction: preparedItem.extraction,
                            response: preparedItem.response
                        ),
                        warnings: previewWarnings(
                            extraction: preparedItem.extraction,
                            response: preparedItem.response,
                            plan: planSnapshot
                        ),
                        risks: previewRisks(
                            extraction: preparedItem.extraction,
                            response: preparedItem.response,
                            plan: planSnapshot,
                            minimumConfidence: policy.minConfidence
                        ),
                        status: status,
                        errorCode: errorCode,
                        candidate: candidate,
                        modelMetrics: preparedItem.response.metrics
                    )
                }
            }

            await model.release()
            return results.compactMap { $0 }
        } catch {
            await model.release()
            throw error
        }
    }

    private struct PreparedPreview: Sendable {
        let index: Int
        let url: URL
        let extraction: FileNamingExtraction
        let response: NamingModelResponse
    }

    private static func blockedItem(
        candidateId: String,
        url: URL,
        kind: FileNamingContentKind,
        errorCode: String,
        evidence: [String],
        warnings: [String]
    ) -> AutoNamingPreviewItem {
        AutoNamingPreviewItem(
            candidateId: candidateId,
            sourceURL: url,
            originalName: url.lastPathComponent,
            kind: kind,
            targetName: nil,
            confidence: 0,
            evidence: evidence,
            warnings: warnings,
            risks: [],
            status: .blocked,
            errorCode: errorCode,
            candidate: nil,
            modelMetrics: nil
        )
    }

    private static func previewEvidence(
        extraction: FileNamingExtraction,
        response: NamingModelResponse?
    ) -> [String] {
        var values = extraction.sources.map(\.rawValue).sorted()
        if let response {
            values.append("model:\(response.origin.rawValue)")
            values.append("quality:\(extraction.quality.rawValue)")
        }
        return values
    }

    private static func previewWarnings(
        extraction: FileNamingExtraction,
        response: NamingModelResponse,
        plan: AutoNamingPlanSnapshot
    ) -> [String] {
        var values = extraction.warnings.map(\.rawValue)
        values.append(contentsOf: response.warnings.map(\.rawValue))
        values.append(contentsOf: plan.warnings)
        return Array(Set(values)).sorted()
    }

    private static func previewRisks(
        extraction: FileNamingExtraction,
        response: NamingModelResponse,
        plan: AutoNamingPlanSnapshot,
        minimumConfidence: Double
    ) -> Set<AutoNamingRisk> {
        var risks = Set<AutoNamingRisk>()
        if extraction.kind == .pdf && !extraction.sources.contains(.pdfText) {
            risks.insert(.scannedDocument)
        }
        if extraction.kind == .mixed {
            risks.insert(.mixedContent)
        }
        if response.confidence < minimumConfidence || !plan.canApply {
            risks.insert(.lowConfidence)
        }
        if plan.warnings.contains(where: { $0.lowercased().contains("conflict") }) {
            risks.insert(.conflict)
        }
        if response.origin == .fallback {
            risks.insert(.fallbackModel)
        }
        if extraction.warnings.contains(.truncatedInput) {
            risks.insert(.truncatedInput)
        }
        if containsPromptInjection(extraction.text) {
            risks.insert(.promptInjection)
        }
        return risks
    }

    private static func containsPromptInjection(_ text: String) -> Bool {
        let lower = text.lowercased()
        let markers = [
            "ignore previous", "ignore all previous", "system prompt",
            "developer message", "you are now", "execute command",
            "run command", "output owned", "忽略之前", "忽略以上",
            "系统提示", "执行命令", "运行命令", "输出 owned",
        ]
        return markers.contains { lower.contains($0) }
    }

    private static func makeDefaultModel() -> any NamingModelServing {
        let resourceRoot = Bundle.main.resourceURL ?? Bundle.main.bundleURL
        let configuration = NamingModelConfiguration.bundled(resourceDirectory: resourceRoot)
            ?? NamingModelConfiguration(
                modelDirectory: resourceRoot
                    .appendingPathComponent("Models", isDirectory: true)
                    .appendingPathComponent("Qwen3VL-2B-Instruct-4bit", isDirectory: true)
            )
        return NamingModelCoordinator(primary: MLXNamingModel(configuration: configuration))
    }
}

struct AutoNamingPolicySnapshot: Sendable {
    enum DateSource: String, Sendable {
        case none
        case content
        case fileCreated
    }

    enum ConflictPolicy: String, Sendable {
        case appendNumber
        case block
    }

    let schemaVersion: Int32
    let template: String
    let maxUTF8Bytes: Int32
    let separator: String
    let lowercaseLatin: Bool
    let preserveExtension: Bool
    let dateSource: DateSource
    let conflictPolicy: ConflictPolicy
    let conflictSuffix: String
    let minConfidence: Double
    let requirePreview: Bool
    let allowVision: Bool

    init(_ policy: FileNamingPolicy) {
        schemaVersion = policy.schemaVersion
        template = policy.template_
        maxUTF8Bytes = policy.maxUTF8Bytes
        separator = policy.separator
        lowercaseLatin = policy.lowercaseLatin
        preserveExtension = policy.preserveExtension
        if policy.dateSource == FileNamingDateSource.content {
            dateSource = .content
        } else if policy.dateSource == FileNamingDateSource.fileCreated {
            dateSource = .fileCreated
        } else {
            dateSource = .none
        }
        conflictPolicy = policy.conflictPolicy == FileNamingConflictPolicy.block
            ? .block
            : .appendNumber
        conflictSuffix = policy.conflictSuffix
        minConfidence = policy.minConfidence
        requirePreview = policy.requirePreview
        allowVision = policy.allowVision
    }

    func makePolicy() -> FileNamingPolicy {
        FileNamingPolicy(
            schemaVersion: schemaVersion,
            template: template,
            maxUTF8Bytes: maxUTF8Bytes,
            separator: separator,
            lowercaseLatin: lowercaseLatin,
            preserveExtension: preserveExtension,
            dateSource: dateSource.kmpValue,
            conflictPolicy: conflictPolicy.kmpValue,
            conflictSuffix: conflictSuffix,
            minConfidence: minConfidence,
            requirePreview: requirePreview,
            allowVision: allowVision
        )
    }
}

private extension AutoNamingPolicySnapshot.DateSource {
    var kmpValue: FileNamingDateSource {
        switch self {
        case .none: .none
        case .content: .content
        case .fileCreated: .fileCreated
        }
    }
}

private extension AutoNamingPolicySnapshot.ConflictPolicy {
    var kmpValue: FileNamingConflictPolicy {
        switch self {
        case .appendNumber: .appendNumber
        case .block: .block
        }
    }
}
