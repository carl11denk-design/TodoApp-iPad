import SwiftUI
import WebKit
import QuickLook

// MARK: - Moodle WebView Tab

struct MoodleView: View {
    @AppStorage("dualis_username") private var storedUsername = ""

    @State private var isLoading = true
    @State private var pageTitle = "Moodle"
    @State private var canGoBack = false
    @State private var canGoForward = false
    @State private var webView: WKWebView?
    @State private var previewURL: URL?

    private let moodleCoursesURL = "https://elearning.dhbw-stuttgart.de/moodle/my/courses.php"

    private var storedPassword: String {
        guard let data = UserDefaults.standard.data(forKey: "dualis_password"),
              let pw = String(data: data, encoding: .utf8) else { return "" }
        return pw
    }

    var body: some View {
        VStack(spacing: 0) {
            if storedUsername.isEmpty {
                noCredentialsState
            } else {
                ZStack {
                    MoodleWebView(
                        urlString: moodleCoursesURL,
                        username: storedUsername,
                        password: storedPassword,
                        isLoading: $isLoading,
                        pageTitle: $pageTitle,
                        canGoBack: $canGoBack,
                        canGoForward: $canGoForward,
                        webView: $webView,
                        previewURL: $previewURL
                    )

                    if isLoading {
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("Moodle wird geladen…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.ultraThinMaterial)
                    }
                }
            }
        }
        .navigationTitle(pageTitle)
        .toolbar { toolbarContent }
        .sheet(item: $previewURL) { url in
            DocumentPreviewSheet(url: url)
            .ignoresSafeArea()
        }
    }

    private var noCredentialsState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "person.badge.key")
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)
            Text("Keine Zugangsdaten")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Text("Hinterlege deine DHBW-Zugangsdaten in den Einstellungen unter \"DUALIS Zugangsdaten\", um dich automatisch bei Moodle anzumelden.")
                .font(.body)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            Spacer()
        }
        .padding()
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            Button { webView?.goBack() } label: {
                Image(systemName: "chevron.left")
            }.disabled(!canGoBack)

            Button { webView?.goForward() } label: {
                Image(systemName: "chevron.right")
            }.disabled(!canGoForward)

            Button { webView?.reload() } label: {
                Image(systemName: "arrow.clockwise")
            }

            Button {
                if let url = URL(string: moodleCoursesURL) {
                    webView?.load(URLRequest(url: url))
                }
            } label: {
                Image(systemName: "house")
            }
        }
    }
}

// MARK: - Make URL Identifiable for .sheet(item:)

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

// MARK: - Document Preview Sheet (QLPreview + Navigation Bar with Share/Save)

private struct DocumentPreviewSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UINavigationController {
        let qlController = QLPreviewController()
        qlController.dataSource = context.coordinator
        let navController = UINavigationController(rootViewController: qlController)
        return navController
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as QLPreviewItem
        }
    }
}

// MARK: - WKWebView Wrapper

private struct MoodleWebView: UIViewRepresentable {
    let urlString: String
    let username: String
    let password: String

    @Binding var isLoading: Bool
    @Binding var pageTitle: String
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    @Binding var webView: WKWebView?
    @Binding var previewURL: URL?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        // Allow inline media playback
        config.allowsInlineMediaPlayback = true

        let wk = WKWebView(frame: .zero, configuration: config)
        wk.navigationDelegate = context.coordinator
        wk.uiDelegate = context.coordinator
        wk.allowsBackForwardNavigationGestures = true
        wk.customUserAgent = "Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

        DispatchQueue.main.async {
            self.webView = wk
        }

        if let url = URL(string: urlString) {
            wk.load(URLRequest(url: url))
        }

        return wk
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    // MARK: - Coordinator

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
        let parent: MoodleWebView
        private var loginSubmitted = false
        private var loginAttemptCount = 0
        private let maxLoginAttempts = 5
        private var downloadDestURL: URL?

        init(parent: MoodleWebView) {
            self.parent = parent
        }

        // MARK: - Navigation lifecycle

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async { self.parent.isLoading = true }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.canGoBack = webView.canGoBack
                self.parent.canGoForward = webView.canGoForward

                let currentURL = webView.url?.absoluteString ?? ""

                webView.evaluateJavaScript("document.title") { result, _ in
                    if let title = result as? String, !title.isEmpty {
                        DispatchQueue.main.async { self.parent.pageTitle = title }
                    }
                }

                if currentURL.contains("saml.dhbw-stuttgart.de") || currentURL.contains("/idp/") {
                    self.attemptAutoLogin(webView: webView)
                } else {
                    self.parent.isLoading = false
                    self.loginSubmitted = false
                    self.loginAttemptCount = 0
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async { self.parent.isLoading = false }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async { self.parent.isLoading = false }
        }

