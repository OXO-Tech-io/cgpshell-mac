import SwiftUI
import WebKit

struct SecureWebView: NSViewRepresentable {
    let url: URL
    var onShortcutDetected: (String) -> Void // Tells the manager which shortcut was pressed
    var onAssessmentStarted: (String, String, String) -> Void // (examId, studentId, sessionToken) from the assessment_started bridge message

    func makeNSView(context: Context) -> WKWebView {
        let webConfiguration = WKWebViewConfiguration()
        webConfiguration.preferences.javaScriptEnabled = true

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
        let bridgeScript = WKUserScript(source: bridgeScriptSource, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        let contentController = WKUserContentController()
        contentController.addUserScript(bridgeScript)
        contentController.add(context.coordinator, name: "cgpBridge")
        webConfiguration.userContentController = contentController

        SessionLogger.log("SecureWebView.makeNSView: bridge configured, loading \(url.absoluteString)")

        let webView = WKWebView(frame: .zero, configuration: webConfiguration)
        webView.navigationDelegate = context.coordinator
        webView.isInspectable = false
        webView.customUserAgent = "SecureExamBrowser-MacOS-Native-1.0"
        
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

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: SecureWebView

        init(_ parent: SecureWebView) {
            self.parent = parent
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
            if let url = navigationAction.request.url {
                let allowedHosts = [
                    "cgp-assessment-frontend-app-297614602590.us-central1.run.app",
                    "keycloak-297614602590.us-central1.run.app", // Identity provider login page (Continue with Password / Sign in)
                    "cgp-main-app-297614602590.us-central1.run.app" // Exam/question content after assessment start
                ]
                if let host = url.host, allowedHosts.contains(where: { host.contains($0) }) {
                    SessionLogger.log("Navigation ALLOWED -> \(url.absoluteString)")
                    decisionHandler(.allow)
                    return
                }
                SessionLogger.log("Navigation BLOCKED -> \(url.absoluteString) (host: \(url.host ?? "nil"))")
            }
            decisionHandler(.cancel) // Blocks navigating to outside websites
        }
    }
}
