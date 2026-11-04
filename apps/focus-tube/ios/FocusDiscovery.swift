import Foundation
import Combine

// The public HackerTube endpoints are best-effort and may change independently.
// No YouTube account credentials or cookies are sent to this service.
@MainActor
final class FocusDiscovery: ObservableObject {
    @Published private(set) var videos: [FocusRecommendation] = []
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var loading = false
    @Published private(set) var notice: String?
    private let cacheKey = "focus.discovery.v1"
    private static let offlineHint = "Offline videos have no publication dates. Choose Any age in recommendation preferences to include them."
    private var lastAttempt: Date?
    private var partial = false

    init() {
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let cache = try? JSONDecoder().decode(FocusDiscoveryCache.self, from: data) {
            let safe = cache.videos.filter { FocusPolicy.validID($0.id) && FocusRecommendations.topics.contains($0.topic) }
            videos = Array(safe.prefix(96))
            lastUpdated = cache.date
            partial = cache.partial ?? false
            lastAttempt = cache.lastAttempt ?? cache.date
            if partial {
                notice = videos.isEmpty && lastUpdated == nil
                    ? "Some sources could not be refreshed. " + Self.offlineHint
                    : "Some sources could not be refreshed. Earlier results may still be shown."
            }
        }
    }

    func refreshIfNeeded() async {
        guard FocusRecommendations.needsDiscoveryRefresh(lastUpdated: lastUpdated, lastAttempt: lastAttempt, partial: partial, now: Date()) else { return }
        await refresh()
    }

    func refresh() async {
        guard !loading else { return }
        FocusDiagnostics.shared.record(.recommendationsStarted)
        loading = true
        notice = nil
        let sources = [
            Source(area: "ai-data", topic: "AI & ML"),
            Source(area: "math-theory", topic: "Science & math"),
            Source(area: "software", topic: "Computing"),
            Source(area: "business-economics", topic: "Startups & economics"),
            Source(area: "ai-data", topic: "AI & ML", sort: "date"),
            Source(area: "math-theory", topic: "Science & math", sort: "date"),
            Source(area: "software", topic: "Computing", sort: "date"),
            Source(area: "business-economics", topic: "Startups & economics", sort: "date"),
            Source(query: "Google DeepMind", topic: "AI & ML"),
            Source(query: "Veritasium", topic: "Science & math"),
            Source(query: "Computerphile", topic: "Computing"),
            Source(query: "Patrick Boyle", topic: "Startups & economics")
        ]
        let lists = await withTaskGroup(of: (Int, [FocusRecommendation]?).self, returning: [[FocusRecommendation]?].self) { group in
            for (index, source) in sources.enumerated() {
                group.addTask { (index, await Self.fetch(source)) }
            }
            var received = Array<[FocusRecommendation]?>(repeating: nil, count: sources.count)
            for await (index, items) in group { received[index] = items }
            return received
        }
        // Keep a mix across areas and preset channel searches, instead of letting
        // the fastest response fill the entire finite list.
        var perSource = Array(repeating: [FocusRecommendation](), count: sources.count)
        for offset in 0..<8 {
            for (index, list) in lists.enumerated() {
                if let list, offset < list.count { perSource[index].append(list[offset]) }
            }
        }
        let outcomes = sources.indices.map { index in
            FocusDiscoveryResult(topic: sources[index].topic, videos: lists[index].map { _ in perSource[index] })
        }
        let merged = FocusRecommendations.mergeDiscovery(outcomes, previous: videos)
        partial = merged.partial
        lastAttempt = Date()
        videos = merged.videos
        if lists.allSatisfy({ if case .none = $0 { return true }; return false }) {
            FocusDiagnostics.shared.record(.recommendationsFailed)
            notice = videos.isEmpty ? (lastUpdated == nil ? "Could not refresh. " + Self.offlineHint : "Could not refresh. No HackerTube videos are saved.") : "Could not refresh. Showing the last saved selection."
        } else if partial {
            FocusDiagnostics.shared.record(.recommendationsPartial, count: videos.count)
            notice = videos.isEmpty && lastUpdated == nil
                ? "Some sources could not be refreshed. " + Self.offlineHint
                : "Some sources could not be refreshed. Earlier results may still be shown."
        } else {
            lastUpdated = Date()
            FocusDiagnostics.shared.record(.recommendationsSucceeded, count: videos.count)
            notice = videos.isEmpty ? "No HackerTube videos were found." : nil
        }
        if let data = try? JSONEncoder().encode(FocusDiscoveryCache(videos: videos, date: lastUpdated, partial: partial, lastAttempt: lastAttempt)) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
        loading = false
    }

    private struct Source: Sendable {
        let area: String?
        let query: String?
        let topic: String
        let sort: String
        init(area: String, topic: String, sort: String = "recent") { self.area = area; self.query = nil; self.topic = topic; self.sort = sort }
        init(query: String, topic: String) { self.area = nil; self.query = query; self.topic = topic; self.sort = "recent" }
    }
    private struct Video: Decodable {
        struct HackerNews: Decodable { let recommenders: Int? }
        let vid: String
        let title: String
        let channel: String
        let duration_s: Int?
        let published: String?
        let shelf_life: String?
        let hn: HackerNews?
    }
    private struct SearchResponse: Decodable { let results: [Video] }

    nonisolated private static func fetch(_ source: Source) async -> [FocusRecommendation]? {
        var components = URLComponents(string: source.area == nil ? "https://hackertube.org/api/search" : "https://hackertube.org/api/list")!
        if let area = source.area {
            components.queryItems = [URLQueryItem(name: "area", value: area), URLQueryItem(name: "sort", value: source.sort), URLQueryItem(name: "offset", value: "0"), URLQueryItem(name: "n", value: "12")]
        } else if let query = source.query {
            components.queryItems = [URLQueryItem(name: "q", value: query)]
        }
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), data.count <= 2_000_000 else { return nil }
            let decoder = JSONDecoder()
            let entries: [Video]
            if source.query != nil { entries = try decoder.decode(SearchResponse.self, from: data).results }
            else { entries = try decoder.decode([Video].self, from: data) }
            return entries.prefix(30).compactMap { video in
                guard FocusPolicy.validID(video.vid), let duration = video.duration_s, duration > 180,
                      !video.title.isEmpty, !video.channel.isEmpty,
                      source.query == nil || video.channel.caseInsensitiveCompare(source.query!) == .orderedSame else { return nil }
                let recommenders = video.hn?.recommenders
                return FocusRecommendation(id: video.vid, title: String(video.title.prefix(200)), channel: String(video.channel.prefix(100)), topic: source.topic,
                    reason: source.query == nil ? "Listed on HackerTube" : "From a preset channel", publishedAt: FocusRecommendations.publishedDate(video.published),
                    shelfLife: ["evergreen", "dated", "news"].contains(video.shelf_life ?? "") ? video.shelf_life : nil,
                    hnRecommenders: recommenders.flatMap { $0 >= 0 ? min($0, 100_000) : nil })
            }
        } catch { return nil }
    }
}
