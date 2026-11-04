import CryptoKit
import Darwin
import Foundation

struct LocalModelPackageFile: Codable, Equatable, Sendable {
    let path: String
    let size: Int64
    let sha256: String
}

struct LocalModelPackageManifest: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let tier: LocalModelTier
    let modelID: String
    let revision: String
    let displayName: String
    let runtimeDirectory: String
    let license: String
    let licenseFile: String
    let noticeFile: String
    let totalBytes: Int64
    let files: [LocalModelPackageFile]
}

enum LocalModelPackageError: String, Error, Sendable, Equatable {
    case manifestUnreadable
    case unsupportedSchema
    case tierMismatch
    case modelMismatch
    case revisionMismatch
    case licenseRejected
    case invalidPath
    case symbolicLink
    case fileMissing
    case fileSizeMismatch
    case checksumMismatch
    case totalSizeMismatch
    case insufficientHardware
    case insufficientMemory
    case modelBusy
}

struct LocalModelPackageFailure: Error, Sendable, Equatable, LocalizedError {
    let code: LocalModelPackageError
    let detail: String

    var errorDescription: String? { detail }
}

struct LocalModelPackageExpectation: Sendable, Equatable {
    let modelID: String
    let revision: String
    let totalBytes: Int64
    let license: String
}

struct LocalModelMemorySnapshot: Sendable, Equatable {
    let physicalBytes: UInt64
    let availableBytes: UInt64
}

enum LocalModelMemoryProbe {
    static func current() -> LocalModelMemorySnapshot {
        let physical = ProcessInfo.processInfo.physicalMemory
        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            return LocalModelMemorySnapshot(physicalBytes: physical, availableBytes: 0)
        }
        let pageSize = UInt64(sysconf(_SC_PAGESIZE))
        let pages = UInt64(statistics.free_count)
            + UInt64(statistics.inactive_count)
            + UInt64(statistics.speculative_count)
        return LocalModelMemorySnapshot(
            physicalBytes: physical,
            availableBytes: min(physical, pages * pageSize)
        )
    }
}

struct LocalModelPackageVerifier: Sendable {
    let expectations: [LocalModelTier: LocalModelPackageExpectation]
    let memorySnapshot: @Sendable () -> LocalModelMemorySnapshot
    let nowEpochMilliseconds: @Sendable () -> Int64

    init(
        expectations: [LocalModelTier: LocalModelPackageExpectation] = LocalModelPackageCatalog.expectations,
        memorySnapshot: @escaping @Sendable () -> LocalModelMemorySnapshot = {
            LocalModelMemoryProbe.current()
        },
        nowEpochMilliseconds: @escaping @Sendable () -> Int64 = {
            Int64((Date().timeIntervalSince1970 * 1_000).rounded())
        }
    ) {
        self.expectations = expectations
        self.memorySnapshot = memorySnapshot
        self.nowEpochMilliseconds = nowEpochMilliseconds
    }

    func verify(
        directory: URL,
        tier: LocalModelTier
    ) throws -> VerifiedLocalModelPackage {
        try Task.checkCancellation()
        guard let expectation = expectations[tier] else {
            throw failure(.modelMismatch, "This model tier has no trusted package definition.")
        }
        let memory = memorySnapshot()
        guard memory.physicalBytes >= tier.minimumPhysicalMemoryBytes else {
            throw failure(.insufficientHardware, "This Mac does not meet the model tier memory requirement.")
        }
        guard memory.availableBytes >= tier.estimatedWorkingSetBytes else {
            throw failure(.insufficientMemory, "Close memory-heavy apps before loading this model.")
        }

        let root = directory.standardizedFileURL
        try requireDirectory(root)
        let manifestURL = root.appendingPathComponent("FileNamingModelManifest.json")
        _ = try requireRegularFile(
            manifestURL,
            code: .manifestUnreadable,
            detail: "The package manifest is missing."
        )
        let manifestData: Data
        do {
            manifestData = try Data(contentsOf: manifestURL, options: .mappedIfSafe)
        } catch {
            throw failure(.manifestUnreadable, "The package manifest cannot be read.")
        }
        let metadataValidation = ModelPackageContract.shared.validateManifestText(
            manifestText: String(decoding: manifestData, as: UTF8.self),
            expectedTier: tier.rawValue,
            expectedModelId: expectation.modelID,
            expectedRevision: expectation.revision,
            expectedRuntimeDirectory: "Models/\(tier.runtimeDirectoryName)",
            expectedTotalBytes: expectation.totalBytes,
            expectedLicense: expectation.license
        )
        guard metadataValidation.valid else {
            let code = metadataValidation.errorCode
                .flatMap(LocalModelPackageError.init(rawValue:))
                ?? .manifestUnreadable
            throw failure(code, metadataValidation.detail)
        }
        let manifest: LocalModelPackageManifest
        do {
            manifest = try JSONDecoder().decode(LocalModelPackageManifest.self, from: manifestData)
        } catch {
            throw failure(.manifestUnreadable, "The package manifest is not valid.")
        }
        for item in manifest.files {
            try Task.checkCancellation()
            let fileURL = root.appendingPathComponent(item.path)
            try verifyFile(
                fileURL,
                expectedSize: item.size,
                expectedSHA256: item.sha256
            )
        }
        for name in [manifest.licenseFile, manifest.noticeFile] {
            _ = try requireRegularFile(
                root.appendingPathComponent(name),
                code: .fileMissing,
                detail: "The package is missing its license or notice file."
            )
        }

        return VerifiedLocalModelPackage(
            tier: tier,
            directory: root,
            manifest: manifest,
            verifiedAtEpochMilliseconds: nowEpochMilliseconds()
        )
    }

