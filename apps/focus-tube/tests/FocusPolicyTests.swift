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
        precondition(FocusPolicy.officialAppLink(url("https://m.youtube.com/watch?v=dQw4w9WgXcQ&list=private&t=42"))?.absoluteString == "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
        for input in ["https://m.youtube.com/shorts/dQw4w9WgXcQ", "https://evil.com/watch?v=dQw4w9WgXcQ", "https://m.youtube.com/watch?v=bad"] { precondition(FocusPolicy.officialAppLink(url(input)) == nil, input) }
        let sharedVideo = FocusPolicy.videoLink(url("https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=private&t=42"))
        precondition(sharedVideo?.absoluteString == "https://m.youtube.com/watch?v=dQw4w9WgXcQ")
        for input in ["https://m.youtube.com/shorts/dQw4w9WgXcQ", "https://evil.com/watch?v=dQw4w9WgXcQ", "https://m.youtube.com/results?search_query=anything", "https://m.youtube.com/watch?v=bad", "http://youtube.com/watch?v=dQw4w9WgXcQ"] { precondition(FocusPolicy.videoLink(url(input)) == nil, input) }
        precondition(!FocusRecommendations.freshSearchTitleMatches("घर के छोटे कमरे से शुरू करे ₹5,000 में बिज़नेस | Small business ideas 2026", topic: "Startups & economics"))
        precondition(!FocusRecommendations.freshSearchTitleMatches("How to maintain your hair", topic: "AI & ML"))
        precondition(FocusRecommendations.freshSearchTitleMatches("Introduction to machine learning", topic: "AI & ML"))
        precondition(FocusRecommendations.freshSearchTitleMatches("Nowe badania: fizyka kwantowa", topic: "Science & math"))
        precondition(FocusRecommendations.freshSearchTitleMatches("Computer science lecture", topic: "Computing"))
        precondition(FocusRecommendations.freshSearchTitleMatches("Startup fundraising and venture capital", topic: "Startups & economics"))
        precondition(!FocusRecommendations.freshSearchTitleMatches("Venture capital", topic: "AI & ML"))
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
        let anyAge = FocusRankingPreferences(maxAgeMonths: nil)
        precondition(FocusRecommendations.prioritize(items, selectedChannelNames: [], preferences: anyAge).map(\.id) == [b.id, a.id, c.id])
        precondition(FocusRecommendations.prioritize(items, selectedChannelNames: ["  example channel\n"], preferences: anyAge).map(\.id) == [a.id, c.id, b.id])
        precondition(FocusRecommendations.prioritize(items, selectedChannelNames: ["example"], preferences: anyAge).map(\.id) == [b.id, a.id, c.id])
        precondition(FocusRecommendations.prioritize(items, selectedChannelNames: [" "], preferences: anyAge).map(\.id) == [b.id, a.id, c.id])
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
        let oldCache = try! JSONDecoder().decode(FocusRecommendation.self, from: cached)
        precondition(oldCache.shelfLife == nil && oldCache.hnRecommenders == nil && oldCache.additionalTopics == nil)

        // The same video from different sources must appear once but match
        // every source topic and keep useful metadata from both records.
        var hackerNews = a; hackerNews.shelfLife = "evergreen"; hackerNews.hnRecommenders = 4
        var youtube = FocusRecommendation(id: a.id, title: "from YouTube", channel: a.channel, topic: "AI & ML", reason: "Recent YouTube search result")
        youtube.publishedAt = recent
        let merged = FocusRecommendations.mergeDuplicates([youtube, b, hackerNews])
        precondition(merged.map(\.id) == [a.id, b.id])
        precondition(Set(merged[0].allTopics) == Set(["Computing", "AI & ML"]))
        precondition(merged[0].publishedAt == recent && merged[0].shelfLife == "evergreen" && merged[0].hnRecommenders == 4)
        precondition(merged[0].reason == hackerNews.reason)
        let restoredMerged = try! JSONDecoder().decode(FocusRecommendation.self, from: JSONEncoder().encode(merged[0]))
        precondition(Set(restoredMerged.allTopics) == Set(["Computing", "AI & ML"]))
        var crossTopicFeedback = FocusRankingPreferences(maxAgeMonths: nil)
        crossTopicFeedback.moreLike(merged[0], topic: "AI & ML")
        precondition(crossTopicFeedback.topics["AI & ML"] == 1 && crossTopicFeedback.topics["Computing"] == nil)

        let partialResults = [FocusDiscoveryResult(topic: "Computing", videos: [hackerNews]), FocusDiscoveryResult(topic: "AI & ML", videos: nil)]
        let partialMerge = FocusRecommendations.mergeDiscovery(partialResults, previous: [youtube, b])
        precondition(partialMerge.partial && partialMerge.videos.map(\.id) == [a.id, b.id])
        precondition(Set(partialMerge.videos[0].allTopics) == Set(["Computing", "AI & ML"]))
        let successfulEmpty = [FocusDiscoveryResult(topic: "Computing", videos: [hackerNews]), FocusDiscoveryResult(topic: "AI & ML", videos: [])]
        let fullMerge = FocusRecommendations.mergeDiscovery(successfulEmpty, previous: [b])
        precondition(!fullMerge.partial && fullMerge.videos.map(\.id) == [a.id])
        let allEmpty = FocusRecommendations.mergeDiscovery([FocusDiscoveryResult(topic: "AI & ML", videos: [])], previous: [b])
        precondition(!allEmpty.partial && allEmpty.videos.isEmpty)
        let capped = FocusRecommendations.mergeDiscovery(partialResults, previous: [youtube, b], limit: 1)
        precondition(capped.partial && capped.videos.count == 1)
        let oldDiscoveryCache = #"{"videos":[],"date":0}"#.data(using: .utf8)!
        let decodedDiscoveryCache = try! JSONDecoder().decode(FocusDiscoveryCache.self, from: oldDiscoveryCache)
        precondition(decodedDiscoveryCache.date != nil && decodedDiscoveryCache.partial == nil && decodedDiscoveryCache.lastAttempt == nil)

        let now = FocusRecommendations.publishedDate("2026-11-04T12:00:00Z")!
        let partialCache = FocusDiscoveryCache(videos: partialMerge.videos, date: now, partial: true, lastAttempt: now.addingTimeInterval(30))
        let restoredPartial = try! JSONDecoder().decode(FocusDiscoveryCache.self, from: JSONEncoder().encode(partialCache))
        precondition(restoredPartial.partial == true && restoredPartial.date == now && restoredPartial.lastAttempt == now.addingTimeInterval(30))
        precondition(!FocusRecommendations.needsDiscoveryRefresh(lastUpdated: now, lastAttempt: now, partial: true, now: now.addingTimeInterval(299)))
        precondition(FocusRecommendations.needsDiscoveryRefresh(lastUpdated: now, lastAttempt: now, partial: true, now: now.addingTimeInterval(300)))
        precondition(!FocusRecommendations.needsDiscoveryRefresh(lastUpdated: now, lastAttempt: now, partial: false, now: now.addingTimeInterval(1799)))
        precondition(FocusRecommendations.needsDiscoveryRefresh(lastUpdated: now, lastAttempt: now, partial: false, now: now.addingTimeInterval(1800)))
        precondition(FocusRecommendations.needsDiscoveryRefresh(lastUpdated: now, lastAttempt: now, partial: false, now: now.addingTimeInterval(-1)))
        var fresh = a; fresh.publishedAt = FocusRecommendations.publishedDate("2026-10-30T12:00:00Z")
        var evergreen = b; evergreen.publishedAt = FocusRecommendations.publishedDate("2020-01-01T12:00:00Z"); evergreen.shelfLife = "evergreen"; evergreen.hnRecommenders = 4
        var staleNews = c; staleNews.publishedAt = evergreen.publishedAt; staleNews.shelfLife = "news"; staleNews.hnRecommenders = 4
        precondition(FocusRecommendations.prioritize([staleNews, evergreen, fresh], selectedChannelNames: [], now: now).map(\.id) == [fresh.id])
        let ranked = FocusRecommendations.prioritize([staleNews, evergreen, fresh], selectedChannelNames: [], preferences: anyAge, now: now)
        precondition(ranked.map(\.id) == [fresh.id, evergreen.id, staleNews.id])
        precondition(ranked[0].reason.contains("Published recently"))
        precondition(ranked[1].reason.contains("Marked evergreen by HackerTube"))
        var weakEvergreen = evergreen; weakEvergreen.hnRecommenders = 1
        precondition(!FocusRecommendations.prioritize([weakEvergreen], selectedChannelNames: [], preferences: anyAge, now: now)[0].reason.contains("Marked evergreen"))

        var feedback = FocusRankingPreferences(maxAgeMonths: nil)
        feedback.moreLike(evergreen)
        for _ in 0..<10 { feedback.moreLike(evergreen) }
        precondition(feedback.channels[FocusRecommendations.channelNameKey(evergreen.channel)] == 3)
        precondition(feedback.topics[evergreen.topic] == 3)
        var sameAge = fresh; sameAge.publishedAt = evergreen.publishedAt
        let learned = FocusRecommendations.prioritize([sameAge, evergreen], selectedChannelNames: [], preferences: feedback, now: now)
        precondition(learned[0].id == evergreen.id && learned[0].reason.contains("asked to see more"))
        feedback.hide(evergreen)
        precondition(FocusRecommendations.prioritize([sameAge, evergreen], selectedChannelNames: [], preferences: feedback, now: now).map(\.id) == [sameAge.id])
        feedback.unhideAll()
        precondition(feedback.hiddenIDs.isEmpty)
        feedback.maxAgeMonths = 12
        var future = staleNews; future.publishedAt = now.addingTimeInterval(3 * 86400)
        precondition(FocusRecommendations.prioritize([fresh, evergreen, oldCache, future], selectedChannelNames: [], preferences: feedback, now: now).map(\.id) == [fresh.id])
        var slightlyFuture = staleNews; slightlyFuture.publishedAt = now.addingTimeInterval(12 * 3600); slightlyFuture.shelfLife = nil; slightlyFuture.hnRecommenders = nil
        let tolerated = FocusRecommendations.prioritize([slightlyFuture, fresh], selectedChannelNames: [], now: now)
        precondition(tolerated.map(\.id) == [fresh.id, slightlyFuture.id])
        precondition(!tolerated[1].reason.contains("Published recently"))
        let storedFeedback = try! JSONEncoder().encode(feedback)
        precondition((try! JSONDecoder().decode(FocusRankingPreferences.self, from: storedFeedback)) == feedback)
        let oldPreferences = #"{"channels":{},"topics":{},"hiddenIDs":[]}"#.data(using: .utf8)!
        precondition((try! JSONDecoder().decode(FocusRankingPreferences.self, from: oldPreferences)).maxAgeMonths == 24)
        let anyAgePreferences = try! JSONEncoder().encode(anyAge)
        precondition((try! JSONDecoder().decode(FocusRankingPreferences.self, from: anyAgePreferences)).maxAgeMonths == nil)
        print("Native URL policy: search, video links, Shorts, auth allowlist and hostile URLs passed")
    }
}
