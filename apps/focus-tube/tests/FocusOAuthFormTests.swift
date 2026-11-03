import Foundation

@main struct OAuthFormTests {
    static func main() {
        let original = "code+with/slashes=and space&symbols"
        guard let data = FocusOAuthForm.encode(["code": original]), let encoded = String(data: data, encoding: .utf8) else { fatalError("Encoding failed") }
        precondition(encoded.contains("%2B"), "A plus must not be interpreted as a space")
        let raw = String(encoded.dropFirst("code=".count)).replacingOccurrences(of: "+", with: " ")
        precondition(raw.removingPercentEncoding == original, "Authorization code must survive form decoding")
        print("OAuth form encoding passed")
    }
}
