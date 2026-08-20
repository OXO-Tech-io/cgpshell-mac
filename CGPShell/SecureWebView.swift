import SwiftUI
import WebKit
import AVFoundation

struct SecureWebView: NSViewRepresentable {
    let url: URL
    var onShortcutDetected: (String) -> Void // Tells the manager which shortcut was pressed
    var onAssessmentStarted: (String, String, String) -> Void // (examId, studentId, sessionToken) from the assessment_started bridge message
    var ssoTokens: SSOTokens? // From opencgpshell:// launch — seeded before load so the frontend can skip showing Keycloak login again.

    // Exact hostname match, not substring — `contains` would also match
    // e.g. "cgp-assessment-frontend-app-...run.app.attacker.example".
    static let allowedHosts: Set<String> = [
        "cgp-assessment-frontend-app-297614602590.us-central1.run.app",
        "keycloak-297614602590.us-central1.run.app", // Identity provider login page (Continue with Password / Sign in)
        "cgp-main-app-297614602590.us-central1.run.app" // Exam/question content after assessment start
    ]

    func makeNSView(context: Context) -> WKWebView {
        let webConfiguration = WKWebViewConfiguration()
        webConfiguration.preferences.javaScriptEnabled = true

        let contentController = WKUserContentController()

        if let tokens = ssoTokens, let ssoScript = Self.ssoSeedScript(for: tokens) {
            // Added first so it runs before the bridge/page scripts, on every
            // origin the WebView navigates through (Keycloak, frontend, main
            // app all use separate localStorage per-origin).
            contentController.addUserScript(ssoScript)
            SessionLogger.log("SecureWebView.makeNSView: SSO handoff tokens will be seeded before load (values redacted)")
        }

        // Bridge: the frontend calls window.chrome.webview.postMessage(...), the WebView2
        // (Windows/Edge) host-messaging API. That object doesn't exist in WKWebView, so on
        // macOS the call silently no-ops. Shimming it here — before page scripts run —
        // lets the same frontend code path work unmodified on Mac, forwarding to
        // window.webkit.messageHandlers.cgpBridge, where the Coordinator below picks it up.
        let bridgeScriptSource = """
        window.chrome = window.chrome || {};
        window.chrome.webview = window.chrome.webview || {
            postMessage: function(payload) {
                try {
                    window.webkit.messageHandlers.cgpBridge.postMessage(payload);
                } catch (e) {}
            }
        };
        try {
            window.chrome.webview.postMessage({ event: 'cgpshell_bridge_ready', href: window.location.href });
        } catch (e) {}
        """
        // forMainFrameOnly: true — no legitimate reason for a subframe (e.g. a
        // third-party widget/ad embedded in an otherwise-allowed page) to be
        // able to invoke the bridge and post fabricated shell events.
        let bridgeScript = WKUserScript(source: bridgeScriptSource, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        contentController.addUserScript(bridgeScript)
        contentController.add(context.coordinator, name: "cgpBridge")
        webConfiguration.userContentController = contentController

        SessionLogger.log("SecureWebView.makeNSView: bridge configured, loading \(url.absoluteString)")

        let webView = WKWebView(frame: .zero, configuration: webConfiguration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.isInspectable = false
        webView.customUserAgent = "SecureExamBrowser-MacOS-Native-1.0"

        // Ask for microphone access up front, with the anti-cheat refocus
        // handler suspended (see AppDelegate.isAwaitingSystemPermissionPrompt)
        // so the system "CGPShell would like to access the microphone" dialog
        // can actually keep focus long enough for the user to respond to it,
        // instead of getting its focus stolen back and staying invisible
        // until the app quits.
        Self.requestMicrophonePermissionIfNeeded()
        
        // 1. KEYBOARD TRAP: Intercepts shortcuts before they can execute
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags
            
            if flags.contains(.command) {
                if let keys = event.charactersIgnoringModifiers?.lowercased() {
                    // List of forbidden shortcut keys (Q=Quit, C=Copy, V=Paste, W=Close, Z=Undo)
                    if ["q", "w", "c", "v", "z"].contains(keys) {
                        let pressedCombo = "Cmd + \(keys.uppercased())"
                        
                        // Fire the violation trigger back to the manager
                        onShortcutDetected(pressedCombo)
                        
                        return nil // BLOCKS THE KEYBOARD KEY: Returns nil so macOS ignores the shortcut entirely
                    }
                }
            }
            return event
        }
        
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    private static func requestMicrophonePermissionIfNeeded() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        guard status == .notDetermined else {
            SessionLogger.log("SecureWebView: microphone permission already resolved (\(status.rawValue)), skipping prompt")
            return
        }
        AppDelegate.isAwaitingSystemPermissionPrompt = true
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                AppDelegate.isAwaitingSystemPermissionPrompt = false
                SessionLogger.log("SecureWebView: microphone permission \(granted ? "granted" : "denied")")
            }
        }
    }

    /// Seeds the SSO tokens into sessionStorage under the exact keys the
    /// frontend reads once at app-mount to bootstrap Keycloak directly
    /// (keycloak.init({ token, idToken, refreshToken, checkLoginIframe: false }))
    /// instead of the normal check-sso redirect flow — confirmed by reading
    /// the frontend's own bundle (index-B8M_rSm0.js): it does
    /// sessionStorage.getItem("cgp_bootstrap_token"/"_id_token"/"_refresh_token")
    /// once and immediately clears them.
    private static func ssoSeedScript(for tokens: SSOTokens) -> WKUserScript? {
        func jsStringLiteral(_ value: String) -> String? {
            guard let data = try? JSONSerialization.data(withJSONObject: [value]),
                  let arrayLiteral = String(data: data, encoding: .utf8) else { return nil }
            return String(arrayLiteral.dropFirst().dropLast()) // strip the [ ] JSONSerialization wraps it in
        }

        guard let accessTokenLiteral = jsStringLiteral(tokens.accessToken) else { return nil }
        var statements = ["sessionStorage.setItem('cgp_bootstrap_token', \(accessTokenLiteral));"]
        if let idToken = tokens.idToken, let literal = jsStringLiteral(idToken) {
            statements.append("sessionStorage.setItem('cgp_bootstrap_id_token', \(literal));")
        }
        if let refreshToken = tokens.refreshToken, let literal = jsStringLiteral(refreshToken) {
            statements.append("sessionStorage.setItem('cgp_bootstrap_refresh_token', \(literal));")
        }

        let source = """
        (function() {
            try {
                \(statements.joined(separator: "\n                "))
            } catch (e) {}
        })();
        """
        // forMainFrameOnly: true — these tokens must never be handed to a
        // subframe; only the actual top-level frontend page needs them.
        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        var parent: SecureWebView

        init(_ parent: SecureWebView) {
            self.parent = parent
        }

        // WebKit's own internal capture-permission gate, separate from the OS
        // TCC dialog — grant it here since the OS-level prompt (see
        // requestMicrophonePermissionIfNeeded) is the real gatekeeper.
        func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            decisionHandler(.grant)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "cgpBridge" else { return }

            if JSONSerialization.isValidJSONObject(message.body),
               let jsonData = try? JSONSerialization.data(withJSONObject: message.body, options: [.prettyPrinted, .sortedKeys]),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                SessionLogger.log("chrome.webview.postMessage payload received:\n\(jsonString)")
            } else {
                SessionLogger.log("chrome.webview.postMessage payload received (non-JSON body): \(message.body)")
            }

            guard let payload = Self.payloadDictionary(from: message.body),
                  let event = payload["event"] as? String else { return }

            switch event {
            case "assessment_started":
                guard let examId = payload["examId"] as? String,
                      let studentId = payload["studentId"] as? String,
                      let sessionToken = payload["sessionToken"] as? String else {
                    SessionLogger.log("assessment_started payload missing examId/studentId/sessionToken — ignoring")
                    return
                }
                parent.onAssessmentStarted(examId, studentId, sessionToken)
            default:
                break
            }
        }

        /// The frontend may post either a JS object (delivered here as an
        /// NSDictionary) or a JSON string — handle both so this doesn't
        /// silently no-op if the wire format changes.
        private static func payloadDictionary(from body: Any) -> [String: Any]? {
            if let dict = body as? [String: Any] {
                return dict
            }
            if let jsonString = body as? String,
               let data = jsonString.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return dict
            }
            return nil
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url,
                  url.scheme?.lowercased() == "https",
                  let host = url.host?.lowercased(),
                  SecureWebView.allowedHosts.contains(host) else {
                let url = navigationAction.request.url
                SessionLogger.log("Navigation BLOCKED -> \(url?.absoluteString ?? "nil") (host: \(url?.host ?? "nil"))")
                decisionHandler(.cancel) // Blocks navigating to outside websites
                return
            }
            SessionLogger.log("Navigation ALLOWED -> \(url.absoluteString)")
            decisionHandler(.allow)
        }
    }
}
