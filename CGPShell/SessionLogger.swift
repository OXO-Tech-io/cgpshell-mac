import Foundation

enum SessionLogger {
    // NOT ~/sessionLog.txt or ~/Desktop: this target has App Sandbox enabled
    // (com.apple.security.app-sandbox, see the project's build settings), and
    // its only file entitlement is files.user-selected.read-only — writing to
    // an arbitrary home-directory path is silently denied under sandbox (the
    // catch block below swallows it, visible only via Console.app/NSLog).
    // Application Support is inside the app's own sandbox container, which
    // FileManager's .applicationSupportDirectory lookup transparently resolves
    // to under sandbox — always writable with zero extra entitlements.
    static let logFileURL: URL = {
        let supportDir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        return supportDir.appendingPathComponent("sessionLog.txt")
    }()

    static func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }

        do {
            if FileManager.default.fileExists(atPath: logFileURL.path) {
                let handle = try FileHandle(forWritingTo: logFileURL)
                defer { try? handle.close() }
                handle.seekToEndOfFile()
                handle.write(data)
            } else {
                try data.write(to: logFileURL, options: .atomic)
            }
        } catch {
            NSLog("SessionLogger: failed to write to \(logFileURL.path): \(error)")
        }
    }
}
