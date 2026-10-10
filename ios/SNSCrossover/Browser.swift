import SwiftUI
import WebKit

/// SNS 1 つ分のブラウザ画面。画面セットを切り替えても読み込み直さないよう、アプリ起動中は使い回す。
@MainActor
final class Browser: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    let sns: SNS
    let webView: WKWebView
    @Published var canGoBack = false
    @Published var isLoading = false
    /// 「Google でログイン」などで開かれた小窓
    @Published var popup: Popup?

    struct Popup: Identifiable {
        let id = UUID()
        let webView: WKWebView
    }

    private var observations: [NSKeyValueObservation] = []
    private var loaded = false

    init(sns: SNS) {
        self.sns = sns
        let config = WKWebViewConfiguration()
        // ログイン状態はアプリを閉じても残る
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        // Google などはアプリ内ブラウザからのログインを拒否するので、Safari と同じ名乗り方をする
        let iosVersion = UIDevice.current.systemVersion.split(separator: ".").first ?? "18"
        config.applicationNameForUserAgent = "Version/\(iosVersion).0 Mobile/15E148 Safari/604.1"
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground

        // 下に引っぱって更新
        let refresh = UIRefreshControl()
        refresh.addTarget(self, action: #selector(pullToRefresh), for: .valueChanged)
        webView.scrollView.refreshControl = refresh

        observations = [
            webView.observe(\.canGoBack) { [weak self] webView, _ in
                DispatchQueue.main.async { self?.canGoBack = webView.canGoBack }
            },
            webView.observe(\.isLoading) { [weak self] webView, _ in
                DispatchQueue.main.async { self?.isLoading = webView.isLoading }
            },
        ]
    }

    /// 初めて表示されたときに読み込む
    func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        webView.load(URLRequest(url: sns.home))
    }

    func goHome() { webView.load(URLRequest(url: sns.home)) }
    func goBack() { webView.goBack() }
    func reload() { webView.reload() }

    @objc private func pullToRefresh() { webView.reload() }

    private func endRefreshing() { webView.scrollView.refreshControl?.endRefreshing() }

    private func isAllowed(_ url: URL) -> Bool {
        switch url.scheme {
        case "http", "https": url.hostMatches(sns.domains) || url.hostMatches(authDomains)
        case "about", "data", "blob": true
        default: false
        }
    }

    private func openInSafari(_ url: URL) {
        guard url.scheme == "http" || url.scheme == "https" else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else { return .allow }
        // 広告や埋め込みなど、ページ内の部品の読み込みはそのまま許可
        guard navigationAction.targetFrame?.isMainFrame ?? true else { return .allow }
        if isAllowed(url) { return .allow }
        // ニュース記事など SNS の外へのリンクは Safari で開く
        openInSafari(url)
        return .cancel
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { endRefreshing() }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { endRefreshing() }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        endRefreshing()
        let code = (error as NSError).code
        guard code != NSURLErrorCancelled, code != 102 /* WebKit のフレーム読み込み中断 */ else { return }
        webView.loadHTMLString(errorPage(error.localizedDescription), baseURL: nil)
    }

    private func errorPage(_ message: String) -> String {
        """
        <!doctype html><meta name="viewport" content="width=device-width,initial-scale=1">
        <body style="font:16px -apple-system;text-align:center;padding:40px 20px;color:#888">
        <p style="font-weight:600;color:inherit">\(sns.name) を読み込めませんでした</p>
        <p>\(message.replacingOccurrences(of: "<", with: "&lt;"))</p>
        <p><a href="\(sns.home.absoluteString)">もう一度読み込む</a></p>
        """
    }

    // MARK: - WKUIDelegate

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        let url = navigationAction.request.url
        // ログイン用の小窓は、元の画面とつながったまま開く必要がある
        if url == nil || url?.absoluteString == "about:blank" || url!.hostMatches(authDomains) {
            let popupView = WKWebView(frame: .zero, configuration: configuration)
            popupView.uiDelegate = self
            popup = Popup(webView: popupView)
            return popupView
        }
        // 同じ SNS 内の「新しいタブで開く」はこの画面の中で開く
        if let url {
            if isAllowed(url) { webView.load(navigationAction.request) } else { openInSafari(url) }
        }
        return nil
    }

    func webViewDidClose(_ webView: WKWebView) {
        if popup?.webView === webView { popup = nil }
    }
}

/// SNS ごとの Browser を持っておく入れ物
@MainActor
final class BrowserStore: ObservableObject {
    private var browsers: [SNS: Browser] = [:]

    func browser(for sns: SNS) -> Browser {
        if let browser = browsers[sns] { return browser }
        let browser = Browser(sns: sns)
        browsers[sns] = browser
        return browser
    }
}

/// WKWebView を SwiftUI の画面に置くための部品。
/// 画面セットを切り替えたときは、同じ WKWebView を新しい置き場所へ移し替える。
struct WebViewContainer: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        attach(to: container)
        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        if webView.superview !== container { attach(to: container) }
    }

    private func attach(to container: UIView) {
        webView.removeFromSuperview()
        webView.frame = container.bounds
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(webView)
    }
}
