import Foundation

@main
@MainActor
struct FocusDiagnosticsTests {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }

    static func main() throws {
        let suite = "focus.diagnostics.tests." + UUID().uuidString
        let store = UserDefaults(suiteName: suite)!
        defer { store.removePersistentDomain(forName: suite) }
        var now = Date(timeIntervalSince1970: 1_700_000_000)
        let log = FocusDiagnostics(store: store, capacity: 3, clock: { now })
        log.record(.appStarted)
        now.addTimeInterval(1)
        log.record(.signInStarted)
        now.addTimeInterval(1)
        log.record(.pageLoadFailed, code: .offline, count: -8)
        now.addTimeInterval(1)
        log.record(.recommendationsSucceeded, count: 100_000)
        check(log.entries.count == 3, "ring buffer must respect its capacity")
        check(log.entries.first?.event == .signInStarted, "oldest event must be removed")
        check(log.entries[1].count == 0 && log.entries[2].count == 999, "counts must be bounded")
        let report = log.report(version: "0.5.0")
        check(report.contains("App version: 0.5.0"), "valid version should be shown")
        check(report.contains("pageLoadFailed code=offline count=0"), "only mapped safe code should be shown")
        log.record(.signInFailed, code: .authorization)
        check(log.report().contains("signInFailed code=authorization"), "authentication code must be a fixed category")
        check(!report.contains("appStarted"), "evicted event must not be exported")
        check(log.report(version: "secret@example.test/token").contains("App version: unknown"), "untrusted version must be rejected")
        let restored = FocusDiagnostics(store: store, capacity: 3, clock: { now })
        check(restored.entries == log.entries, "events should survive an app restart")
        restored.clear()
        check(restored.entries.isEmpty && store.data(forKey: "focus.diagnostics.v1") == nil, "clear must remove persisted events")

        // Unknown event values and untrusted extra fields must never reach an export.
        let forged = """
        [{"time":0,"event":"token=secret@example.test","code":"offline","count":1,"url":"https://secret.example/"}]
        """.data(using: .utf8)!
        store.set(forged, forKey: "focus.diagnostics.v1")
        let reloaded = FocusDiagnostics(store: store, clock: { now })
        let safe = reloaded.report(version: "token=secret@example.test")
        check(!safe.contains("secret@example.test") && !safe.contains("https://"), "unknown data must not leak")
        check(reloaded.entries.isEmpty, "unknown categories must be discarded")
        print("FOCUS_DIAGNOSTICS_TESTS_PASSED")
    }
}
