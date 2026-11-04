import Foundation
import Hub

enum LocalModelDownloadPhase: String, Codable, Sendable, Equatable {
    case notDownloaded
    case downloading
    case paused
    case verifying
    case ready
    case failed
}

enum LocalModelDownloadErrorCode: String, Codable, Sendable, Equatable {
    case busy
    case sourceUnavailable
    case manifestInvalid
    case revisionMismatch
    case insufficientHardware
    case insufficientMemory
    case insufficientDisk
    case cancelled
    case downloadFailed
    case verificationFailed
    case existingPackageInvalid
    case activationFailed
}

struct LocalModelDownloadFailure: Error, Sendable, Equatable, LocalizedError {
    let code: LocalModelDownloadErrorCode
    let detail: String

    var errorDescription: String? { detail }
}

struct LocalModelDownloadStatus: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let tier: LocalModelTier
    let modelID: String
    let displayName: String
    let revision: String
    let license: String
    let totalBytes: Int64
    var phase: LocalModelDownloadPhase
    var fractionCompleted: Double
    var downloadedBytes: Int64
    var errorCode: LocalModelDownloadErrorCode?
    var detail: String?
    var updatedAtEpochMilliseconds: Int64

    init(
        source: LocalModelPackageSource,
        phase: LocalModelDownloadPhase,
        fractionCompleted: Double = 0,
        errorCode: LocalModelDownloadErrorCode? = nil,
        detail: String? = nil,
        updatedAtEpochMilliseconds: Int64
    ) {
        let fraction = ModelDownloadStatePolicy.shared.clampProgress(value: fractionCompleted)
        self.schemaVersion = Self.schemaVersion
        tier = source.manifest.tier
        modelID = source.manifest.modelID
        displayName = source.manifest.displayName
        revision = source.manifest.revision
        license = source.manifest.license
        totalBytes = source.manifest.totalBytes
        self.phase = phase
        self.fractionCompleted = fraction
        downloadedBytes = ModelDownloadStatePolicy.shared.downloadedBytes(
            fractionCompleted: fraction,
            totalBytes: source.manifest.totalBytes
        )
        self.errorCode = errorCode
        self.detail = detail
        self.updatedAtEpochMilliseconds = updatedAtEpochMilliseconds
    }

    mutating func setFraction(_ fraction: Double, now: Int64) {
        let clamped = ModelDownloadStatePolicy.shared.clampProgress(value: fraction)
        guard clamped >= fractionCompleted else { return }
        fractionCompleted = clamped
        downloadedBytes = ModelDownloadStatePolicy.shared.downloadedBytes(
            fractionCompleted: clamped,
            totalBytes: totalBytes
        )
        updatedAtEpochMilliseconds = now
    }
}

struct LocalModelPackageSource: Sendable, Equatable {
    let manifest: LocalModelPackageManifest
    let manifestData: Data
    let licenseData: Data
    let noticeData: Data
}

protocol LocalModelPackageSourceProviding: Sendable {
    func source(for tier: LocalModelTier) throws -> LocalModelPackageSource
}

struct BundleLocalModelPackageSourceProvider: LocalModelPackageSourceProviding {
    let resourceDirectory: URL

    init(resourceDirectory: URL? = nil) {
        self.resourceDirectory = resourceDirectory
            ?? Bundle.main.resourceURL
            ?? Bundle.main.bundleURL
    }

