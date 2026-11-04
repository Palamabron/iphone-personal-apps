import Foundation
import Combine

// Only these fixed categories may be stored or exported. Never add URLs,
// user-provided text, account details, video IDs, headers, or error objects.
enum FocusDiagnosticEvent: String, Codable, CaseIterable, Sendable {
    case appStarted
    case signInStarted, signInSucceeded, signInFailed
    case subscriptionSyncStarted, subscriptionSyncSucceeded, subscriptionSyncFailed
    case uploadLoadStarted, uploadLoadSucceeded, uploadLoadFailed
    case freshSearchStarted, freshSearchSucceeded, freshSearchFailed
    case recommendationsStarted, recommendationsSucceeded, recommendationsPartial, recommendationsFailed
    case navigationBlocked, pageLoaded, pageLoadFailed, webContentTerminated
    case filterReady, filterUnavailable, premiumTestOpened
}

// Codes are deliberately broad and contain no raw NSError data or HTTP body.
enum FocusDiagnosticCode: String, Codable, Sendable {
    case timeout, offline, network, authorization, invalidResponse, notSignedIn, api, security, keychain, other
}

struct FocusDiagnosticEntry: Codable, Equatable {
    let time: Date
    let event: FocusDiagnosticEvent
    let code: FocusDiagnosticCode?
    let count: Int?
}

@MainActor
final class FocusDiagnostics: ObservableObject {
    static let shared = FocusDiagnostics()
    static let maximumEntries = 100
    private let storageKey = "focus.diagnostics.v1"
    private let store: UserDefaults
    private let clock: () -> Date
    private let capacity: Int
    @Published private(set) var entries: [FocusDiagnosticEntry]

    init(store: UserDefaults = .standard, capacity: Int = FocusDiagnostics.maximumEntries, clock: @escaping () -> Date = Date.init) {
        self.store = store
        self.clock = clock
        self.capacity = min(Self.maximumEntries, max(1, capacity))
        let data = store.data(forKey: storageKey)
        let decoded = data.flatMap { try? JSONDecoder().decode([FocusDiagnosticEntry].self, from: $0) } ?? []
        self.entries = Array(decoded.suffix(self.capacity)).map {
            FocusDiagnosticEntry(time: $0.time, event: $0.event, code: $0.code, count: Self.bounded($0.count))
        }
    }

    func record(_ event: FocusDiagnosticEvent, code: FocusDiagnosticCode? = nil, count: Int? = nil) {
        entries.append(FocusDiagnosticEntry(time: clock(), event: event, code: code, count: Self.bounded(count)))
        if entries.count > capacity { entries.removeFirst(entries.count - capacity) }
        if let data = try? JSONEncoder().encode(entries) { store.set(data, forKey: storageKey) }
    }

    func clear() {
        entries = []
        store.removeObject(forKey: storageKey)
    }

    // Export is built only from an enum, bounded numbers and normalized dates.
    // It intentionally excludes the page-check result and all errors' text.
    func report(version: String? = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) -> String {
        let dateFormatter = ISO8601DateFormatter()
        let versionText = Self.safeVersion(version)
        let system = ProcessInfo.processInfo.operatingSystemVersion
        var lines = ["Focus Tube diagnostics", "App version: \(versionText)",
                     "OS version: \(system.majorVersion).\(system.minorVersion).\(system.patchVersion)",
                     "Generated: \(dateFormatter.string(from: clock()))",
                     "Entries: \(entries.count)", ""]
        for entry in entries {
            var line = "\(dateFormatter.string(from: entry.time)) \(entry.event.rawValue)"
            if let code = entry.code { line += " code=\(code.rawValue)" }
            if let count = Self.bounded(entry.count) { line += " count=\(count)" }
            lines.append(line)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func bounded(_ value: Int?) -> Int? { value.map { min(999, max(0, $0)) } }
    private static func safeVersion(_ value: String?) -> String {
        guard let value, value.count <= 20,
              value.range(of: #"^[0-9]+(\.[0-9]+){0,3}$"#, options: .regularExpression) != nil else { return "unknown" }
        return value
    }
}
