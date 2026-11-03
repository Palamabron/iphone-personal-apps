import Foundation

enum FocusOAuthForm {
    static func encode(_ fields: [String: String]) -> Data? {
        var components = URLComponents()
        components.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        // A plus sign in application/x-www-form-urlencoded represents a space.
        return components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
    }
}
