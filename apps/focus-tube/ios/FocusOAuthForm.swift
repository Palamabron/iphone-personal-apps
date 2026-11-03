import Foundation

enum FocusOAuthForm {
    static func encode(_ fields: [String: String]) -> Data? {
        var components = URLComponents()
        components.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        // A plus sign in application/x-www-form-urlencoded represents a space.
        return components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
    }
}

enum FocusDuration {
    static func seconds(_ value: String) -> Int? {
        let pattern = #"^P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) else { return nil }
        var total = 0
        var found = false
        for (index, factor) in [(1, 86400), (2, 3600), (3, 60), (4, 1)] {
            guard match.range(at: index).location != NSNotFound else { continue }
            guard let range = Range(match.range(at: index), in: value), let amount = Int(value[range]), amount <= 1_000_000 else { return nil }
            total += amount * factor
            found = true
        }
        return found ? total : nil
    }
}