    func source(for tier: LocalModelTier) throws -> LocalModelPackageSource {
        let manifestURL = resourceDirectory.appendingPathComponent(Self.manifestFile(for: tier))
        let manifestData: Data
        let manifest: LocalModelPackageManifest
        do {
            manifestData = try Data(contentsOf: manifestURL, options: .mappedIfSafe)
            manifest = try JSONDecoder().decode(LocalModelPackageManifest.self, from: manifestData)
        } catch {
            throw LocalModelDownloadFailure(
                code: .sourceUnavailable,
                detail: "The bundled model manifest is unavailable or invalid."
            )
        }
        guard manifest.tier == tier else {
            throw LocalModelDownloadFailure(
                code: .manifestInvalid,
                detail: "The bundled model manifest does not match the requested tier."
            )
        }
        guard ModelPackageContract.shared.isSafeFileName(name: manifest.licenseFile),
              ModelPackageContract.shared.isSafeFileName(name: manifest.noticeFile)
        else {
            throw LocalModelDownloadFailure(
                code: .manifestInvalid,
                detail: "The bundled model manifest contains an unsafe attribution path."
            )
        }

        let attributionDirectory = resourceDirectory
            .appendingPathComponent("ThirdPartyNotices", isDirectory: true)
            .appendingPathComponent("model", isDirectory: true)
            .appendingPathComponent(Self.attributionDirectory(for: tier), isDirectory: true)
        do {
            return LocalModelPackageSource(
                manifest: manifest,
                manifestData: manifestData,
                licenseData: try Data(
                    contentsOf: attributionDirectory.appendingPathComponent(manifest.licenseFile),
                    options: .mappedIfSafe
                ),
                noticeData: try Data(
                    contentsOf: attributionDirectory.appendingPathComponent(manifest.noticeFile),
                    options: .mappedIfSafe
                )
            )
        } catch {
            throw LocalModelDownloadFailure(
                code: .sourceUnavailable,
                detail: "The bundled model license or notice is missing."
            )
        }
    }

    private static func manifestFile(for tier: LocalModelTier) -> String {
        switch tier {
        case .compact2B: "FileNamingModelManifest.json"
        case .balanced4B: "FileNamingModelManifest-balanced4B.json"
        case .highQuality8B: "FileNamingModelManifest-highQuality8B.json"
        case .heavy30BA3B: "FileNamingModelManifest-heavy30BA3B.json"
        }
    }

    private static func attributionDirectory(for tier: LocalModelTier) -> String {
        switch tier {
        case .compact2B: "Qwen3-VL-2B-Instruct"
        case .balanced4B: "Qwen3-VL-4B-Instruct"
        case .highQuality8B: "Qwen3-VL-8B-Instruct"
        case .heavy30BA3B: "Qwen3-VL-30B-A3B-Instruct"
        }
    }

}

protocol LocalModelRemoteDownloading: Sendable {
    func download(
        manifest: LocalModelPackageManifest,
        to downloadBase: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL
}

struct HubLocalModelRemoteDownloader: LocalModelRemoteDownloading {
    func download(
        manifest: LocalModelPackageManifest,
        to downloadBase: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let hub = HubApi(downloadBase: downloadBase, useBackgroundSession: false)
        return try await hub.snapshot(
            from: manifest.modelID,
            revision: manifest.revision,
            matching: manifest.files.map(\.path)
        ) { current, _ in
            progress(current.fractionCompleted)
        }
    }
}

struct LocalModelDownloadRoots: Sendable, Equatable {
    let downloadsDirectory: URL
    let packagesDirectory: URL

    func statusFile(for tier: LocalModelTier) -> URL {
        downloadsDirectory
            .appendingPathComponent(tier.rawValue, isDirectory: true)
            .appendingPathComponent("status.json")
    }

    func stagingDirectory(for tier: LocalModelTier, revision: String) -> URL {
        downloadsDirectory
            .appendingPathComponent(tier.rawValue, isDirectory: true)
            .appendingPathComponent(revision, isDirectory: true)
    }

    func packageDirectory(for tier: LocalModelTier, revision: String) -> URL {
        packagesDirectory
            .appendingPathComponent(tier.rawValue, isDirectory: true)
            .appendingPathComponent(revision, isDirectory: true)
    }
}

struct LocalModelDownloadStatusStore: Sendable {
    let roots: LocalModelDownloadRoots

    func load(for tier: LocalModelTier) -> LocalModelDownloadStatus? {
        do {
            let data = try Data(contentsOf: roots.statusFile(for: tier), options: .mappedIfSafe)
            let status = try JSONDecoder().decode(LocalModelDownloadStatus.self, from: data)
            guard status.schemaVersion == LocalModelDownloadStatus.schemaVersion,
                  status.tier == tier
            else { return nil }
            return status
        } catch {
            return nil
        }
    }

