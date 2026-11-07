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
    // The REST API is limited per public IP. The Atom feed is not.
    private static let endpoint = URL(
        string: "https://github.com/\(UpdaterContract.repository)/releases.atom"
    )!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func releases() async throws -> [UpdaterReleaseCandidate] {
        var request = URLRequest(url: Self.endpoint)
        request.timeoutInterval = 15
        request.setValue("application/atom+xml", forHTTPHeaderField: "Accept")
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
        let parser = AtomReleaseParser()
        let xml = XMLParser(data: data)
        xml.delegate = parser
        guard xml.parse() else {
            throw UpdaterFeedError.invalidResponse
        }
        let candidates = parser.entries.compactMap { entry -> UpdaterReleaseCandidate? in
            guard let tag = entry.tag,
                  let version = clientVersion(fromInternalTag: tag),
                  let publishedAt = entry.updatedAt,
                  ISO8601DateFormatter().date(from: publishedAt) != nil,
                  let manifestURL = assetURL(
                      tag: tag,
                      name: "CovioUpdate-\(version).json"
                  ),
                  let signatureURL = assetURL(
                      tag: tag,
                      name: "CovioUpdate-\(version).sig.json"
                  ),
                  let archiveURL = assetURL(
                      tag: tag,
                      name: "CovioUpdate-\(version).zip"
                  )
            else {
                return nil
            }
            return UpdaterReleaseCandidate(
                tagName: tag,
                clientVersion: version,
                manifestURL: manifestURL,
                signatureURL: signatureURL,
                archiveURL: archiveURL,
                publishedAt: publishedAt
            )
        }
        return candidates.sorted {
            let left = ReleaseVersion($0.clientVersion)!
            let right = ReleaseVersion($1.clientVersion)!
            return left > right
        }
    }

    private static func assetURL(tag: String, name: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "github.com"
        components.path = "/\(UpdaterContract.repository)/releases/download/\(tag)/\(name)"
        return components.url
    }

    static func clientVersion(fromInternalTag tag: String) -> String? {
        guard tag.hasPrefix("v"),
              let version = ReleaseVersion(String(tag.dropFirst())),
              version.prerelease.count == 2,
              version.prerelease[0] == "internal",
              let build = Int(version.prerelease[1]),
              version.isInternalBuild(build)
        else {
            return nil
        }
        return version.description
    }
}

private final class AtomReleaseParser: NSObject, XMLParserDelegate {
    struct Entry {
        var tag: String?
        var updatedAt: String?
    }

    private(set) var entries: [Entry] = []
    private var currentEntry: Entry?
    private var currentText = ""
    private var isReadingUpdatedAt = false

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch elementName {
        case "entry":
            currentEntry = Entry()
        case "updated":
            currentText = ""
            isReadingUpdatedAt = currentEntry != nil
        case "link":
            guard currentEntry != nil,
                  attributeDict["rel"] == "alternate",
                  attributeDict["type"] == "text/html",
                  let href = attributeDict["href"]
            else {
                return
            }
            currentEntry?.tag = UpdaterContract.releaseTag(from: href)
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard isReadingUpdatedAt else { return }
        currentText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch elementName {
        case "updated":
            if isReadingUpdatedAt {
                currentEntry?.updatedAt = currentText.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
            }
            currentText = ""
            isReadingUpdatedAt = false
        case "entry":
            if let currentEntry {
                entries.append(currentEntry)
            }
            currentEntry = nil
        default:
            break
        }
    }

}

enum UpdaterFeedError: Error, Equatable, LocalizedError {
    case httpFailure
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .httpFailure: "GitHub release feed request failed"
        case .invalidResponse: "GitHub release feed is invalid"
        }
    }
}
