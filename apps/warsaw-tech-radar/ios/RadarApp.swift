import SwiftUI
import WebKit

@main
struct RadarApp: App {
    var body: some Scene {
        WindowGroup { RadarBrowser().ignoresSafeArea(.container, edges: .bottom) }
    }
}

struct RadarBrowser: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        let keys = ["warsaw-radar-v1", "warsaw-radar-snapshot-v1"]
        var values: [String: String] = [:]
        for key in keys { values[key] = UserDefaults.standard.string(forKey: "native." + key) }
        let state = (try? JSONSerialization.data(withJSONObject: values)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        controller.addUserScript(WKUserScript(source: "window.__RADAR_NATIVE_STATE__ = \(state);", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        controller.add(context.coordinator, name: "radar")
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.allowsBackForwardNavigationGestures = true
        view.isOpaque = false
        view.backgroundColor = UIColor(red: 0.957, green: 0.965, blue: 0.949, alpha: 1)
        context.coordinator.webView = view
        if let page = Bundle.main.url(forResource: "radar", withExtension: "html") {
            view.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
        }
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
        weak var webView: WKWebView?
        private let permittedKeys = Set(["warsaw-radar-v1", "warsaw-radar-snapshot-v1"])
        private let permittedHosts = Set(["luma.com", "www.luma.com", "lu.ma", "www.lu.ma", "evenea.pl", "www.evenea.pl", "app.evenea.pl"])

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame, message.frameInfo.request.url?.isFileURL == true,
                  let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            if type == "store", let key = body["key"] as? String, permittedKeys.contains(key),
               let value = body["value"] as? String, value.utf8.count <= 4_000_000 {
                UserDefaults.standard.set(value, forKey: "native." + key)
            } else if type == "share", let value = body["content"] as? String, value.utf8.count <= 4_000_000,
                      let id = body["id"] as? String, id.count < 30,
                      let filename = body["filename"] as? String, ["wydarzenie.ics", "warsaw-radar-kopia.json"].contains(filename) {
                do {
                    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    let url = folder.appendingPathComponent(filename)
                    try Data(value.utf8).write(to: url)
                    let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                    sheet.completionWithItemsHandler = { _, _, _, _ in try? FileManager.default.removeItem(at: folder) }
                    if let popover = sheet.popoverPresentationController { popover.sourceView = webView; popover.sourceRect = CGRect(x: 20, y: 20, width: 1, height: 1) }
                    var presenter = webView?.window?.rootViewController
                    while let next = presenter?.presentedViewController { presenter = next }
                    guard let presenter else { complete(id, ["error": "Nie można otworzyć udostępniania."]); return }
                    presenter.present(sheet, animated: true) { self.complete(id, ["ok": true]) }
                } catch { complete(id, ["error": "Nie udało się zapisać pliku do udostępnienia."]) }
            } else if type == "fetch", let id = body["id"] as? String, id.count < 30,
                      let raw = body["url"] as? String, let url = URL(string: raw) {
                guard url.scheme == "https", let host = url.host?.lowercased(), permittedHosts.contains(host),
                      url.user == nil, url.password == nil, url.port == nil || url.port == 443 else {
                    complete(id, ["error": "Niedozwolony adres źródła."]); return
                }
                Task { [weak self] in
                    do {
                        let response = try await PublicPageReader().read(url)
                        await MainActor.run { self?.complete(id, response) }
                    } catch {
                        await MainActor.run { self?.complete(id, ["error": "Nie udało się pobrać publicznej strony. Źródło może ograniczać odczyt."]) }
                    }
                }
            }
        }

        private func complete(_ id: String, _ result: [String: Any]) {
            guard let arguments = try? JSONSerialization.data(withJSONObject: [id, result]), let text = String(data: arguments, encoding: .utf8) else { return }
            webView?.evaluateJavaScript("window.__radarNativeComplete(...\(text));", completionHandler: nil)
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { decisionHandler(.cancel); return }
            if url.isFileURL || url.absoluteString == "about:blank" { decisionHandler(.allow); return }
            if action.navigationType == .linkActivated, ["https", "http"].contains(url.scheme ?? "") { UIApplication.shared.open(url) }
            decisionHandler(.cancel)
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = action.request.url, ["https", "http"].contains(url.scheme ?? "") { UIApplication.shared.open(url) }
            return nil
        }
    }
}

// One bounded, cookie-free request. Redirects are returned to the shared JS collector,
// which validates each destination before issuing the next request.
private final class PublicPageReader: NSObject, URLSessionDataDelegate, URLSessionTaskDelegate {
    private var continuation: CheckedContinuation<[String: Any], Error>?
    private var response: HTTPURLResponse?
    private var bytes = Data()
    private var boundedError: Error?
    private var session: URLSession?
    private let maximum = 2_000_000

    func read(_ url: URL) async throws -> [String: Any] {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let config = URLSessionConfiguration.ephemeral
            config.httpCookieStorage = nil
            config.httpShouldSetCookies = false
            config.timeoutIntervalForRequest = 12
            config.timeoutIntervalForResource = 15
            let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
            self.session = session
            var request = URLRequest(url: url)
            request.setValue("text/html, application/ld+json, application/json", forHTTPHeaderField: "Accept")
            request.setValue("WarsawTechRadar/1.0 (personal public event reader)", forHTTPHeaderField: "User-Agent")
            session.dataTask(with: request).resume()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse, response.expectedContentLength <= Int64(maximum) else {
            boundedError = URLError(.dataLengthExceedsMaximum); completionHandler(.cancel); return
        }
        self.response = http
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if bytes.count + data.count > maximum { boundedError = URLError(.dataLengthExceedsMaximum); dataTask.cancel() }
        else { bytes.append(data) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        defer { continuation = nil; session.finishTasksAndInvalidate(); self.session = nil }
        if let error = boundedError ?? error { continuation?.resume(throwing: error); return }
        guard let response else { continuation?.resume(throwing: URLError(.badServerResponse)); return }
        var headers: [String: String] = [:]
        for key in ["Content-Type", "Location", "Content-Length"] { if let value = response.value(forHTTPHeaderField: key) { headers[key] = value } }
        continuation?.resume(returning: ["status": response.statusCode, "headers": headers, "body": String(decoding: bytes, as: UTF8.self)])
    }
}
