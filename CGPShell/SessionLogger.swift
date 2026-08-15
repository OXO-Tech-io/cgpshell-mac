import Foundation

enum SessionLogger {
    // NOT ~/Desktop: that folder requires a one-time TCC consent prompt per app,
    // and writes fail silently (no prompt at all) for ad-hoc/dev-signed builds.
    // The home directory root needs no special permission.
    static let logFileURL: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("sessionLog.txt")

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
