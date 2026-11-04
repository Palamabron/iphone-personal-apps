import SwiftUI
import WebKit
import UIKit
import SafariServices

private enum FocusTheme {
    private static func adaptive(light: UIColor, dark: UIColor) -> UIColor {
        UIColor { traits in traits.userInterfaceStyle == .dark ? dark : light }
    }
    static let uiBackground = adaptive(light: UIColor(red: 0.965, green: 0.973, blue: 0.961, alpha: 1), dark: UIColor(red: 0.035, green: 0.055, blue: 0.050, alpha: 1))
    static let background = Color(uiColor: uiBackground)
    static let accent = Color(uiColor: adaptive(light: UIColor(red: 0.161, green: 0.349, blue: 0.278, alpha: 1), dark: UIColor(red: 0.81, green: 0.92, blue: 0.65, alpha: 1)))
    static let surface = Color(uiColor: adaptive(light: .white, dark: UIColor(red: 0.095, green: 0.125, blue: 0.113, alpha: 1)))
    static let border = Color.primary.opacity(0.09)
    static let corner: CGFloat = 18
}

@main
struct FocusApp: App {
    @StateObject private var browser = FocusBrowser()
    var body: some Scene {
        WindowGroup { FocusScreen(browser: browser).tint(FocusTheme.accent) }
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
    @Published var diagnostics = "Open a YouTube page, then run the check."
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
        webView.backgroundColor = FocusTheme.uiBackground
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
    func inspectPage() {
        guard !home, let url = webView.url, FocusPolicy.isYouTube(url) else {
            diagnostics = "Open the affected YouTube page and try again."
            return
        }
        let script = """
        (() => {
          const root = document.documentElement;
          const count = selector => document.querySelectorAll(selector).length;
          return JSON.stringify({route: root.getAttribute('data-ft-route') || 'unknown', list: root.getAttribute('data-ft-list') || 'none', cards: count('ytm-video-with-context-renderer,ytm-video-renderer,ytm-rich-item-renderer,ytd-video-renderer,ytd-rich-item-renderer'), signInLinks: count('a[href*="signin"],a[href*="ServiceLogin"]'), listRoots: count('ytm-browse,ytm-search,ytm-section-list-renderer,ytd-browse,ytd-search')});
        })()
        """
        webView.evaluateJavaScript(script) { [weak self] value, error in
            guard let self else { return }
            self.diagnostics = error == nil ? (value as? String ?? "Page information unavailable.") : "Could not inspect this page."
        }
    }
    private func persist() { if let data = try? JSONEncoder().encode(saved) { UserDefaults.standard.set(data, forKey: "focus.saved.v1") } }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Only top-level navigation is restricted; YouTube's media/CDN requests are left to WebKit.
        guard navigationAction.targetFrame?.isMainFrame != false else { decisionHandler(.allow); return }
        guard let url = navigationAction.request.url, FocusPolicy.allowed(url) else {
            decisionHandler(.cancel)
            // A blocked redirect may arrive after open() set the loading state.
            // No failure callback is guaranteed for a navigation we cancel here.
            loading = false
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

// A separate system view for an optional Premium experiment. It cannot inject
// the app's filter or access the user's web session or page contents.
private struct PremiumTestView: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    private static let videoURL = URL(string: "https://m.youtube.com/watch?v=VMj-3S1tku0")!

    func makeCoordinator() -> Coordinator { Coordinator(isPresented: $isPresented) }
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: Self.videoURL)
        controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}

    final class Coordinator: NSObject, SFSafariViewControllerDelegate {
        private var isPresented: Binding<Bool>
        init(isPresented: Binding<Bool>) { self.isPresented = isPresented }
        func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
            isPresented.wrappedValue = false
        }
    }
}

