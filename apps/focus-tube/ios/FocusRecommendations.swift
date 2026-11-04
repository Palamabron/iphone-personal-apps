import Foundation

// A small, offline selection from HackerTube's 2026-10-31 export. HackerTube
// data is licensed ODC-By 1.0 and based on open-index/hacker-news.
// https://hackertube.org/data
// https://huggingface.co/datasets/open-index/hacker-news
// https://opendatacommons.org/licenses/by/1-0/
struct FocusRecommendation: Identifiable, Codable {
    let id: String
    let title: String
    let channel: String
    let topic: String
    var reason: String
    var publishedAt: Date? = nil
    // HackerTube's own classification and count, when supplied by that source.
    // Neither is a guarantee of video quality or present-day accuracy.
    var shelfLife: String? = nil
    var hnRecommenders: Int? = nil

    var url: URL { URL(string: "https://m.youtube.com/watch?v=" + id)! }
}

// All feedback remains on this device. Keys are normalized before matching.
struct FocusRankingPreferences: Codable, Equatable {
    var channels: [String: Int] = [:]
    var topics: [String: Int] = [:]
    var hiddenIDs: Set<String> = []
    // nil has no hard age cutoff; the ranking still favors recent videos.
    var maxAgeMonths: Int? = 24

    private enum CodingKeys: String, CodingKey { case channels, topics, hiddenIDs, maxAgeMonths }

    init(channels: [String: Int] = [:], topics: [String: Int] = [:], hiddenIDs: Set<String> = [], maxAgeMonths: Int? = 24) {
        self.channels = channels; self.topics = topics; self.hiddenIDs = hiddenIDs; self.maxAgeMonths = maxAgeMonths
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        channels = try values.decodeIfPresent([String: Int].self, forKey: .channels) ?? [:]
        topics = try values.decodeIfPresent([String: Int].self, forKey: .topics) ?? [:]
        hiddenIDs = try values.decodeIfPresent(Set<String>.self, forKey: .hiddenIDs) ?? []
        // An older stored object without this key adopts the new default.
        // Explicit null is reserved for the user's "Any age" choice.
        if values.contains(.maxAgeMonths) { maxAgeMonths = try values.decodeIfPresent(Int.self, forKey: .maxAgeMonths) }
        else { maxAgeMonths = 24 }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(channels, forKey: .channels)
        try values.encode(topics, forKey: .topics)
        try values.encode(hiddenIDs, forKey: .hiddenIDs)
        if let maxAgeMonths { try values.encode(maxAgeMonths, forKey: .maxAgeMonths) }
        else { try values.encodeNil(forKey: .maxAgeMonths) }
    }

    mutating func moreLike(_ video: FocusRecommendation) {
        let key = FocusRecommendations.channelNameKey(video.channel)
        if !key.isEmpty { channels[key] = min(3, max(0, channels[key] ?? 0) + 1) }
        if FocusRecommendations.topics.contains(video.topic) {
            topics[video.topic] = min(3, max(0, topics[video.topic] ?? 0) + 1)
        }
    }

    mutating func hide(_ video: FocusRecommendation) { hiddenIDs.insert(video.id) }
    mutating func unhideAll() { hiddenIDs.removeAll() }
}

struct FocusChannel: Identifiable {
    let name: String
    let topic: String
    var id: String { name }
    // These shortcuts search YouTube; they are not a synchronized subscription list.
    var query: String { name }
}

enum FocusRecommendations {
    static let topics = ["AI & ML", "Science & math", "Computing", "Startups & economics"]

    enum Order: String, CaseIterable, Identifiable {
        case recommended = "Recommended", newest = "Newest", oldest = "Oldest"
        var id: String { rawValue }
    }

