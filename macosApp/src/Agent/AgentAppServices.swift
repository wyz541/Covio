import AppKit
import Foundation
import MLXLMCommon

@MainActor
enum AgentAppServices {
    static func handlers(
        shelf: ShelfRuntime,
        clipboard: ClipboardRuntime,
        workspace: WorkspaceRuntime,
        attachments: AgentAttachmentStore,
        autoNaming: AutoNamingRuntime,
        fileNamingPolicy: FileNamingPolicy,
        uiActions: AgentUIActionRouter,
        modelRuntime: LocalModelRuntime
    ) -> AgentServiceHandlers {
        let monitor = MonitorSampler()
        let inspector = AgentFileInspector()
        let namingService = AgentFileNamingService(
            autoNaming: autoNaming,
            policy: fileNamingPolicy
        )
        let searchIndex = AgentFileSearchIndex()
        let visionQA = AgentVisionQAService(containerRuntime: modelRuntime)
        return AgentServiceHandlers(
            monitorSnapshot: {
                let snapshot = await monitor.sample()
                return monitorResult(snapshot)
            },
            powerStatus: {
                let power = await monitor.samplePowerOnly()
                return powerResult(power)
            },
            workspaceFiles: { query, limit in
                await MainActor.run {
                    workspaceResult(workspace.entries, query: query, limit: limit)
                }
            },
            screenshots: { limit in
                await MainActor.run {
                    screenshotResult(shelf.items, limit: limit)
                }
            },
            clipboardMetadata: { limit in
                await MainActor.run {
                    clipboardResult(clipboard.items, limit: limit)
                }
            },
            copyText: { text in
                await MainActor.run {
                    copyTextResult(text)
                }
            },
            inspectFile: { fileId, maxCharacters in
                guard let file = await MainActor.run(body: {
                    resolveFile(fileId: fileId, workspace: workspace, attachments: attachments)
                }) else {
                    return .failure("The file is not authorized.", code: .fileUnavailable)
                }
                return await Task.detached(priority: .userInitiated) {
                    inspector.inspect(file, maxCharacters: maxCharacters)
                }.value
            },
            describeImage: { fileId, question in
                guard let file = await MainActor.run(body: {
                    resolveFile(fileId: fileId, workspace: workspace, attachments: attachments)
                }) else {
                    return .failure("The file is not authorized.", code: .fileUnavailable)
                }
                return await visionQA.answer(file: file, question: question)
            },
            previewFileNames: { fileIds, maxResults in
                var seen = Set<String>()
                let uniqueIds = fileIds.filter { seen.insert($0).inserted }
                let files = await MainActor.run {
                    uniqueIds.compactMap {
                        resolveFile(
                            fileId: $0,
                            workspace: workspace,
                            attachments: attachments
                        )
                    }
                }
                guard files.count == uniqueIds.count, !files.isEmpty else {
                    return .failure(
                        "One or more files are not authorized.",
                        code: .fileUnavailable
                    )
                }
                return await namingService.preview(files: files, maxResults: maxResults)
            },
            applyFileRenames: { previewIds in
                await namingService.apply(previewIds: previewIds)
            },
            undoRenameRun: { runId in
                await namingService.undo(runId: runId)
            },
            searchFileContent: { fileIds, query, limit in
                var seen = Set<String>()
                let uniqueIds = fileIds.filter { seen.insert($0).inserted }
                let files = await MainActor.run {
                    uniqueIds.compactMap {
                        resolveFile(
                            fileId: $0,
                            workspace: workspace,
                            attachments: attachments
                        )
                    }
                }
                guard files.count == uniqueIds.count, !files.isEmpty else {
                    return .failure(
                        "One or more files are not authorized.",
                        code: .fileUnavailable
                    )
                }
                return await searchIndex.search(files: files, query: query, limit: limit)
            },
            openPane: { pane in
                await uiActions.openPane(pane)
            },
            readSetting: { key in
                await uiActions.readSetting(key)
            },
            requestSettingChange: { key, value in
                await uiActions.requestSettingChange(key, valueText: value)
            }
        )
    }

    nonisolated private static func monitorResult(_ snapshot: MonitorSnapshot) -> AgentServiceResult {
        var data: [String: JSONValue] = [
            "thermal": .string(snapshot.thermal.rawValue),
            "sampledAt": .double(snapshot.sampledAt.timeIntervalSince1970),
        ]
        if let cpu = snapshot.cpu {
            data["cpuPercent"] = .double(cpu.usage * 100)
            data["loadAverage"] = .double(cpu.loadAverage)
            data["coreCount"] = .int(cpu.coreCount)
        }
        if let gpu = snapshot.gpu {
            data["gpuPercent"] = .double(gpu.usage * 100)
            data["gpuMemoryUsed"] = .double(gpu.memoryUsed)
        }
        if let memory = snapshot.memory {
            data["memoryUsed"] = .double(memory.used)
            data["memoryTotal"] = .double(memory.total)
            data["swapUsed"] = .double(memory.swapUsed)
            data["memoryPressure"] = .string(memory.pressure.rawValue)
        }
        if let disk = snapshot.disk {
            data["diskFree"] = .double(disk.free)
            data["diskTotal"] = .double(disk.total)
            data["diskReadRate"] = .double(disk.readRate)
            data["diskWriteRate"] = .double(disk.writeRate)
        }
        if let network = snapshot.network {
            data["networkInterface"] = .string(network.interfaceName)
            data["downloadRate"] = .double(network.downloadRate)
            data["uploadRate"] = .double(network.uploadRate)
        }
        if let battery = snapshot.battery {
            data["batteryPercent"] = .double(battery.percent)
            data["batteryState"] = .string(battery.state.rawValue)
        }
        if let power = snapshot.power {
            data["powerSupply"] = .string(power.supply.rawValue)
            if let watts = power.watts { data["watts"] = .double(watts) }
            if let temperature = power.temperatureCelsius {
                data["temperatureCelsius"] = .double(temperature)
            }
        }
        return AgentServiceResult(
            ok: true,
            summary: "Read the current local monitor snapshot.",
            data: .object(data)
        )
    }