    private func verifyFile(
        _ url: URL,
        expectedSize: Int64,
        expectedSHA256: String
    ) throws {
        let values = try requireRegularFile(
            url,
            code: .fileMissing,
            detail: "A model file is missing."
        )
        guard values.fileSize.map(Int64.init) == expectedSize else {
            throw failure(.fileSizeMismatch, "A model file size does not match the manifest.")
        }
        let digest = try sha256(url)
        guard digest == expectedSHA256.lowercased() else {
            throw failure(.checksumMismatch, "A model file checksum does not match the manifest.")
        }
    }

    private func requireDirectory(_ url: URL) throws {
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        } catch {
            throw failure(.fileMissing, "The package directory is unavailable.")
        }
        guard values.isSymbolicLink != true else {
            throw failure(.symbolicLink, "Symbolic links are not allowed in model packages.")
        }
        guard values.isDirectory == true else {
            throw failure(.fileMissing, "The package directory is unavailable.")
        }
    }

    private func requireRegularFile(
        _ url: URL,
        code: LocalModelPackageError,
        detail: String
    ) throws -> URLResourceValues {
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .fileSizeKey,
            ])
        } catch {
            throw failure(code, detail)
        }
        guard values.isSymbolicLink != true else {
            throw failure(.symbolicLink, "Symbolic links are not allowed in model packages.")
        }
        guard values.isRegularFile == true else {
            throw failure(code, detail)
        }
        return values
    }

    private func sha256(_ url: URL) throws -> String {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw failure(.fileMissing, "A model file cannot be opened.")
        }
        defer { try? handle.close() }
        var hasher = SHA256()
        do {
            while let data = try handle.read(upToCount: 8 * 1_024 * 1_024), !data.isEmpty {
                try Task.checkCancellation()
                hasher.update(data: data)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw failure(.fileMissing, "A model file cannot be read.")
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func failure(
        _ code: LocalModelPackageError,
        _ detail: String
    ) -> LocalModelPackageFailure {
        LocalModelPackageFailure(code: code, detail: detail)
    }
}

struct VerifiedLocalModelPackage: Sendable, Equatable {
    let tier: LocalModelTier
    let directory: URL
    let manifest: LocalModelPackageManifest
    let verifiedAtEpochMilliseconds: Int64
}

enum LocalModelPackageCatalog {
    static let expectations: [LocalModelTier: LocalModelPackageExpectation] = [
        .compact2B: LocalModelPackageExpectation(
            modelID: "mlx-community/Qwen3-VL-2B-Instruct-4bit",
            revision: "9c4f5209e57b31f4b9dfba735de3fb983739c9cc",
            totalBytes: 1_798_021_605,
            license: "Apache-2.0"
        ),
        .balanced4B: LocalModelPackageExpectation(
            modelID: "mlx-community/Qwen3-VL-4B-Instruct-4bit",
            revision: "2fd8dacbdb8f1e54b8c005f081ec5bf79c56376b",
            totalBytes: 3_109_729_929,
            license: "Apache-2.0"
        ),
        .highQuality8B: LocalModelPackageExpectation(
            modelID: "mlx-community/Qwen3-VL-8B-Instruct-4bit",
            revision: "defcdea7cc7a4b0858fea563cbbce171d328e457",
            totalBytes: 5_776_630_909,
            license: "Apache-2.0"
        ),
        .heavy30BA3B: LocalModelPackageExpectation(
            modelID: "lmstudio-community/Qwen3-VL-30B-A3B-Instruct-MLX-4bit",
            revision: "61c11f42d7bc01e00f5ea7f2e667c0a216f48397",
            totalBytes: 18_268_088_064,
            license: "Apache-2.0"
        ),
    ]
}

struct ImportedLocalModelPackage: Codable, Equatable, Sendable {
    let tier: LocalModelTier
    let directoryPath: String
    let modelID: String
    let revision: String
    let totalBytes: Int64
    let license: String
    let verifiedAtEpochMilliseconds: Int64
}

struct LocalModelPackageRegistry: Codable, Equatable, Sendable {
    var selectedTier: LocalModelTier?
    var packages: [ImportedLocalModelPackage]

    static let empty = LocalModelPackageRegistry(selectedTier: nil, packages: [])

    func registration(for tier: LocalModelTier) -> ImportedLocalModelPackage? {
        packages.first { $0.tier == tier }
    }
}

struct LocalModelPackageRegistryStore: Sendable {
    let path: URL

    func load() -> LocalModelPackageRegistry {
        do {
            let data = try Data(contentsOf: path, options: .mappedIfSafe)
            return try JSONDecoder().decode(LocalModelPackageRegistry.self, from: data)
        } catch {
            return .empty
        }
    }

    @discardableResult
    func register(_ package: VerifiedLocalModelPackage) throws -> LocalModelPackageRegistry {
        var registry = load()
        let registration = ImportedLocalModelPackage(
            tier: package.tier,
            directoryPath: package.directory.path,
            modelID: package.manifest.modelID,
            revision: package.manifest.revision,
            totalBytes: package.manifest.totalBytes,
            license: package.manifest.license,
            verifiedAtEpochMilliseconds: package.verifiedAtEpochMilliseconds
        )
        registry.packages.removeAll { $0.tier == package.tier }
        registry.packages.append(registration)
        registry.packages.sort { $0.tier.rank < $1.tier.rank }
        registry.selectedTier = package.tier
        try save(registry)
        return registry
    }

    @discardableResult
    func select(tier: LocalModelTier?) throws -> LocalModelPackageRegistry {
        var registry = load()
        if let tier, registry.registration(for: tier) == nil {
            throw LocalModelPackageFailure(
                code: .fileMissing,
                detail: "The selected model package is not registered."
            )
        }
        registry.selectedTier = tier
        try save(registry)
        return registry
    }

    @discardableResult
    func remove(tier: LocalModelTier) throws -> LocalModelPackageRegistry {
        var registry = load()
        registry.packages.removeAll { $0.tier == tier }
        if registry.selectedTier == tier {
            registry.selectedTier = nil
        }
        try save(registry)
        return registry
    }

    private func save(_ registry: LocalModelPackageRegistry) throws {
        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(registry)
        try data.write(to: path, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: path.path
        )
    }
}

struct LocalModelPackageImporter: Sendable {
    let verifier: LocalModelPackageVerifier
    let registry: LocalModelPackageRegistryStore

    init(
        verifier: LocalModelPackageVerifier = LocalModelPackageVerifier(),
        registry: LocalModelPackageRegistryStore
    ) {
        self.verifier = verifier
        self.registry = registry
    }

    func importPackage(directory: URL, tier: LocalModelTier) throws -> VerifiedLocalModelPackage {
        let verified = try verifier.verify(directory: directory, tier: tier)
        try registry.register(verified)
        return verified
    }
}

actor LocalModelSelectionState {
    private var tier: LocalModelTier?

    init(initialTier: LocalModelTier?) {
        tier = initialTier
    }

    func set(_ next: LocalModelTier?) {
        tier = next
    }

    func currentTier() -> LocalModelTier? {
        tier
    }

    func supportsAgentToolCalling() -> Bool {
        tier?.supportsAgentToolCalling == true
    }
}