    static func publishedDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }

    // Unknown dates always remain at the end, with stable ordering for ties.
    static func sortByPublication<T>(_ values: [T], order: Order, date: (T) -> Date?) -> [T] {
        guard order != .recommended else { return values }
        return values.enumerated().sorted { left, right in
            switch (date(left.element), date(right.element)) {
            case let (a?, b?):
                return a == b ? left.offset < right.offset : (order == .newest ? a > b : a < b)
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return left.offset < right.offset
            }
        }.map(\.element)
    }

    // HackerTube results contain display names, not verified YouTube channel IDs.
    // Ranking is a local heuristic, not a guarantee of quality or accuracy.
    static func prioritize(_ videos: [FocusRecommendation], selectedChannelNames: [String], preferences: FocusRankingPreferences = .init(), now: Date = Date()) -> [FocusRecommendation] {
        let names = Set(selectedChannelNames.map(channelNameKey).filter { !$0.isEmpty })
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let cutoff = preferences.maxAgeMonths.flatMap { calendar.date(byAdding: .month, value: -min(120, max(1, $0)), to: now) }
        let candidates = videos.enumerated().compactMap { index, original -> (Int, Int, FocusRecommendation)? in
            guard !preferences.hiddenIDs.contains(original.id) else { return nil }
            // A future date is not evidence of freshness. With a hard age limit,
            // exclude unknown or implausibly future-dated items as well.
            let validDate = original.publishedAt.flatMap { $0 <= now.addingTimeInterval(86400) ? $0 : nil }
            if let cutoff { guard let validDate, validDate >= cutoff else { return nil } }
            let ageDays = validDate.map { max(0, now.timeIntervalSince($0) / 86400) }
            let freshness: Int
            switch ageDays {
            case let days? where days <= 30: freshness = 100
            case let days? where days <= 90: freshness = 80
            case let days? where days <= 180: freshness = 60
            case let days? where days <= 365: freshness = 40
            case let days? where days <= 730: freshness = 15
            case .some(_): freshness = -10
            case nil: freshness = -30
            }
            let key = channelNameKey(original.channel)
            let selected = names.contains(key)
            let channelWeight = min(3, max(0, preferences.channels[key] ?? 0))
            let topicWeight = min(3, max(0, preferences.topics[original.topic] ?? 0))
            let recommenders = min(5, max(0, original.hnRecommenders ?? 0))
            let evergreen = original.shelfLife?.lowercased() == "evergreen" && recommenders >= 2
            let oldNews = original.shelfLife?.lowercased() == "news" && (ageDays ?? 0) > 365
            let score = freshness + (selected ? 22 : 0) + channelWeight * 10 + topicWeight * 5 + recommenders * 3 + (evergreen ? 20 : 0) - (oldNews ? 40 : 0)
            var video = original
            let signal: String?
            if selected { signal = "Channel name matches your selection" }
            else if channelWeight > 0 { signal = "Channel you asked to see more of" }
            else if topicWeight > 0 { signal = "Topic you asked to see more of" }
            else if let ageDays, ageDays <= 90 { signal = "Published recently" }
            else if evergreen { signal = "Marked evergreen by HackerTube" }
            else { signal = nil }
            if let signal { video.reason = original.reason + " · " + signal }
            return (index, score, video)
        }
        return candidates.sorted { left, right in
            left.1 == right.1 ? left.0 < right.0 : left.1 > right.1
        }.map { $0.2 }
    }

    static func channelNameKey(_ name: String) -> String {
        name.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
    }

    static let videos: [FocusRecommendation] = [
        .init(id: "VMj-3S1tku0", title: "Building micrograd: neural networks and backpropagation", channel: "Andrej Karpathy", topic: "AI & ML", reason: "A hands-on introduction to neural networks."),
        .init(id: "7xTGNNLPyMI", title: "Deep Dive into LLMs like ChatGPT", channel: "Andrej Karpathy", topic: "AI & ML", reason: "A detailed look at how language models work."),
        .init(id: "wjZofJX0v4M", title: "Transformers, the tech behind LLMs", channel: "3Blue1Brown", topic: "AI & ML", reason: "A visual explanation of transformers."),
        .init(id: "2pWv7GOvuf0", title: "Reinforcement Learning: Introduction", channel: "Google DeepMind", topic: "AI & ML", reason: "The first lecture in David Silver's RL course."),
        .init(id: "fNk_zzaMoSs", title: "Vectors | Essence of linear algebra", channel: "3Blue1Brown", topic: "Science & math", reason: "Build intuition for a core ML concept."),
        .init(id: "spUNpyF58BY", title: "But what is the Fourier Transform?", channel: "3Blue1Brown", topic: "Science & math", reason: "A visual introduction to Fourier transforms."),
        .init(id: "ZuvK-od647c", title: "Quantum Entanglement & Spooky Action at a Distance", channel: "Veritasium", topic: "Science & math", reason: "An introduction to quantum entanglement."),
        .init(id: "42QuXLucH3Q", title: "Is Most Published Research Wrong?", channel: "Veritasium", topic: "Science & math", reason: "A look at reproducibility and research."),
        .init(id: "-5wpm-gesOY", title: "The Problem with Time & Timezones", channel: "Computerphile", topic: "Computing", reason: "A practical computing problem explained."),
        .init(id: "LkH2r-sNjQs", title: "Why Electronic Voting Is Still A Bad Idea", channel: "Tom Scott", topic: "Computing", reason: "Security and verification in electronic voting."),
        .init(id: "FITJMJjASUs", title: "Y Not: Adventures in Functional Programming", channel: "Confreaks", topic: "Computing", reason: "A programming talk about the Y combinator."),
        .init(id: "BLGFriOKz6U", title: "Behind the Scenes of iOS Security", channel: "Black Hat", topic: "Computing", reason: "A technical talk on iOS security."),
        .init(id: "otbnC2zE2rw", title: "Designing the Ideal Bootstrapped Business", channel: "Rob Walling", topic: "Startups & economics", reason: "An interview about bootstrapped companies."),
        .init(id: "id1WShzzMCQ", title: "How to Invent the Future", channel: "Stanford Online", topic: "Startups & economics", reason: "A lecture from Stanford's startup course."),
        .init(id: "PHe0bXAIuk0", title: "How The Economic Machine Works", channel: "Principles by Ray Dalio", topic: "Startups & economics", reason: "One perspective on how economic cycles work."),
        .init(id: "jbkSRLYSojo", title: "Hans Rosling's 200 Countries, 200 Years, 4 Minutes", channel: "BBC", topic: "Startups & economics", reason: "A visual tour of economic development.")
    ]

    static let channels: [FocusChannel] = [
        .init(name: "Google DeepMind", topic: "AI & ML"),
        .init(name: "Two Minute Papers", topic: "AI & ML"),
        .init(name: "AI Engineer", topic: "AI & ML"),
        .init(name: "Veritasium", topic: "Science & math"),
        .init(name: "Quanta Magazine", topic: "Science & math"),
        .init(name: "Numberphile", topic: "Science & math"),
        .init(name: "Computerphile", topic: "Computing"),
        .init(name: "freeCodeCamp", topic: "Computing"),
        .init(name: "NeetCode", topic: "Computing"),
        .init(name: "Sequoia Capital", topic: "Startups & economics"),
        .init(name: "Patrick Boyle", topic: "Startups & economics"),
        .init(name: "The Plain Bagel", topic: "Startups & economics")
    ]
}
