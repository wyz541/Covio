import CryptoKit
import Darwin
import Foundation

final class UpdaterCoordinator: @unchecked Sendable {
    struct PersistedStatus {
        let state: UpdaterEngineState
        let lastCheckAt: String?
        let availableVersion: String?
        let targetReleaseId: String?
        let message: String?
        let downloadProgress: Double?
    }

    private struct VerifiedCandidate {
        let manifest: UpdateManifest
        let manifestData: Data
        let signatureData: Data
    }

    private struct InstalledUpdaterIdentity {
        let releaseId: String
        let updaterSHA256: String
        let launcherSHA256: String
    }

    private let paths: UpdaterPaths
    private let currentReleaseId: String
    private let feed: any UpdaterFeedProviding
    private let trustedKeys: [String: Data]
    private let session: URLSession
    private let environment: [String: String]
    private let lock = NSLock()
    private var candidate: VerifiedCandidate?
    private var operationInProgress = false

    init(
        paths: UpdaterPaths,
        currentReleaseId: String,
        feed: any UpdaterFeedProviding = GithubUpdaterFeed(),
        trustedKeys: [String: Data] = GeneratedUpdateTrust.keys,
        session: URLSession = .shared,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.paths = paths
        self.currentReleaseId = currentReleaseId
        self.feed = feed
        self.trustedKeys = trustedKeys
        self.session = session
        self.environment = environment
    }

    var persistedStatus: PersistedStatus {
        if let data = try? Data(contentsOf: paths.updateState),
           let state = try? JSONDecoder().decode(UpdaterPersistedState.self, from: data),
           state.schemaVersion == 1
        {
            return PersistedStatus(
                state: state.state,
                lastCheckAt: state.lastCheckAt,
                availableVersion: state.availableVersion,
                targetReleaseId: state.targetReleaseId,
                message: state.message,
                downloadProgress: state.downloadProgress
            )
        }
        return PersistedStatus(
            state: trustedKeys.isEmpty ? .notConfigured : .idle,
            lastCheckAt: nil,
            availableVersion: nil,
            targetReleaseId: nil,
            message: nil,
            downloadProgress: nil
        )
    }

    func startupStatus() -> PersistedStatus {
        reconcileCompletedTransaction()
        recoverInterruptedInstallIfNeeded()
        return persistedStatus
    }

    func check(completion: @escaping (UpdaterOperationResult) -> Void) {
        let box = CallbackBox(completion)
        startExclusive {
            await self.performCheck()
        } completion: { result in
            box.call(result)
        }
    }

    func install(completion: @escaping (UpdaterOperationResult) -> Void) {
        let box = CallbackBox(completion)
        startExclusive {
            await self.performInstall()
        } completion: { result in
            box.call(result)
        }
    }

    func checkAndInstall(completion: @escaping (UpdaterOperationResult) -> Void) {
        let box = CallbackBox(completion)
        startExclusive {
            let check = await self.performCheck()
            guard check.state == .available else { return check }
            return await self.performInstall()
        } completion: { result in
            box.call(result)
        }
    }

    private func startExclusive(
        operation: @escaping @Sendable () async -> UpdaterOperationResult,
        completion: @escaping @Sendable (UpdaterOperationResult) -> Void
    ) {
        guard beginOperation() else {
            completion(UpdaterOperationResult(
                ok: false,
                state: persistedStatus.state,
                message: "Another updater operation is in progress",
                availableVersion: persistedStatus.availableVersion
            ))
            return
        }
        Task { [operation, completion] in
            let result = await operation()
            self.endOperation()
            completion(result)
        }
    }

