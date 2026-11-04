import SwiftUI
import CryptoKit

// Offline simulator harness: the production account implementation is used,
// while every network request, browser callback and credential write is mocked.
// Never compile this target as part of the user-facing application.
private struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

private func check(_ condition: @autoclosure () -> Bool, _ description: String) throws {
    if !condition() { throw TestFailure(description: description) }
}

private struct Reply {
    let status: Int
    let json: String
    var delay: TimeInterval = 0
    var redirect: URL? = nil
    var error: Error? = nil
}

private final class MockURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var callback: ((URLRequest) -> Reply)?
    private static var captured: [URLRequest] = []

    static func configure(_ handler: @escaping (URLRequest) -> Reply) {
        lock.lock(); defer { lock.unlock() }
        callback = handler
        captured = []
    }
    static func requests() -> [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return captured
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.captured.append(request)
        let handler = Self.callback
        Self.lock.unlock()
        // No real traffic is permitted, even when a test forgets a handler.
        let reply = handler?(request) ?? Reply(status: 599, json: "{}")
        if reply.delay > 0 { Thread.sleep(forTimeInterval: reply.delay) }
        if let error = reply.error { client?.urlProtocol(self, didFailWithError: error); return }
        var headers = ["Content-Type": "application/json"]
        if let target = reply.redirect { headers["Location"] = target.absoluteString }
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: nil, headerFields: headers) else { return }
        if let target = reply.redirect {
            var redirected = request
            redirected.url = target
            client?.urlProtocol(self, wasRedirectedTo: redirected, redirectResponse: response)
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
private final class TestBed {
    enum CallbackMode: Equatable { case good, slowGood, wrongState, wrongScheme, duplicateState, duplicateCode, cancelled }
    var mode = CallbackMode.good
    var stored: Data?
    var challenge: String?
    var tokenRequests: [URLRequest] = []
    var now = Date()
    let freshCache = UserDefaults(suiteName: "FocusFreshTest-" + UUID().uuidString)!
    let client = "12345-test.apps.googleusercontent.com"
    let oauthScope = "https://www.googleapis.com/auth/youtube.readonly"

    func makeAccount() -> FocusYouTubeAccount {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let hooks = FocusAccountTestHooks(
            clientID: client,
            configuration: configuration,
            authenticate: { [unowned self] url, scheme in
                let request = URLComponents(url: url, resolvingAgainstBaseURL: false)!
                let items = request.queryItems ?? []
                self.challenge = items.first { $0.name == "code_challenge" }?.value
                guard items.first(where: { $0.name == "code_challenge_method" })?.value == "S256",
                      let state = items.first(where: { $0.name == "state" })?.value else {
                    throw TestFailure(description: "Missing state or PKCE challenge")
                }
                if self.mode == .cancelled { throw TestFailure(description: "User cancelled") }
                if self.mode == .slowGood { try await Task.sleep(nanoseconds: 200_000_000) }
                var callback = URLComponents(string: (self.mode == .wrongScheme ? "other.scheme" : scheme) + ":/oauth2redirect")!
                callback.queryItems = [.init(name: "state", value: self.mode == .wrongState ? "wrong" : state), .init(name: "code", value: "a+b/=")]
                if self.mode == .duplicateState { callback.queryItems?.append(.init(name: "state", value: state)) }
                if self.mode == .duplicateCode { callback.queryItems?.append(.init(name: "code", value: "second")) }
                return callback.url!
            },
            observeTokenRequest: { [unowned self] in self.tokenRequests.append($0) },
            now: { [unowned self] in self.now },
            freshCache: freshCache,
            read: { [unowned self] in self.stored },
            write: { [unowned self] in self.stored = $0 },
            delete: { [unowned self] in self.stored = nil }
        )
        return FocusYouTubeAccount(testHooks: hooks)
    }
}

@MainActor
private func testFreshYouTubeDiscovery() async throws {
    let bed = TestBed()
    let account = bed.makeAccount()
    MockURLProtocol.configure { _ in Reply(status: 500, json: "{}") }
    await account.refreshFreshVideosIfNeeded()
    try check(MockURLProtocol.requests().isEmpty && account.freshNotice != nil, "Signed-out discovery must explain the requirement and make no requests")

    let recent = ISO8601DateFormatter().string(from: bed.now.addingTimeInterval(-86_400))
    let old = ISO8601DateFormatter().string(from: bed.now.addingTimeInterval(-400 * 86_400))
    let searchItems = [
        ("aaaaaaaaaaa", "Useful", "Channel A"), ("bbbbbbbbbbb", "Short", "Channel A"),
        ("ccccccccccc", "Old", "Channel B"), ("ddddddddddd", "Live", "Channel C"),
        ("eeeeeeeeeee", "Recent", "Channel D")
    ].map { "{\"id\":{\"videoId\":\"\($0.0)\"},\"snippet\":{\"title\":\"\($0.1)\",\"channelTitle\":\"\($0.2)\"}}" }.joined(separator: ",")
    func video(_ id: String, _ duration: String, _ date: String, _ live: String) -> String {
        "{\"id\":\"\(id)\",\"contentDetails\":{\"duration\":\"\(duration)\"},\"snippet\":{\"publishedAt\":\"\(date)\",\"liveBroadcastContent\":\"\(live)\"}}"
    }
    let details = [video("aaaaaaaaaaa", "PT600S", recent, "none"), video("bbbbbbbbbbb", "PT120S", recent, "none"),
                   video("ccccccccccc", "PT600S", old, "none"), video("ddddddddddd", "PT600S", recent, "live"),
                   video("eeeeeeeeeee", "PT600S", recent, "none")].joined(separator: ",")
    func configure(_ failSearch: Bool = false) {
        MockURLProtocol.configure { request in
            switch request.url?.path {
            case "/token": return Reply(status: 200, json: tokenResponse)
            case "/youtube/v3/search": return failSearch ? Reply(status: 500, json: "{}") : Reply(status: 200, json: "{\"items\":[\(searchItems)]}")
            case "/youtube/v3/videos": return Reply(status: 200, json: "{\"items\":[\(details)]}")
            default: return Reply(status: 500, json: "{}")
            }
        }
    }
    configure()
    await account.signIn()
    try check(account.freshNotice == nil, "Successful sign-in must clear the stale connect notice")
    await account.refreshFreshVideosIfNeeded()
    try check(account.freshVideos.map(\.id) == ["aaaaaaaaaaa", "eeeeeeeeeee"], "Discovery must deduplicate and exclude short, old and live videos")
    try check(account.freshVideos.allSatisfy { $0.publishedAt != nil && $0.reason == "Recent YouTube search result" }, "Discovery must report actual dates and its source")
    let searches = MockURLProtocol.requests().filter { $0.url?.path == "/youtube/v3/search" }
    try check(searches.count == 4, "Only four bounded topic searches are allowed")
    try check(Set(searches.compactMap { query($0, "q") }) == Set(["machine learning", "science research", "computer science", "startup entrepreneurship"]), "Queries must be fixed and independent of private account data")
    try check(searches.allSatisfy { query($0, "order") == "relevance" && query($0, "publishedAfter") != nil && query($0, "maxResults") == "25" }, "Queries must bound age and number of results")
    try check(MockURLProtocol.requests().filter { $0.url?.path == "/youtube/v3/videos" }.count == 1, "Video metadata is retrieved in bounded batches")
    configure()
    await account.refreshFreshVideosIfNeeded()
    try check(MockURLProtocol.requests().isEmpty, "A successful search must be cached for 24 hours")
    await account.refreshFreshVideos(force: true)
    try check(MockURLProtocol.requests().isEmpty && account.freshNotice?.contains("wait") == true, "Manual refresh must respect the shared cooldown after an automatic search")
    bed.now.addTimeInterval(2 * 60)
    await account.refreshFreshVideosIfNeeded()
    try check(MockURLProtocol.requests().isEmpty && account.freshNotice?.contains("3 min") == true, "Automatic checks must update a visible cooldown")
    bed.now.addTimeInterval(3 * 60 + 1)
    await account.refreshFreshVideosIfNeeded()
    try check(MockURLProtocol.requests().isEmpty && account.freshNotice == nil, "An expired cooldown notice must clear even while cached results remain fresh")
    await account.refreshFreshVideos(force: true)
    try check(MockURLProtocol.requests().filter { $0.url?.path == "/youtube/v3/search" }.count == 4, "A manual refresh must bypass a fresh automatic cache after the shared cooldown")
    configure()
    await account.refreshFreshVideos(force: true)
    try check(MockURLProtocol.requests().isEmpty && account.freshNotice?.contains("wait") == true, "Repeated manual taps must observe the visible cooldown")
    bed.now.addTimeInterval(5 * 60 + 1)
    await account.refreshFreshVideos(force: true)
    try check(MockURLProtocol.requests().filter { $0.url?.path == "/youtube/v3/search" }.count == 4, "Manual refresh must work after its cooldown")
    let restored = bed.makeAccount()
    try check(restored.freshVideos.map(\.id) == account.freshVideos.map(\.id) && restored.freshLastUpdated != nil, "A later launch must restore the dated public cache")
    bed.now.addTimeInterval(24 * 60 * 60 + 1)
    configure(true)
    await account.refreshFreshVideosIfNeeded()
    try check(account.freshVideos.count == 2 && account.freshNotice != nil, "Failed refresh must preserve cached results and explain the failure")
    configure()
    await account.refreshFreshVideosIfNeeded()
    try check(MockURLProtocol.requests().isEmpty, "A failed refresh must observe its retry delay")
    bed.now.addTimeInterval(6 * 60 * 60 + 1)
    await account.refreshFreshVideosIfNeeded()
    try check(MockURLProtocol.requests().filter { $0.url?.path == "/youtube/v3/search" }.count == 4, "Discovery must retry after the bounded failure delay")
    let lastSuccessfulUpdate = account.freshLastUpdated
    MockURLProtocol.configure { request in
        if request.url?.path == "/youtube/v3/search" { return Reply(status: 200, json: #"{"items":[]}"#) }
        return Reply(status: 500, json: "{}")
    }
    bed.now.addTimeInterval(5 * 60 + 1)
    await account.refreshFreshVideos(force: true)
    try check(account.freshVideos.count == 2 && account.freshLastUpdated == lastSuccessfulUpdate, "An empty search must keep the previous results and their original date")
    try check(account.freshNotice?.contains("last saved results") == true, "An empty search must explain that the visible results are saved")

    let limitBed = TestBed()
    let limited = limitBed.makeAccount()
    configure()
    await limited.signIn()
    for _ in 0..<12 {
        configure()
        await limited.refreshFreshVideos(force: true)
        try check(MockURLProtocol.requests().filter { $0.url?.path == "/youtube/v3/search" }.count == 4, "Manual refreshes below the daily cap must run")
        limitBed.now.addTimeInterval(5 * 60 + 1)
    }
    configure()
    await limited.refreshFreshVideos(force: true)
    try check(MockURLProtocol.requests().isEmpty && limited.freshNotice?.contains("limit") == true, "Daily limit must visibly stop further searches")
    limitBed.now.addTimeInterval(24 * 60 * 60)
    await limited.refreshFreshVideos(force: true)
    try check(MockURLProtocol.requests().filter { $0.url?.path == "/youtube/v3/search" }.count == 4, "Manual searches must recover when the rolling limit expires")
    try check(limited.freshNotice == nil, "A successful search must clear the expired quota notice")

    let busyBed = TestBed()
    let busyAccount = busyBed.makeAccount()
    configure()
    await busyAccount.signIn()
    MockURLProtocol.configure { request in
        if request.url?.path == "/youtube/v3/channels" { return Reply(status: 200, json: ownResponse, delay: 0.2) }
        if request.url?.path == "/youtube/v3/subscriptions" { return Reply(status: 200, json: #"{"items":[]}"#) }
        return Reply(status: 500, json: "{}")
    }
    let syncing = Task { await busyAccount.sync() }
    try await Task.sleep(nanoseconds: 60_000_000)
    await busyAccount.refreshFreshVideos(force: true)
    try check(busyAccount.freshNotice?.contains("busy") == true, "Manual refresh must explain when account sync is busy")
    try check(!MockURLProtocol.requests().contains { $0.url?.path == "/youtube/v3/search" }, "A refresh must not race an account sync")
    await syncing.value

    let loadingBed = TestBed()
    let loading = loadingBed.makeAccount()
    configure()
    await loading.signIn()
    MockURLProtocol.configure { request in
        if request.url?.path == "/youtube/v3/search" { return Reply(status: 200, json: "{\"items\":[\(searchItems)]}", delay: 0.2) }
        if request.url?.path == "/youtube/v3/videos" { return Reply(status: 200, json: "{\"items\":[\(details)]}") }
        return Reply(status: 500, json: "{}")
    }
    let firstSearch = Task { await loading.refreshFreshVideosIfNeeded() }
    try await Task.sleep(nanoseconds: 60_000_000)
    await loading.refreshFreshVideos(force: true)
    try check(loading.freshNotice?.contains("already in progress") == true, "Repeated taps must explain that a search is running")
    await firstSearch.value
    try check(MockURLProtocol.requests().filter { $0.url?.path == "/youtube/v3/search" }.count == 4, "A repeated tap must not start another search batch")
    MockURLProtocol.configure { request in
        if request.url?.path == "/youtube/v3/channels" { return Reply(status: 200, json: ownResponse, delay: 0.2) }
        if request.url?.path == "/youtube/v3/subscriptions" { return Reply(status: 200, json: #"{"items":[]}"#) }
        return Reply(status: 500, json: "{}")
    }
    let loadingSync = Task { await loading.sync() }
    try await Task.sleep(nanoseconds: 60_000_000)
    await loading.refreshFreshVideos(force: true)
    try check(loading.freshNotice?.contains("busy") == true, "A manual search during sync should report a busy account")
    await loadingSync.value
    await loading.refreshFreshVideosIfNeeded()
    try check(loading.freshNotice == nil, "A cached successful result must clear a stale busy notice")

    let clearBed = TestBed()
    let clearAccount = clearBed.makeAccount()
    configure()
    await clearAccount.signIn()
    await clearAccount.refreshFreshVideosIfNeeded()
    try check(!clearAccount.freshVideos.isEmpty, "A successful search should fill the public cache")
    clearAccount.signOut()
    try check(clearAccount.freshVideos.isEmpty && clearAccount.freshLastUpdated == nil && clearAccount.freshNotice == nil, "Sign-out must clear the displayed discovery cache")
    try check(clearBed.freshCache.data(forKey: "focus.youtube.discovery.v1") == nil, "Sign-out must remove stored YouTube discovery data")

    let expiredBed = TestBed()
    let expiry = expiredBed.makeAccount()
    configure()
    await expiry.signIn()
    await expiry.refreshFreshVideosIfNeeded()
    expiredBed.now.addTimeInterval(8 * 24 * 60 * 60)
    let afterExpiry = expiredBed.makeAccount()
    try check(afterExpiry.freshVideos.isEmpty && expiredBed.freshCache.data(forKey: "focus.youtube.discovery.v1") == nil, "Expired YouTube API metadata must not survive a later launch")

    let signingOutBed = TestBed()
    let signingOut = signingOutBed.makeAccount()
    configure()
    await signingOut.signIn()
    MockURLProtocol.configure { request in
        if request.url?.path == "/youtube/v3/search" { return Reply(status: 200, json: "{\"items\":[\(searchItems)]}", delay: 0.2) }
        return Reply(status: 500, json: "{}")
    }
    let pending = Task { await signingOut.refreshFreshVideosIfNeeded() }
    try await Task.sleep(nanoseconds: 60_000_000)
    signingOut.signOut()
    await pending.value
    try check(signingOut.freshVideos.isEmpty, "A response received after sign-out must not publish discovery results")
    let pendingSearches = MockURLProtocol.requests().filter { $0.url?.path == "/youtube/v3/search" }.count
    try check((1...4).contains(pendingSearches), "Concurrent public searches must stay within their fixed bound")
    try check(!MockURLProtocol.requests().contains { $0.url?.path == "/youtube/v3/videos" }, "Sign-out must stop authenticated metadata requests")
    try check(signingOutBed.freshCache.data(forKey: "focus.youtube.discovery.v1") == nil && signingOutBed.freshCache.object(forKey: "focus.youtube.discovery.attempt.v1") == nil, "Sign-out must remove cached results and an interrupted retry delay")
    configure()
    await signingOut.signIn()
    await signingOut.refreshFreshVideosIfNeeded()
    try check(!MockURLProtocol.requests().contains { $0.url?.path == "/youtube/v3/search" } && signingOut.freshNotice?.contains("wait") == true, "A fresh sign-in must respect the shared cooldown after cancellation")
    signingOutBed.now.addTimeInterval(5 * 60 + 1)
    await signingOut.refreshFreshVideosIfNeeded()
    try check(MockURLProtocol.requests().filter { $0.url?.path == "/youtube/v3/search" }.count == 4, "Cancelled attempts must be retriable after the shared cooldown rather than six hours")

    let reconnectBed = TestBed()
    let reconnecting = reconnectBed.makeAccount()
    for _ in 0..<12 {
        configure()
        await reconnecting.signIn()
        await reconnecting.refreshFreshVideosIfNeeded()
        try check(MockURLProtocol.requests().filter { $0.url?.path == "/youtube/v3/search" }.count == 4, "Automatic search should run while within the shared budget")
        reconnecting.signOut()
        reconnectBed.now.addTimeInterval(5 * 60 + 1)
    }
    configure()
    await reconnecting.signIn()
    await reconnecting.refreshFreshVideosIfNeeded()
    try check(!MockURLProtocol.requests().contains { $0.url?.path == "/youtube/v3/search" } && reconnecting.freshNotice?.contains("limit") == true, "Repeated sign-out and sign-in must not bypass the shared search budget")
}

private let a = "UC" + String(repeating: "a", count: 22)
private let b = "UC" + String(repeating: "b", count: 22)
private let ownResponse = #"{"items":[{"snippet":{"title":"My channel"}}]}"#
private let tokenResponse = #"{"access_token":"access-1","refresh_token":"refresh-1","expires_in":3600,"scope":"https://www.googleapis.com/auth/youtube.readonly"}"#

private func query(_ request: URLRequest, _ key: String) -> String? {
    URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == key }?.value
}

private func bodyItems(_ request: URLRequest) -> [URLQueryItem] {
    var components = URLComponents()
    components.percentEncodedQuery = String(data: request.httpBody ?? Data(), encoding: .utf8)
    return components.queryItems ?? []
}

@MainActor
private func testInvalidCallbacks() async throws {
    for mode in [TestBed.CallbackMode.wrongState, .wrongScheme, .duplicateState, .duplicateCode, .cancelled] {
        let bed = TestBed(); bed.mode = mode
        MockURLProtocol.configure { _ in Reply(status: 500, json: "{}") }
        let account = bed.makeAccount()
        await account.signIn()
        try check(!account.signedIn && !account.signInSucceeded && bed.stored == nil, "Bad callback must not sign in or store credentials")
        try check(MockURLProtocol.requests().isEmpty, "Bad callback must not reach the token endpoint")
        try check(account.notice != nil, "Bad callback should be reported")
    }
}

@MainActor
private func testSafeAccountDiagnostics() async throws {
    let diagnostics = FocusDiagnostics.shared
    diagnostics.clear()
    let invalidBed = TestBed(); invalidBed.mode = .wrongState
    MockURLProtocol.configure { _ in Reply(status: 500, json: "{}") }
    let invalid = invalidBed.makeAccount()
    await invalid.signIn()
    try check(diagnostics.entries.last?.event == .signInFailed && diagnostics.entries.last?.code == .invalidResponse, "Invalid callbacks must be reported only as a fixed error category")

    let authBed = TestBed()
    MockURLProtocol.configure { _ in Reply(status: 401, json: "{}") }
    let unauthorized = authBed.makeAccount()
    await unauthorized.signIn()
    try check(diagnostics.entries.last?.event == .signInFailed && diagnostics.entries.last?.code == .authorization, "Authorization failures must have their fixed category")

    let networkBed = TestBed()
    let privateMarker = "PRIVATE_ERROR_MARKER"
    let offline = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet, userInfo: [NSLocalizedDescriptionKey: privateMarker])
    MockURLProtocol.configure { _ in Reply(status: 0, json: "", error: offline) }
    let disconnected = networkBed.makeAccount()
    await disconnected.signIn()
    try check(diagnostics.entries.last?.event == .signInFailed && diagnostics.entries.last?.code == .offline, "Offline failures must have their fixed category")
    let report = diagnostics.report(version: "0.5.0")
    try check(!report.contains(privateMarker) && !report.contains("https://") && !report.contains("access-1"), "Diagnostics must never contain raw errors, URLs or tokens")
    diagnostics.clear()
}

@MainActor
private func testPaginationAndUploads() async throws {
    let bed = TestBed()
    MockURLProtocol.configure { request in
        let path = request.url?.path ?? ""
        if path == "/token" { return Reply(status: 200, json: tokenResponse) }
        if path == "/youtube/v3/channels", query(request, "mine") == "true" { return Reply(status: 200, json: ownResponse) }
        if path == "/youtube/v3/subscriptions" {
            if query(request, "pageToken") == nil {
                return Reply(status: 200, json: "{\"items\":[{\"snippet\":{\"title\":\"A\",\"resourceId\":{\"channelId\":\"\(a)\"}}}],\"nextPageToken\":\"page2\"}")
            }
            return Reply(status: 200, json: "{\"items\":[{\"snippet\":{\"title\":\"A duplicate\",\"resourceId\":{\"channelId\":\"\(a)\"}}},{\"snippet\":{\"title\":\"B\",\"resourceId\":{\"channelId\":\"\(b)\"}}}]}")
        }
        if path == "/youtube/v3/channels" { return Reply(status: 200, json: "{\"items\":[{\"id\":\"\(a)\",\"contentDetails\":{\"relatedPlaylists\":{\"uploads\":\"UUa\"}}}]}") }
        if path == "/youtube/v3/playlistItems" {
            let entries = [("aaaaaaaaaaa", "2026-01-03T12:00:00Z"), ("bbbbbbbbbbb", "2026-01-05T12:00:00.000Z"), ("ccccccccccc", "2026-01-04T12:00:00Z")]
            let items = entries.map { "{\"snippet\":{\"title\":\"Video\",\"channelTitle\":\"A\",\"publishedAt\":\"\($0.1)\",\"resourceId\":{\"videoId\":\"\($0.0)\"}}}" }.joined(separator: ",")
            return Reply(status: 200, json: "{\"items\":[\(items)]}")
        }
        if path == "/youtube/v3/videos" {
            return Reply(status: 200, json: #"{"items":[{"id":"aaaaaaaaaaa","contentDetails":{"duration":"PT180S"},"snippet":{"liveBroadcastContent":"none","publishedAt":"2026-01-03T12:00:00Z"}},{"id":"bbbbbbbbbbb","contentDetails":{"duration":"PT181S"},"snippet":{"liveBroadcastContent":"none","publishedAt":"2026-01-01T12:00:00.000Z"}},{"id":"ccccccccccc","contentDetails":{"duration":"P1DT1H"},"snippet":{"liveBroadcastContent":"none","publishedAt":"2026-01-04T12:00:00Z"}}]}"#)
        }
        return Reply(status: 500, json: "{}")
    }
    let account = bed.makeAccount()
    await account.signIn()
    try check(account.signInSucceeded && account.hasRefreshToken && bed.stored != nil, "Valid sign-in must persist credentials")
    guard let tokenRequest = bed.tokenRequests.first else { throw TestFailure(description: "Missing token request") }
    let body = String(data: tokenRequest.httpBody ?? Data(), encoding: .utf8) ?? ""
    try check(body.contains("%2B"), "A plus sign in the authorization code must be percent-encoded")
    try check(bodyItems(tokenRequest).first(where: { $0.name == "code" })?.value == "a+b/=", "The authorization code must round-trip")
    let verifier = bodyItems(tokenRequest).first { $0.name == "code_verifier" }?.value ?? ""
    let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    try check(challenge == bed.challenge, "PKCE verifier must match the original S256 challenge")
    await account.sync()
    try check(account.syncSucceeded && account.channels.count == 2, "Two pages must be combined and deduplicated")
    try check(account.connectedChannel == "My channel", "The authorized channel name must be shown")
    try check(MockURLProtocol.requests().filter { $0.url?.path == "/youtube/v3/subscriptions" }.count == 2, "Both pages must be requested")
    let skipped = await account.syncIfNeeded()
    try check(!skipped && MockURLProtocol.requests().filter { $0.url?.path == "/youtube/v3/subscriptions" }.count == 2, "Foreground refresh must not repeat a recent sync")
    await account.loadUploads(for: [account.channels[0]])
    try check(account.uploads.map(\.id) == ["ccccccccccc", "bbbbbbbbbbb"], "Uploads must sort by video publication rather than playlist addition date and exclude the three-minute item")
    let playlistRequest = MockURLProtocol.requests().first { $0.url?.path == "/youtube/v3/playlistItems" }
    try check(URLComponents(url: playlistRequest!.url!, resolvingAgainstBaseURL: false)?.queryItems?.contains(URLQueryItem(name: "maxResults", value: "20")) == true, "Fetch enough playlist items to allow for Shorts")
    let restored = bed.makeAccount()
    try check(restored.signedIn && restored.hasRefreshToken, "A new account instance must restore credentials from its store")
}

@MainActor
private func testPaginationCycle() async throws {
    let bed = TestBed()
    MockURLProtocol.configure { request in
        if request.url?.path == "/token" { return Reply(status: 200, json: tokenResponse) }
        if request.url?.path == "/youtube/v3/channels" { return Reply(status: 200, json: ownResponse) }
        return Reply(status: 200, json: #"{"items":[],"nextPageToken":"repeat"}"#)
    }
    let account = bed.makeAccount()
    await account.signIn(); await account.sync()
    try check(!account.syncSucceeded && account.notice != nil, "Cyclic pagination must fail rather than loop or publish partial data")
    try check(MockURLProtocol.requests().filter { $0.url?.path == "/youtube/v3/subscriptions" }.count == 2, "Pagination must stop on a repeated token")
}

// The UI retries a complete or partial upload failure after a bounded delay,
// while successful refreshes retain the longer quota-saving interval.
@MainActor
private func testAutomaticRetry() async throws {
    func configure(_ failure: String?) {
        MockURLProtocol.configure { request in
            let path = request.url?.path ?? ""
            if path == "/token" { return Reply(status: 200, json: tokenResponse) }
            if path == "/youtube/v3/channels", query(request, "mine") == "true" { return Reply(status: 200, json: ownResponse) }
            if path == "/youtube/v3/subscriptions" {
                if failure == "subscriptions" { return Reply(status: 500, json: "{}") }
                return Reply(status: 200, json: "{\"items\":[{\"snippet\":{\"title\":\"A\",\"resourceId\":{\"channelId\":\"\(a)\"}}},{\"snippet\":{\"title\":\"B\",\"resourceId\":{\"channelId\":\"\(b)\"}}}]}")
            }
            if path == "/youtube/v3/channels" { return Reply(status: 200, json: "{\"items\":[{\"id\":\"\(a)\",\"contentDetails\":{\"relatedPlaylists\":{\"uploads\":\"UUa\"}}},{\"id\":\"\(b)\",\"contentDetails\":{\"relatedPlaylists\":{\"uploads\":\"UUb\"}}}]}") }
            if path == "/youtube/v3/playlistItems" {
                if failure == "partial", query(request, "playlistId") == "UUb" { return Reply(status: 500, json: "{}") }
                return Reply(status: 200, json: #"{"items":[{"snippet":{"title":"Video","channelTitle":"A","publishedAt":"2026-01-01T12:00:00Z","resourceId":{"videoId":"aaaaaaaaaaa"}}}]}"#)
            }
            if path == "/youtube/v3/videos" {
                if failure == "uploads" { return Reply(status: 500, json: "{}") }
                return Reply(status: 200, json: #"{"items":[{"id":"aaaaaaaaaaa","contentDetails":{"duration":"PT181S"},"snippet":{"liveBroadcastContent":"none","publishedAt":"2026-01-01T12:00:00Z"}}]}"#)
            }
            return Reply(status: 500, json: "{}")
        }
    }

    for failure in ["subscriptions", "uploads", "partial"] {
        let bed = TestBed()
        configure(failure)
        let account = bed.makeAccount()
        await account.signIn()
        await account.sync()
        if account.syncSucceeded { await account.loadUploads(for: account.channels) }
        try check(account.notice != nil, "The \(failure) failure should be visible")
        configure(nil)
        bed.now.addTimeInterval(299)
        let tooSoon = await account.syncIfNeeded()
        try check(!tooSoon && MockURLProtocol.requests().isEmpty, "The \(failure) retry must wait at least five minutes")
        bed.now.addTimeInterval(2)
        let retried = await account.syncIfNeeded()
        try check(retried, "The \(failure) failure should retry after five minutes")
        await account.loadUploads(for: account.channels)
        try check(account.uploads.count == 1 && account.notice == nil, "A successful retry should restore uploads")
        configure(nil)
        bed.now.addTimeInterval(5 * 60)
        let afterSuccess = await account.syncIfNeeded()
        try check(!afterSuccess && MockURLProtocol.requests().isEmpty, "A successful refresh should use the thirty-minute interval")
    }

    let bed = TestBed()
    configure(nil)
    let account = bed.makeAccount()
    await account.signIn(); await account.sync()
    try check(account.syncSucceeded, "The first sync must succeed")
    bed.now.addTimeInterval(30 * 60 + 1)
    configure("subscriptions")
    let failed = await account.syncIfNeeded()
    try check(!failed && !account.syncSucceeded, "A later failure must not retain the previous success")
    configure(nil)
    bed.now.addTimeInterval(299)
    let tooSoon = await account.syncIfNeeded()
    try check(!tooSoon && MockURLProtocol.requests().isEmpty, "A later failure must still observe the retry delay")
    bed.now.addTimeInterval(2)
    let recovered = await account.syncIfNeeded()
    try check(recovered && account.syncSucceeded, "A later failure must retry successfully after the delay")
    await account.loadUploads(for: account.channels)

    let repeatedBed = TestBed()
    configure("partial")
    let repeated = repeatedBed.makeAccount()
    await repeated.signIn(); await repeated.sync(); await repeated.loadUploads(for: repeated.channels)
    for delay in [300, 600, 1200, 1800, 1800] {
        configure("partial")
        repeatedBed.now.addTimeInterval(TimeInterval(delay - 1))
        let early = await repeated.syncIfNeeded()
        try check(!early && MockURLProtocol.requests().isEmpty, "Repeated failures must back off before retrying")
        repeatedBed.now.addTimeInterval(2)
        let due = await repeated.syncIfNeeded()
        try check(due, "Repeated failures should retry when backoff expires")
        await repeated.loadUploads(for: repeated.channels)
        try check(repeated.notice != nil, "The partial failure must remain visible")
    }
    configure(nil)
    repeatedBed.now.addTimeInterval(1801)
    let retryAfterBackoff = await repeated.syncIfNeeded()
    try check(retryAfterBackoff, "A full refresh must retry after the capped delay")
    await repeated.loadUploads(for: repeated.channels)
    configure("partial")
    await repeated.loadUploads(for: repeated.channels)
    configure(nil)
    repeatedBed.now.addTimeInterval(301)
    let resetDelay = await repeated.syncIfNeeded()
    try check(resetDelay, "A full success must reset later failures to the initial delay")
}

@MainActor
private func testExpiredToken() async throws {
    let bed = TestBed()
    MockURLProtocol.configure { request in
        if request.url?.path == "/token" {
            if MockURLProtocol.requests().filter({ $0.url?.path == "/token" }).count > 1 { return Reply(status: 401, json: "{}") }
            return Reply(status: 200, json: #"{"access_token":"expired","refresh_token":"refresh","expires_in":0}"#)
        }
        return Reply(status: 500, json: "{}")
    }
    let account = bed.makeAccount()
    await account.signIn(); await account.sync()
    try check(!account.syncSucceeded && account.notice != nil, "Expired token refresh failure must be visible")
    try check(!MockURLProtocol.requests().contains { $0.url?.path.hasPrefix("/youtube/v3/") == true }, "API calls must not run after token refresh fails")
}

@MainActor
private func testRefreshTokenSuccess() async throws {
    let bed = TestBed()
    MockURLProtocol.configure { request in
        if request.url?.path == "/token" {
            if MockURLProtocol.requests().filter({ $0.url?.path == "/token" }).count > 1 {
                return Reply(status: 200, json: #"{"access_token":"new-token","expires_in":3600}"#)
            }
            return Reply(status: 200, json: #"{"access_token":"expired","refresh_token":"refresh","expires_in":0}"#)
        }
        if request.url?.path == "/youtube/v3/channels" { return Reply(status: 200, json: ownResponse) }
        return Reply(status: 200, json: "{\"items\":[{\"snippet\":{\"title\":\"A\",\"resourceId\":{\"channelId\":\"\(a)\"}}}]}")
    }
    let account = bed.makeAccount()
    await account.signIn(); await account.sync()
    try check(account.syncSucceeded && account.channels.count == 1, "Refresh token must restore an expired session")
    let apiRequests = MockURLProtocol.requests().filter { $0.url?.path.hasPrefix("/youtube/v3/") == true }
    try check(!apiRequests.isEmpty && apiRequests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer new-token" }, "Only the refreshed access token may be used for API requests")
    try check(account.hasRefreshToken, "Refresh response without refresh_token must retain the existing token")
}

@MainActor
private func testSignOutDuringRequest() async throws {
    let bed = TestBed()
    MockURLProtocol.configure { request in
        if request.url?.path == "/token" { return Reply(status: 200, json: tokenResponse) }
        if request.url?.path == "/youtube/v3/channels" { return Reply(status: 200, json: ownResponse, delay: 0.2) }
        return Reply(status: 200, json: "{\"items\":[{\"snippet\":{\"title\":\"A\",\"resourceId\":{\"channelId\":\"\(a)\"}}}]}")
    }
    let account = bed.makeAccount()
    await account.signIn()
    let request = Task { await account.sync() }
    try await Task.sleep(nanoseconds: 60_000_000)
    account.signOut()
    await request.value
    try check(!account.signedIn && account.channels.isEmpty && account.connectedChannel == nil && bed.stored == nil, "A late response must not restore a signed-out account")
    try check(!MockURLProtocol.requests().contains { $0.url?.path == "/youtube/v3/subscriptions" }, "Sign-out during the account request must not initiate another authenticated request")
}

@MainActor
private func testSignOutDuringAuthorization() async throws {
    let bed = TestBed(); bed.mode = .slowGood
    MockURLProtocol.configure { _ in Reply(status: 200, json: tokenResponse) }
    let account = bed.makeAccount()
    let request = Task { await account.signIn() }
    try await Task.sleep(nanoseconds: 60_000_000)
    account.signOut()
    await request.value
    try check(!account.signedIn && bed.stored == nil, "A late authorization callback must not restore a signed-out account")
    try check(MockURLProtocol.requests().isEmpty, "Sign-out during authentication must not exchange the authorization code")
}

@MainActor
private func testRedirectDelegate() throws {
    let target = URL(string: "https://evil.invalid/steal")!
    let response = HTTPURLResponse(url: URL(string: "https://www.googleapis.com/")!, statusCode: 302, httpVersion: nil, headerFields: ["Location": target.absoluteString])!
    var redirected: URLRequest? = URLRequest(url: target)
    let task = URLSession.shared.dataTask(with: URL(string: "https://www.googleapis.com/")!)
    NoRedirect().urlSession(URLSession.shared, task: task, willPerformHTTPRedirection: response, newRequest: URLRequest(url: target)) { redirected = $0 }
    try check(redirected == nil, "The production redirect delegate must refuse the next request")
}

@MainActor
private func testNoBearerTokenOnRedirect() async throws {
    let bed = TestBed()
    MockURLProtocol.configure { request in
        if request.url?.path == "/token" { return Reply(status: 200, json: tokenResponse) }
        if request.url?.path == "/youtube/v3/channels" {
            return Reply(status: 302, json: "{}", redirect: URL(string: "https://evil.invalid/steal")!)
        }
        return Reply(status: 200, json: #"{"items":[]}"#)
    }
    let account = bed.makeAccount()
    await account.signIn(); await account.sync()
    let requests = MockURLProtocol.requests()
    try check(requests.contains { $0.url?.path == "/youtube/v3/channels" }, "The simulated redirect must actually be exercised")
    try check(!requests.contains { $0.url?.host == "evil.invalid" }, "Redirects must not transmit the bearer token to another host")
}

@main
struct AccountIntegrationTestApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Running offline subscription tests…").task {
                Task.detached {
                    try? await Task.sleep(nanoseconds: 60_000_000_000)
                    print("FOCUS_ACCOUNT_TESTS_FAILED: Test execution timed out")
                    fflush(stdout)
                    exit(1)
                }
                do {
                    try await testInvalidCallbacks()
                    try await testSafeAccountDiagnostics()
                    try await testPaginationAndUploads()
                    try await testFreshYouTubeDiscovery()
                    try await testPaginationCycle()
                    try await testAutomaticRetry()
                    try await testExpiredToken()
                    try await testRefreshTokenSuccess()
                    try await testSignOutDuringRequest()
                    try await testSignOutDuringAuthorization()
                    try await testRedirectDelegate()
                    try await testNoBearerTokenOnRedirect()
                    print("FOCUS_ACCOUNT_TESTS_PASSED")
                    fflush(stdout)
                    exit(0)
                } catch {
                    print("FOCUS_ACCOUNT_TESTS_FAILED: \(error)")
                    fflush(stdout)
                    exit(1)
                }
            }
        }
    }
}
