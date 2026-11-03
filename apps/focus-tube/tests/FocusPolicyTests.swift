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
        print("Native URL policy: search, video links, Shorts, auth allowlist and hostile URLs passed")
    }
}