struct FocusScreen: View {
    @ObservedObject var browser: FocusBrowser
    @State private var input = ""
    @State private var showInfo = false
    @State private var showPremiumTest = false
    @State private var selectedTopic = "All"
    @State private var recommendationOrder = FocusRecommendations.Order.recommended
    @State private var uploadOrder = FocusRecommendations.Order.newest
    @State private var recommendationLimit = 15
    @State private var showRecommendationSettings = false
    @State private var confirmRecommendationReset = false
    @State private var previousRecommendationPreferences: FocusRankingPreferences?
    @State private var recommendationFeedback: String?
    @StateObject private var discovery = FocusDiscovery()
    @StateObject private var account = FocusYouTubeAccount()
    @AppStorage("focus.subscriptionSelection.v1") private var selectedChannelIDs = ""
    @AppStorage("focus.recommendationPreferences.v1") private var recommendationPreferencesJSON = ""
    @State private var showChannels = false
    @Environment(\.scenePhase) private var scenePhase
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
                        Button { browser.open(URL(string: "https://m.youtube.com/channel_switcher")!) } label: { Image(systemName: "person.crop.circle") }.accessibilityLabel("YouTube account")
                    }
                }
            }
            .alert("Focus Tube", isPresented: Binding(get: { browser.message != nil }, set: { if !$0 { browser.message = nil } })) { Button("OK") { browser.message = nil } } message: { Text(browser.message ?? "") }
            .task {
                if await account.syncIfNeeded() { await loadSelectedUploads() }
                await discovery.refreshIfNeeded()
                await account.refreshFreshVideosIfNeeded()
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 300_000_000_000)
                    guard !Task.isCancelled else { break }
                    if scenePhase == .active {
                        await discovery.refreshIfNeeded()
                        if await account.syncIfNeeded() { await loadSelectedUploads() }
                        await account.refreshFreshVideosIfNeeded()
                    }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task {
                        await discovery.refreshIfNeeded()
                        if await account.syncIfNeeded() { await loadSelectedUploads() }
                        await account.refreshFreshVideosIfNeeded()
                    }
                }
            }
            .sheet(isPresented: $showInfo) {
                NavigationStack { ScrollView { VStack(alignment: .leading, spacing: 18) {
                    Text("About Focus Tube").font(.title.bold())
                    Text("Search YouTube without Shorts or an endless feed. Results load 15 at a time.")
                    Text("YouTube handles playback and sign-in. Google may block sign-in here. Premium, picture in picture and background playback need testing on your device. Offline playback is unavailable.")
                    Text("Premium playback test").font(.headline)
                    Text("Opens one public video in a system browser view. Sign in to your Premium account there if needed and check your account status. Shorts and feed filtering do not work in this view. The system view may use a separate sign-in from Focus Tube.").font(.footnote)
                    Button("Open test video") { showPremiumTest = true }.buttonStyle(.bordered)
                    Text("HackerTube picks are separate from Google subscription sync. Saved videos stay on this device. This app does not block the official YouTube app.").foregroundStyle(.secondary)
                    Text("Selected subscription names and your feedback can influence Recommended order on this device. Different channels can share a name.").foregroundStyle(.secondary)
                    Text("Page check").font(.headline)
                    Text("Run this while a YouTube page is open. It shows filter state and element counts; it does not show account details or page text.").font(.footnote).foregroundStyle(.secondary)
                    Button("Check current page") { browser.inspectPage() }.buttonStyle(.bordered)
                    Text(browser.diagnostics).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                    Text("Focus Tube 0.5.0 development").font(.footnote)
                }.padding(24) }.navigationTitle("About").toolbar { Button("Done") { showInfo = false } } }
                    .sheet(isPresented: $showPremiumTest) { PremiumTestView(isPresented: $showPremiumTest).ignoresSafeArea() }
            }
            .sheet(isPresented: $showChannels) { subscriptionPicker }
            .sheet(isPresented: $showRecommendationSettings) { recommendationSettings }
        }
    }
    private var topics: [String] {
        ["All"] + FocusRecommendations.topics
    }

    private var visibleVideos: [FocusRecommendation] {
        let picks = discovery.videos.isEmpty ? FocusRecommendations.videos : discovery.videos
        var seen = Set<String>()
        let items = (picks + account.freshVideos).filter { seen.insert($0.id).inserted }
        let filtered = selectedTopic == "All" ? items : items.filter { $0.topic == selectedTopic }
        let names = account.channels.filter { selectedIDs.contains($0.id) }.map(\.title)
        let preferred = FocusRecommendations.prioritize(filtered, selectedChannelNames: names, preferences: recommendationPreferences)
        return FocusRecommendations.sortByPublication(preferred, order: recommendationOrder, date: { $0.publishedAt })
    }

    private var startScreen: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Discover").font(.title2.weight(.bold))
                }.padding(.top, 8)

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                    TextField("Search or paste a video link", text: $input)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.search).focused($typing).onSubmit(search).accessibilityLabel("Search YouTube or paste a video link")
                    Button("Search", action: search)
                        .buttonStyle(.borderedProminent).controlSize(.large).tint(FocusTheme.accent)
                        .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.leading, 16).padding(.trailing, 6).padding(.vertical, 6)
                .background(FocusTheme.surface, in: RoundedRectangle(cornerRadius: FocusTheme.corner))

                ViewThatFits(in: .horizontal) {
                    quickLinks
                    VStack(spacing: 10) { subscriptionsLink; accountLink }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Your channels").font(.headline)
                    if !account.configured {
                        Text("Subscription sync is not configured on this build.").font(.caption).foregroundStyle(.secondary)
                    } else if !account.signedIn {
                        Text("Connect Google to see recent uploads from your channels.").font(.subheadline).foregroundStyle(.secondary)
                        Button("Connect with Google") { Task { await account.signIn(); if account.signInSucceeded { await account.sync(); await account.refreshFreshVideosIfNeeded() } } }.buttonStyle(.bordered)
                    } else {
                        if let channel = account.connectedChannel { Text("Connected channel: \(channel)").font(.caption).foregroundStyle(.secondary) }
                        if !account.hasRefreshToken { Text("Google did not provide a refresh token. You may need to reconnect when this session expires.").font(.caption).foregroundStyle(.secondary) }
                        HStack {
                            Button("Choose channels") { showChannels = true }.buttonStyle(.bordered).disabled(account.busy)
                            Button("Refresh") { Task { await account.sync(); if account.syncSucceeded { await loadSelectedUploads() } } }.buttonStyle(.bordered).disabled(account.busy)
                            if account.busy { ProgressView().controlSize(.small) }
                        }
                        Picker("Sort uploads", selection: $uploadOrder) {
                            Text("Newest").tag(FocusRecommendations.Order.newest)
                            Text("Oldest").tag(FocusRecommendations.Order.oldest)
                        }.pickerStyle(.menu)
                        if !account.uploads.isEmpty {
                            Text("Up to 60 recent uploads. Sorting applies to this list; unknown publication dates appear last.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(FocusRecommendations.sortByPublication(account.uploads, order: uploadOrder, date: { $0.publishedAt })) { video in
                            Button { browser.open(URL(string: "https://m.youtube.com/watch?v=" + video.id)!) } label: {
                                recommendationRow(FocusRecommendation(id: video.id, title: video.title, channel: video.channel, topic: "Computing", reason: "From a selected subscription", publishedAt: video.publishedAt))
                            }.buttonStyle(.plain)
                        }
                        Button("Disconnect subscriptions", role: .destructive) { account.signOut(); selectedChannelIDs = "" }.font(.footnote)
                        Button("Reconnect Google account") { Task { await account.signIn(); if account.signInSucceeded { await account.sync(); if account.syncSucceeded { await loadSelectedUploads() }; await account.refreshFreshVideosIfNeeded() } } }.font(.footnote).disabled(account.busy)
                    }
                    if let notice = account.notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
                    Text("Playback uses a separate YouTube sign-in.").font(.caption).foregroundStyle(.secondary)
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(FocusTheme.surface, in: RoundedRectangle(cornerRadius: FocusTheme.corner))
                .overlay(RoundedRectangle(cornerRadius: FocusTheme.corner).stroke(FocusTheme.border))

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Selected videos").font(.title2.bold())
                        Spacer()
                        if discovery.loading { ProgressView().controlSize(.small) }
                        else {
                            Button {
                                Task { await discovery.refresh() }
                                Task { await account.refreshFreshVideos(force: true) }
                            } label: { Image(systemName: "arrow.clockwise").frame(width: 44, height: 44) }
                                .accessibilityLabel("Refresh recommendations")
                        }
                        Button { showRecommendationSettings = true } label: { Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44) }
                            .accessibilityLabel("Recommendation preferences")
                    }
                    if let date = discovery.lastUpdated {
                        Text("HackerTube updated \(date.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("HackerTube offline selection").font(.caption).foregroundStyle(.secondary)
                    }
                    if let notice = discovery.notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
                    if account.freshLoading { ProgressView("Updating YouTube searches").font(.caption) }
                    if let date = account.freshLastUpdated {
                        Text("YouTube searches updated \(date.formatted(date: .abbreviated, time: .shortened)) · automatic refresh daily")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let notice = account.freshNotice { Text(notice).font(.caption).foregroundStyle(.secondary) }
                    Text("\(visibleVideos.count) videos").font(.caption).foregroundStyle(.secondary)
                    if let feedback = recommendationFeedback, previousRecommendationPreferences != nil {
                        HStack {
                            Text(feedback).font(.footnote).foregroundStyle(.secondary)
                            Spacer()
                            Button("Undo") { undoRecommendationChange() }
                        }
                        .accessibilityElement(children: .contain)
                    }
                    Picker("Sort recommendations", selection: $recommendationOrder) {
                        ForEach(FocusRecommendations.Order.allCases) { order in Text(order.rawValue).tag(order) }
                    }.pickerStyle(.menu)
                    Text("Sorts the videos currently loaded. The age filter can exclude videos without a known date.")
                        .font(.caption).foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(topics, id: \.self) { topic in
                                Button { selectedTopic = topic; recommendationLimit = 15 } label: {
                                    Text(topic).font(.subheadline.weight(.medium)).padding(.horizontal, 14).padding(.vertical, 9)
                                        .frame(minHeight: 44)
                                        .foregroundStyle(selectedTopic == topic ? FocusTheme.background : Color.primary)
                                        .background(selectedTopic == topic ? FocusTheme.accent : FocusTheme.surface, in: Capsule())
                                }.buttonStyle(.plain).accessibilityAddTraits(selectedTopic == topic ? .isSelected : [])
                            }
                        }
                    }
                    if visibleVideos.isEmpty {
                        Text("No videos match these filters. Try a longer time range, another topic, or refresh.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    ForEach(Array(visibleVideos.prefix(recommendationLimit))) { video in
                        HStack(alignment: .top, spacing: 4) {
                            Button { browser.open(video.url) } label: { recommendationRow(video) }.buttonStyle(.plain)
                            Menu {
                                Button { updateRecommendationPreferences(message: "Saved. Use Recommended order to see the effect.") { $0.moreLike(video) } } label: {
                                    Label("More like this", systemImage: "hand.thumbsup")
                                }
                                Button { updateRecommendationPreferences(message: "Video hidden from recommendations.") { $0.hide(video) } } label: {
                                    Label("Not interested", systemImage: "eye.slash")
                                }
                            } label: {
                                Image(systemName: "ellipsis").frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("Recommendation options for \(video.title)")
                        }
                    }
                    if visibleVideos.count > recommendationLimit {
                        Button("Show 15 more") { recommendationLimit += 15 }
                            .buttonStyle(.bordered).controlSize(.large)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Selections from HackerTube, based on open-index/hacker-news. Data: ODC-By 1.0.")
                        HStack {
                            Link("HackerTube", destination: URL(string: "https://hackertube.org/data")!)
                            Link("Hacker News dataset", destination: URL(string: "https://huggingface.co/datasets/open-index/hacker-news")!)
                            Link("License", destination: URL(string: "https://opendatacommons.org/licenses/by/1-0/")!)
                        }
                    }.font(.footnote).foregroundStyle(.secondary).padding(.top, 4)
                }

                if !browser.saved.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Saved videos").font(.title2.bold())
                        ForEach(browser.saved) { film in
                            HStack {
                                Button { if let url = URL(string: film.url) { browser.open(url) } } label: { Label(film.title, systemImage: "play.circle").multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10) }
                                Button(role: .destructive) { browser.remove(film) } label: { Image(systemName: "trash").padding(10) }.accessibilityLabel("Remove saved video")
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Explore channels").font(.title2.bold())
                    Text("Search YouTube for these channels.").font(.subheadline).foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(FocusRecommendations.channels) { channel in
                                Button { browser.submit(channel.query) } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Image(systemName: "play.rectangle.fill").foregroundStyle(FocusTheme.accent)
                                        Text(channel.name).font(.subheadline.weight(.semibold)).lineLimit(2).multilineTextAlignment(.leading)
                                        Text(channel.topic).font(.caption).foregroundStyle(.secondary)
                                    }.frame(width: 130, alignment: .topLeading).frame(minHeight: 100, alignment: .topLeading).padding(14)
                                        .background(FocusTheme.surface, in: RoundedRectangle(cornerRadius: FocusTheme.corner))
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }



            }.padding(.horizontal, 20).padding(.bottom, 32)
        }.scrollDismissesKeyboard(.interactively)
    }

    private var quickLinks: some View {
        HStack(spacing: 10) { subscriptionsLink; accountLink }
    }

    private var subscriptionsLink: some View {
        Button { browser.open(URL(string: "https://m.youtube.com/feed/subscriptions")!) } label: {
            Label("Subscriptions", systemImage: "rectangle.stack")
                .frame(maxWidth: .infinity, minHeight: 44)
        }.buttonStyle(.bordered).tint(.primary).font(.subheadline.weight(.medium))
    }

    private var accountLink: some View {
        Button { browser.open(URL(string: "https://m.youtube.com/channel_switcher")!) } label: {
            Label("Account", systemImage: "person.crop.circle")
                .frame(maxWidth: .infinity, minHeight: 44)
        }.buttonStyle(.bordered).tint(.primary).font(.subheadline.weight(.medium))
    }

    private func recommendationRow(_ video: FocusRecommendation) -> some View {
        HStack(alignment: .top, spacing: 14) {
            AsyncImage(url: URL(string: "https://i.ytimg.com/vi/\(video.id)/mqdefault.jpg")) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Rectangle().fill(FocusTheme.surface).overlay(Image(systemName: "play.fill").foregroundStyle(FocusTheme.accent))
            }
            .frame(width: 120, height: 68).clipped().clipShape(RoundedRectangle(cornerRadius: 9)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(video.title).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                Text(video.channel).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                if let date = video.publishedAt {
                    Text("Published \(date.formatted(date: .abbreviated, time: .omitted))").font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text("Publication date unavailable").font(.caption2).foregroundStyle(.secondary)
                }
                Text(video.reason).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8).frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .contentShape(Rectangle()).accessibilityElement(children: .combine)
    }

    private var recommendationPreferences: FocusRankingPreferences {
        guard let data = recommendationPreferencesJSON.data(using: .utf8),
              let stored = try? JSONDecoder().decode(FocusRankingPreferences.self, from: data) else { return .init() }
        return stored
    }

    private func saveRecommendationPreferences(_ preferences: FocusRankingPreferences) -> Bool {
        guard let data = try? JSONEncoder().encode(preferences),
              let json = String(data: data, encoding: .utf8) else { return false }
        recommendationPreferencesJSON = json
        return true
    }

    private func updateRecommendationPreferences(message: String, _ update: (inout FocusRankingPreferences) -> Void) {
        let previous = recommendationPreferences
        var updated = previous
        update(&updated)
        guard updated != previous, saveRecommendationPreferences(updated) else { return }
        previousRecommendationPreferences = previous
        recommendationFeedback = message
        recommendationLimit = 15
    }

    private func undoRecommendationChange() {
        guard let previous = previousRecommendationPreferences,
              saveRecommendationPreferences(previous) else { return }
        previousRecommendationPreferences = nil
        recommendationFeedback = nil
    }

    private var recommendationSettings: some View {
        NavigationStack {
            Form {
                Section("Video age") {
                    Picker("Published", selection: Binding<Int?>(
                        get: { recommendationPreferences.maxAgeMonths },
                        set: { age in updateRecommendationPreferences(message: "Age filter updated.") { $0.maxAgeMonths = age } }
                    )) {
                        Text("Any age").tag(Optional<Int>.none)
                        Text("Past year").tag(Optional.some(12))
                        Text("Past 2 years").tag(Optional.some(24))
                        Text("Past 3 years").tag(Optional.some(36))
                    }
                    Text("Videos without a known publication date are hidden when an age limit is selected.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Feedback") {
                    Button("Show hidden videos (\(recommendationPreferences.hiddenIDs.count))") {
                        updateRecommendationPreferences(message: "Hidden videos restored.") { $0.unhideAll() }
                    }.disabled(recommendationPreferences.hiddenIDs.isEmpty)
                    Button("Reset recommendation preferences", role: .destructive) { confirmRecommendationReset = true }
                        .disabled(recommendationPreferences == .init())
                    if let feedback = recommendationFeedback, previousRecommendationPreferences != nil {
                        HStack {
                            Text(feedback).font(.footnote).foregroundStyle(.secondary)
                            Spacer()
                            Button("Undo") { undoRecommendationChange() }
                        }
                    }
                    Text("More like this affects Recommended order.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Privacy") {
                    Text("Your feedback and age filter stay on this device. Resetting them does not change your YouTube subscriptions.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Recommendations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showRecommendationSettings = false } } }
            .confirmationDialog("Reset recommendation preferences?", isPresented: $confirmRecommendationReset, titleVisibility: .visible) {
                Button("Reset preferences", role: .destructive) {
                    updateRecommendationPreferences(message: "Preferences reset.") { $0 = .init() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This clears feedback and the age filter on this device. Your subscriptions stay the same.")
            }
        }
    }

    private func search() { typing = false; browser.submit(input) }
    private var selectedIDs: Set<String> { Set(selectedChannelIDs.split(separator: ",").map(String.init)) }
    private func loadSelectedUploads() async {
        let selected = account.channels.filter { selectedIDs.contains($0.id) }
        if selected.isEmpty { account.clearUploads() }
        else { await account.loadUploads(for: selected) }
    }
    private var subscriptionPicker: some View {
        NavigationStack {
            List {
                Section("Choose up to 30 channels") {
                    ForEach(account.channels) { channel in
                        Button {
                            var selection = selectedIDs
                            if selection.contains(channel.id) { selection.remove(channel.id) }
                            else if selection.count < 30 { selection.insert(channel.id) }
                            selectedChannelIDs = selection.sorted().joined(separator: ",")
                        } label: {
                            HStack { Text(channel.title); Spacer(); if selectedIDs.contains(channel.id) { Image(systemName: "checkmark") } }
                        }.disabled(account.busy)
                    }
                }
            }.navigationTitle("Subscriptions")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showChannels = false; Task { await loadSelectedUploads() } }.disabled(account.busy)
                    }
                }
        }
    }
}
