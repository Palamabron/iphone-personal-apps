import Foundation
import AuthenticationServices
import Combine
import CryptoKit
import Security
import UIKit

#if FOCUS_ACCOUNT_TESTING
// Compiled only in the simulator test target. Production always uses the
// system browser, Keychain and an ephemeral URLSession with redirect blocking.
struct FocusAccountTestHooks {
    let clientID: String
    let configuration: URLSessionConfiguration
    let authenticate: (URL, String) async throws -> URL
    let observeTokenRequest: (URLRequest) -> Void
    let now: () -> Date
    let freshCache: UserDefaults
    let read: () throws -> Data?
    let write: (Data) throws -> Void
    let delete: () -> Void
}
#endif

/// Google API authorization is independent of the YouTube web player's session.
/// The OAuth client ID and its reversed URL scheme must be registered at build time.
@MainActor
final class FocusYouTubeAccount: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    #if FOCUS_ACCOUNT_TESTING
    private var testHooks: FocusAccountTestHooks?
    #endif
    struct Channel: Identifiable, Codable, Hashable {
        let id: String
        let title: String
    }
    struct Upload: Identifiable {
        let id: String
        let title: String
        let channel: String
        let publishedAt: Date?
    }
    @Published private(set) var channels: [Channel] = []
    @Published private(set) var connectedChannel: String?
    @Published private(set) var uploads: [Upload] = []
    @Published private(set) var signedIn = false
    @Published private(set) var busy = false
    @Published private(set) var syncSucceeded = false
    // A truncated or failed sync must never be used to discard saved selections.
    @Published private(set) var subscriptionsComplete = false
    @Published private(set) var subscriptionSyncRevision = 0
    @Published private(set) var signInSucceeded = false
    @Published private(set) var notice: String?
    /// Public, fixed-topic YouTube searches; never derived from private account data.
    @Published private(set) var freshVideos: [FocusRecommendation] = []
    @Published private(set) var freshLastUpdated: Date?
    @Published private(set) var freshNotice: String?
    @Published private(set) var freshLoading = false
    private let freshCacheKey = "focus.youtube.discovery.v1"
    private let freshAttemptKey = "focus.youtube.discovery.attempt.v1"
    private let freshAttemptQueryVersionKey = "focus.youtube.discovery.attempt.query-version.v1"
    // Bump when the fixed queries or their admission rules change. Old cache
    // remains visible after filtering but does not suppress the new search.
    private static let freshQueryVersion = 2
    // Kept across sign-out: reconnecting must not bypass the shared API budget.
    private let freshBudgetAttemptsKey = "focus.youtube.discovery.search-budget.v1"
    private let freshSuccessInterval: TimeInterval = 24 * 60 * 60
    private let freshRetryInterval: TimeInterval = 6 * 60 * 60
    private let freshSearchInterval: TimeInterval = 5 * 60
    private let freshSearchDailyLimit = 12
    private let freshRetention: TimeInterval = 7 * 24 * 60 * 60
    private var freshSearchWork: Task<[FreshSearchBatch], Never>?
    private var freshMetadataWork: Task<[FreshMetadataBatch], Never>?

    private struct FreshCache: Codable {
        let videos: [FocusRecommendation]
        let updatedAt: Date
        let partial: Bool
        let queryVersion: Int?
    }

    private var freshCacheStore: UserDefaults {
        #if FOCUS_ACCOUNT_TESTING
        if let store = testHooks?.freshCache { return store }
        #endif
        return .standard
    }
    private var lastSyncedAt: Date?
    private var lastRefreshFailureAt: Date?
    private var consecutiveRefreshFailures = 0

    private var now: Date {
        #if FOCUS_ACCOUNT_TESTING
        if let clock = testHooks?.now { return clock() }
        #endif
        return Date()
    }

    private func recordRefreshFailure() {
        consecutiveRefreshFailures = min(consecutiveRefreshFailures + 1, 4)
        lastRefreshFailureAt = now
    }

    private func clearRefreshFailure() {
        consecutiveRefreshFailures = 0
        lastRefreshFailureAt = nil
    }

    private struct Credentials: Codable {
        let clientID: String
        let accessToken: String
        let refreshToken: String?
        let expiresAt: Date
    }
    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String?
        let expires_in: Double
        let scope: String?
    }
    private struct SubscriptionResponse: Decodable {
        struct Item: Decodable {
            struct Snippet: Decodable {
                struct Resource: Decodable { let channelId: String? }
                let title: String
                let resourceId: Resource
            }
            let snippet: Snippet
        }
        let items: [Item]
        let nextPageToken: String?
    }
    private struct ChannelsResponse: Decodable {
        struct Item: Decodable {
            struct Details: Decodable {
                struct Playlists: Decodable { let uploads: String? }
                let relatedPlaylists: Playlists
            }
            let id: String
            let contentDetails: Details
        }
        let items: [Item]
    }
    private struct OwnChannelResponse: Decodable {
        struct Item: Decodable {
            struct Snippet: Decodable { let title: String }
            let snippet: Snippet
        }
        let items: [Item]
    }
    private struct PlaylistResponse: Decodable {
        struct Item: Decodable {
            struct Snippet: Decodable {
                struct Resource: Decodable { let videoId: String? }
                let title: String
                let channelTitle: String
                let publishedAt: String
                let resourceId: Resource
            }
            let snippet: Snippet
        }
        let items: [Item]
    }
    private struct VideosResponse: Decodable {
        struct Item: Decodable {
            struct Content: Decodable { let duration: String }
            struct Snippet: Decodable { let liveBroadcastContent: String?; let publishedAt: String? }
            let id: String
            let contentDetails: Content
            let snippet: Snippet
        }
        let items: [Item]
    }
    private struct FreshSearchResponse: Decodable {
        struct Item: Decodable {
            struct Resource: Decodable { let videoId: String? }
            struct Snippet: Decodable { let title: String; let channelTitle: String }
            let id: Resource
            let snippet: Snippet
        }
        let items: [Item]
    }
    private struct Candidate: Sendable {
        let id: String
        let title: String
        let channel: String
        let publishedAt: Date
    }
    private struct FreshCandidate: Sendable {
        let id: String
        let title: String
        let channel: String
        let topic: String
        var additionalTopics: [String] = []
    }
    private struct FreshSearchBatch: Sendable {
        let items: [FreshCandidate]?
        let failure: FocusDiagnosticCode?
    }
    private struct FreshMetadataBatch: Sendable {
        let dates: [String: Date]?
        let failure: FocusDiagnosticCode?
    }
    private let service = "dev.palamabron.focustube.google-api"
    private var session: ASWebAuthenticationSession?
    private var credentials: Credentials?
    private var generation = 0
    private var uploadsGeneration = 0
    // A selection made while another account operation is active must not be lost.
    // Keep only the most recent selection; an empty selection clears it immediately.
    private var pendingUploadSelection: [Channel]?
    private let noRedirect = NoRedirect()
    private lazy var network: URLSession = {
        #if FOCUS_ACCOUNT_TESTING
        let configuration = testHooks?.configuration ?? URLSessionConfiguration.ephemeral
        #else
        let configuration = URLSessionConfiguration.ephemeral
        #endif
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 20
        return URLSession(configuration: configuration, delegate: noRedirect, delegateQueue: nil)
    }()

    private var clientID: String? {
        #if FOCUS_ACCOUNT_TESTING
        if let value = testHooks?.clientID { return value }
        #endif
        guard let value = Bundle.main.object(forInfoDictionaryKey: "FocusGoogleClientID") as? String,
              value.range(of: #"^[A-Za-z0-9-]+\.apps\.googleusercontent\.com$"#, options: .regularExpression) != nil else { return nil }
        let scheme = value.split(separator: ".").reversed().joined(separator: ".")
        let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
        let schemes = types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        return schemes.contains(scheme) ? value : nil
    }
    var configured: Bool { clientID != nil }
    var hasRefreshToken: Bool { credentials?.refreshToken != nil }

    override init() {
        super.init()
        restoreCredentials()
        restoreFreshCache()
    }
    #if FOCUS_ACCOUNT_TESTING
    init(testHooks: FocusAccountTestHooks) {
        self.testHooks = testHooks
        super.init()
        restoreCredentials()
        restoreFreshCache()
    }
    #endif
    private func restoreCredentials() {
        if let client = clientID, let stored = try? readCredentials(), stored.clientID == client {
            credentials = stored
            signedIn = true
        }
    }

    private func restoreFreshCache() {
        guard let data = freshCacheStore.data(forKey: freshCacheKey),
              let cached = try? JSONDecoder().decode(FreshCache.self, from: data) else { return }
        guard cached.updatedAt <= now, now.timeIntervalSince(cached.updatedAt) < freshRetention else {
            freshCacheStore.removeObject(forKey: freshCacheKey)
            return
        }
        freshVideos = Array(cached.videos.compactMap { video -> FocusRecommendation? in
            guard FocusPolicy.validID(video.id), !video.title.isEmpty, !video.channel.isEmpty,
                  video.publishedAt != nil else { return nil }
            let matchingTopics = video.allTopics.filter { FocusRecommendations.freshSearchTitleMatches(video.title, topic: $0) }
            guard let first = matchingTopics.first else { return nil }
            return FocusRecommendation(id: video.id, title: video.title, channel: video.channel,
                topic: first, reason: video.reason, publishedAt: video.publishedAt,
                shelfLife: video.shelfLife, hnRecommenders: video.hnRecommenders,
                additionalTopics: Array(matchingTopics.dropFirst()))
        }.prefix(60))
        freshLastUpdated = cached.updatedAt
        if cached.partial { freshNotice = "Some YouTube searches could not be refreshed." }
    }

    /// Searches only these four fixed public topics, independently of subscriptions,
    /// saved videos, account history and all local recommendation preferences.
    /// Search relevance and age are discovery signals, not judgments of quality.
    func refreshFreshVideosIfNeeded() async {
        await refreshFreshVideos(force: false)
    }

    /// A user-initiated refresh can bypass the automatic cache, but is still
    /// rate limited so repeated taps cannot exhaust the project's quota.
    func refreshFreshVideos(force: Bool) async {
        if let updated = freshLastUpdated, now.timeIntervalSince(updated) >= freshRetention {
            freshVideos = []; freshLastUpdated = nil
            freshCacheStore.removeObject(forKey: freshCacheKey)
        }
        guard signedIn else {
            freshNotice = "Connect Google to refresh recent YouTube discoveries."
            return
        }
        guard !busy, !freshLoading else {
            if force { freshNotice = freshLoading ? "YouTube search is already in progress." : "Google account is busy. Try refreshing again shortly." }
            return
        }
        let clock = now
        let searchAttempts = (freshCacheStore.array(forKey: freshBudgetAttemptsKey) as? [Date] ?? [])
            .filter { $0 <= clock && clock.timeIntervalSince($0) < 24 * 60 * 60 }.sorted()
        let cache = freshCacheStore.data(forKey: freshCacheKey).flatMap { try? JSONDecoder().decode(FreshCache.self, from: $0) }
        let budgetNotice: String?
        if let last = searchAttempts.last, clock.timeIntervalSince(last) < freshSearchInterval {
            let minutes = max(1, Int(ceil((freshSearchInterval - clock.timeIntervalSince(last)) / 60)))
            budgetNotice = "Please wait \(minutes) min before searching YouTube again."
        } else if searchAttempts.count >= freshSearchDailyLimit, let first = searchAttempts.first {
            let minutes = max(1, Int(ceil((24 * 60 * 60 - clock.timeIntervalSince(first)) / 60)))
            budgetNotice = "YouTube search limit reached. Try again in \(minutes) min."
        } else {
            budgetNotice = nil
        }
        if freshNotice?.hasPrefix("Please wait ") == true || freshNotice?.hasPrefix("YouTube search limit reached.") == true {
            freshNotice = budgetNotice ?? (cache?.partial == true ? "Some YouTube searches could not be refreshed." : nil)
        }
        if !force {
            if let cache, cache.queryVersion == Self.freshQueryVersion, cache.updatedAt <= clock,
               clock.timeIntervalSince(cache.updatedAt) < (cache.partial ? freshRetryInterval : freshSuccessInterval) {
                if freshNotice == "Connect Google to refresh recent YouTube discoveries."
                    || freshNotice == "YouTube search is already in progress."
                    || freshNotice == "Google account is busy. Try refreshing again shortly." {
                    freshNotice = cache.partial ? "Some YouTube searches could not be refreshed." : nil
                }
                return
            }
            if freshCacheStore.integer(forKey: freshAttemptQueryVersionKey) == Self.freshQueryVersion,
               let attempt = freshCacheStore.object(forKey: freshAttemptKey) as? Date,
               attempt <= clock, clock.timeIntervalSince(attempt) < freshRetryInterval { return }
        }
        if let budgetNotice { freshNotice = budgetNotice; return }
        busy = true; freshLoading = true
        FocusDiagnostics.shared.record(.freshSearchStarted)
        let requestGeneration = generation
        defer { freshLoading = false; finishOperation() }
        do {
            let token = try await accessToken()
            guard requestGeneration == generation else { return }
            freshCacheStore.set(searchAttempts + [now], forKey: freshBudgetAttemptsKey)
            freshCacheStore.set(now, forKey: freshAttemptKey)
            freshCacheStore.set(Self.freshQueryVersion, forKey: freshAttemptQueryVersionKey)
            let after = ISO8601DateFormatter().string(from: now.addingTimeInterval(-365 * 24 * 60 * 60))
            let searches = [
                ("machine learning", "AI & ML"), ("science research", "Science & math"),
                ("computer science", "Computing"), ("software engineering", "Computing")
            ]
            let network = self.network
            // Run only four fixed queries concurrently. The account remains busy,
            // but bounded parallel requests avoid blocking it for four timeouts.
            let searchWork = Task { await withTaskGroup(of: (Int, FreshSearchBatch).self, returning: [FreshSearchBatch].self) { group in
                for (index, search) in searches.enumerated() {
                    group.addTask {
                        do {
                            try Task.checkCancellation()
                            let result: FreshSearchResponse = try await Self.apiRequest("search", query: [
                                .init(name: "part", value: "snippet"), .init(name: "type", value: "video"),
                                .init(name: "q", value: search.0), .init(name: "order", value: "relevance"),
                                .init(name: "publishedAfter", value: after), .init(name: "maxResults", value: "25"),
                                .init(name: "relevanceLanguage", value: "en")
                            ], token: token, network: network, timeout: 12)
                            let items: [FreshCandidate] = result.items.prefix(25).compactMap { item in
                                guard let id = item.id.videoId, FocusPolicy.validID(id),
                                      !item.snippet.title.isEmpty, !item.snippet.channelTitle.isEmpty,
                                      FocusRecommendations.freshSearchTitleMatches(item.snippet.title, topic: search.1) else { return nil }
                                return FreshCandidate(id: id, title: String(item.snippet.title.prefix(200)),
                                    channel: String(item.snippet.channelTitle.prefix(100)), topic: search.1)
                            }
                            return (index, FreshSearchBatch(items: items, failure: nil))
                        } catch { return (index, FreshSearchBatch(items: nil, failure: Self.diagnosticCode(error))) }
                    }
                }
                var ordered = Array(repeating: FreshSearchBatch(items: nil, failure: .other), count: searches.count)
                for await (index, values) in group { ordered[index] = values }
                return ordered
            } }
            freshSearchWork = searchWork
            let results = await searchWork.value
            guard requestGeneration == generation else { return }
            freshSearchWork = nil
            let failures = results.filter { $0.items == nil }.count
            let searchFailureCode = results.compactMap(\.failure).first
            let lists = results.map { $0.items ?? [] }
            var candidates: [FreshCandidate] = []
            var candidateIndices: [String: Int] = [:]
            for offset in 0..<25 {
                for list in lists where offset < list.count {
                    let item = list[offset]
                    if let index = candidateIndices[item.id] {
                        if candidates[index].topic != item.topic && !candidates[index].additionalTopics.contains(item.topic) {
                            candidates[index].additionalTopics.append(item.topic)
                        }
                    } else {
                        candidateIndices[item.id] = candidates.count
                        candidates.append(item)
                    }
                }
            }
            let batches = stride(from: 0, to: candidates.count, by: 50).map { start in
                Array(candidates[start..<min(start + 50, candidates.count)]).map(\.id).joined(separator: ",")
            }
            let validationTime = now
            let metadataWork = Task { await withTaskGroup(of: FreshMetadataBatch.self, returning: [FreshMetadataBatch].self) { group in
                for ids in batches {
                    group.addTask {
                        do {
                            try Task.checkCancellation()
                            let result: VideosResponse = try await Self.apiRequest("videos", query: [
                                .init(name: "part", value: "contentDetails,snippet"), .init(name: "id", value: ids)
                            ], token: token, network: network, timeout: 12)
                            var dates: [String: Date] = [:]
                            for item in result.items where item.snippet.liveBroadcastContent == "none" {
                                guard (Self.durationSeconds(item.contentDetails.duration) ?? 0) > 180,
                                      let date = FocusRecommendations.publishedDate(item.snippet.publishedAt),
                                      date <= validationTime, validationTime.timeIntervalSince(date) <= 365 * 24 * 60 * 60 else { continue }
                                dates[item.id] = date
                            }
                            return FreshMetadataBatch(dates: dates, failure: nil)
                        } catch { return FreshMetadataBatch(dates: nil, failure: Self.diagnosticCode(error)) }
                    }
                }
                var values: [FreshMetadataBatch] = []
                for await value in group { values.append(value) }
                return values
            } }
            freshMetadataWork = metadataWork
            let checked = await metadataWork.value
            guard requestGeneration == generation else { return }
            freshMetadataWork = nil
            if let failure = checked.first(where: { $0.dates == nil }) {
                FocusDiagnostics.shared.record(.freshSearchFailed, code: failure.failure ?? .other)
                freshNotice = freshVideos.isEmpty ? "YouTube discovery could not be refreshed." : "YouTube discovery could not be refreshed. Showing the last saved results."
                return
            }
            var valid: [String: Date] = [:]
            for result in checked { if let dates = result.dates { valid.merge(dates) { first, _ in first } } }
            var perChannel: [String: Int] = [:]
            let found = candidates.compactMap { item -> FocusRecommendation? in
                guard let date = valid[item.id] else { return nil }
                let channel = item.channel.lowercased()
                guard (perChannel[channel] ?? 0) < 3 else { return nil }
                perChannel[channel, default: 0] += 1
                return FocusRecommendation(id: item.id, title: item.title, channel: item.channel,
                    topic: item.topic, reason: "Recent YouTube search result", publishedAt: date,
                    additionalTopics: item.additionalTopics)
            }
            guard !found.isEmpty else {
                if failures > 0 {
                    FocusDiagnostics.shared.record(.freshSearchFailed, code: searchFailureCode ?? .other)
                    freshNotice = freshVideos.isEmpty ? "YouTube discovery could not be refreshed." : "YouTube discovery could not be refreshed. Showing the last saved results."
                } else {
                    FocusDiagnostics.shared.record(.freshSearchSucceeded)
                    freshNotice = freshVideos.isEmpty ? "No recent videos matched these searches." : "No recent videos matched. Showing the last saved results."
                }
                return
            }
            let values = Array(found.prefix(60))
            let updated = now
            let cached = FreshCache(videos: values, updatedAt: updated, partial: failures > 0, queryVersion: Self.freshQueryVersion)
            if let data = try? JSONEncoder().encode(cached) { freshCacheStore.set(data, forKey: freshCacheKey) }
            freshVideos = values
            freshLastUpdated = updated
            FocusDiagnostics.shared.record(failures > 0 ? .freshSearchFailed : .freshSearchSucceeded, code: failures > 0 ? (searchFailureCode ?? .other) : nil)
            freshNotice = failures > 0 ? "Some YouTube searches could not be refreshed." : nil
        } catch {
            guard requestGeneration == generation else { return }
            FocusDiagnostics.shared.record(.freshSearchFailed, code: Self.diagnosticCode(error))
            freshNotice = freshVideos.isEmpty ? "YouTube discovery could not be refreshed." : "YouTube discovery could not be refreshed. Showing the last saved results."
        }
    }

    func signIn() async {
        guard !busy else { return }
        signInSucceeded = false
        guard let client = clientID else {
            notice = "Google sign-in is not configured for this build. An iOS OAuth client and its URL scheme are required."
            return
        }
        busy = true; notice = nil
        FocusDiagnostics.shared.record(.signInStarted)
        let requestGeneration = generation
        defer { finishOperation() }
        do {
            let verifier = try randomURLSafe(bytes: 32)
            let state = try randomURLSafe(bytes: 32)
            let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
            let scheme = client.split(separator: ".").reversed().joined(separator: ".")
            let redirect = scheme + ":/oauth2redirect"
            var url = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
            url.queryItems = [
                .init(name: "client_id", value: client), .init(name: "redirect_uri", value: redirect),
                .init(name: "response_type", value: "code"),
                .init(name: "scope", value: "https://www.googleapis.com/auth/youtube.readonly"),
                .init(name: "code_challenge", value: challenge), .init(name: "code_challenge_method", value: "S256"),
                .init(name: "state", value: state), .init(name: "access_type", value: "offline"),
                .init(name: "prompt", value: "consent")
            ]
            guard let authorizationURL = url.url else { throw Failure.invalidResponse }
            let callback = try await authenticate(url: authorizationURL, scheme: scheme)
            guard requestGeneration == generation else { return }
            guard callback.scheme?.lowercased() == scheme.lowercased(), callback.host == nil, callback.path == "/oauth2redirect",
                  let components = URLComponents(url: callback, resolvingAgainstBaseURL: false) else { throw Failure.invalidResponse }
            let items = components.queryItems ?? []
            guard items.filter({ $0.name == "state" }).count == 1,
                  items.first(where: { $0.name == "state" })?.value == state else { throw Failure.invalidResponse }
            guard items.filter({ $0.name == "code" }).count == 1,
                  let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else { throw Failure.authorization }
            let token = try await exchange(["code": code, "client_id": client, "redirect_uri": redirect,
                                            "grant_type": "authorization_code", "code_verifier": verifier])
            guard requestGeneration == generation else { return }
            if let scopes = token.scope, !scopes.split(separator: " ").contains("https://www.googleapis.com/auth/youtube.readonly") { throw Failure.authorization }
            let stored = Credentials(clientID: client, accessToken: token.access_token, refreshToken: token.refresh_token,
                                     expiresAt: Date().addingTimeInterval(max(0, token.expires_in - 60)))
            try writeCredentials(stored)
            credentials = stored; signedIn = true; syncSucceeded = false; subscriptionsComplete = false; signInSucceeded = true; lastSyncedAt = nil; clearRefreshFailure()
            FocusDiagnostics.shared.record(.signInSucceeded)
            channels = []; uploads = []; connectedChannel = nil
            let previousFresh = freshCacheStore.data(forKey: freshCacheKey).flatMap { try? JSONDecoder().decode(FreshCache.self, from: $0) }
            freshNotice = previousFresh?.partial == true ? "Some YouTube searches could not be refreshed." : nil
            notice = token.refresh_token == nil ? "Connected, but Google did not provide a refresh token. You may need to sign in again. Playback sign-in is separate." : "Connected to the YouTube Data API. Playback sign-in is separate."
        } catch {
            guard requestGeneration == generation else { return }
            FocusDiagnostics.shared.record(.signInFailed, code: Self.diagnosticCode(error))
            notice = error is ASWebAuthenticationSessionError ? "Sign-in was cancelled or could not be completed." : (error as? LocalizedError)?.errorDescription ?? "Could not connect to Google."
        }
    }

    func sync() async {
        guard !busy else { return }
        busy = true; notice = nil; syncSucceeded = false; subscriptionsComplete = false
        FocusDiagnostics.shared.record(.subscriptionSyncStarted)
        let requestGeneration = generation
        defer { finishOperation() }
        do {
            let token = try await accessToken()
            let own: OwnChannelResponse? = try? await api("channels", query: [.init(name: "part", value: "snippet"), .init(name: "mine", value: "true"), .init(name: "maxResults", value: "1")], token: token)
            guard requestGeneration == generation else { return }
            var next: String? = nil
            var all: [Channel] = []
            var seen = Set<String>()
            var pageTokens = Set<String>()
            var pages = 0
            repeat {
                pages += 1
                var query = [URLQueryItem(name: "part", value: "snippet"), .init(name: "mine", value: "true"), .init(name: "maxResults", value: "50")]
                if let next { query.append(.init(name: "pageToken", value: next)) }
                let page: SubscriptionResponse = try await api("subscriptions", query: query, token: token)
                guard requestGeneration == generation else { return }
                for item in page.items {
                    if let id = item.snippet.resourceId.channelId, Self.validChannelID(id), seen.insert(id).inserted {
                        all.append(Channel(id: id, title: String(item.snippet.title.prefix(200))))
                    }
                }
                next = page.nextPageToken
                if let next, !pageTokens.insert(next).inserted { throw Failure.invalidResponse }
            } while next != nil && all.count < 1000 && pages < 20
            guard requestGeneration == generation else { return }
            channels = all
            connectedChannel = own?.items.first.map { String($0.snippet.title.prefix(200)) }
            subscriptionsComplete = next == nil
            syncSucceeded = true; lastSyncedAt = now
            subscriptionSyncRevision += 1
            FocusDiagnostics.shared.record(.subscriptionSyncSucceeded)
            notice = next == nil ? "Subscriptions updated. Choose channels to load recent uploads." : "Showing the first 1,000 subscriptions."
        } catch { if requestGeneration == generation { FocusDiagnostics.shared.record(.subscriptionSyncFailed, code: Self.diagnosticCode(error)); recordRefreshFailure(); notice = (error as? LocalizedError)?.errorDescription ?? "Could not load subscriptions." } }
    }

    // Returning to the app repeatedly should not consume API quota each time.
    func syncIfNeeded() async -> Bool {
        guard signedIn, !busy else { return false }
        if let date = lastRefreshFailureAt {
            let delay = min(30 * 60, 5 * 60 * (1 << max(0, consecutiveRefreshFailures - 1)))
            if now.timeIntervalSince(date) < TimeInterval(delay) { return false }
        } else if let date = lastSyncedAt, now.timeIntervalSince(date) < 30 * 60 { return false }
        await sync()
        return syncSucceeded
    }

    // Keep stale IDs until the entire subscription list is known. Partial
    // results and errors cannot establish that a channel was unsubscribed.
    static func retainedSelectedIDs(_ ids: Set<String>, channels: [Channel], complete: Bool) -> Set<String> {
        guard complete else { return ids }
        return ids.intersection(Set(channels.map(\.id)))
    }

    /// Release the serialized account operation and, if necessary, load the latest
    /// selection. The deferred task rechecks state so sign-out and newer choices win.
    private func finishOperation() {
        busy = false
        guard pendingUploadSelection != nil else { return }
        Task { [weak self] in
            guard let self, self.signedIn, !self.busy, let selected = self.pendingUploadSelection else { return }
            self.pendingUploadSelection = nil
            await self.loadUploads(for: selected)
        }
    }

    /// Explicit selection bounds requests and avoids presenting every subscription as a recommendation.
    func loadUploads(for selected: [Channel]) async {
        guard signedIn else { return }
        guard !selected.isEmpty else { clearUploads(); notice = "Choose at least one channel."; return }
        guard !busy else {
            uploadsGeneration += 1
            pendingUploadSelection = selected
            notice = "Selected channels will load after the current account request."
            return
        }
        pendingUploadSelection = nil
        busy = true; notice = nil
        FocusDiagnostics.shared.record(.uploadLoadStarted)
        let requestGeneration = generation
        let currentUploadsGeneration = uploadsGeneration
        defer { finishOperation() }
        do {
            let token = try await accessToken()
            let unique = Array(Set(selected.map(\.id))).filter(Self.validChannelID).sorted()
            let ids = Array(unique.prefix(30))
            guard !ids.isEmpty else { throw Failure.invalidResponse }
            let response: ChannelsResponse = try await api("channels", query: [.init(name: "part", value: "contentDetails"), .init(name: "id", value: ids.joined(separator: ",")), .init(name: "maxResults", value: "50")], token: token)
            guard requestGeneration == generation, currentUploadsGeneration == uploadsGeneration else { return }
            let playlistIDs = response.items.compactMap { $0.contentDetails.relatedPlaylists.uploads }
            var candidates: [Candidate] = []
            var failed = 0
            // Bounded batches avoid opening dozens of simultaneous connections.
            for start in stride(from: 0, to: playlistIDs.count, by: 5) {
                let batch = Array(playlistIDs[start..<min(start + 5, playlistIDs.count)])
                let session = network
                let results = await withTaskGroup(of: [Candidate]?.self, returning: [[Candidate]?].self) { group in
                    for playlist in batch {
                        group.addTask { await Self.playlistCandidates(playlist, token: token, network: session) }
                    }
                    var values: [[Candidate]?] = []
                    for await value in group { values.append(value) }
                    return values
                }
                guard requestGeneration == generation, currentUploadsGeneration == uploadsGeneration else { return }
                for result in results { if let result { candidates.append(contentsOf: result) } else { failed += 1 } }
            }
            candidates.sort { $0.publishedAt > $1.publishedAt }
            let first = Array(candidates.prefix(600))
            var durations: [String: Int] = [:]
            var publicationDates: [String: Date] = [:]
            for start in stride(from: 0, to: first.count, by: 50) {
                let batch = first[start..<min(start + 50, first.count)]
                let details: VideosResponse = try await api("videos", query: [.init(name: "part", value: "contentDetails,snippet"), .init(name: "id", value: batch.map(\.id).joined(separator: ","))], token: token)
                guard requestGeneration == generation, currentUploadsGeneration == uploadsGeneration else { return }
                for item in details.items where item.snippet.liveBroadcastContent == "none" {
                    durations[item.id] = Self.durationSeconds(item.contentDetails.duration)
                    publicationDates[item.id] = FocusRecommendations.publishedDate(item.snippet.publishedAt)
                }
            }
            var seen = Set<String>()
            guard requestGeneration == generation, currentUploadsGeneration == uploadsGeneration else { return }
            let published = first.compactMap { candidate -> Upload? in
                guard (durations[candidate.id] ?? 0) > 180, seen.insert(candidate.id).inserted else { return nil }
                return Upload(id: candidate.id, title: candidate.title, channel: candidate.channel, publishedAt: publicationDates[candidate.id])
            }
            uploads = Array(FocusRecommendations.sortByPublication(published, order: .newest, date: { $0.publishedAt }).prefix(60))
            FocusDiagnostics.shared.record(failed > 0 ? .uploadLoadFailed : .uploadLoadSucceeded)
            if failed > 0 { recordRefreshFailure() } else { clearRefreshFailure() }
            notice = unique.count > 30 ? "Showing uploads from the first 30 selected channels." : (failed > 0 ? "Some channels could not be refreshed." : (uploads.isEmpty ? "No eligible recent videos were found." : nil))
        } catch { if requestGeneration == generation, currentUploadsGeneration == uploadsGeneration { FocusDiagnostics.shared.record(.uploadLoadFailed, code: Self.diagnosticCode(error)); recordRefreshFailure(); notice = (error as? LocalizedError)?.errorDescription ?? "Could not load uploads." } }
    }

    func clearUploads() {
        uploadsGeneration += 1
        pendingUploadSelection = nil
        uploads = []
        clearRefreshFailure()
    }

    func signOut() {
        generation += 1
        pendingUploadSelection = nil
        session?.cancel(); session = nil
        freshSearchWork?.cancel(); freshSearchWork = nil
        freshMetadataWork?.cancel(); freshMetadataWork = nil
        credentials = nil; signedIn = false; syncSucceeded = false; subscriptionsComplete = false; signInSucceeded = false; connectedChannel = nil; channels = []; uploads = []; lastSyncedAt = nil; clearRefreshFailure()
        freshVideos = []; freshLastUpdated = nil; freshNotice = nil
        freshCacheStore.removeObject(forKey: freshCacheKey)
        freshCacheStore.removeObject(forKey: freshAttemptKey)
        freshCacheStore.removeObject(forKey: freshAttemptQueryVersionKey)
        deleteCredentials()
        notice = "Local API credentials removed. Playback sign-in is separate."
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: { $0.isKeyWindow }) ?? ASPresentationAnchor()
    }

    private func authenticate(url: URL, scheme: String) async throws -> URL {
        #if FOCUS_ACCOUNT_TESTING
        if let hook = testHooks?.authenticate { return try await hook(url, scheme) }
        #endif
        return try await withCheckedThrowingContinuation { continuation in
            let auth = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { [weak self] url, error in
                Task { @MainActor in
                    self?.session = nil
                    if let error { continuation.resume(throwing: error) }
                    else if let url { continuation.resume(returning: url) }
                    else { continuation.resume(throwing: Failure.invalidResponse) }
                }
            }
            auth.presentationContextProvider = self
            session = auth
            if !auth.start() { session = nil; continuation.resume(throwing: Failure.authorization) }
        }
    }
    private func randomURLSafe(bytes: Int) throws -> String {
        var bytesArray = [UInt8](repeating: 0, count: bytes)
        guard SecRandomCopyBytes(kSecRandomDefault, bytesArray.count, &bytesArray) == errSecSuccess else { throw Failure.security }
        return Data(bytesArray).base64URL
    }
    private func accessToken() async throws -> String {
        guard let current = credentials else { throw Failure.notSignedIn }
        if current.expiresAt > Date() { return current.accessToken }
        guard let refresh = current.refreshToken, let client = clientID else { throw Failure.notSignedIn }
        let requestGeneration = generation
        let updated = try await exchange(["refresh_token": refresh, "client_id": client, "grant_type": "refresh_token"])
        guard requestGeneration == generation else { throw Failure.notSignedIn }
        let stored = Credentials(clientID: client, accessToken: updated.access_token, refreshToken: updated.refresh_token ?? refresh,
                                 expiresAt: Date().addingTimeInterval(max(0, updated.expires_in - 60)))
        try writeCredentials(stored); credentials = stored
        return stored.accessToken
    }
    private func exchange(_ fields: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        guard let body = FocusOAuthForm.encode(fields) else { throw Failure.invalidResponse }
        request.httpBody = body
        #if FOCUS_ACCOUNT_TESTING
        testHooks?.observeTokenRequest(request)
        #endif
        let (data, response) = try await network.data(for: request)
        guard let response = response as? HTTPURLResponse, data.count < 100_000 else { throw Failure.authorization }
        guard (200..<300).contains(response.statusCode) else { throw Self.httpFailure(response.statusCode, fallback: .authorization) }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }
    private func api<T: Decodable>(_ path: String, query: [URLQueryItem], token: String) async throws -> T {
        try await Self.apiRequest(path, query: query, token: token, network: network)
    }
    nonisolated private static func apiRequest<T: Decodable>(_ path: String, query: [URLQueryItem], token: String, network: URLSession, timeout: TimeInterval? = nil) async throws -> T {
        guard ["subscriptions", "channels", "playlistItems", "videos", "search"].contains(path) else { throw Failure.invalidResponse }
        var url = URLComponents(string: "https://www.googleapis.com/youtube/v3/" + path)!
        url.queryItems = query
        guard let target = url.url else { throw Failure.invalidResponse }
        var request = URLRequest(url: target)
        if let timeout { request.timeoutInterval = timeout }
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        let (data, response) = try await network.data(for: request)
        guard let response = response as? HTTPURLResponse, data.count < 2_000_000 else { throw Failure.api }
        guard (200..<300).contains(response.statusCode) else { throw Self.httpFailure(response.statusCode, fallback: .api) }
        return try JSONDecoder().decode(T.self, from: data)
    }
    nonisolated private static func playlistCandidates(_ playlist: String, token: String, network: URLSession) async -> [Candidate]? {
        do {
            let result: PlaylistResponse = try await apiRequest("playlistItems", query: [.init(name: "part", value: "snippet"), .init(name: "playlistId", value: playlist), .init(name: "maxResults", value: "20")], token: token, network: network)
            let formatter = ISO8601DateFormatter()
            let fractionalFormatter = ISO8601DateFormatter()
            fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return result.items.compactMap { item in
                guard let id = item.snippet.resourceId.videoId, FocusPolicy.validID(id),
                      let date = formatter.date(from: item.snippet.publishedAt) ?? fractionalFormatter.date(from: item.snippet.publishedAt), !item.snippet.title.isEmpty else { return nil }
                return Candidate(id: id, title: String(item.snippet.title.prefix(200)), channel: String(item.snippet.channelTitle.prefix(100)), publishedAt: date)
            }
        } catch { return nil }
    }
    nonisolated private static func validChannelID(_ id: String) -> Bool {
        id.range(of: #"^UC[A-Za-z0-9_-]{22}$"#, options: .regularExpression) != nil
    }
    nonisolated static func durationSeconds(_ value: String) -> Int? {
        FocusDuration.seconds(value)
    }
    private func readCredentials() throws -> Credentials? {
        #if FOCUS_ACCOUNT_TESTING
        if let hook = testHooks?.read {
            guard let data = try hook() else { return nil }
            return try JSONDecoder().decode(Credentials.self, from: data)
        }
        #endif
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: "oauth", kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw Failure.security }
        return try JSONDecoder().decode(Credentials.self, from: data)
    }
    private func writeCredentials(_ value: Credentials) throws {
        let data = try JSONEncoder().encode(value)
        #if FOCUS_ACCOUNT_TESTING
        if let hook = testHooks?.write { try hook(data); return }
        #endif
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "oauth"]
        let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query; for (key, value) in attributes { item[key] = value }
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw Failure.security }
        } else if status != errSecSuccess { throw Failure.security }
    }
    private func deleteCredentials() {
        #if FOCUS_ACCOUNT_TESTING
        if let hook = testHooks?.delete { hook(); return }
        #endif
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "oauth"] as CFDictionary)
    }
    private enum Failure: LocalizedError {
        case invalidResponse, authorization, notSignedIn, api, security
        case http400, http401, http403, http429, http5xx
        var errorDescription: String? {
            switch self {
            case .invalidResponse: return "The authorization response was invalid."
            case .authorization: return "Google authorization failed. Check the OAuth configuration or sign in again."
            case .notSignedIn: return "Sign in to your YouTube account first."
            case .api: return "YouTube could not load the requested data. Check access and try again."
            case .security: return "Could not store credentials securely on this device."
            case .http400: return "Google rejected the request. Check the app configuration or reconnect your account."
            case .http401: return "Google could not verify this session. Try signing in again."
            case .http403: return "Google denied access. Check account permissions and the API quota."
            case .http429: return "Google is limiting requests. Try again later."
            case .http5xx: return "Google's service is temporarily unavailable. Try again later."
            }
        }
    }

    // Only fixed status classes cross the network/diagnostics boundary. The
    // response body, request URL, headers, and any raw error remain private.
    nonisolated private static func httpFailure(_ status: Int, fallback: Failure) -> Failure {
        switch status {
        case 400: return .http400
        case 401: return .http401
        case 403: return .http403
        case 429: return .http429
        case 500...599: return .http5xx
        default: return fallback
        }
    }

    // Convert known failures into a small closed vocabulary; never persist the
    // original error, description, response, URL, account identifier or token.
    nonisolated private static func diagnosticCode(_ error: Error) -> FocusDiagnosticCode {
        if let failure = error as? Failure {
            switch failure {
            case .authorization: return .authorization
            case .invalidResponse: return .invalidResponse
            case .notSignedIn: return .notSignedIn
            case .api: return .api
            case .security: return .security
            case .http400: return .http400
            case .http401: return .http401
            case .http403: return .http403
            case .http429: return .http429
            case .http5xx: return .http5xx
            }
        }
        let issue = error as NSError
        if issue.domain == NSURLErrorDomain {
            switch issue.code {
            case NSURLErrorTimedOut: return .timeout
            case NSURLErrorNotConnectedToInternet: return .offline
            case NSURLErrorNetworkConnectionLost, NSURLErrorCannotConnectToHost,
                 NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed: return .network
            default: break
            }
        }
        return .other
    }
}

private extension Data {
    var base64URL: String { base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
}

final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
