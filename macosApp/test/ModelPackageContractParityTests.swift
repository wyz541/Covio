import Foundation
import XCTest
@testable import Covio

/// 模型包合同的共享语料，在 Swift 侧再跑一遍。
///
/// Kotlin 侧钉住规则。这里钉住 framework 导出形状与 Swift Codable 镜像。
final class ModelPackageContractParityTests: XCTestCase {
    private static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private static let fixture = repositoryRoot
        .appendingPathComponent("kmpDomain/test/fixtures/model-package-vectors.json")

    func testManifestValidationUsesTheSharedKotlinContract() throws {
        let document = try Self.document()
        let manifest = try XCTUnwrap(document["manifest"] as? [String: Any])
        let expectation = try XCTUnwrap(document["expectation"] as? [String: Any])
        let manifestData = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])

        let validation = ModelPackageContract.shared.validateManifestText(
            manifestText: String(decoding: manifestData, as: UTF8.self),
            expectedTier: try XCTUnwrap(expectation["tier"] as? String),
            expectedModelId: try XCTUnwrap(expectation["modelID"] as? String),
            expectedRevision: try XCTUnwrap(expectation["revision"] as? String),
            expectedRuntimeDirectory: try XCTUnwrap(expectation["runtimeDirectory"] as? String),
            expectedTotalBytes: Int64(try XCTUnwrap(expectation["totalBytes"] as? Int)),
            expectedLicense: try XCTUnwrap(expectation["license"] as? String)
        )

        XCTAssertTrue(validation.valid, validation.detail)
        let decoded = try JSONDecoder().decode(LocalModelPackageManifest.self, from: manifestData)
        XCTAssertEqual(decoded.modelID, expectation["modelID"] as? String)
        XCTAssertEqual(decoded.revision, expectation["revision"] as? String)
        XCTAssertEqual(decoded.totalBytes, Int64(try XCTUnwrap(expectation["totalBytes"] as? Int)))
    }

    func testEveryShippedManifestPassesTheSharedContract() throws {
        for tier in LocalModelTier.allCases {
            let expectation = try XCTUnwrap(LocalModelPackageCatalog.expectations[tier])
            let manifestURL = Self.repositoryRoot
                .appendingPathComponent("macosApp/src/AutoNaming")
                .appendingPathComponent(Self.manifestFileName(for: tier))
            let manifestData = try Data(contentsOf: manifestURL)
            let validation = ModelPackageContract.shared.validateManifestText(
                manifestText: String(decoding: manifestData, as: UTF8.self),
                expectedTier: tier.rawValue,
                expectedModelId: expectation.modelID,
                expectedRevision: expectation.revision,
                expectedRuntimeDirectory: "Models/\(tier.runtimeDirectoryName)",
                expectedTotalBytes: expectation.totalBytes,
                expectedLicense: expectation.license
            )

            XCTAssertTrue(validation.valid, "\(tier.rawValue): \(validation.detail)")
        }
    }

    func testStatusAndRegistryKeepTheSharedJSONShape() throws {
        let document = try Self.document()
        let statusObject = try XCTUnwrap(document["status"] as? [String: Any])
        let registryObject = try XCTUnwrap(document["registry"] as? [String: Any])
        let statusData = try JSONSerialization.data(withJSONObject: statusObject, options: [.sortedKeys])
        let registryData = try JSONSerialization.data(withJSONObject: registryObject, options: [.sortedKeys])

        let sharedStatus = try XCTUnwrap(
            ModelPackageContract.shared.decodeStatus(text: String(decoding: statusData, as: UTF8.self))
        )
        let swiftStatus = try JSONDecoder().decode(LocalModelDownloadStatus.self, from: statusData)
        XCTAssertEqual(sharedStatus.modelId, swiftStatus.modelID)
        XCTAssertEqual(sharedStatus.phase.wire, swiftStatus.phase.rawValue)

        let sharedRegistry = try XCTUnwrap(
            ModelPackageContract.shared.decodeRegistry(text: String(decoding: registryData, as: UTF8.self))
        )
        let swiftRegistry = try JSONDecoder().decode(LocalModelPackageRegistry.self, from: registryData)
        XCTAssertEqual(sharedRegistry.selectedTier, swiftRegistry.selectedTier?.rawValue)
        XCTAssertEqual(sharedRegistry.packages.first?.modelId, swiftRegistry.packages.first?.modelID)
    }

    private static func document() throws -> [String: Any] {
        let data = try Data(contentsOf: fixture)
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any],
            "The model package fixture is not a JSON object: \(fixture.path)"
        )
    }

    private static func manifestFileName(for tier: LocalModelTier) -> String {
        switch tier {
        case .compact2B: "FileNamingModelManifest.json"
        case .balanced4B: "FileNamingModelManifest-balanced4B.json"
        case .highQuality8B: "FileNamingModelManifest-highQuality8B.json"
        case .heavy30BA3B: "FileNamingModelManifest-heavy30BA3B.json"
        }
    }
}
