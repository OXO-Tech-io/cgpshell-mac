import SwiftUI
import WebKit

struct SecureWebView: NSViewRepresentable {
    let url: URL
    var onShortcutDetected: (String) -> Void // Tells the manager which shortcut was pressed

    func makeNSView(context: Context) -> WKWebView {
        let webConfiguration = WKWebViewConfiguration()
        webConfiguration.preferences.javaScriptEnabled = true
        
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

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: SecureWebView

        init(_ parent: SecureWebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url {
                let allowedHost = "cgp-assessment-frontend-app-297614602590.us-central1.run.app"
                if url.host?.contains(allowedHost) == true {
                    decisionHandler(.allow)
                    return
                }
            }
            decisionHandler(.cancel) // Blocks navigating to outside websites
        }
    }
}
