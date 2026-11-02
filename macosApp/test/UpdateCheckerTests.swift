import XCTest
import kmpDomain
@testable import Covio

/// `GithubUpdateChecker` 的解析与状态判定。
///
/// 这是唯一一处直连 GitHub 的代码。解析器是纯函数，测试直接喂 HTML 字符串。
/// 断言对应 M6 删掉的 `GithubUpdateCheckerTest.kt`。
///
/// 网络那两条走注入的 `URLProtocol`：`init` 收一个 `URLSession`，
/// 正是为了让这几条不用真发请求。
final class UpdateCheckerTests: XCTestCase {
    private let releasePage = """
    <html>
    <body>
    <a href="/wyz541/kmp-Covio/releases/tag/v0.0.1.6">Covio 0.0.1.6</a>
    <a href="/wyz541/kmp-Covio/releases/tag/v0.0.1.5">Covio 0.0.1.5</a>
    <a href="/wyz541/kmp-Covio/releases/tag/v0.0.1.7-internal">Internal</a>
    <a href="/wyz541/kmp-Covio/releases/tag/v0.6.0-internal.15">Legacy internal</a>
    </body>
    </html>
    """

    func testInternalBuildPrefersANewerInternalRelease() {
        let info = GithubUpdateChecker.parseRelease(releasePage, includeInternal: true)
        XCTAssertEqual(info?.version, "0.0.1.7")
        XCTAssertEqual(info?.title, "Covio 0.0.1.7")
        XCTAssertEqual(
            info?.releaseUrl,
            "https://github.com/wyz541/kmp-Covio/releases/tag/v0.0.1.7-internal"
        )
    }

    func testPublicBuildIgnoresInternalReleases() {
        let info = GithubUpdateChecker.parseRelease(releasePage, includeInternal: false)
        XCTAssertEqual(info?.version, "0.0.1.6")
        XCTAssertEqual(
            info?.releaseUrl,
            "https://github.com/wyz541/kmp-Covio/releases/tag/v0.0.1.6"
        )
    }

    /// 旧语义版本标签不进入更新提示。
    func testLegacySemanticTagsAreIgnored() {
        let body = """
        <a href="https://github.com/wyz541/kmp-Covio/releases/tag/v0.0.1.9">stable</a>
        <a href="/wyz541/kmp-Covio/releases/tag/v0.1.0.0-internal">candidate</a>
        <a href="/wyz541/kmp-Covio/releases/tag/v0.6.0-internal.15">legacy</a>
        """
        let info = GithubUpdateChecker.parseRelease(body, includeInternal: true)
        XCTAssertEqual(info?.version, "0.1.0.0")
        XCTAssertEqual(
            info?.releaseUrl,
            "https://github.com/wyz541/kmp-Covio/releases/tag/v0.1.0.0-internal"
        )
    }

    func testFourPartVersionsUseDecimalOrder() {
        let body = """
        <a href="/wyz541/kmp-Covio/releases/tag/v0.0.9.9">old</a>
        <a href="/wyz541/kmp-Covio/releases/tag/v0.1.0.0">new</a>
        """
        XCTAssertEqual(GithubUpdateChecker.parseRelease(body)?.version, "0.1.0.0")
    }

    /// 相对路径要补成绝对地址，否则界面上的「打开」按钮没有落点。
    func testRelativeHrefBecomesAnAbsoluteURL() {
        let body = #"<a href="/wyz541/kmp-Covio/releases/tag/v0.0.1.6">x</a>"#
        let info = GithubUpdateChecker.parseRelease(body)
        XCTAssertEqual(
            info?.releaseUrl,
            "https://github.com/wyz541/kmp-Covio/releases/tag/v0.0.1.6"
        )
    }

    func testMalformedBodyReturnsNil() {
        XCTAssertNil(GithubUpdateChecker.parseRelease("not a release page"))
        XCTAssertNil(GithubUpdateChecker.parseRelease(""))
        XCTAssertNil(
            GithubUpdateChecker.parseRelease(#"<a href="/releases/tag/not-a-version">bad</a>"#)
        )
    }

    func testOnlyInternalReleasesAreIgnoredByPublicBuilds() {
        let body = """
        <a href="/wyz541/kmp-Covio/releases/tag/v0.0.2.0-internal">internal</a>
        <a href="/wyz541/kmp-Covio/releases/tag/v0.6.0-internal.15">legacy</a>
        """
        XCTAssertNil(GithubUpdateChecker.parseRelease(body, includeInternal: false))
        XCTAssertEqual(
            GithubUpdateChecker.parseRelease(body, includeInternal: true)?.version,
            "0.0.2.0"
        )
    }

    /// 限流时 GitHub 返回 403。这一条不能当成「已是最新」。
    func testNonSuccessStatusReturnsNil() {
        let checker = GithubUpdateChecker(session: session(status: 403, body: releasePage))
        XCTAssertNil(checker.latestRelease())
    }

    func testSuccessStatusParsesTheBody() {
        let checker = GithubUpdateChecker(session: session(status: 200, body: releasePage))
        XCTAssertEqual(checker.latestRelease()?.version, "0.0.1.7")
    }

    /// 一个只应答固定状态码与固定正文的会话。
    private func session(status: Int, body: String) -> URLSession {
        UpdateCheckerURLProtocol.status = status
        UpdateCheckerURLProtocol.body = body
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UpdateCheckerURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

/// 拦下请求，回一份写死的应答。
private final class UpdateCheckerURLProtocol: URLProtocol {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var body = ""

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/html"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
