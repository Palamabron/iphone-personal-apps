import Foundation

@main struct PolicyTests {
    static func main() {
        func url(_ s: String) -> URL { URL(string: s)! }
        precondition(FocusPolicy.destination("  koty & psy ")?.query?.contains("search_query=") == true)
        precondition(FocusPolicy.destination("https://youtu.be/dQw4w9WgXcQ?t=42")?.host == "m.youtube.com")
        precondition(FocusPolicy.destination("https://youtube.com/watch?v=dQw4w9WgXcQ") != nil)
        for input in ["", "https://evil.com/watch?v=dQw4w9WgXcQ", "https://youtube.com/shorts/dQw4w9WgXcQ", "https://youtube.com/watch?v=bad", "http://youtube.com/watch?v=dQw4w9WgXcQ", "https://youtube.com.evil.com/watch?v=dQw4w9WgXcQ", "https://user@youtube.com/watch?v=dQw4w9WgXcQ"] { precondition(FocusPolicy.destination(input) == nil, input) }
        for input in ["https://m.youtube.com/shorts/abc", "https://youtube.com/%73horts/abc", "https://youtube.com//Shorts/abc", "youtube://watch", "https://youtube.com.evil.com/", "https://evil.com/", "https://accounts.google.com.evil.com/", "https://youtube.com:444/", "http://youtube.com/"] { precondition(!FocusPolicy.allowed(url(input)), input) }
        for input in ["https://m.youtube.com/results?search_query=hello", "https://www.youtube.com/watch?v=dQw4w9WgXcQ", "https://accounts.google.com/ServiceLogin", "https://consent.youtube.com/"] { precondition(FocusPolicy.allowed(url(input)), input) }
        let videos = FocusRecommendations.videos
        precondition(!videos.isEmpty && videos.count <= 30)
        precondition(Set(videos.map(\.id)).count == videos.count)
        for video in videos {
            precondition(FocusPolicy.validID(video.id) && FocusPolicy.allowed(video.url))
            precondition(FocusRecommendations.topics.contains(video.topic))
            precondition(!video.title.isEmpty && !video.channel.isEmpty && !video.reason.isEmpty)
        }
        precondition(Set(FocusRecommendations.channels.map(\.id)).count == FocusRecommendations.channels.count)
        for channel in FocusRecommendations.channels {
            precondition(FocusRecommendations.topics.contains(channel.topic))
            precondition(FocusPolicy.destination(channel.query) != nil)
        }
        let a = FocusRecommendation(id: "aaaaaaaaaaa", title: "a", channel: "Example Channel", topic: "Computing", reason: "test")
        let b = FocusRecommendation(id: "bbbbbbbbbbb", title: "b", channel: "Other", topic: "AI & ML", reason: "test")
        let c = FocusRecommendation(id: "ccccccccccc", title: "c", channel: "EXAMPLE   CHANNEL", topic: "AI & ML", reason: "test")
        let items = [b, a, c]
        precondition(FocusRecommendations.prioritize(items, selectedChannelNames: []).map(\.id) == [b.id, a.id, c.id])
        precondition(FocusRecommendations.prioritize(items, selectedChannelNames: ["  example channel\n"]).map(\.id) == [a.id, c.id, b.id])
        precondition(FocusRecommendations.prioritize(items, selectedChannelNames: ["example"]).map(\.id) == [b.id, a.id, c.id])
        precondition(FocusRecommendations.prioritize(items, selectedChannelNames: [" "]).map(\.id) == [b.id, a.id, c.id])
        let old = FocusRecommendations.publishedDate("2020-01-01T12:00:00Z")!
        let recent = FocusRecommendations.publishedDate("2026-01-01T12:00:00.000Z")!
        precondition(FocusRecommendations.publishedDate("not-a-date") == nil)
        var datedA = a; datedA.publishedAt = old
        var datedB = b; datedB.publishedAt = recent
        let dated = [c, datedA, datedB]
        precondition(FocusRecommendations.sortByPublication(dated, order: .recommended, date: { $0.publishedAt }).map(\.id) == [c.id, a.id, b.id])
        precondition(FocusRecommendations.sortByPublication(dated, order: .newest, date: { $0.publishedAt }).map(\.id) == [b.id, a.id, c.id])
        precondition(FocusRecommendations.sortByPublication(dated, order: .oldest, date: { $0.publishedAt }).map(\.id) == [a.id, b.id, c.id])
        var sameDate = c; sameDate.publishedAt = old
        precondition(FocusRecommendations.sortByPublication([sameDate, datedA], order: .newest, date: { $0.publishedAt }).map(\.id) == [c.id, a.id])
        let cached = #"{"id":"aaaaaaaaaaa","title":"a","channel":"Example Channel","topic":"Computing","reason":"test"}"#.data(using: .utf8)!
        precondition((try! JSONDecoder().decode(FocusRecommendation.self, from: cached)).publishedAt == nil)
        print("Native URL policy: search, video links, Shorts, auth allowlist and hostile URLs passed")
    }
}
