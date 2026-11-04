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

struct FocusScreen: View {
    @ObservedObject var browser: FocusBrowser
    @State private var input = ""
    @State private var showInfo = false
    @State private var selectedTopic = "All"
    @State private var recommendationOrder = FocusRecommendations.Order.recommended
    @State private var uploadOrder = FocusRecommendations.Order.newest
    @StateObject private var discovery = FocusDiscovery()
    @StateObject private var account = FocusYouTubeAccount()
    @AppStorage("focus.subscriptionSelection.v1") private var selectedChannelIDs = ""
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
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 300_000_000_000)
                    guard !Task.isCancelled else { break }
                    if scenePhase == .active {
                        await discovery.refreshIfNeeded()
                        if await account.syncIfNeeded() { await loadSelectedUploads() }
                    }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task {
                        await discovery.refreshIfNeeded()
                        if await account.syncIfNeeded() { await loadSelectedUploads() }
                    }
                }
            }
            .sheet(isPresented: $showInfo) {
                NavigationStack { ScrollView { VStack(alignment: .leading, spacing: 18) {
                    Text("About Focus Tube").font(.title.bold())
                    Text("Search YouTube without Shorts or an endless feed. Results load 15 at a time.")
                    Text("YouTube handles playback and sign-in. Google may block sign-in here. Premium, picture in picture and background playback need testing on your device. Offline playback is unavailable.")
                    Text("HackerTube picks are separate from Google subscription sync. Saved videos stay on this device. This app does not block the official YouTube app.").foregroundStyle(.secondary)
                    Text("Page check").font(.headline)
                    Text("Run this while a YouTube page is open. It shows filter state and element counts; it does not show account details or page text.").font(.footnote).foregroundStyle(.secondary)
                    Button("Check current page") { browser.inspectPage() }.buttonStyle(.bordered)
                    Text(browser.diagnostics).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                    Text("Focus Tube 0.5.0 development").font(.footnote)
                }.padding(24) }.navigationTitle("About").toolbar { Button("Done") { showInfo = false } } }
            }
            .sheet(isPresented: $showChannels) { subscriptionPicker }
        }
    }
    private var topics: [String] {
        ["All"] + FocusRecommendations.topics
    }

    private var visibleVideos: [FocusRecommendation] {
        let items = discovery.videos.isEmpty ? FocusRecommendations.videos : discovery.videos
        let filtered = selectedTopic == "All" ? items : items.filter { $0.topic == selectedTopic }
        let names = account.channels.filter { selectedIDs.contains($0.id) }.map(\.title)
        let preferred = FocusRecommendations.prioritize(filtered, selectedChannelNames: names)
        return FocusRecommendations.sortByPublication(preferred, order: recommendationOrder, date: { $0.publishedAt })
    }

    private var startScreen: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("FOCUS TUBE").font(.caption.weight(.bold)).tracking(1.4).foregroundStyle(FocusTheme.accent)
                    Text("What would you like to watch?").font(.largeTitle.weight(.bold)).fixedSize(horizontal: false, vertical: true)
                    Text("Search YouTube or choose a video below.").foregroundStyle(.secondary)
                }.padding(.top, 12)

                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search or paste a video link", text: $input)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.search).focused($typing).onSubmit(search)
                    }.padding(16).background(FocusTheme.surface, in: RoundedRectangle(cornerRadius: FocusTheme.corner))
                    Button(action: search) { Text("Search YouTube").fontWeight(.semibold).frame(maxWidth: .infinity).padding(.vertical, 8) }
                        .buttonStyle(.borderedProminent).disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                HStack(spacing: 10) {
                    Button { browser.open(URL(string: "https://m.youtube.com/feed/subscriptions")!) } label: {
                        Label("Subscriptions", systemImage: "rectangle.stack").frame(maxWidth: .infinity).padding(.vertical, 8)
                    }
                    Button { browser.open(URL(string: "https://m.youtube.com/channel_switcher")!) } label: {
                        Label("Account", systemImage: "person.crop.circle").frame(maxWidth: .infinity).padding(.vertical, 8)
                    }
                }.buttonStyle(.bordered).font(.subheadline.weight(.medium))

                VStack(alignment: .leading, spacing: 12) {
                    Text("Your channels").font(.title2.bold())
                    Text("Choose subscribed channels for recent uploads. Google account access for playback is separate.").font(.subheadline).foregroundStyle(.secondary)
                    if !account.configured {
                        Text("Subscription sync needs an iOS Google OAuth client configured for this app.").font(.caption).foregroundStyle(.secondary)
                    } else if !account.signedIn {
                        Button("Connect subscriptions") { Task { await account.signIn(); if account.signInSucceeded { await account.sync() } } }.buttonStyle(.bordered)
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
                        Button("Reconnect Google account") { Task { await account.signIn(); if account.signInSucceeded { await account.sync(); if account.syncSucceeded { await loadSelectedUploads() } } } }.font(.footnote).disabled(account.busy)
                    }
                    if let notice = account.notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
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
                    Text("Explore your interests").font(.title2.bold())
                    Text("Channel searches based on your interests.").font(.subheadline).foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(FocusRecommendations.channels) { channel in
                                Button { browser.submit(channel.query) } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Image(systemName: "play.rectangle.fill").foregroundStyle(FocusTheme.accent)
                                        Text(channel.name).font(.subheadline.weight(.semibold)).lineLimit(2).multilineTextAlignment(.leading)
                                        Text(channel.topic).font(.caption).foregroundStyle(.secondary)
                                    }.frame(width: 130, height: 100, alignment: .topLeading).padding(14)
                                        .background(FocusTheme.surface, in: RoundedRectangle(cornerRadius: FocusTheme.corner))
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Selected videos").font(.title2.bold())
                        Spacer()
                        if discovery.loading { ProgressView().controlSize(.small) }
                        else {
                            Button { Task { await discovery.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                                .accessibilityLabel("Refresh recommendations")
                        }
                    }
                    Text("HackerTube picks from preset topics. Videos from channels whose names match your selected subscriptions appear first. Matching happens on this device; names may not be unique.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if let date = discovery.lastUpdated {
                        Text("Updated \(date.formatted(date: .abbreviated, time: .shortened)) · \(visibleVideos.count) videos")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Offline selection · \(visibleVideos.count) videos").font(.caption).foregroundStyle(.secondary)
                    }
                    if let notice = discovery.notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
                    Picker("Sort recommendations", selection: $recommendationOrder) {
                        ForEach(FocusRecommendations.Order.allCases) { order in Text(order.rawValue).tag(order) }
                    }.pickerStyle(.menu)
                    Text("Sorts the videos currently loaded. Videos with unknown publication dates appear last.")
                        .font(.caption).foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(topics, id: \.self) { topic in
                                Button { selectedTopic = topic } label: {
                                    Text(topic).font(.subheadline.weight(.medium)).padding(.horizontal, 14).padding(.vertical, 9)
                                        .foregroundStyle(selectedTopic == topic ? FocusTheme.background : Color.primary)
                                        .background(selectedTopic == topic ? FocusTheme.accent : FocusTheme.surface, in: Capsule())
                                }.buttonStyle(.plain).accessibilityAddTraits(selectedTopic == topic ? .isSelected : [])
                            }
                        }
                    }
                    ForEach(visibleVideos) { video in
                        Button { browser.open(video.url) } label: { recommendationRow(video) }.buttonStyle(.plain)
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


            }.padding(.horizontal, 20).padding(.bottom, 32)
        }.scrollDismissesKeyboard(.interactively)
    }

    private func recommendationRow(_ video: FocusRecommendation) -> some View {
        HStack(alignment: .top, spacing: 12) {
            AsyncImage(url: URL(string: "https://i.ytimg.com/vi/\(video.id)/mqdefault.jpg")) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Rectangle().fill(FocusTheme.surface).overlay(Image(systemName: "play.fill").foregroundStyle(FocusTheme.accent))
            }
            .frame(width: 112, height: 72).clipped().clipShape(RoundedRectangle(cornerRadius: 10)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(video.title).font(.subheadline.weight(.semibold)).lineLimit(3).multilineTextAlignment(.leading)
                Text(video.channel).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if let date = video.publishedAt {
                    Text("Published \(date.formatted(date: .abbreviated, time: .omitted))").font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text("Publication date unavailable").font(.caption2).foregroundStyle(.secondary)
                }
                Text(video.reason).font(.caption2).foregroundStyle(FocusTheme.accent).lineLimit(2).multilineTextAlignment(.leading)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(FocusTheme.surface, in: RoundedRectangle(cornerRadius: FocusTheme.corner))
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
