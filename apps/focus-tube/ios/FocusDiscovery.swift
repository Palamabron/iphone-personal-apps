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
    private let refreshInterval: TimeInterval = 30 * 60

    private struct Cache: Codable {
        let videos: [FocusRecommendation]
        let date: Date
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let cache = try? JSONDecoder().decode(Cache.self, from: data) {
            let safe = cache.videos.filter { FocusPolicy.validID($0.id) && FocusRecommendations.topics.contains($0.topic) }
            if !safe.isEmpty { videos = Array(safe.prefix(32)); lastUpdated = cache.date }
        }
    }

    func refreshIfNeeded() async {
        if let date = lastUpdated, Date().timeIntervalSince(date) < refreshInterval { return }
        await refresh()
    }

    func refresh() async {
        guard !loading else { return }
        loading = true
        notice = nil
        let sources = [
            Source(area: "ai-data", topic: "AI & ML"),
            Source(area: "math-theory", topic: "Science & math"),
            Source(area: "software", topic: "Computing"),
            Source(area: "business-economics", topic: "Startups & economics"),
            Source(query: "Google DeepMind", topic: "AI & ML"),
            Source(query: "Veritasium", topic: "Science & math"),
            Source(query: "Computerphile", topic: "Computing"),
            Source(query: "Patrick Boyle", topic: "Startups & economics")
        ]
        let lists = await withTaskGroup(of: (Int, [FocusRecommendation]).self, returning: [[FocusRecommendation]].self) { group in
            for (index, source) in sources.enumerated() {
                group.addTask { (index, await Self.fetch(source)) }
            }
            var received = Array(repeating: [FocusRecommendation](), count: sources.count)
            for await (index, items) in group { received[index] = items }
            return received
        }
        // Keep a mix across areas and preset channel searches, instead of letting
        // the fastest response fill the entire finite list.
        var merged: [FocusRecommendation] = []
        var seen = Set<String>()
        for offset in 0..<8 {
            for list in lists where offset < list.count {
                let item = list[offset]
                if seen.insert(item.id).inserted { merged.append(item) }
            }
        }
        if merged.isEmpty {
            notice = videos.isEmpty ? "Could not refresh. Showing the offline selection." : "Could not refresh. Showing the last saved selection."
        } else {
            videos = Array(merged.prefix(32))
            lastUpdated = Date()
            if lists.contains(where: { $0.isEmpty }) { notice = "Some sources did not return results." }
            if let data = try? JSONEncoder().encode(Cache(videos: videos, date: lastUpdated!)) {
                UserDefaults.standard.set(data, forKey: cacheKey)
            }
        }
        loading = false
    }

    private struct Source: Sendable {
        let area: String?
        let query: String?
        let topic: String
        init(area: String, topic: String) { self.area = area; self.query = nil; self.topic = topic }
        init(query: String, topic: String) { self.area = nil; self.query = query; self.topic = topic }
    }
    private struct Video: Decodable {
        let vid: String
        let title: String
        let channel: String
        let duration_s: Int?
    }
    private struct SearchResponse: Decodable { let results: [Video] }

    nonisolated private static func fetch(_ source: Source) async -> [FocusRecommendation] {
        var components = URLComponents(string: source.area == nil ? "https://hackertube.org/api/search" : "https://hackertube.org/api/list")!
        if let area = source.area {
            components.queryItems = [URLQueryItem(name: "area", value: area), URLQueryItem(name: "sort", value: "recent"), URLQueryItem(name: "offset", value: "0"), URLQueryItem(name: "n", value: "12")]
        } else if let query = source.query {
            components.queryItems = [URLQueryItem(name: "q", value: query)]
        }
        guard let url = components.url else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), data.count <= 2_000_000 else { return [] }
            let decoder = JSONDecoder()
            let entries: [Video]
            if source.query != nil { entries = try decoder.decode(SearchResponse.self, from: data).results }
            else { entries = try decoder.decode([Video].self, from: data) }
            return entries.prefix(30).compactMap { video in
                guard FocusPolicy.validID(video.vid), let duration = video.duration_s, duration > 180,
                      !video.title.isEmpty, !video.channel.isEmpty,
                      source.query == nil || video.channel.caseInsensitiveCompare(source.query!) == .orderedSame else { return nil }
                return FocusRecommendation(id: video.vid, title: String(video.title.prefix(200)), channel: String(video.channel.prefix(100)), topic: source.topic,
                    reason: source.query == nil ? "Recommended on Hacker News" : "From a selected channel")
            }
        } catch { return [] }
    }
}
