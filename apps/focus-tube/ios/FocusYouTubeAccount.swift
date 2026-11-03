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
        let publishedAt: Date
    }
    @Published private(set) var channels: [Channel] = []
    @Published private(set) var connectedChannel: String?
    @Published private(set) var uploads: [Upload] = []
    @Published private(set) var signedIn = false
    @Published private(set) var busy = false
    @Published private(set) var syncSucceeded = false
    @Published private(set) var signInSucceeded = false
    @Published private(set) var notice: String?

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
            struct Snippet: Decodable { let liveBroadcastContent: String? }
            let id: String
            let contentDetails: Content
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
    private let service = "dev.palamabron.focustube.google-api"
    private var session: ASWebAuthenticationSession?
    private var credentials: Credentials?
    private var generation = 0
    private var uploadsGeneration = 0
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
    }
    #if FOCUS_ACCOUNT_TESTING
    init(testHooks: FocusAccountTestHooks) {
        self.testHooks = testHooks
        super.init()
        restoreCredentials()
    }
    #endif
    private func restoreCredentials() {
        if let client = clientID, let stored = try? readCredentials(), stored.clientID == client {
            credentials = stored
            signedIn = true
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
        let requestGeneration = generation
        defer { busy = false }
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
            credentials = stored; signedIn = true; syncSucceeded = false; signInSucceeded = true
            channels = []; uploads = []; connectedChannel = nil
            notice = token.refresh_token == nil ? "Connected, but Google did not provide a refresh token. You may need to sign in again. Playback sign-in is separate." : "Connected to the YouTube Data API. Playback sign-in is separate."
        } catch {
            guard requestGeneration == generation else { return }
            notice = error is ASWebAuthenticationSessionError ? "Sign-in was cancelled or could not be completed." : (error as? LocalizedError)?.errorDescription ?? "Could not connect to Google."
        }
    }

    func sync() async {
        guard !busy else { return }
        busy = true; notice = nil; syncSucceeded = false
        let requestGeneration = generation
        defer { busy = false }
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
            syncSucceeded = true
            notice = next == nil ? "Subscriptions updated. Choose channels to load recent uploads." : "Showing the first 1,000 subscriptions."
        } catch { if requestGeneration == generation { notice = (error as? LocalizedError)?.errorDescription ?? "Could not load subscriptions." } }
    }

    /// Explicit selection bounds requests and avoids presenting every subscription as a recommendation.
    func loadUploads(for selected: [Channel]) async {
        guard !busy else { return }
        guard !selected.isEmpty else { notice = "Choose at least one channel."; return }
        busy = true; notice = nil
        let requestGeneration = generation
        let currentUploadsGeneration = uploadsGeneration
        defer { busy = false }
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
            let first = Array(candidates.prefix(150))
            var durations: [String: Int] = [:]
            for start in stride(from: 0, to: first.count, by: 50) {
                let batch = first[start..<min(start + 50, first.count)]
                let details: VideosResponse = try await api("videos", query: [.init(name: "part", value: "contentDetails,snippet"), .init(name: "id", value: batch.map(\.id).joined(separator: ",")), .init(name: "maxResults", value: "50")], token: token)
                guard requestGeneration == generation, currentUploadsGeneration == uploadsGeneration else { return }
                for item in details.items where item.snippet.liveBroadcastContent == "none" {
                    durations[item.id] = Self.durationSeconds(item.contentDetails.duration)
                }
            }
            var seen = Set<String>()
            guard requestGeneration == generation, currentUploadsGeneration == uploadsGeneration else { return }
            uploads = first.compactMap { candidate in
                guard (durations[candidate.id] ?? 0) > 180, seen.insert(candidate.id).inserted else { return nil }
                return Upload(id: candidate.id, title: candidate.title, channel: candidate.channel, publishedAt: candidate.publishedAt)
            }
            notice = unique.count > 30 ? "Showing uploads from the first 30 selected channels." : (failed > 0 ? "Some channels could not be refreshed." : (uploads.isEmpty ? "No eligible recent videos were found." : nil))
        } catch { if requestGeneration == generation, currentUploadsGeneration == uploadsGeneration { notice = (error as? LocalizedError)?.errorDescription ?? "Could not load uploads." } }
    }

    func clearUploads() {
        uploadsGeneration += 1
        uploads = []
    }

    func signOut() {
        generation += 1
        session?.cancel(); session = nil
        credentials = nil; signedIn = false; syncSucceeded = false; signInSucceeded = false; connectedChannel = nil; channels = []; uploads = []
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
        let (data, response) = try await network.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode), data.count < 100_000 else { throw Failure.authorization }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }
    private func api<T: Decodable>(_ path: String, query: [URLQueryItem], token: String) async throws -> T {
        try await Self.apiRequest(path, query: query, token: token, network: network)
    }
    nonisolated private static func apiRequest<T: Decodable>(_ path: String, query: [URLQueryItem], token: String, network: URLSession) async throws -> T {
        guard ["subscriptions", "channels", "playlistItems", "videos"].contains(path) else { throw Failure.invalidResponse }
        var url = URLComponents(string: "https://www.googleapis.com/youtube/v3/" + path)!
        url.queryItems = query
        guard let target = url.url else { throw Failure.invalidResponse }
        var request = URLRequest(url: target)
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        let (data, response) = try await network.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode), data.count < 2_000_000 else { throw Failure.api }
        return try JSONDecoder().decode(T.self, from: data)
    }
    nonisolated private static func playlistCandidates(_ playlist: String, token: String, network: URLSession) async -> [Candidate]? {
        do {
            let result: PlaylistResponse = try await apiRequest("playlistItems", query: [.init(name: "part", value: "snippet"), .init(name: "playlistId", value: playlist), .init(name: "maxResults", value: "5")], token: token, network: network)
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
        var errorDescription: String? {
            switch self {
            case .invalidResponse: return "The authorization response was invalid."
            case .authorization: return "Google authorization failed. Check the OAuth configuration or sign in again."
            case .notSignedIn: return "Sign in to your YouTube account first."
            case .api: return "YouTube could not load the requested data. Check access and try again."
            case .security: return "Could not store credentials securely on this device."
            }
        }
    }
}

private extension Data {
    var base64URL: String { base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
}

final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
