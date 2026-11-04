import Foundation
import XCTest
@testable import Covio

@MainActor
final class AgentFileNamingServiceTests: XCTestCase {
    func testPreviewApplyAndUndoRestoresAttachment() async throws {
        let fixture = try AgentRenameFixture()
        defer { fixture.cleanUp() }
        let source = try fixture.file("old.txt", contents: "Quarterly budget review")
        let service = fixture.service()

        let preview = await service.preview(
            files: [fixture.attachment(source)],
            maxResults: 1
        )
        let previewItem = try firstPreview(preview)
        XCTAssertEqual(previewItem["canApply"] as? Bool, true)
        let previewId = try XCTUnwrap(previewItem["previewId"] as? String)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))

        let applied = await service.apply(previewIds: [previewId])
        let appliedRoot = try payload(applied)
        XCTAssertTrue(applied.ok)
        XCTAssertEqual(appliedRoot["runId"] as? String, "agent-run-1")
        let renamed = fixture.directory.appendingPathComponent("Quarterly Report.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamed.path))

        let undone = await service.undo(runId: "agent-run-1")
        XCTAssertTrue(undone.ok)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: renamed.path))
    }

    func testWorkspaceCopyCannotBeRenamedByAgent() async throws {
        let fixture = try AgentRenameFixture()
        defer { fixture.cleanUp() }
        let source = try fixture.file("copy.txt", contents: "Workspace copy")
        let file = ResolvedAgentFile(
            fileId: "workspace:\(String(repeating: "a", count: 64))",
            displayName: "copy.txt",
            url: source
        )
        let service = fixture.service()

        let preview = await service.preview(files: [file], maxResults: 1)
        let item = try firstPreview(preview)
        XCTAssertEqual(item["canApply"] as? Bool, false)
        XCTAssertEqual(item["applyUnavailableReason"] as? String, "workspaceCopy")
    }

    func testFileChangedAfterPreviewIsRejected() async throws {
        let fixture = try AgentRenameFixture()
        defer { fixture.cleanUp() }
        let source = try fixture.file("old.txt", contents: "Original")
        let service = fixture.service()
        let preview = await service.preview(files: [fixture.attachment(source)], maxResults: 1)
        let previewId = try XCTUnwrap(firstPreview(preview)["previewId"] as? String)
        try Data("Changed".utf8).write(to: source, options: .atomic)

        let applied = await service.apply(previewIds: [previewId])

        XCTAssertFalse(applied.ok)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: fixture.directory.appendingPathComponent("Quarterly Report.txt").path
            )
        )
    }

    func testTargetConflictIsRejected() async throws {
        let fixture = try AgentRenameFixture()
        defer { fixture.cleanUp() }
        let source = try fixture.file("old.txt", contents: "Original")
        let service = fixture.service()
        let preview = await service.preview(files: [fixture.attachment(source)], maxResults: 1)
        let previewId = try XCTUnwrap(firstPreview(preview)["previewId"] as? String)
        _ = try fixture.file("Quarterly Report.txt", contents: "Existing")

        let applied = await service.apply(previewIds: [previewId])

        XCTAssertFalse(applied.ok)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testUndoRejectsExternalModificationAfterRename() async throws {
        let fixture = try AgentRenameFixture()
        defer { fixture.cleanUp() }
        let source = try fixture.file("old.txt", contents: "Original")
        let service = fixture.service()
        let preview = await service.preview(files: [fixture.attachment(source)], maxResults: 1)
        let previewId = try XCTUnwrap(firstPreview(preview)["previewId"] as? String)
        let applied = await service.apply(previewIds: [previewId])
        XCTAssertTrue(applied.ok)
        let renamed = fixture.directory.appendingPathComponent("Quarterly Report.txt")
        try Data("Changed after rename".utf8).write(to: renamed, options: .atomic)

        let undone = await service.undo(runId: "agent-run-1")

        XCTAssertFalse(undone.ok)
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamed.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
    }

    private func firstPreview(_ result: AgentServiceResult) throws -> [String: Any] {
        let root = try payload(result)
        let items = try XCTUnwrap(root["items"] as? [[String: Any]])
        return try XCTUnwrap(items.first)
    }

    private func payload(_ result: AgentServiceResult) throws -> [String: Any] {
        let data = try JSONEncoder().encode(result)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap(root["data"] as? [String: Any])
    }
}

@MainActor
private final class AgentRenameFixture {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("covio-agent-naming-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func file(_ name: String, contents: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url, options: .atomic)
        return url
    }

    func attachment(_ url: URL) -> ResolvedAgentFile {
        ResolvedAgentFile(
            fileId: "attachment:\(UUID().uuidString.lowercased())",
            displayName: url.lastPathComponent,
            url: url
        )
    }

    func service() -> AgentFileNamingService {
        let model = AgentPreviewNamingModel()
        let autoNaming = AutoNamingRuntime(model: model)
        return AgentFileNamingService(
            autoNaming: autoNaming,
            policy: FileNamingPolicy.companion.defaults(),
            renameService: FileRenameService(
                journal: FileRenameJournalStore(
                    directory: directory.appendingPathComponent("journal", isDirectory: true)
                )
            ),
            nowEpochSeconds: { 1_000 },
            makeRunID: { "agent-run-1" }
        )
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private final class AgentPreviewNamingModel: NamingModelServing, @unchecked Sendable {
    func preheat() async throws -> NamingModelMetrics {
        metrics()
    }

    func generate(_ request: NamingModelRequest) async throws -> NamingModelResponse {
        NamingModelResponse(
            candidateId: request.candidateId,
            kind: request.kind,
            title: "Quarterly Report",
            category: "Finance",
            confidence: 0.9,
            origin: .mlx,
            primaryErrorCode: nil,
            warnings: [],
            metrics: metrics()
        )
    }

    func cancel() async {}
    func release() async {}

    private func metrics() -> NamingModelMetrics {
        NamingModelMetrics(
            modelLoadMilliseconds: 1,
            preheatMilliseconds: 1,
            generationMilliseconds: 1,
            inputTokenCount: 1,
            outputTokenCount: 1,
            peakResidentBytes: 1
        )
    }
}
