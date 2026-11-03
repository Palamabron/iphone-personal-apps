// Internal experiment only. It deliberately does not provide Focus Tube's filter.
import SwiftUI
import SafariServices

@main
struct PremiumProbeApp: App {
    var body: some Scene { WindowGroup { ProbeScreen() } }
}

private struct ProbeTarget: Identifiable {
    let id: String
    let url: URL
}

private struct ProbeScreen: View {
    @State private var target: ProbeTarget?

    private func open(_ id: String, _ address: String) {
        guard let url = URL(string: address) else { return }
        target = ProbeTarget(id: id, url: url)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Internal playback experiment").font(.title2.bold())
                Text("This separate test opens YouTube in the iOS system browser view. Focus Tube's Shorts and feed filter does not run here.")
                Text("First sign in, then test the same video in both views. This app does not read your account, cookies, or browsing activity.").foregroundStyle(.secondary)
                Button("Open YouTube account") { open("account", "https://m.youtube.com/") }
                Button("Open regular video page") { open("watch", "https://m.youtube.com/watch?v=VMj-3S1tku0") }
                Button("Open embedded player") { open("embed", "https://www.youtube.com/embed/VMj-3S1tku0") }
                Spacer()
            }.padding().navigationTitle("Premium probe")
        }
        .sheet(item: $target) { destination in
            SafariProbeView(url: destination.url).ignoresSafeArea()
        }
    }
}

private struct SafariProbeView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
