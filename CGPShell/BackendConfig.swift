import Foundation

/// Resolves the shell API base URL from config rather than source, so it can
/// change between environments without a rebuild.
///
/// Resolution order:
/// 1. ~/Library/Application Support/CGPShell/Config.plist — optional, host-editable
///    override for pointing a deployed build at a different environment.
/// 2. Config.plist bundled with the app — ships with the production BASE_URL.
enum BackendConfig {
    static var baseURL: URL? {
        if let override = overrideConfig()?["APIBaseURL"] as? String, let url = normalizedURL(from: override) {
            return url
        }
        if let bundled = bundledConfig()?["APIBaseURL"] as? String, let url = normalizedURL(from: bundled) {
            return url
        }
        return nil
    }

    private static func overrideConfig() -> [String: Any]? {
        guard let supportDir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first else { return nil }
        let url = supportDir.appendingPathComponent("CGPShell/Config.plist")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    }

    private static func bundledConfig() -> [String: Any]? {
        guard let url = Bundle.main.url(forResource: "Config", withExtension: "plist"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    }

    private static func normalizedURL(from string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed), url.scheme != nil else { return nil }
        return url
    }
}
