import SwiftUI
import WebKit
import UIKit

private enum FocusTheme {
    static let background = Color(red: 0.07, green: 0.14, blue: 0.11)
    static let accent = Color(red: 0.84, green: 0.95, blue: 0.61)
    static let surface = Color.white.opacity(0.08)
    static let corner: CGFloat = 16
}

@main
struct FocusApp: App {
    @StateObject private var browser = FocusBrowser()
    var body: some Scene {
        WindowGroup { FocusScreen(browser: browser).preferredColorScheme(.dark).tint(FocusTheme.accent) }
    }
}

struct SavedFilm: Codable, Identifiable {
    var id: String { url }
    let title: String
    let url: String
}

@MainActor
final class FocusBrowser: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    @Published var home = true
    @Published var loading = false
    @Published var ready = false
    @Published var message: String?
    @Published var title = "Focus Tube"
    @Published var saved: [SavedFilm] = []
    @Published var canGoBack = false
    let webView: WKWebView
    private var observations: [NSKeyValueObservation] = []

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        if let resource = Bundle.main.url(forResource: "filter", withExtension: "js"), let code = try? String(contentsOf: resource, encoding: .utf8) {
            configuration.userContentController.addUserScript(WKUserScript(source: code, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 0.07, green: 0.14, blue: 0.11, alpha: 1)
        saved = (UserDefaults.standard.data(forKey: "focus.saved.v1").flatMap { try? JSONDecoder().decode([SavedFilm].self, from: $0) } ?? []).filter { URL(string: $0.url).map { FocusPolicy.isYouTube($0) && !FocusPolicy.isShorts($0) } ?? false }
        observations.append(webView.observe(\.canGoBack, options: [.new]) { [weak self] _, change in
            DispatchQueue.main.async { self?.canGoBack = change.newValue ?? false }
        })
        observations.append(webView.observe(\.title, options: [.new]) { [weak self] _, change in
            DispatchQueue.main.async { self?.title = change.newValue.flatMap { $0 } ?? "Focus Tube" }
        })
    }

    func open(_ url: URL) {
        guard FocusPolicy.allowed(url) else { message = "This link is blocked. Paste a regular YouTube video link."; return }
        home = false; message = nil; ready = false; loading = true
        webView.load(URLRequest(url: url))
    }
    func submit(_ input: String) {
        guard let url = FocusPolicy.destination(input) else { message = "Enter a search or a video link. Shorts links are blocked."; return }
        open(url)
    }
    func goHome() {
        webView.evaluateJavaScript("document.querySelectorAll('video').forEach(v => v.pause())")
        home = true
    }
    func saveCurrent() {
        guard let url = webView.url, FocusPolicy.isYouTube(url), url.path == "/watch", !FocusPolicy.isShorts(url) else { message = "Open a video to save it for later."; return }
        guard let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "v" })?.value, FocusPolicy.validID(id) else { return }
        let canonical = "https://m.youtube.com/watch?v=" + id
        saved.removeAll { $0.url == canonical }
        saved.insert(SavedFilm(title: title.replacingOccurrences(of: " - YouTube", with: ""), url: canonical), at: 0)
        saved = Array(saved.prefix(100)); persist()
        message = "Saved for later."
    }
    func remove(_ film: SavedFilm) { saved.removeAll { $0.id == film.id }; persist() }
    private func persist() { if let data = try? JSONEncoder().encode(saved) { UserDefaults.standard.set(data, forKey: "focus.saved.v1") } }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Only top-level navigation is restricted; YouTube's media/CDN requests are left to WebKit.
        guard navigationAction.targetFrame?.isMainFrame != false else { decisionHandler(.allow); return }
        guard let url = navigationAction.request.url, FocusPolicy.allowed(url) else {
            decisionHandler(.cancel)
            message = "This link cannot be opened in Focus Tube."
            return
        }
        decisionHandler(.allow)
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        loading = true; ready = false
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loading = false; title = webView.title ?? "Focus Tube"
        guard let url = webView.url, FocusPolicy.isYouTube(url) else { ready = true; return }
        webView.evaluateJavaScript("document.documentElement.hasAttribute('data-ft-active')") { [weak self] result, _ in
            guard let self else { return }
            guard self.webView.url == url else { return }
            self.ready = result as? Bool == true
            if !self.ready { self.message = "The filter did not start. Tap refresh to try again." }
        }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed(error) }
    private func failed(_ error: Error) {
        if (error as NSError).code == NSURLErrorCancelled { return }
        loading = false; ready = false; message = "Could not load the page. Check your connection and try again."
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { loading = false; ready = false; message = "The player stopped. Tap refresh to try again." }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url { open(url) }
        return nil
    }
}

