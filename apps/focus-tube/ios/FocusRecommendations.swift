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
    let reason: String
    var publishedAt: Date? = nil

    var url: URL { URL(string: "https://m.youtube.com/watch?v=" + id)! }
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
    // Match locally and keep each partition in its original source order.
    static func prioritize(_ videos: [FocusRecommendation], selectedChannelNames: [String]) -> [FocusRecommendation] {
        let names = Set(selectedChannelNames.map(channelNameKey).filter { !$0.isEmpty })
        guard !names.isEmpty else { return videos }
        var matching: [FocusRecommendation] = []
        var other: [FocusRecommendation] = []
        for video in videos {
            if names.contains(channelNameKey(video.channel)) { matching.append(video) }
            else { other.append(video) }
        }
        return matching + other
    }

    private static func channelNameKey(_ name: String) -> String {
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