        // MARK: - WKUIDelegate: handle target="_blank" links (new tab → open in same view)

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            // Moodle opens documents in new tabs — load them in current webview instead
            if let url = navigationAction.request.url {
                print("[MOODLE] target=_blank intercepted: \(url.absoluteString)")
                webView.load(URLRequest(url: url))
            }
            return nil
        }

        // MARK: - Navigation policy: allow everything

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            let url = navigationAction.request.url?.absoluteString ?? "?"
            print("[MOODLE] nav → \(url)")
            decisionHandler(.allow)
        }

        // MARK: - Response policy: only download what WKWebView can't show

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationResponse: WKNavigationResponse,
            decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
        ) {
            guard let response = navigationResponse.response as? HTTPURLResponse else {
                decisionHandler(.allow)
                return
            }

            let contentType = (response.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
            let disposition = (response.value(forHTTPHeaderField: "Content-Disposition") ?? "").lowercased()
            let url = response.url?.absoluteString ?? "?"

            print("[MOODLE] resp ← \(url) type=\(contentType) disp=\(disposition) canShow=\(navigationResponse.canShowMIMEType)")

            // Case 1: Server forces download (Content-Disposition: attachment)
            if disposition.contains("attachment") {
                print("[MOODLE] → download (attachment)")
                DispatchQueue.main.async { self.parent.isLoading = true }
                decisionHandler(.download)
                return
            }

            // Case 2: Document MIME types → download & show in QuickLook
            let docMIMEs = [
                "application/pdf",
                "application/vnd.ms-powerpoint",
                "application/vnd.openxmlformats-officedocument.presentationml",
                "application/msword",
                "application/vnd.openxmlformats-officedocument.wordprocessingml",
                "application/vnd.ms-excel",
                "application/vnd.openxmlformats-officedocument.spreadsheetml"
            ]
            if docMIMEs.contains(where: { contentType.contains($0) }) {
                print("[MOODLE] → download (document MIME: \(contentType))")
                DispatchQueue.main.async { self.parent.isLoading = true }
                decisionHandler(.download)
                return
            }

            // Case 3: WKWebView can't render this content type
            if !navigationResponse.canShowMIMEType {
                print("[MOODLE] → download (can't show MIME)")
                DispatchQueue.main.async { self.parent.isLoading = true }
                decisionHandler(.download)
                return
            }

            // Everything else: let WKWebView handle it normally
            decisionHandler(.allow)
        }

        // MARK: - Download delegates

        func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
            download.delegate = self
            print("[MOODLE] download started (from action)")
        }

        func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
            download.delegate = self
            print("[MOODLE] download started (from response)")
        }

        func download(
            _ download: WKDownload,
            decideDestinationUsing response: URLResponse,
            suggestedFilename: String
        ) async -> URL? {
            let destDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("MoodlePreview", isDirectory: true)
            try? FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

            let destURL = destDir.appendingPathComponent(suggestedFilename)
            try? FileManager.default.removeItem(at: destURL)

            self.downloadDestURL = destURL
            print("[MOODLE] saving to: \(suggestedFilename)")
            return destURL
        }

        func downloadDidFinish(_ download: WKDownload) {
            print("[MOODLE] download complete: \(downloadDestURL?.lastPathComponent ?? "?")")
            guard let destURL = downloadDestURL else {
                DispatchQueue.main.async { self.parent.isLoading = false }
                return
            }
            DispatchQueue.main.async {
                self.parent.isLoading = false
                self.parent.previewURL = destURL
            }
        }

        func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
            print("[MOODLE] download failed: \(error.localizedDescription)")
            DispatchQueue.main.async { self.parent.isLoading = false }
        }

        // MARK: - Auto Login

        private func attemptAutoLogin(webView: WKWebView) {
            guard !loginSubmitted else {
                DispatchQueue.main.async { self.parent.isLoading = false }
                return
            }
            guard loginAttemptCount < maxLoginAttempts else {
                print("[MOODLE] Auto-login: max attempts reached, giving up")
                DispatchQueue.main.async { self.parent.isLoading = false }
                return
            }
            loginAttemptCount += 1

            // Read credentials directly from UserDefaults to ensure fresh values
            let username = UserDefaults.standard.string(forKey: "dualis_username") ?? ""
            let password: String = {
                guard let data = UserDefaults.standard.data(forKey: "dualis_password"),
                      let pw = String(data: data, encoding: .utf8) else { return "" }
                return pw
            }()

            guard !username.isEmpty, !password.isEmpty else {
                print("[MOODLE] Auto-login skipped: no credentials in UserDefaults")
                DispatchQueue.main.async { self.parent.isLoading = false }
                return
            }

            let escapedUser = username
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
            let escapedPass = password
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")

            let js = """
            (function() {
                var userField = document.getElementById('username') || document.querySelector('input[name="j_username"]');
                var passField = document.getElementById('password') || document.querySelector('input[name="j_password"]');
                if (userField && passField) {
                    userField.value = '\(escapedUser)';
                    passField.value = '\(escapedPass)';
                    var form = userField.closest('form');
                    if (form) {
                        var submitBtn = form.querySelector('button[type="submit"], input[type="submit"]');
                        if (submitBtn) {
                            submitBtn.click();
                        } else {
                            form.submit();
                        }
                        return 'submitted';
                    }
                    return 'no-form';
                }
                return 'no-fields';
            })();
            """

            // Small delay to let client-side JS finish rendering the login form
            let delay = loginAttemptCount == 1 ? 0.5 : 1.0
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                webView.evaluateJavaScript(js) { result, error in
                    if let status = result as? String {
                        print("[MOODLE] Auto-login attempt \(self.loginAttemptCount): \(status)")
                        if status == "submitted" {
                            self.loginSubmitted = true
                        } else if status == "no-fields" || status == "no-form" {
                            // Form not found yet, retry after a delay
                            print("[MOODLE] Retrying auto-login...")
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                self.attemptAutoLogin(webView: webView)
                            }
                        }
                    }
                    if let error = error {
                        print("[MOODLE] JS error: \(error)")
                        DispatchQueue.main.async { self.parent.isLoading = false }
                    }
                }
            }
        }
    }
}
