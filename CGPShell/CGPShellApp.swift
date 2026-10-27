import SwiftUI
import AppKit

@main
struct CGPShellApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set true while intentionally triggering a system permission dialog
    /// (e.g. microphone access for exam answer recording). Those dialogs need
    /// focus for the user to respond to them — without this guard,
    /// applicationDidResignActive snaps focus straight back to CGPShell
    /// before the user can click Allow, so the dialog stays queued and
    /// invisible until the app quits and stops competing for activation.
    static var isAwaitingSystemPermissionPrompt = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Enforce native full-screen kiosk presentation behaviors at startup
        NSApp.presentationOptions = [
            .hideDock,               // Hides bottom dock
            .hideMenuBar,            // Hides Apple top status bar
            .disableProcessSwitching // Disables standard shortcuts like Cmd+Tab
        ]
        
        if let window = NSApp.windows.first {
            window.styleMask.remove([.closable, .miniaturizable, .resizable])
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.toggleFullScreen(nil)
            
            // Keep our browser window pinned on top of all other system overlays
            window.level = .mainMenu
        }
    }
    
    // ANTI-CHEAT WORKSPACE MONITOR: If the user presses Fn + Q or switches apps, snap back instantly!
    func applicationDidResignActive(_ notification: Notification) {
        // Don't fight a system dialog we ourselves asked for (e.g. the
        // microphone permission prompt) — let it keep focus long enough for
        // the user to respond.
        guard !AppDelegate.isAwaitingSystemPermissionPrompt else { return }

        // Snatch focus back from the operating system immediately
        NSApp.activate(ignoringOtherApps: true)

        // Push a global notification to trigger the warning layout screen inside ContentView
        NotificationCenter.default.post(name: Notification.Name("SystemSwitchAttempted"), object: nil)
    }
}
