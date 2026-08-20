import Foundation

/// Tokens + routing info handed off from the exam portal website's
/// "Begin Assessment" button, via the cgpshell://start protocol launch (same
/// pattern as msteams:// — browser navigates to the custom scheme, OS routes
/// it to the installed app). Confirmed against the live frontend bundle
/// (index-B8M_rSm0.js): it builds `cgpshell://start?path=...&assignment_id=...
/// &access_token=...&id_token=...&refresh_token=...` via its w0()/x0() helpers.
struct SSOTokens {
    let accessToken: String
    let refreshToken: String?
    let idToken: String?
    let path: String?
    let assignmentId: String?
    // Everything else the launch URL carried (skill_name, job_role, career_path,
    // level, exam_type, career_path_name, level_name, skill_career_path_name,
    // etc.) — the frontend's own w0()/x0() spreads ALL of its current query
    // params into the cgpshell:// URL, and reads several of them back out
    // (e.g. o("skill_name","skill_name")) to populate the "Ready to Begin?"
    // screen. Forwarded as-is rather than named individually since the exact
    // set varies by exam type (assignment vs. general-exam).
    let extraParams: [String: String]
}

enum SSOHandoffParser {
    private static let reservedKeys: Set<String> = [
        "access_token", "refresh_token", "id_token", "path", "assignment_id"
    ]

    static func parse(_ url: URL) -> SSOTokens? {
        guard url.scheme?.lowercased() == "cgpshell" else { return nil }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let items = components.queryItems ?? []

        func value(_ name: String) -> String? {
            items.first(where: { $0.name == name })?.value
        }

        guard let accessToken = value("access_token"), !accessToken.isEmpty else { return nil }

        var extraParams: [String: String] = [:]
        for item in items {
            guard !reservedKeys.contains(item.name), let v = item.value, !v.isEmpty else { continue }
            extraParams[item.name] = v
        }

        return SSOTokens(
            accessToken: accessToken,
            refreshToken: value("refresh_token"),
            idToken: value("id_token"),
            path: value("path"),
            assignmentId: value("assignment_id"),
            extraParams: extraParams
        )
    }
}
