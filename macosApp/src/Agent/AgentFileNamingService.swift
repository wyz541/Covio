import Foundation
import MLXLMCommon

@MainActor
final class AgentFileNamingService {
    private let autoNaming: AutoNamingRuntime
    private let policy: AutoNamingPolicySnapshot
    private let renameService: FileRenameService
    private let nowEpochSeconds: @Sendable () -> Int64
    private let makeRunID: @Sendable () -> String
    private var previews: [String: AutoNamingPreviewItem] = [:]
    private var agentRunIDs: Set<String> = []

    init(
        autoNaming: AutoNamingRuntime,
        policy: FileNamingPolicy,
        renameService: FileRenameService = FileRenameService(),
        nowEpochSeconds: @escaping @Sendable () -> Int64 = {
            Int64(Date().timeIntervalSince1970)
        },
        makeRunID: @escaping @Sendable () -> String = { UUID().uuidString }
    ) {
        self.autoNaming = autoNaming
        self.policy = AutoNamingPolicySnapshot(policy)
        self.renameService = renameService
        self.nowEpochSeconds = nowEpochSeconds
        self.makeRunID = makeRunID
    }

    func preview(
        files: [ResolvedAgentFile],
        maxResults: Int
    ) async -> AgentServiceResult {
        do {
            let items = try await autoNaming.preview(
                urls: files.map(\.url),
                policy: policy.makePolicy()
            )
            return previewResult(files: files, items: items, maxResults: maxResults)
        } catch AutoNamingPreviewError.busy {
            return .failure("File naming analysis is already running.", code: .executionFailed)
        } catch {
            return .failure("File naming preview failed.", code: .executionFailed)
        }
    }

    func apply(previewIds: [String]) async -> AgentServiceResult {
        var seen = Set<String>()
        let ids = previewIds.filter { seen.insert($0).inserted }
        guard !ids.isEmpty else {
            return .failure("Preview IDs are required.", code: .invalidArguments)
        }
        let selected = ids.compactMap { previews[$0] }
        guard selected.count == ids.count else {
            return .failure("One or more previews have expired.", code: .executionFailed)
        }
        guard selected.allSatisfy({ $0.canSelect && $0.candidate != nil && !$0.risks.contains(.promptInjection) }) else {
            return .failure("One or more previews are not safe to apply.", code: .executionFailed)
        }
        let candidates = selected.compactMap(\.candidate)
        guard candidates.count == selected.count else {
            return .failure("One or more previews have no rename candidate.", code: .executionFailed)
        }
        let runId = makeRunID()
        let plan = FileRenamePlan(
            runId: runId,
            createdAtEpochSeconds: nowEpochSeconds(),
            items: candidates
        )
        let renameService = self.renameService
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try renameService.apply(plan)
            }.value
            agentRunIDs.insert(runId)
            for id in ids {
                previews.removeValue(forKey: id)
            }
            return renameResult(result, operation: "rename")
        } catch let error as FileRenameError {
            return .failure(
                "File rename failed: \(error.code.rawValue).",
                code: .executionFailed
            )
        } catch {
            return .failure("File rename failed.", code: .executionFailed)
        }
    }

    func undo(runId: String) async -> AgentServiceResult {
        guard agentRunIDs.contains(runId) else {
            return .failure("Rename run is not available for undo.", code: .executionFailed)
        }
        let renameService = self.renameService
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try renameService.undo(runId: runId)
            }.value
            agentRunIDs.remove(runId)
            return renameResult(result, operation: "undo")
        } catch let error as FileRenameError {
            return .failure(
                "Rename undo failed: \(error.code.rawValue).",
                code: .executionFailed
            )
        } catch {
            return .failure("Rename undo failed.", code: .executionFailed)
        }
    }

    private func previewResult(
        files: [ResolvedAgentFile],
        items: [AutoNamingPreviewItem],
        maxResults: Int
    ) -> AgentServiceResult {
        var fileByPath: [String: ResolvedAgentFile] = [:]
        for file in files where fileByPath[file.url.standardizedFileURL.path] == nil {
            fileByPath[file.url.standardizedFileURL.path] = file
        }
        let selected = items.prefix(min(20, max(1, maxResults))).map { item in
            let file = fileByPath[item.sourceURL.standardizedFileURL.path]
            let fileId = file?.fileId ?? ""
            let promptInjection = item.risks.contains(.promptInjection)
            let attachment = fileId.hasPrefix("attachment:")
            let canApply = attachment && item.canSelect && !promptInjection
            if canApply {
                previews[item.candidateId] = item
            }
            let reason: JSONValue
            if !attachment {
                reason = .string("workspaceCopy")
            } else if promptInjection {
                reason = .string("promptInjection")
            } else if !item.canSelect {
                reason = .string("blocked")
            } else {
                reason = .null
            }
            return JSONValue.object([
                "fileId": .string(fileId),
                "previewId": .string(item.candidateId),
                "originalName": .string(item.originalName),
                "suggestedName": item.targetName.map(JSONValue.string) ?? .null,
                "status": .string(item.status.rawValue),
                "confidence": .double(item.confidence),
                "riskLevels": .array(
                    item.risks.map(\.rawValue).sorted().map(JSONValue.string)
                ),
                "warnings": .array(item.warnings.sorted().map(JSONValue.string)),
                "canApply": .bool(canApply),
                "applyUnavailableReason": reason,
                "errorCode": item.errorCode.map(JSONValue.string) ?? .null,
            ])
        }
        let lines = selected.compactMap { value -> String? in
            guard case .object(let object) = value,
                  case .string(let original)? = object["originalName"]
            else { return nil }
            let target: String
            if case .string(let name)? = object["suggestedName"] {
                target = name
            } else {
                target = "blocked"
            }
            return "\(original) → \(target)"
        }
        return AgentServiceResult(
            ok: true,
            summary: (
                ["Generated \(selected.count) file naming previews. No files were changed."]
                    + lines
            ).joined(separator: "\n"),
            data: .object(["items": .array(selected)])
        )
    }

    private func renameResult(
        _ result: FileRenameRunResult,
        operation: String
    ) -> AgentServiceResult {
        let items = result.items.map { item in
            JSONValue.object([
                "candidateId": .string(item.candidateId),
                "originalName": .string(item.originalName),
                "targetName": .string(item.targetName),
                "status": .string(item.status.rawValue),
                "errorCode": item.error.map { .string($0.code.rawValue) } ?? .null,
            ])
        }
        let summary = operation == "rename"
            ? "Renamed \(result.successCount) files. Run \(result.runId) can be undone."
            : "Undo restored \(result.successCount) files."
        return AgentServiceResult(
            ok: result.failureCount == 0,
            summary: summary,
            data: .object([
                "runId": .string(result.runId),
                "operation": .string(operation),
                "items": .array(items),
            ]),
            errorCode: result.failureCount == 0 ? nil : .executionFailed
        )
    }
}