    nonisolated private static func powerResult(_ power: MonitorSnapshot.Power) -> AgentServiceResult {
        var data: [String: JSONValue] = [
            "supply": .string(power.supply.rawValue),
            "hasBattery": .bool(power.hasBattery),
            "batteryDataAvailable": .bool(power.batteryDataAvailable),
            "powerDataAvailable": .bool(power.powerDataAvailable),
        ]
        if let percent = power.batteryPercent { data["batteryPercent"] = .double(percent) }
        if let watts = power.watts { data["watts"] = .double(watts) }
        if let temperature = power.temperatureCelsius {
            data["temperatureCelsius"] = .double(temperature)
        }
        if let seconds = power.remainingSeconds { data["remainingSeconds"] = .double(seconds) }
        if let health = power.batteryHealthPercent {
            data["batteryHealthPercent"] = .double(health)
        }
        return AgentServiceResult(
            ok: true,
            summary: "Read the current local power state.",
            data: .object(data)
        )
    }

    private static func workspaceResult(
        _ entries: [WorkspaceEntry],
        query: String?,
        limit: Int
    ) -> AgentServiceResult {
        let normalizedQuery = query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let matches = entries
            .filter {
                normalizedQuery.isEmpty
                    || $0.displayName.localizedCaseInsensitiveContains(normalizedQuery)
            }
            .sorted { $0.createdAtEpochSeconds > $1.createdAtEpochSeconds }
            .prefix(limit)
            .map { entry in
                JSONValue.object([
                    "fileId": .string("workspace:\(entry.entryId)"),
                    "name": .string(entry.displayName),
                    "kind": .string(workspaceKindName(entry.kind)),
                    "contentType": .string(entry.contentType),
                    "byteSize": .int(Int(clamping: entry.byteSize)),
                    "createdAt": .int(Int(clamping: entry.createdAtEpochSeconds)),
                    "pinned": .bool(entry.pinned),
                    "availability": .string(workspaceAvailabilityName(entry.availability)),
                ])
            }
        return AgentServiceResult(
            ok: true,
            summary: "Found \(Array(matches).count) workspace entries.",
            data: .object(["items": .array(Array(matches))])
        )
    }

    @MainActor
    private static func resolveFile(
        fileId: String,
        workspace: WorkspaceRuntime,
        attachments: AgentAttachmentStore
    ) -> ResolvedAgentFile? {
        guard let reference = AgentFileReference(fileId: fileId) else { return nil }
        switch reference {
        case .workspace(let entryId):
            guard let entry = workspace.entries.first(where: { $0.entryId == entryId }),
                  let url = workspace.contentURL(entryId)
            else { return nil }
            return ResolvedAgentFile(
                fileId: fileId,
                displayName: entry.displayName,
                url: url
            )
        case .attachment:
            guard let file = attachments.file(id: fileId) else { return nil }
            return ResolvedAgentFile(
                fileId: file.id,
                displayName: file.displayName,
                url: file.url
            )
        }
    }

    private static func screenshotResult(_ items: [ShelfItem], limit: Int) -> AgentServiceResult {
        let matches = items.suffix(limit).map { item in
            JSONValue.object([
                "name": .string(URL(fileURLWithPath: item.path).lastPathComponent),
                "addedAt": .int(Int(clamping: item.addedAtEpochSeconds)),
            ])
        }
        return AgentServiceResult(
            ok: true,
            summary: "Found \(matches.count) recent screenshots.",
            data: .object(["items": .array(matches)])
        )
    }



    private static func clipboardResult(_ items: [ClipItem], limit: Int) -> AgentServiceResult {
        let matches = items.suffix(limit).map { item in
            JSONValue.object([
                "kind": .string(clipboardKindName(item.kind)),
                "byteSize": .int(Int(clamping: item.byteSize)),
                "createdAt": .int(Int(clamping: item.createdAtEpochSeconds)),
                "pinned": .bool(item.pinned),
            ])
        }
        return AgentServiceResult(
            ok: true,
            summary: "Found \(matches.count) clipboard entries. Content is hidden.",
            data: .object(["items": .array(matches)])
        )
    }

    private static func copyTextResult(_ text: String) -> AgentServiceResult {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let ok = pasteboard.setString(text, forType: .string)
        return AgentServiceResult(
            ok: ok,
            summary: ok ? "Copied text to the clipboard." : "Could not copy text.",
            data: nil
        )
    }

    private static func clipboardKindName(_ kind: ClipKind) -> String {
        if kind == ClipKind.link { return "link" }
        if kind == ClipKind.image { return "image" }
        if kind == ClipKind.color { return "color" }
        if kind == ClipKind.files { return "files" }
        return "text"
    }

    private static func workspaceKindName(_ kind: WorkspaceKind) -> String {
        if kind == WorkspaceKind.image { return "image" }
        if kind == WorkspaceKind.audio { return "audio" }
        if kind == WorkspaceKind.pdf { return "pdf" }
        if kind == WorkspaceKind.text { return "text" }
        return "file"
    }

    private static func workspaceAvailabilityName(_ availability: WorkspaceAvailability) -> String {
        if availability == WorkspaceAvailability.remote { return "remote" }
        if availability == WorkspaceAvailability.fetching { return "fetching" }
        if availability == WorkspaceAvailability.evicted { return "evicted" }
        return "local"
    }
}
