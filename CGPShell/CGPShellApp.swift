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
        // Snatch focus back from the operating system immediately
        NSApp.activate(ignoringOtherApps: true)
        
        // Push a global notification to trigger the warning layout screen inside ContentView
        NotificationCenter.default.post(name: Notification.Name("SystemSwitchAttempted"), object: nil)
    }
}
