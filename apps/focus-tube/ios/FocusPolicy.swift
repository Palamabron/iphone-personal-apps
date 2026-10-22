import Foundation

enum FocusPolicy {
    static let youtubeHosts: Set<String> = ["youtube.com", "www.youtube.com", "m.youtube.com"]
    static func isYouTube(_ url: URL) -> Bool {
        url.scheme == "https" && youtubeHosts.contains(url.host?.lowercased() ?? "") && url.user == nil && url.password == nil && (url.port == nil || url.port == 443)
    }
    static func isShorts(_ url: URL) -> Bool {
        isYouTube(url) && url.path.lowercased().split(separator: "/").contains("shorts")
    }
    static func allowed(_ url: URL) -> Bool {
        if isYouTube(url) { return !isShorts(url) }
        return url.scheme == "https" && ["accounts.google.com", "consent.google.com", "consent.youtube.com"].contains(url.host?.lowercased() ?? "") && url.user == nil && url.password == nil && (url.port == nil || url.port == 443)
    }
    static func destination(_ input: String) -> URL? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if value.contains("://") || value.hasPrefix("youtu.be/") || value.hasPrefix("www.youtube.com/") || value.hasPrefix("m.youtube.com/") || value.hasPrefix("youtube.com/") {
            guard let url = URL(string: value.contains("://") ? value : "https://" + value), url.scheme == "https", url.user == nil, url.password == nil, url.port == nil || url.port == 443 else { return nil }
            if url.host == "youtu.be" {
                let id = String(url.path.dropFirst())
                guard validID(id) else { return nil }
                var target = URLComponents(string: "https://m.youtube.com/watch")!
                target.queryItems = [URLQueryItem(name: "v", value: id)]
                target.queryItems! += (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).filter { ["t", "list", "start"].contains($0.name) }
                return target.url
            }
            guard isYouTube(url), !isShorts(url), url.path == "/watch", let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "v" })?.value, validID(id) else { return nil }
            return url
        }
        var search = URLComponents(string: "https://m.youtube.com/results")!
        search.queryItems = [URLQueryItem(name: "search_query", value: value)]
        return search.url
    }
    static func validID(_ value: String) -> Bool {
        value.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) != nil
    }
}