struct FocusWebView: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct FocusScreen: View {
    @ObservedObject var browser: FocusBrowser
    @State private var input = ""
    @State private var showInfo = false
    @FocusState private var typing: Bool
    private let background = FocusTheme.background
    var body: some View {
        NavigationStack {
            ZStack {
                background.ignoresSafeArea()
                FocusWebView(webView: browser.webView).opacity(!browser.home && browser.ready ? 1 : 0).allowsHitTesting(!browser.home && browser.ready)
                if browser.home { startScreen }
                else if !browser.ready {
                    VStack(spacing: 20) {
                        if browser.loading { ProgressView(); Text("Opening YouTube…") }
                        else { Image(systemName: "wifi.exclamationmark").font(.largeTitle); Text("Could not open this page."); Button("Refresh") { browser.webView.reload() } }
                    }.padding()
                }
            }
            .navigationTitle("Focus Tube").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button { browser.goHome() } label: { Image(systemName: "house") }.accessibilityLabel("Home") }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if !browser.home { Button { browser.saveCurrent() } label: { Image(systemName: "bookmark") }.accessibilityLabel("Save video") }
                    Button { showInfo = true } label: { Image(systemName: "info.circle") }.accessibilityLabel("About")
                }
                if !browser.home {
                    ToolbarItemGroup(placement: .bottomBar) {
                        Button { browser.webView.goBack() } label: { Image(systemName: "chevron.left") }.disabled(!browser.canGoBack).accessibilityLabel("Back")
                        Spacer()
                        Button("Search") { browser.goHome(); typing = true }
                        Spacer()
                        Button { browser.webView.reload() } label: { Image(systemName: "arrow.clockwise") }.accessibilityLabel("Refresh")
                        Spacer()
                        Button { browser.open(URL(string: "https://m.youtube.com/feed/you")!) } label: { Image(systemName: "person.crop.circle") }.accessibilityLabel("YouTube account")
                    }
                }
            }
            .alert("Focus Tube", isPresented: Binding(get: { browser.message != nil }, set: { if !$0 { browser.message = nil } })) { Button("OK") { browser.message = nil } } message: { Text(browser.message ?? "") }
            .sheet(isPresented: $showInfo) {
                NavigationStack { ScrollView { VStack(alignment: .leading, spacing: 18) {
                    Text("About Focus Tube").font(.title.bold())
                    Text("Search YouTube without Shorts or an endless feed. Results load 15 at a time.")
                    Text("YouTube handles playback and sign-in. Google may block sign-in here. Premium, picture in picture and background playback need testing on your device. Offline playback is unavailable.")
                    Text("Saved videos stay on this device. This app does not block the official YouTube app.").foregroundStyle(.secondary)
                    Text("Focus Tube 0.3.0").font(.footnote)
                }.padding(24) }.navigationTitle("About").toolbar { Button("Done") { showInfo = false } } }
            }
        }
    }
    private var startScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack { Image(systemName: "play.fill").font(.system(size: 17, weight: .bold)).foregroundStyle(background).frame(width: 44, height: 44).background(FocusTheme.accent, in: RoundedRectangle(cornerRadius: 14)); Text("FOCUS TUBE").font(.caption.weight(.bold)).tracking(2).foregroundStyle(.secondary); Spacer() }.padding(.top, 22)
                Text("Search YouTube").font(.largeTitle.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                Text("Search YouTube or open a video link.").foregroundStyle(.secondary)
                VStack(spacing: 12) {
                    TextField("Search or paste a video link", text: $input).textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.search).focused($typing).padding(16).background(FocusTheme.surface, in: RoundedRectangle(cornerRadius: FocusTheme.corner)).onSubmit(search)
                    Button(action: search) { Label("Search videos", systemImage: "magnifyingglass").frame(maxWidth: .infinity).padding(8) }.buttonStyle(.borderedProminent).disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                HStack {
                    Button { browser.open(URL(string: "https://m.youtube.com/feed/subscriptions")!) } label: { Label("Subscriptions", systemImage: "rectangle.stack").frame(maxWidth: .infinity).padding(.vertical, 8) }
                    Button { browser.open(URL(string: "https://m.youtube.com/feed/you")!) } label: { Label("Account", systemImage: "person.crop.circle").frame(maxWidth: .infinity).padding(.vertical, 8) }
                }.buttonStyle(.bordered)
                if !browser.saved.isEmpty {
                    Text("Saved videos").font(.title2.bold())
                    ForEach(browser.saved) { film in
                        HStack {
                            Button { if let url = URL(string: film.url) { browser.open(url) } } label: { Label(film.title, systemImage: "play.circle").multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10) }
                            Button(role: .destructive) { browser.remove(film) } label: { Image(systemName: "trash").padding(10) }.accessibilityLabel("Remove saved video")
                        }
                    }
                }
                Text("Tap the bookmark while watching to save a video.").font(.footnote).foregroundStyle(.secondary)
            }.padding(24)
        }.scrollDismissesKeyboard(.interactively)
    }
    private func search() { typing = false; browser.submit(input) }
}
