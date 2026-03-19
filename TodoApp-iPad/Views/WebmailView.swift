import SwiftUI
import WebKit

// MARK: - Loading Phase

private enum WebmailPhase: Equatable {
    case connecting
    case authenticating
    case loadingInbox
    case ready
    case error(String)

    var message: String {
        switch self {
        case .connecting:      return "Verbindung wird hergestellt…"
        case .authenticating:  return "Anmeldung läuft…"
        case .loadingInbox:    return "Postfach wird geladen…"
        case .ready:           return ""
        case .error(let msg):  return msg
        }
    }

    var isLoading: Bool {
        switch self {
        case .connecting, .authenticating, .loadingInbox: return true
        default: return false
        }
    }
}

// MARK: - Webmail View

struct WebmailView: View {
    @AppStorage("dualis_username") private var storedUsername = ""

    @State private var phase: WebmailPhase = .connecting
    @State private var pageTitle = "Webmail"
    @State private var canGoBack = false
    @State private var canGoForward = false
    @State private var webView: WKWebView?
    @State private var unreadCount: Int = 0

    private let inboxURL = "https://lehre-webmail.dhbw-stuttgart.de/roundcubemail/?_task=mail&_mbox=INBOX"
    private let composeURL = "https://lehre-webmail.dhbw-stuttgart.de/roundcubemail/?_task=mail&_action=compose"

    private var storedPassword: String {
        guard let data = UserDefaults.standard.data(forKey: "dualis_password"),
              let pw = String(data: data, encoding: .utf8) else { return "" }
        return pw
    }

    var body: some View {
        ZStack {
            if storedUsername.isEmpty {
                noCredentialsView
            } else {
                webContent
            }
        }
        .navigationTitle(pageTitle)
        .toolbar { toolbarContent }
    }

    // MARK: - No Credentials

    private var noCredentialsView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "envelope.badge.person.crop")
                .font(.system(size: 64))
                .foregroundStyle(.blue.opacity(0.4))
            Text("Keine Zugangsdaten")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("Hinterlege deine DHBW-Zugangsdaten in den Einstellungen, um dich automatisch beim Webmail anzumelden.")
                .font(.body)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Spacer()
        }
        .padding()
    }

    // MARK: - Web Content

    private var webContent: some View {
        ZStack {
            WebmailWebView(
                urlString: inboxURL,
                phase: $phase,
                pageTitle: $pageTitle,
                canGoBack: $canGoBack,
                canGoForward: $canGoForward,
                webView: $webView,
                unreadCount: $unreadCount
            )

            if phase.isLoading {
                loadingOverlay
            }

            if case .error(let msg) = phase {
                errorOverlay(msg)
            }
        }
    }

    // MARK: - Loading Overlay

    private var loadingOverlay: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.3)
                .tint(.blue)

            Text(phase.message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.05))
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.3), value: phase)
    }

    // MARK: - Error Overlay

    private func errorOverlay(_ message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 48))
                .foregroundStyle(.red.opacity(0.6))
            Text("Verbindung fehlgeschlagen")
                .font(.title3.weight(.semibold))
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button {
                phase = .connecting
                if let url = URL(string: inboxURL) {
                    webView?.load(URLRequest(url: url))
                }
            } label: {
                Label("Erneut versuchen", systemImage: "arrow.clockwise")
                    .font(.body.weight(.medium))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(.blue, in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(.white)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }

    // MARK: - Toolbar

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

            Divider()

            Button {
                if let url = URL(string: inboxURL) {
                    webView?.load(URLRequest(url: url))
                }
            } label: {
                Label {
                    Text("Posteingang")
                } icon: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "tray.fill")
                        if unreadCount > 0 {
                            Text("\(unreadCount)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(.red, in: Capsule())
                                .offset(x: 6, y: -6)
                        }
                    }
                }
            }

            Button {
                if let url = URL(string: composeURL) {
                    webView?.load(URLRequest(url: url))
                }
            } label: {
                Image(systemName: "square.and.pencil")
            }

            Button {
                if let currentURL = webView?.url {
                    UIApplication.shared.open(currentURL)
                }
            } label: {
                Image(systemName: "safari")
            }
        }
    }
}

// MARK: - WKWebView Wrapper

private struct WebmailWebView: UIViewRepresentable {
    let urlString: String

    @Binding var phase: WebmailPhase
    @Binding var pageTitle: String
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    @Binding var webView: WKWebView?
    @Binding var unreadCount: Int

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true

        let wk = WKWebView(frame: .zero, configuration: config)
        wk.navigationDelegate = context.coordinator
        wk.uiDelegate = context.coordinator
        wk.allowsBackForwardNavigationGestures = true
        wk.customUserAgent = "Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

        DispatchQueue.main.async { self.webView = wk }

