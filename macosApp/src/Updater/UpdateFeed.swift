import Foundation

struct UpdaterReleaseCandidate: Equatable, Sendable {
    let tagName: String
    let clientVersion: String
    let manifestURL: URL
    let signatureURL: URL
    let archiveURL: URL
    let publishedAt: String

    var archiveName: String { archiveURL.lastPathComponent }
}

protocol UpdaterFeedProviding: Sendable {
    func releases() async throws -> [UpdaterReleaseCandidate]
}

final class GithubUpdaterFeed: UpdaterFeedProviding, @unchecked Sendable {
    private static let endpoint = URL(
        string: "https://api.github.com/repos/wyz541/kmp-Covio/releases?per_page=30"
    )!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func releases() async throws -> [UpdaterReleaseCandidate] {
        var request = URLRequest(url: Self.endpoint)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("CovioUpdater/1", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode)
        else {
            throw UpdaterFeedError.httpFailure
        }
        return try Self.parseReleases(data)
    }

    static func parseReleases(_ data: Data) throws -> [UpdaterReleaseCandidate] {
        guard let releases = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw UpdaterFeedError.invalidResponse
        }
        var candidates: [UpdaterReleaseCandidate] = []
        for release in releases {
            guard release["draft"] as? Bool == false,
                  release["prerelease"] as? Bool == true,
                  let tag = release["tag_name"] as? String,
                  let version = clientVersion(fromInternalTag: tag),
                  let publishedAt = release["published_at"] as? String,
                  ISO8601DateFormatter().date(from: publishedAt) != nil,
                  let assets = release["assets"] as? [[String: Any]]
            else {
                continue
            }
            let manifestName = "CovioUpdate-\(version).json"
            let signatureName = "CovioUpdate-\(version).sig.json"
            let archiveName = "CovioUpdate-\(version).zip"
            var urls: [String: URL] = [:]
            var duplicate = false
            for asset in assets {
                guard let name = asset["name"] as? String,
                      [manifestName, signatureName, archiveName].contains(name),
                      let rawURL = asset["browser_download_url"] as? String,
                      let url = URL(string: rawURL),
                      trustedAssetURL(url, tag: tag, assetName: name)
                else {
                    continue
                }
                if urls[name] != nil {
                    duplicate = true
                    break
                }
                urls[name] = url
            }
            guard !duplicate,
                  let manifestURL = urls[manifestName],
                  let signatureURL = urls[signatureName],
                  let archiveURL = urls[archiveName]
            else {
                continue
            }
            candidates.append(
                UpdaterReleaseCandidate(
                    tagName: tag,
                    clientVersion: version,
                    manifestURL: manifestURL,
                    signatureURL: signatureURL,
                    archiveURL: archiveURL,
                    publishedAt: publishedAt
                )
            )
        }
        return candidates.sorted {
            (clientVersionRank($0.clientVersion) ?? 0)
                > (clientVersionRank($1.clientVersion) ?? 0)
        }
    }

    private static func trustedAssetURL(
        _ url: URL,
        tag: String,
        assetName: String
    ) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "https",
              components.host == "github.com",
              components.user == nil,
              components.password == nil,
              components.port == nil,
              components.query == nil,
              components.fragment == nil
        else {
            return false
        }
        let expectedPath = "/wyz541/kmp-Covio/releases/download/\(tag)/\(assetName)"
        return components.percentEncodedPath == expectedPath
    }


    static func clientVersion(fromInternalTag tag: String) -> String? {
        let suffix = "-internal"
        guard tag.hasPrefix("v"), tag.hasSuffix(suffix) else { return nil }
        let version = String(tag.dropFirst().dropLast(suffix.count))
        return clientVersionRank(version) == nil ? nil : version
    }

    static func clientVersionRank(_ value: String) -> Int? {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        let numbers = parts.compactMap { part in
            part.count == 1 ? Int(part) : nil
        }
        guard numbers.count == 4 else { return nil }
        return numbers.reduce(0) { $0 * 10 + $1 }
    }
}

enum UpdaterFeedError: Error, Equatable, LocalizedError {
    case httpFailure
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .httpFailure: "GitHub release request failed"
        case .invalidResponse: "GitHub release response is invalid"
        }
    }
}