    func save(_ status: LocalModelDownloadStatus) throws {
        let path = roots.statusFile(for: status.tier)
        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(status)
        try data.write(to: path, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: path.path
        )
    }
}

/// The model setup view model uses this boundary for download and recovery.
/// Tests can replace the real Hub downloader without opening the network.
protocol LocalModelInstalling: Actor {
    func status(for tier: LocalModelTier) throws -> LocalModelDownloadStatus
    func download(tier: LocalModelTier) async throws -> VerifiedLocalModelPackage
    func pause() -> LocalModelDownloadStatus?
    func reset(tier: LocalModelTier) throws
}

actor LocalModelDownloader {
    private static let progressPersistInterval: Double = 1
    private static let progressPersistStep: Double = 0.01
    private static let diskReserveBytes: Int64 = 128 * 1_024 * 1_024

    private let roots: LocalModelDownloadRoots
    private let registry: LocalModelPackageRegistryStore
    private let verifier: LocalModelPackageVerifier
    private let expectations: [LocalModelTier: LocalModelPackageExpectation]
    private let sourceProvider: any LocalModelPackageSourceProviding
    private let remoteFactory: @Sendable (URL) -> any LocalModelRemoteDownloading
    private let memorySnapshot: @Sendable () -> LocalModelMemorySnapshot
    private let availableDiskBytes: @Sendable (URL) -> Int64?
    private let nowEpochMilliseconds: @Sendable () -> Int64
    private let statusStore: LocalModelDownloadStatusStore

    private var activeTask: Task<VerifiedLocalModelPackage, Error>?
    private var activeTier: LocalModelTier?
    private var activeStatus: LocalModelDownloadStatus?
    private var pauseRequested = false
    private var lastProgressPersistedAt: Int64 = 0
    private var lastPersistedFraction: Double = -1

    init(
        downloadsDirectory: URL = AppPaths.localModelDownloadsDirectory,
        packagesDirectory: URL = AppPaths.localModelPackagesDirectory,
        registry: LocalModelPackageRegistryStore = LocalModelPackageRegistryStore(
            path: AppPaths.localModelPackagesFile
        ),
        verifier: LocalModelPackageVerifier = LocalModelPackageVerifier(),
        expectations: [LocalModelTier: LocalModelPackageExpectation] = LocalModelPackageCatalog.expectations,
        sourceProvider: any LocalModelPackageSourceProviding = BundleLocalModelPackageSourceProvider(),
        remoteFactory: @escaping @Sendable (URL) -> any LocalModelRemoteDownloading = {
            _ in HubLocalModelRemoteDownloader()
        },
        memorySnapshot: @escaping @Sendable () -> LocalModelMemorySnapshot = {
            LocalModelMemoryProbe.current()
        },
        availableDiskBytes: @escaping @Sendable (URL) -> Int64? = {
            localModelVolumeAvailableBytes(at: $0)
        },
        nowEpochMilliseconds: @escaping @Sendable () -> Int64 = {
            Int64((Date().timeIntervalSince1970 * 1_000).rounded())
        }
    ) {
        roots = LocalModelDownloadRoots(
            downloadsDirectory: downloadsDirectory,
            packagesDirectory: packagesDirectory
        )
        self.registry = registry
        self.verifier = verifier
        self.expectations = expectations
        self.sourceProvider = sourceProvider
        self.remoteFactory = remoteFactory
        self.memorySnapshot = memorySnapshot
        self.availableDiskBytes = availableDiskBytes
        self.nowEpochMilliseconds = nowEpochMilliseconds
        statusStore = LocalModelDownloadStatusStore(
            roots: LocalModelDownloadRoots(
                downloadsDirectory: downloadsDirectory,
                packagesDirectory: packagesDirectory
            )
        )
    }

    func status(for tier: LocalModelTier) throws -> LocalModelDownloadStatus {
        if activeTier == tier, let activeStatus {
            return activeStatus
        }
        let source = try sourceProvider.source(for: tier)
        var status = statusStore.load(for: tier)
            ?? LocalModelDownloadStatus(
                source: source,
                phase: .notDownloaded,
                updatedAtEpochMilliseconds: nowEpochMilliseconds()
            )
        var normalized = false
        if status.modelID != source.manifest.modelID
            || status.revision != source.manifest.revision
        {
            status = LocalModelDownloadStatus(
                source: source,
                phase: .notDownloaded,
                updatedAtEpochMilliseconds: nowEpochMilliseconds()
            )
            normalized = true
        }

        if let registration = registry.load().registration(for: tier),
           registration.revision == source.manifest.revision {
            status.phase = .ready
            status.fractionCompleted = 1
            status.downloadedBytes = status.totalBytes
            status.errorCode = nil
            status.detail = nil
            return status
        }
        if status.phase == .ready {
            status.phase = .paused
            status.detail = "The downloaded model is not registered."
            status.updatedAtEpochMilliseconds = nowEpochMilliseconds()
            normalized = true
        }
        let normalizedPhaseKey = ModelDownloadStatePolicy.shared.phaseKeyAfterInterruption(
            phaseKey: status.phase.rawValue
        )
        if normalizedPhaseKey != status.phase.rawValue,
           let normalizedPhase = LocalModelDownloadPhase(rawValue: normalizedPhaseKey)
        {
            status.phase = normalizedPhase
            status.detail = "The previous download was interrupted."
            status.updatedAtEpochMilliseconds = nowEpochMilliseconds()
            normalized = true
        }
        if normalized {
            try? statusStore.save(status)
        }
        return status
    }

    func download(tier: LocalModelTier) async throws -> VerifiedLocalModelPackage {
        guard activeTask == nil else {
            throw LocalModelDownloadFailure(
                code: .busy,
                detail: "Another model download is already in progress."
            )
        }

        let source: LocalModelPackageSource
        do {
            source = try sourceProvider.source(for: tier)
        } catch let failure as LocalModelDownloadFailure {
            throw failure
        } catch {
            throw LocalModelDownloadFailure(
                code: .sourceUnavailable,
                detail: "The model package source is unavailable."
            )
        }

        do {
            try validate(source: source, tier: tier)
        } catch let failure as LocalModelDownloadFailure {
            try? statusStore.save(
                LocalModelDownloadStatus(
                    source: source,
                    phase: .failed,
                    errorCode: failure.code,
                    detail: failure.detail,
                    updatedAtEpochMilliseconds: nowEpochMilliseconds()
                )
            )
            throw failure
        }

        if let registration = registry.load().registration(for: tier),
           registration.revision == source.manifest.revision {
            do {
                let verified = try verifier.verify(
                    directory: URL(fileURLWithPath: registration.directoryPath, isDirectory: true),
                    tier: tier
                )
                try finishReady(source: source)
                return verified
            } catch let failure as LocalModelPackageFailure {
                let downloadFailure = LocalModelDownloadFailure(
                    code: .verificationFailed,
                    detail: failure.detail
                )
                try? statusStore.save(
                    LocalModelDownloadStatus(
                        source: source,
                        phase: .failed,
                        errorCode: downloadFailure.code,
                        detail: downloadFailure.detail,
                        updatedAtEpochMilliseconds: nowEpochMilliseconds()
                    )
                )
                throw downloadFailure
            }
        }

        let destination = roots.packageDirectory(
            for: tier,
            revision: source.manifest.revision
        )
        if FileManager.default.fileExists(atPath: destination.path) {
            return try activateExistingPackage(at: destination, source: source)
        }

        do {
            try preflightHardware(tier: tier)
            try preflightDisk(source: source)
        } catch let failure as LocalModelDownloadFailure {
            try? statusStore.save(
                LocalModelDownloadStatus(
                    source: source,
                    phase: .failed,
                    errorCode: failure.code,
                    detail: failure.detail,
                    updatedAtEpochMilliseconds: nowEpochMilliseconds()
                )
            )
            throw failure
        }

        var status = statusStore.load(for: tier)
            ?? LocalModelDownloadStatus(
                source: source,
                phase: .downloading,
                updatedAtEpochMilliseconds: nowEpochMilliseconds()
            )
        if status.revision != source.manifest.revision {
            status = LocalModelDownloadStatus(
                source: source,
                phase: .downloading,
                updatedAtEpochMilliseconds: nowEpochMilliseconds()
            )
        }
        status.phase = .downloading
        status.errorCode = nil
        status.detail = nil
        status.updatedAtEpochMilliseconds = nowEpochMilliseconds()
        activeTier = tier
        activeStatus = status
        pauseRequested = false
        lastProgressPersistedAt = 0
        lastPersistedFraction = -1
        try? statusStore.save(status)

        let task = Task {
            try await self.performDownload(source: source)
        }
        activeTask = task

        do {
            let verified = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            activeTask = nil
            activeTier = nil
            activeStatus = nil
            pauseRequested = false
            return verified
        } catch {
            let cancelled = pauseRequested || Task.isCancelled || Self.isCancellation(error)
            let failure = Self.failure(from: error)
            var next = activeStatus ?? status
            next.phase = LocalModelDownloadPhase(
                rawValue: ModelDownloadStatePolicy.shared.phaseKeyAfterFailure(paused: cancelled)
            ) ?? .failed
            if cancelled {
                next.errorCode = .cancelled
                next.detail = "The model download is paused."
            } else {
                next.errorCode = failure.code
                next.detail = failure.detail
            }
            next.updatedAtEpochMilliseconds = nowEpochMilliseconds()
            try? statusStore.save(next)
            activeTask = nil
            activeTier = nil
            activeStatus = nil
            pauseRequested = false
            if cancelled {
                throw LocalModelDownloadFailure(
                    code: .cancelled,
                    detail: "The model download is paused."
                )
            }
            throw failure
        }
    }

    @discardableResult
    func pause() -> LocalModelDownloadStatus? {
        guard let task = activeTask else { return nil }
        pauseRequested = true
        if var status = activeStatus {
            status.phase = .paused
            status.errorCode = .cancelled
            status.detail = "The model download is paused."
            status.updatedAtEpochMilliseconds = nowEpochMilliseconds()
            activeStatus = status
            try? statusStore.save(status)
        }
        task.cancel()
        return activeStatus
    }

    /// Removes only downloader-managed staging and status data.
    /// The registry and installed package are owned by the model setup runtime.
    func reset(tier: LocalModelTier) throws {
        guard activeTask == nil else {
            throw LocalModelDownloadFailure(
                code: .busy,
                detail: "A model download is still active."
            )
        }
        let tierDirectory = roots.downloadsDirectory
            .appendingPathComponent(tier.rawValue, isDirectory: true)
        if FileManager.default.fileExists(atPath: tierDirectory.path) {
            try FileManager.default.removeItem(at: tierDirectory)
        }
    }

    private func performDownload(
        source: LocalModelPackageSource
    ) async throws -> VerifiedLocalModelPackage {
        let manifest = source.manifest
        let staging = roots.stagingDirectory(for: manifest.tier, revision: manifest.revision)
        let downloadBase = staging.appendingPathComponent("hub", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: downloadBase,
                withIntermediateDirectories: true
            )
        } catch {
            throw LocalModelDownloadFailure(
                code: .insufficientDisk,
                detail: "The model staging directory cannot be created."
            )
        }

        let progress: @Sendable (Double) -> Void = { [weak self] fraction in
            Task { await self?.recordProgress(fraction, tier: manifest.tier) }
        }
        let remote = remoteFactory(downloadBase)
        let snapshotURL: URL
        do {
            snapshotURL = try await remote.download(
                manifest: manifest,
                to: downloadBase,
                progress: progress
            )
        } catch {
            if pauseRequested || Task.isCancelled || Self.isCancellation(error) {
                throw CancellationError()
            }
            throw LocalModelDownloadFailure(
                code: .downloadFailed,
                detail: error.localizedDescription
            )
        }
        try Task.checkCancellation()
        do {
            try Self.validateSnapshot(snapshotURL, in: downloadBase)
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }

        do {
            try source.manifestData.write(
                to: snapshotURL.appendingPathComponent("FileNamingModelManifest.json"),
                options: .atomic
            )
            try source.licenseData.write(
                to: snapshotURL.appendingPathComponent(manifest.licenseFile),
                options: .atomic
            )
            try source.noticeData.write(
                to: snapshotURL.appendingPathComponent(manifest.noticeFile),
                options: .atomic
            )
        } catch {
            throw LocalModelDownloadFailure(
                code: .downloadFailed,
                detail: "The model manifest or attribution cannot be written."
            )
        }

        setPhase(.verifying, fraction: 1, clearError: true)
        let verified = try await verify(
            snapshotURL,
            tier: manifest.tier,
            stagingDirectory: staging
        )
        try Task.checkCancellation()
        return try finalize(source: source, verified: verified)
    }