    private func beginOperation() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !operationInProgress else { return false }
        operationInProgress = true
        return true
    }

    private func endOperation() {
        lock.lock()
        operationInProgress = false
        lock.unlock()
    }

    private func performCheck() async -> UpdaterOperationResult {
        if let installing = activeInstallResult() {
            return installing
        }
        guard !trustedKeys.isEmpty else {
            return persistFailure(.notConfigured, "Update trust keys are not configured")
        }
        do {
            try persist(.checking, availableVersion: nil, target: nil)
            let releases = try await feed.releases()
            guard let currentVersion = ReleaseVersion(GeneratedReleaseIdentity.clientVersion) else {
                return persistFailure(.failed, "Installed client version is invalid")
            }
            var firstFailure: Error?
            for release in releases {
                guard let candidateVersion = ReleaseVersion(release.clientVersion),
                      candidateVersion > currentVersion
                else {
                    // The feed is sorted newest first. A current or older release
                    // means no later release can be an update.
                    break
                }
                do {
                    let manifestData = try await downloadSmall(release.manifestURL)
                    let signatureData = try await downloadSmall(release.signatureURL)
                    let manifest = try UpdateManifestVerifier.verify(
                        manifestData: manifestData,
                        signatureData: signatureData,
                        trustedKeys: trustedKeys,
                        expectations: manifestExpectations()
                    )
                    guard release.clientVersion == manifest.clientVersion,
                          release.tagName == "v\(manifest.clientVersion)",
                          UpdaterContract.isTrustedArchiveURL(
                              release.archiveURL,
                              clientVersion: manifest.clientVersion
                          )
                    else {
                        throw UpdaterCoordinatorError.releaseMetadataMismatch
                    }
                    let verified = VerifiedCandidate(
                        manifest: manifest,
                        manifestData: manifestData,
                        signatureData: signatureData
                    )
                    try persistCandidate(verified)
                    setCandidate(verified)
                    try persist(
                        .available,
                        availableVersion: manifest.clientVersion,
                        target: manifest.releaseId
                    )
                    return .init(
                        ok: true,
                        state: .available,
                        message: "A verified update is available",
                        availableVersion: manifest.clientVersion
                    )
                } catch {
                    if firstFailure == nil {
                        firstFailure = error
                    }
                }
            }
            if let firstFailure {
                throw firstFailure
            }
            try clearCandidate()
            try persist(.idle, availableVersion: nil, target: nil)
            return .init(
                ok: true,
                state: .idle,
                message: "No update is available",
                availableVersion: nil
            )
        } catch {
            return persistFailure(.failed, "Update check failed: \(error.localizedDescription)")
        }
    }

    private func performInstall() async -> UpdaterOperationResult {
        if let installing = activeInstallResult() {
            return installing
        }
        do {
            guard let candidate = try currentCandidateOrRestore() else {
                return persistFailure(.failed, "No verified update is available")
            }
            let installed = try loadInstalledUpdaterIdentity()
            let transactionId = "update-\(candidate.manifest.releaseId)-\(UUID().uuidString.prefix(8))"
            let transaction = paths.transactions.appendingPathComponent(
                transactionId,
                isDirectory: true
            )
            try prepareRootDirectory(paths.transactions)
            try FileManager.default.createDirectory(
                at: transaction,
                withIntermediateDirectories: false
            )
            try secureRootItem(transaction, permissions: 0o700)
            try removeResultIfPresent()

            let archive = transaction.appendingPathComponent(
                "CovioUpdate-\(candidate.manifest.clientVersion).zip"
            )
            guard let archiveURL = URL(string: candidate.manifest.archiveURL) else {
                throw UpdaterCoordinatorError.invalidHTTPResponse
            }
            try persist(
                .downloading,
                availableVersion: candidate.manifest.clientVersion,
                target: candidate.manifest.releaseId,
                downloadProgress: 0
            )
            let downloadVersion = candidate.manifest.clientVersion
            let downloadReleaseId = candidate.manifest.releaseId
            try await downloadArchive(
                archiveURL,
                to: archive,
                expectedSize: candidate.manifest.archiveSize
            ) { [weak self] fraction in
                guard let self else { return }
                try? self.persistDownloadProgress(
                    fraction,
                    clientVersion: downloadVersion,
                    releaseId: downloadReleaseId
                )
            }
            try persistDownloadProgress(
                1,
                clientVersion: downloadVersion,
                releaseId: downloadReleaseId
            )
            guard Self.sha256File(archive) == candidate.manifest.archiveSHA256 else {
                throw UpdaterCoordinatorError.archiveDigestMismatch
            }
            try persist(
                .installing,
                availableVersion: candidate.manifest.clientVersion,
                target: candidate.manifest.releaseId
            )

            let extracted = transaction.appendingPathComponent("staging", isDirectory: true)
            try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: false)
            try secureRootItem(extracted, permissions: 0o700)
            try runTool(
                "/usr/bin/ditto",
                arguments: ["-x", "-k", "--norsrc", archive.path, extracted.path]
            )
            try validateArchiveLayout(extracted)
            try validateNoEscapingSymlinks(extracted)
            let app = extracted.appendingPathComponent("Covio.app", isDirectory: true)
            try validateExtractedApp(app, candidate: candidate)

            try candidate.manifestData.write(
                to: transaction.appendingPathComponent("manifest.json"),
                options: .atomic
            )
            try candidate.signatureData.write(
                to: transaction.appendingPathComponent("manifest.sig.json"),
                options: .atomic
            )
            try writeTransactionEnvironment(
                transaction: transaction,
                candidate: candidate,
                app: app,
                installed: installed
            )
            try writeInstallPlist(
                label: transactionLabel(transactionId),
                transaction: transaction
            )
            if environment["COVIO_UPDATER_SKIP_LAUNCHD"] != "1" {
                let label = transactionLabel(transactionId)
                _ = runToolResult("/bin/launchctl", arguments: ["bootout", "system/\(label)"])
                try runTool(
                    "/bin/launchctl",
                    arguments: [
                        "bootstrap",
                        "system",
                        transaction.appendingPathComponent("install-update.plist").path,
                    ]
                )
            }
            return .init(
                ok: true,
                state: .installing,
                message: "The verified update is being installed",
                availableVersion: candidate.manifest.clientVersion
            )
        } catch {
            return persistFailure(
                .failed,
                "Update installation failed: \(error.localizedDescription)"
            )
        }
    }

    private func activeInstallResult() -> UpdaterOperationResult? {
        let status = persistedStatus
        guard status.state == .installing else { return nil }
        return .init(
            ok: false,
            state: .installing,
            message: status.message ?? "An update is being installed",
            availableVersion: status.availableVersion
        )
    }

    private func setCandidate(_ value: VerifiedCandidate?) {
        lock.lock()
        candidate = value
        lock.unlock()
    }

    private func currentCandidateOrRestore() throws -> VerifiedCandidate? {
        lock.lock()
        let value = candidate
        lock.unlock()
        if let value { return value }
        guard FileManager.default.fileExists(atPath: paths.candidateManifest.path),
              FileManager.default.fileExists(atPath: paths.candidateSignature.path)
        else {
            return nil
        }
        let manifestData = try Data(contentsOf: paths.candidateManifest)
        let signatureData = try Data(contentsOf: paths.candidateSignature)
        let manifest = try UpdateManifestVerifier.verify(
            manifestData: manifestData,
            signatureData: signatureData,
            trustedKeys: trustedKeys,
            expectations: manifestExpectations()
        )
        let restored = VerifiedCandidate(
            manifest: manifest,
            manifestData: manifestData,
            signatureData: signatureData
        )
        setCandidate(restored)
        return restored
    }

    private func persistCandidate(_ candidate: VerifiedCandidate) throws {
        try prepareRootDirectory(paths.root)
        try candidate.manifestData.write(to: paths.candidateManifest, options: .atomic)
        try candidate.signatureData.write(to: paths.candidateSignature, options: .atomic)
        try secureRootItem(paths.candidateManifest, permissions: 0o600)
        try secureRootItem(paths.candidateSignature, permissions: 0o600)
    }

    private func clearCandidate() throws {
        setCandidate(nil)
        for path in [paths.candidateManifest, paths.candidateSignature] {
            if FileManager.default.fileExists(atPath: path.path) {
                try FileManager.default.removeItem(at: path)
            }
        }
    }

    private func validateExtractedApp(
        _ app: URL,
        candidate: VerifiedCandidate
    ) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: app.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw UpdaterCoordinatorError.missingApp
        }
        try runTool("/usr/bin/codesign", arguments: ["--verify", "--deep", "--strict", app.path])
        try verifyCodeSignature(
            app.appendingPathComponent("Contents/MacOS/CovioHelper"),
            identifier: "com.wyz.covio.helper"
        )
        try verifyCodeSignature(
            app.appendingPathComponent("Contents/MacOS/CovioUpdater"),
            identifier: UpdaterContract.engineIdentifier
        )
        try verifyCodeSignature(
            app.appendingPathComponent("Contents/MacOS/CovioUpdaterLauncher"),
            identifier: UpdaterContract.launcherIdentifier
        )

        let appExecutable = app.appendingPathComponent("Contents/MacOS/Covio")
        let helper = app.appendingPathComponent("Contents/MacOS/CovioHelper")
        let updater = app.appendingPathComponent("Contents/MacOS/CovioUpdater")
        guard Self.sha256File(appExecutable) == candidate.manifest.componentHashes.app,
              Self.sha256File(helper) == candidate.manifest.componentHashes.helper,
              Self.sha256File(updater) == candidate.manifest.componentHashes.updater
        else {
            throw UpdaterCoordinatorError.componentDigestMismatch
        }
        for executable in [appExecutable, helper, updater] {
            let architecture = try runToolOutput(
                "/usr/bin/lipo",
                arguments: ["-archs", executable.path]
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            guard architecture == "arm64" else {
                throw UpdaterCoordinatorError.componentDigestMismatch
            }
        }

        let infoPath = app.appendingPathComponent("Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: infoPath),
              info["CFBundleIdentifier"] as? String == "com.wyz.covio",
              info["CovioReleaseId"] as? String == candidate.manifest.releaseId,
              info["CovioClientVersion"] as? String == candidate.manifest.clientVersion,
              info["CovioProductVersion"] as? String == candidate.manifest.productVersion,
              info["CovioGitCommit"] as? String == candidate.manifest.gitCommit,
              info["CovioReleaseChannel"] as? String == candidate.manifest.channel,
              (info["CFBundleVersion"] as? String).flatMap(Int.init)
                == candidate.manifest.buildNumber,
              (info["CovioHelperProtocolVersion"] as? String).flatMap(Int.init)
                == candidate.manifest.helperProtocolVersion
        else {
            throw UpdaterCoordinatorError.appIdentityMismatch
        }

        let manifestPath = app.appendingPathComponent("Contents/Resources/release-manifest.json")
        let manifestData = try Data(contentsOf: manifestPath)
        guard let bundleManifest = try JSONSerialization.jsonObject(
            with: manifestData
        ) as? [String: Any],
              (bundleManifest["schemaVersion"] as? NSNumber)?.intValue == 2,
              bundleManifest["releaseId"] as? String == candidate.manifest.releaseId,
              bundleManifest["clientVersion"] as? String == candidate.manifest.clientVersion,
              bundleManifest["productVersion"] as? String == candidate.manifest.productVersion,
              (bundleManifest["buildNumber"] as? NSNumber)?.intValue
                == candidate.manifest.buildNumber,
              bundleManifest["gitCommit"] as? String == candidate.manifest.gitCommit,
              (bundleManifest["helperProtocolVersion"] as? NSNumber)?.intValue
                == candidate.manifest.helperProtocolVersion,
              bundleManifest["helperSHA256"] as? String
                == candidate.manifest.componentHashes.helper,
              bundleManifest["channel"] as? String == candidate.manifest.channel
        else {
            throw UpdaterCoordinatorError.appIdentityMismatch
        }
    }

    private func verifyCodeSignature(_ executable: URL, identifier: String) throws {
        try runTool("/usr/bin/codesign", arguments: ["--verify", "--strict", executable.path])
        let output = try runToolOutput(
            "/usr/bin/codesign",
            arguments: ["-d", "--verbose=2", executable.path]
        )
        guard output.contains("Identifier=\(identifier)") else {
            throw UpdaterCoordinatorError.untrustedCodeSignature
        }
    }

    private func loadInstalledUpdaterIdentity() throws -> InstalledUpdaterIdentity {
        let current = try String(contentsOf: paths.currentPointer, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard current == currentReleaseId else {
            throw UpdaterCoordinatorError.installedIdentityMismatch
        }
        let recordURL = paths.root.deletingLastPathComponent()
            .appendingPathComponent("installed-release.json")
        let data = try Data(contentsOf: recordURL)
        guard let record = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              (record["schemaVersion"] as? NSNumber)?.intValue == 2,
              record["releaseId"] as? String == currentReleaseId,
              record["updaterReleaseId"] as? String == currentReleaseId,
              let updaterSHA256 = record["updaterSHA256"] as? String,
              Self.isLowercaseHex(updaterSHA256),
              let launcherSHA256 = record["updaterLauncherSHA256"] as? String,
              Self.isLowercaseHex(launcherSHA256)
        else {
            throw UpdaterCoordinatorError.installedIdentityMismatch
        }
        let engine = try paths.engine(for: currentReleaseId)
        guard Self.sha256File(engine) == updaterSHA256,
              Self.sha256File(paths.launcher) == launcherSHA256
        else {
            throw UpdaterCoordinatorError.installedIdentityMismatch
        }
        try verifyRootOwnedExecutable(paths.launcher)
        try verifyCodeSignature(paths.launcher, identifier: UpdaterContract.launcherIdentifier)
        try verifyRootOwnedExecutable(engine)
        try verifyCodeSignature(engine, identifier: UpdaterContract.engineIdentifier)
        return InstalledUpdaterIdentity(
            releaseId: current,
            updaterSHA256: updaterSHA256,
            launcherSHA256: launcherSHA256
        )
    }

    private func verifyRootOwnedExecutable(_ url: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let mode = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
        guard (attributes[.type] as? FileAttributeType) == .typeRegular,
              FileManager.default.isExecutableFile(atPath: url.path),
              (attributes[.ownerAccountID] as? NSNumber)?.intValue == 0,
              (attributes[.groupOwnerAccountID] as? NSNumber)?.intValue == 0,
              mode & 0o022 == 0
        else {
            throw UpdaterCoordinatorError.untrustedInstalledUpdater
        }
    }

    private func writeTransactionEnvironment(
        transaction: URL,
        candidate: VerifiedCandidate,
        app: URL,
        installed: InstalledUpdaterIdentity
    ) throws {
        let fields: [(String, String)] = [
            ("TRANSACTION_ID", transaction.lastPathComponent),
            ("UPDATE_MODE", "automatic"),
            ("COVIO_TX_REPORT_SOURCE", "updater"),
            ("EXPECTED_RELEASE_ID", candidate.manifest.releaseId),
            ("EXPECTED_CLIENT_VERSION", candidate.manifest.clientVersion),
            ("EXPECTED_PRODUCT_VERSION", candidate.manifest.productVersion),
            ("EXPECTED_BUILD_NUMBER", String(candidate.manifest.buildNumber)),
            ("EXPECTED_COMMIT", candidate.manifest.gitCommit),
            ("EXPECTED_PROTOCOL_VERSION", String(candidate.manifest.helperProtocolVersion)),
            ("EXPECTED_HELPER_SHA256", candidate.manifest.componentHashes.helper),
            ("EXPECTED_UPDATER_SHA256", candidate.manifest.componentHashes.updater),
            ("EXPECTED_UPDATER_LAUNCHER_SHA256", installed.launcherSHA256),
            ("EXPECTED_PREVIOUS_RELEASE_ID", installed.releaseId),
            ("EXPECTED_CHANNEL", candidate.manifest.channel),
            ("STAGED_APP_PATH", app.path),
        ]
        let content = fields.map { "\($0.0)='\($0.1)'" }.joined(separator: "\n") + "\n"
        let environmentURL = transaction.appendingPathComponent("transaction.env")
        try Data(content.utf8).write(to: environmentURL, options: .atomic)
        try secureRootItem(environmentURL, permissions: 0o600)
    }

    private func writeInstallPlist(label: String, transaction: URL) throws {
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [paths.installUpdateScript.path, transaction.path],
            "RunAtLoad": true,
            "KeepAlive": false,
            "ProcessType": "Background",
            "ThrottleInterval": 5,
            "StandardOutPath": transaction.appendingPathComponent("install.out").path,
            "StandardErrorPath": transaction.appendingPathComponent("install.err").path,
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        let output = transaction.appendingPathComponent("install-update.plist")
        try data.write(to: output, options: .atomic)
        try secureRootItem(output, permissions: 0o600)
    }

    private func validateArchiveLayout(_ extracted: URL) throws {
        let entries = try FileManager.default.contentsOfDirectory(
            at: extracted,
            includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        guard entries.count == 1,
              entries[0].lastPathComponent == "Covio.app"
        else {
            throw UpdaterCoordinatorError.invalidArchiveLayout
        }
        let hidden = try FileManager.default.contentsOfDirectory(atPath: extracted.path)
            .filter { $0.hasPrefix(".") }
        guard hidden.isEmpty else {
            throw UpdaterCoordinatorError.invalidArchiveLayout
        }
    }

    private func validateNoEscapingSymlinks(_ root: URL) throws {
        let keys: [URLResourceKey] = [.isSymbolicLinkKey, .isDirectoryKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            throw UpdaterCoordinatorError.invalidArchiveLayout
        }
        let rootPath = root.resolvingSymlinksInPath().standardizedFileURL.path
        for case let item as URL in enumerator {
            let values = try item.resourceValues(forKeys: Set(keys))
            guard values.isSymbolicLink == true else { continue }
            let resolved = item.resolvingSymlinksInPath().standardizedFileURL.path
            guard resolved == rootPath || resolved.hasPrefix(rootPath + "/") else {
                throw UpdaterCoordinatorError.unsafeArchiveLink
            }
        }
    }

    private func downloadSmall(_ url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        try validateHTTP(response)
        guard data.count <= 1_048_576 else {
            throw UpdaterCoordinatorError.downloadTooLarge
        }
        return data
    }

    private func downloadArchive(
        _ url: URL,
        to destination: URL,
        expectedSize: Int,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let delegate = UpdaterDownloadProgressDelegate(
            expectedBytes: Int64(expectedSize),
            progress: progress
        )
        let (temporary, response) = try await session.download(
            for: URLRequest(url: url),
            delegate: delegate
        )
        try validateHTTP(response)
        let size = (try? FileManager.default.attributesOfItem(atPath: temporary.path)[.size]
            as? NSNumber)?.intValue ?? 0
        guard size > 0,
              size <= UpdateManifestVerifier.maximumArchiveBytes,
              size == expectedSize
        else {
            throw UpdaterCoordinatorError.invalidArchiveSize
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporary, to: destination)
        try secureRootItem(destination, permissions: 0o600)
    }

    private func validateHTTP(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let url = http.url,
              Self.allowedAssetHost(url.host)
        else {
            throw UpdaterCoordinatorError.invalidHTTPResponse
        }
    }

    private func persist(
        _ state: UpdaterEngineState,
        availableVersion: String?,
        target: String?,
        message: String? = nil,
        downloadProgress: Double? = nil
    ) throws {
        try writeState(
            state,
            availableVersion: availableVersion,
            target: target,
            message: message,
            lastCheckAt: ISO8601DateFormatter().string(from: Date()),
            downloadProgress: downloadProgress
        )
    }

    private func persistDownloadProgress(
        _ progress: Double,
        clientVersion: String,
        releaseId: String
    ) throws {
        try writeState(
            .downloading,
            availableVersion: clientVersion,
            target: releaseId,
            message: nil,
            lastCheckAt: persistedStatus.lastCheckAt
                ?? ISO8601DateFormatter().string(from: Date()),
            downloadProgress: progress
        )
    }

    private func writeState(
        _ state: UpdaterEngineState,
        availableVersion: String?,
        target: String?,
        message: String?,
        lastCheckAt: String,
        downloadProgress: Double? = nil
    ) throws {
        let record = UpdaterPersistedState(
            schemaVersion: 1,
            state: state,
            lastCheckAt: lastCheckAt,
            availableVersion: availableVersion,
            targetReleaseId: target,
            message: message,
            downloadProgress: downloadProgress
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var data = try encoder.encode(record)
        data.append(0x0A)
        try prepareRootDirectory(paths.root)
        try data.write(to: paths.updateState, options: .atomic)
        try secureRootItem(paths.updateState, permissions: 0o644)
    }

    private func persistFailure(
        _ state: UpdaterEngineState,
        _ message: String
    ) -> UpdaterOperationResult {
        try? persist(state, availableVersion: nil, target: nil, message: message)
        return .init(
            ok: false,
            state: state,
            message: message,
            availableVersion: nil
        )
    }

    private func reconcileCompletedTransaction() {
        guard let data = try? Data(contentsOf: paths.updateResult),
              let result = try? JSONDecoder().decode(UpdaterTransactionResult.self, from: data),
              result.schemaVersion == 1
        else {
            return
        }
        if let transactionId = result.transactionId {
            _ = runToolResult(
                "/bin/launchctl",
                arguments: [
                    "bootout",
                    "system/\(transactionLabel(transactionId))",
                ]
            )
        }
        let state: UpdaterEngineState = result.state == .idle ? .idle : .failed
        try? writeState(
            state,
            availableVersion: nil,
            target: result.targetReleaseId,
            message: result.rollbackReason ?? result.result,
            lastCheckAt: result.recordedAt,
            downloadProgress: nil
        )
        if state == .idle {
            try? clearCandidate()
            if let transactionId = result.transactionId {
                try? archiveSuccessfulTransaction(transactionId)
            }
        } else if let transactionId = result.transactionId {
            let transaction = paths.transactions.appendingPathComponent(transactionId)
            try? data.write(
                to: transaction.appendingPathComponent("update-result.json"),
                options: .atomic
            )
        }
        try? FileManager.default.removeItem(at: paths.updateResult)
    }

    private func installTransactionMode(at transaction: URL) -> String? {
        let environmentPath = transaction.appendingPathComponent("transaction.env")
        guard let contents = try? String(contentsOf: environmentPath, encoding: .utf8) else {
            return nil
        }
        for line in contents.split(whereSeparator: \.isNewline) {
            let prefix = "UPDATE_MODE="
            guard line.hasPrefix(prefix) else { continue }
            let value = String(line.dropFirst(prefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return value.trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
        }
        return nil
    }

    private func recoverInterruptedInstallIfNeeded() {
        guard FileManager.default.fileExists(atPath: paths.currentInstallTransaction.path),
              !FileManager.default.fileExists(atPath: paths.updateResult.path)
        else {
            return
        }
        let transactionPath = (try? String(
            contentsOf: paths.currentInstallTransaction,
            encoding: .utf8
        ))?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let transactionPath,
              installTransactionMode(at: URL(fileURLWithPath: transactionPath)) == "automatic"
        else {
            return
        }
        let transactionId = URL(fileURLWithPath: transactionPath).lastPathComponent
        if runToolResult(
            "/bin/launchctl",
            arguments: ["print", "system/\(transactionLabel(transactionId))"]
        ) {
            return
        }
        guard FileManager.default.isExecutableFile(atPath: paths.recoverInstallScript.path) else {
            try? persist(
                .repairRequired,
                availableVersion: nil,
                target: nil,
                message: "Interrupted update requires the repair package"
            )
            return
        }
        if runToolResult("/bin/sh", arguments: [paths.recoverInstallScript.path]) {
            try? persist(
                .failed,
                availableVersion: nil,
                target: nil,
                message: "Interrupted update rolled back to the previous release"
            )
        } else {
            try? persist(
                .repairRequired,
                availableVersion: nil,
                target: nil,
                message: "Interrupted update could not be rolled back"
            )
        }
    }

    private func archiveSuccessfulTransaction(_ transactionId: String) throws {
        let transaction = paths.transactions.appendingPathComponent(transactionId)
        guard FileManager.default.fileExists(atPath: transaction.path) else { return }
        let archive = paths.transactions.appendingPathComponent(
            "\(transactionId).success-\(Int(Date().timeIntervalSince1970))"
        )
        try FileManager.default.moveItem(at: transaction, to: archive)
        let staging = archive.appendingPathComponent("staging")
        if FileManager.default.fileExists(atPath: staging.path) {
            try FileManager.default.removeItem(at: staging)
        }
        let archiveFile = archive.appendingPathComponent(
            "CovioUpdate-\(currentReleaseId.split(separator: "-g")[0]).zip"
        )
        if FileManager.default.fileExists(atPath: archiveFile.path) {
            try FileManager.default.removeItem(at: archiveFile)
        }
    }

    private func removeResultIfPresent() throws {
        if FileManager.default.fileExists(atPath: paths.updateResult.path) {
            try FileManager.default.removeItem(at: paths.updateResult)
        }
    }

    private func prepareRootDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        if environment["COVIO_UPDATER_TEST_MODE"] != "1" {
            guard getuid() == 0 else {
                throw UpdaterCoordinatorError.requiresRoot
            }
            try secureRootItem(url, permissions: 0o755)
        }
    }

    private func secureRootItem(_ url: URL, permissions: Int) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: permissions],
            ofItemAtPath: url.path
        )
        if environment["COVIO_UPDATER_TEST_MODE"] != "1" {
            try FileManager.default.setAttributes(
                [
                    .ownerAccountID: 0,
                    .groupOwnerAccountID: 0,
                ],
                ofItemAtPath: url.path
            )
        }
    }

    private func manifestExpectations() -> UpdateManifestExpectations {
        UpdateManifestExpectations(
            currentVersion: GeneratedReleaseIdentity.clientVersion,
            currentBuildNumber: GeneratedReleaseIdentity.buildNumber,
            channel: GeneratedReleaseIdentity.channel,
            helperProtocolVersion: GeneratedReleaseIdentity.helperProtocolVersion,
            updaterProtocolVersion: UpdaterContract.protocolVersion,
            macOSVersion: Self.macOSVersion
        )
    }

    private func transactionLabel(_ transactionId: String) -> String {
        "com.wyz.covio.updater.transaction.\(transactionId)"
    }

    @discardableResult
    private func runToolResult(_ executable: String, arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func runTool(_ executable: String, arguments: [String]) throws {
        guard runToolResult(executable, arguments: arguments) else {
            throw UpdaterCoordinatorError.toolFailed(
                URL(fileURLWithPath: executable).lastPathComponent
            )
        }
    }

    private func runToolOutput(_ executable: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdaterCoordinatorError.toolFailed(
                URL(fileURLWithPath: executable).lastPathComponent
            )
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func allowedAssetHost(_ host: String?) -> Bool {
        host == "github.com" || host == "release-assets.githubusercontent.com"
    }

    private static var macOSVersion: String {
        let value = ProcessInfo.processInfo.operatingSystemVersion
        return "\(value.majorVersion).\(value.minorVersion).\(value.patchVersion)"
    }

    private static func isLowercaseHex(_ value: String) -> Bool {
        value.count == 64 && value.unicodeScalars.allSatisfy {
            ($0.value >= 48 && $0.value <= 57) || ($0.value >= 97 && $0.value <= 102)
        }
    }

    private static func sha256File(_ url: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try? handle.read(upToCount: 1024 * 1024), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

private final class UpdaterDownloadProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let expectedBytes: Int64
    private let progress: @Sendable (Double) -> Void
    private let lock = NSLock()
    private var lastPercent = -1

    init(
        expectedBytes: Int64,
        progress: @escaping @Sendable (Double) -> Void
    ) {
        self.expectedBytes = expectedBytes
        self.progress = progress
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let total = totalBytesExpectedToWrite > 0
            ? totalBytesExpectedToWrite
            : expectedBytes
        guard total > 0 else { return }
        let fraction = min(max(Double(totalBytesWritten) / Double(total), 0), 1)
        let percent = Int((fraction * 100).rounded(.down))
        lock.lock()
        let changed = percent != lastPercent
        if changed {
            lastPercent = percent
        }
        lock.unlock()
        guard changed else { return }
        progress(fraction)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {}
}

private final class CallbackBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var callback: ((Value) -> Void)?

    init(_ callback: @escaping (Value) -> Void) {
        self.callback = callback
    }

    func call(_ value: Value) {
        lock.lock()
        let callback = callback
        self.callback = nil
        lock.unlock()
        callback?(value)
    }
}

enum UpdaterCoordinatorError: Error, LocalizedError {
    case noVerifiedRelease
    case downloadTooLarge
    case archiveDigestMismatch
    case componentDigestMismatch
    case invalidArchiveSize
    case invalidHTTPResponse
    case missingApp
    case appIdentityMismatch
    case releaseMetadataMismatch
    case invalidArchiveLayout
    case unsafeArchiveLink
    case installedIdentityMismatch
    case untrustedInstalledUpdater
    case untrustedCodeSignature
    case requiresRoot
    case toolFailed(String)

    var errorDescription: String? {
        switch self {
        case .noVerifiedRelease: "No verified update is available"
        case .downloadTooLarge: "Update metadata is too large"
        case .archiveDigestMismatch: "Update archive digest does not match"
        case .componentDigestMismatch: "Update component digest does not match"
        case .invalidArchiveSize: "Update archive size is invalid"
        case .invalidHTTPResponse: "Update download response is invalid"
        case .missingApp: "Update archive has no Covio.app"
        case .appIdentityMismatch: "Update app identity does not match its manifest"
        case .releaseMetadataMismatch: "Release asset metadata does not match its manifest"
        case .invalidArchiveLayout: "Update archive layout is invalid"
        case .unsafeArchiveLink: "Update archive contains an unsafe symbolic link"
        case .installedIdentityMismatch: "Installed updater identity does not match its record"
        case .untrustedInstalledUpdater: "Installed updater is not root-owned or executable"
        case .untrustedCodeSignature: "Update component has an untrusted code signature"
        case .requiresRoot: "The updater requires root"
        case .toolFailed(let name): "Update tool failed: \(name)"
        }
    }
}
