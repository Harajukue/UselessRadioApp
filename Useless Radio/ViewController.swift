import UIKit
import WebKit
import SafariServices

class ViewController: UIViewController {

    // MARK: - Config
    private let websiteURL = URL(string: "https://uselessradio.com")!

    // MARK: - UI
    var webView: WKWebView!
    private var loadingIndicator: UIActivityIndicatorView!
    private var progressView: UIProgressView!
    private var progressObserver: NSKeyValueObservation?

    // MARK: - Lifecycle
    override func loadView() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        config.websiteDataStore = WKWebsiteDataStore.default()
        config.userContentController.add(self, name: "retryLoad")

        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .always
        // Spoof Safari UA — fixes Google's "disallowed_useragent" OAuth block
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1"

        // Use safe area so content doesn't hide under the status bar
        super.loadView()
        view.backgroundColor = .black
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupProgressBar()
        setupLoadingIndicator()
        setupRefreshControl()
        loadWebsite()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: false)
    }

    // MARK: - Setup
    private func setupProgressBar() {
        progressView = UIProgressView(progressViewStyle: .default)
        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.tintColor = .systemBlue
        view.addSubview(progressView)
        NSLayoutConstraint.activate([
            progressView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            progressView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progressView.heightAnchor.constraint(equalToConstant: 2)
        ])
        progressObserver = webView.observe(\.estimatedProgress, options: .new) { [weak self] _, change in
            let progress = Float(change.newValue ?? 0)
            self?.progressView.setProgress(progress, animated: true)
            self?.progressView.isHidden = progress >= 1.0
        }
    }

    private func setupLoadingIndicator() {
        loadingIndicator = UIActivityIndicatorView(style: .large)
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.color = .systemGray
        loadingIndicator.hidesWhenStopped = true
        view.addSubview(loadingIndicator)
        NSLayoutConstraint.activate([
            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func setupRefreshControl() {
        let refresh = UIRefreshControl()
        refresh.addTarget(self, action: #selector(refreshWebView), for: .valueChanged)
        webView.scrollView.addSubview(refresh)
    }

    // MARK: - Actions
    private func loadWebsite() {
        loadingIndicator.startAnimating()
        let request = URLRequest(url: websiteURL, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 30)
        webView.load(request)
    }

    @objc private func refreshWebView(_ sender: UIRefreshControl) {
        webView.reload()
        sender.endRefreshing()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
}

// MARK: - WKNavigationDelegate
extension ViewController: WKNavigationDelegate {

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        loadingIndicator.startAnimating()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadingIndicator.stopAnimating()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadingIndicator.stopAnimating()
        showOfflinePage()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loadingIndicator.stopAnimating()
        let nsError = error as NSError
        if nsError.code == NSURLErrorCancelled { return }
        showOfflinePage()
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        let host = url.host ?? ""
        let allowedHosts = [
            "useless.radio",
            "uselessradio.com",
            "npomoktgwlmpwlmfcgeb.supabase.co",
            "accounts.google.com",
            "oauth2.googleapis.com",
            "appleid.apple.com"
        ]

        if url.scheme == "uselessradio" {
            // OAuth callback deep link — let SceneDelegate handle it
            decisionHandler(.cancel)
            return
        }

        if allowedHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
            decisionHandler(.allow)
            return
        }

        if (url.scheme == "https" || url.scheme == "http") && navigationAction.navigationType == .linkActivated {
            let safari = SFSafariViewController(url: url)
            present(safari, animated: true)
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    private func showOfflinePage() {
        let html = """
        <html><body style="font-family:-apple-system;display:flex;flex-direction:column;
        align-items:center;justify-content:center;height:100vh;text-align:center;color:#555;background:#000;">
        <h2 style="color:#fff;">You're offline</h2>
        <p style="color:#aaa;">Check your connection and try again.</p>
        <button onclick="window.webkit.messageHandlers.retryLoad.postMessage(null)"
        style="padding:12px 24px;border-radius:8px;border:none;background:#fff;color:#000;font-size:16px;margin-top:16px;">Retry</button>
        </body></html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }
}

// MARK: - WKScriptMessageHandler
extension ViewController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "retryLoad" {
            loadWebsite()
        }
    }
}

// MARK: - WKUIDelegate
extension ViewController: WKUIDelegate {
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            let safari = SFSafariViewController(url: url)
            present(safari, animated: true)
        }
        return nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        present(alert, animated: true)
    }
}