    private func finalize(
        source: LocalModelPackageSource,
        verified: VerifiedLocalModelPackage
    ) throws -> VerifiedLocalModelPackage {
        let manifest = source.manifest
        let destination = roots.packageDirectory(
            for: manifest.tier,
            revision: manifest.revision
        )
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                return try activateExistingPackage(at: destination, source: source)
            }

            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.moveItem(at: verified.directory, to: destination)
            let moved = VerifiedLocalModelPackage(
                tier: verified.tier,
                directory: destination.standardizedFileURL,
                manifest: verified.manifest,
                verifiedAtEpochMilliseconds: verified.verifiedAtEpochMilliseconds
            )
            try registry.register(moved)
            try finishReady(source: source)
            try? FileManager.default.removeItem(
                at: roots.stagingDirectory(for: manifest.tier, revision: manifest.revision)
            )
            return moved
        } catch let failure as LocalModelDownloadFailure {
            throw failure
        } catch {
            throw LocalModelDownloadFailure(
                code: .activationFailed,
                detail: error.localizedDescription
            )
        }
    }

    private func activateExistingPackage(
        at directory: URL,
        source: LocalModelPackageSource
    ) throws -> VerifiedLocalModelPackage {
        let existing: VerifiedLocalModelPackage
        do {
            existing = try verifier.verify(directory: directory, tier: source.manifest.tier)
        } catch {
            let failure = LocalModelDownloadFailure(
                code: .existingPackageInvalid,
                detail: "A downloaded model directory exists but failed verification."
            )
            try? statusStore.save(
                LocalModelDownloadStatus(
                    source: source,
                    phase: .failed,
                    errorCode: failure.code,
                    detail: failure.detail,
                    updatedAtEpochMilliseconds: nowEpochMilliseconds()
                )
            )
            throw failure
        }
        do {
            try registry.register(existing)
            try finishReady(source: source)
        } catch {
            let failure = LocalModelDownloadFailure(
                code: .activationFailed,
                detail: error.localizedDescription
            )
            try? statusStore.save(
                LocalModelDownloadStatus(
                    source: source,
                    phase: .failed,
                    errorCode: failure.code,
                    detail: failure.detail,
                    updatedAtEpochMilliseconds: nowEpochMilliseconds()
                )
            )
            throw failure
        }
        try? FileManager.default.removeItem(
            at: roots.stagingDirectory(
                for: source.manifest.tier,
                revision: source.manifest.revision
            )
        )
        return existing
    }

    private func verify(
        _ directory: URL,
        tier: LocalModelTier,
        stagingDirectory: URL
    ) async throws -> VerifiedLocalModelPackage {
        let verifier = verifier
        let task = Task.detached(priority: .userInitiated) {
            try verifier.verify(directory: directory, tier: tier)
        }
        do {
            return try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
        } catch let failure as LocalModelPackageFailure {
            try? FileManager.default.removeItem(at: stagingDirectory)
            throw LocalModelDownloadFailure(
                code: .verificationFailed,
                detail: failure.detail
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw LocalModelDownloadFailure(
                code: .verificationFailed,
                detail: error.localizedDescription
            )
        }
    }

    private func validate(
        source: LocalModelPackageSource,
        tier: LocalModelTier
    ) throws {
        guard let expectation = expectations[tier] else {
            throw LocalModelDownloadFailure(
                code: .manifestInvalid,
                detail: "The requested model tier has no trusted package definition."
            )
        }
        let validation = ModelPackageContract.shared.validateManifestText(
            manifestText: String(decoding: source.manifestData, as: UTF8.self),
            expectedTier: tier.rawValue,
            expectedModelId: expectation.modelID,
            expectedRevision: expectation.revision,
            expectedRuntimeDirectory: "Models/\(tier.runtimeDirectoryName)",
            expectedTotalBytes: expectation.totalBytes,
            expectedLicense: expectation.license
        )
        guard validation.valid else {
            throw LocalModelDownloadFailure(
                code: validation.errorCode == "revisionMismatch"
                    ? .revisionMismatch
                    : .manifestInvalid,
                detail: validation.detail
            )
        }
    }

    private func preflightHardware(tier: LocalModelTier) throws {
        let memory = memorySnapshot()
        guard memory.physicalBytes >= tier.minimumPhysicalMemoryBytes else {
            throw LocalModelDownloadFailure(
                code: .insufficientHardware,
                detail: "This Mac does not meet the model tier memory requirement."
            )
        }
        guard memory.availableBytes >= tier.estimatedWorkingSetBytes else {
            throw LocalModelDownloadFailure(
                code: .insufficientMemory,
                detail: "Close memory-heavy apps before downloading this model."
            )
        }
    }

    private func preflightDisk(source: LocalModelPackageSource) throws {
        let root = roots.downloadsDirectory
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        } catch {
            throw LocalModelDownloadFailure(
                code: .insufficientDisk,
                detail: "The model download directory cannot be created."
            )
        }
        guard let available = availableDiskBytes(root) else {
            throw LocalModelDownloadFailure(
                code: .insufficientDisk,
                detail: "The available disk space cannot be determined."
            )
        }
        let (doubled, multiplyOverflow) = source.manifest.totalBytes
            .multipliedReportingOverflow(by: 2)
        let (sum, addOverflow) = doubled.addingReportingOverflow(Self.diskReserveBytes)
        let required = multiplyOverflow || addOverflow ? Int64.max : sum
        guard available >= required else {
            throw LocalModelDownloadFailure(
                code: .insufficientDisk,
                detail: "The model download needs at least \(required) available bytes."
            )
        }
    }

    private func recordProgress(_ fraction: Double, tier: LocalModelTier) {
        guard activeTier == tier, var status = activeStatus else { return }
        let previousFraction = status.fractionCompleted
        status.setFraction(fraction, now: nowEpochMilliseconds())
        status.phase = .downloading
        status.errorCode = nil
        status.detail = nil
        activeStatus = status

        let now = status.updatedAtEpochMilliseconds
        let elapsed = Double(now - lastProgressPersistedAt) / 1_000
        if lastProgressPersistedAt == 0
            || elapsed >= Self.progressPersistInterval
            || status.fractionCompleted - lastPersistedFraction >= Self.progressPersistStep
            || (status.fractionCompleted >= 1 && previousFraction < 1)
        {
            lastProgressPersistedAt = now
            lastPersistedFraction = status.fractionCompleted
            try? statusStore.save(status)
        }
    }

    private func setPhase(
        _ phase: LocalModelDownloadPhase,
        fraction: Double,
        clearError: Bool
    ) {
        guard var status = activeStatus else { return }
        status.phase = phase
        status.setFraction(fraction, now: nowEpochMilliseconds())
        if clearError {
            status.errorCode = nil
            status.detail = nil
        }
        activeStatus = status
        try? statusStore.save(status)
    }

    private func finishReady(source: LocalModelPackageSource) throws {
        var status = LocalModelDownloadStatus(
            source: source,
            phase: .ready,
            fractionCompleted: 1,
            updatedAtEpochMilliseconds: nowEpochMilliseconds()
        )
        status.downloadedBytes = status.totalBytes
        try statusStore.save(status)
        activeStatus = status
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
    }

    private static func failure(from error: Error) -> LocalModelDownloadFailure {
        if let failure = error as? LocalModelDownloadFailure {
            return failure
        }
        if let failure = error as? LocalModelPackageFailure {
            return LocalModelDownloadFailure(
                code: .verificationFailed,
                detail: failure.detail
            )
        }
        return LocalModelDownloadFailure(
            code: .downloadFailed,
            detail: error.localizedDescription
        )
    }

    private static func isContained(_ child: URL, in parent: URL) -> Bool {
        let childPath = child.standardizedFileURL.path
        let parentPath = parent.standardizedFileURL.path
        return childPath.hasPrefix(parentPath + "/")
    }

    private static func validateSnapshot(_ snapshot: URL, in downloadBase: URL) throws {
        let resolvedSnapshot = snapshot.resolvingSymlinksInPath().standardizedFileURL
        let resolvedDownloadBase = downloadBase.resolvingSymlinksInPath().standardizedFileURL
        guard isContained(resolvedSnapshot, in: resolvedDownloadBase) else {
            throw LocalModelDownloadFailure(
                code: .downloadFailed,
                detail: "The downloaded model directory escaped the staging root."
            )
        }
        let values: URLResourceValues
        do {
            values = try snapshot.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        } catch {
            throw LocalModelDownloadFailure(
                code: .downloadFailed,
                detail: "The downloaded model directory is unavailable."
            )
        }
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw LocalModelDownloadFailure(
                code: .downloadFailed,
                detail: "The downloaded model directory is not a regular directory."
            )
        }
    }

}

extension LocalModelDownloader: LocalModelInstalling {}

private func localModelVolumeAvailableBytes(at url: URL) -> Int64? {
    guard let values = try? url.resourceValues(
        forKeys: [.volumeAvailableCapacityForImportantUsageKey]
    ) else { return nil }
    return values.volumeAvailableCapacityForImportantUsage
}