        if let url = URL(string: urlString) {
            wk.load(URLRequest(url: url))
        }
        return wk
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    // MARK: - Coordinator

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let parent: WebmailWebView
        private var loginSubmitted = false
        private var loginAttemptCount = 0
        private let maxLoginAttempts = 5

        init(parent: WebmailWebView) { self.parent = parent }

        // MARK: Navigation

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async {
                if case .ready = self.parent.phase {
                    // Don't show full loading for in-app navigations after initial load
                } else if !self.loginSubmitted {
                    self.parent.phase = .connecting
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.canGoBack = webView.canGoBack
                self.parent.canGoForward = webView.canGoForward

                let currentURL = webView.url?.absoluteString ?? ""

                // Update title
                webView.evaluateJavaScript("document.title") { result, _ in
                    if let title = result as? String, !title.isEmpty {
                        DispatchQueue.main.async {
                            // Clean up Roundcube's verbose titles
                            if title.contains("Roundcube") || title.contains("Webmail") {
                                self.parent.pageTitle = "Webmail"
                            } else {
                                self.parent.pageTitle = title
                            }
                        }
                    }
                }

                // SAML login page
                if currentURL.contains("saml.dhbw-stuttgart.de") || currentURL.contains("/idp/") {
                    self.parent.phase = .authenticating
                    self.attemptAutoLogin(webView: webView)
                    return
                }

                // Roundcube loaded
                if currentURL.contains("roundcubemail") {
                    self.parent.phase = .ready
                    self.loginSubmitted = false
                    self.loginAttemptCount = 0
                    self.scrapeUnreadCount(webView: webView)
                    return
                }

                // Other page
                self.parent.phase = .ready
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            handleError(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            handleError(error)
        }

        private func handleError(_ error: Error) {
            let nsError = error as NSError
            // Ignore cancelled navigations (e.g. redirects)
            guard nsError.code != NSURLErrorCancelled else { return }
            DispatchQueue.main.async {
                self.parent.phase = .error(error.localizedDescription)
            }
        }

        // MARK: WKUIDelegate – target="_blank"

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }

        // MARK: Auto Login (SAML SSO)

        private func attemptAutoLogin(webView: WKWebView) {
            guard !loginSubmitted else { return }
            guard loginAttemptCount < maxLoginAttempts else {
                DispatchQueue.main.async { self.parent.phase = .error("Anmeldung fehlgeschlagen – maximale Versuche erreicht.") }
                return
            }
            loginAttemptCount += 1

            let username = UserDefaults.standard.string(forKey: "dualis_username") ?? ""
            let password: String = {
                guard let data = UserDefaults.standard.data(forKey: "dualis_password"),
                      let pw = String(data: data, encoding: .utf8) else { return "" }
                return pw
            }()

            guard !username.isEmpty, !password.isEmpty else {
                DispatchQueue.main.async { self.parent.phase = .error("Keine Zugangsdaten hinterlegt.") }
                return
            }

            let escapedUser = username.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
            let escapedPass = password.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")

            let js = """
            (function() {
                var u = document.getElementById('username') || document.querySelector('input[name="j_username"]');
                var p = document.getElementById('password') || document.querySelector('input[name="j_password"]');
                if (u && p) {
                    u.value = '\(escapedUser)';
                    p.value = '\(escapedPass)';
                    var form = u.closest('form');
                    if (form) {
                        var btn = form.querySelector('button[type="submit"], input[type="submit"]');
                        if (btn) { btn.click(); } else { form.submit(); }
                        return 'submitted';
                    }
                    return 'no-form';
                }
                return 'no-fields';
            })();
            """

            let delay = loginAttemptCount == 1 ? 0.5 : 1.0
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                webView.evaluateJavaScript(js) { result, _ in
                    if let status = result as? String {
                        if status == "submitted" {
                            self.loginSubmitted = true
                            DispatchQueue.main.async { self.parent.phase = .loadingInbox }
                        } else {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                self.attemptAutoLogin(webView: webView)
                            }
                        }
                    }
                }
            }
        }

        // MARK: Unread Count

        private func scrapeUnreadCount(webView: WKWebView) {
            let js = """
            (function() {
                var el = document.querySelector('.unreadcount') ||
                         document.querySelector('#rcmli_INBOX .unreadcount') ||
                         document.querySelector('.inbox .unreadcount');
                if (el) {
                    var text = el.textContent.replace(/[^0-9]/g, '');
                    return parseInt(text) || 0;
                }
                return 0;
            })();
            """
            // Delay to let Roundcube's JS render the sidebar
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                webView.evaluateJavaScript(js) { result, _ in
                    if let count = result as? Int {
                        DispatchQueue.main.async { self.parent.unreadCount = count }
                    }
                }
            }
        }
    }
}
