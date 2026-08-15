import Foundation

enum ShellAPIError: LocalizedError {
    case missingConfiguration
    case invalidResponse
    case httpError(status: Int, message: String)
    case decodingFailed(Error)

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return "No API base URL configured (checked Config.plist override and bundle)."
        case .invalidResponse:
            return "The server returned an invalid response."
        case .httpError(let status, let message):
            return "Server error (\(status)): \(message)"
        case .decodingFailed(let error):
            return "Failed to decode server response: \(error.localizedDescription)"
        }
    }
}

/// Talks to the real shell backend at BackendConfig.baseURL. The old
/// localhost:5222 stub (cgpshell-backend-api-dotnet) is no longer referenced
/// anywhere in this client.
final class ShellAPIClient {
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - POST /api/v1/shell/sessions

    func createSession(examId: String, studentId: String, sessionToken: String) async throws -> CreateSessionResponse {
        let body = CreateSessionRequest(examId: examId, studentId: studentId, sessionToken: sessionToken)
        let (data, http) = try await send(path: "api/v1/shell/sessions", body: body)

        // Logged once here per the integration doc: if CreateSessionResponse is
        // missing a field the backend actually sends, System.Text.Json-style
        // silent-null decoding won't surface it — the raw body will.
        SessionLogger.log("createSession raw response (\(http.statusCode)): \(rawBody(data))")

        if (200..<300).contains(http.statusCode) {
            return try decode(CreateSessionResponse.self, from: data)
        }
        let message = (try? decoder.decode(ShellErrorEnvelope.self, from: data))?.error ?? "HTTP \(http.statusCode)"
        throw ShellAPIError.httpError(status: http.statusCode, message: message)
    }

    // MARK: - POST /api/v1/shell/audit-logs

    func sendAuditLog(_ body: AuditLogRequest) async throws -> AuditLogResponse {
        let (data, http) = try await send(path: "api/v1/shell/audit-logs", body: body)

        if (200..<300).contains(http.statusCode) {
            return try decode(AuditLogResponse.self, from: data)
        }
        let message = (try? decoder.decode(FastAPIErrorEnvelope.self, from: data))?.detail ?? "HTTP \(http.statusCode)"
        throw ShellAPIError.httpError(status: http.statusCode, message: message)
    }

    // MARK: - POST /api/v1/shell/security-events

    func sendSecurityEvent(_ body: SecurityEventRequest) async throws -> SecurityEventResponse {
        let (data, http) = try await send(path: "api/v1/shell/security-events", body: body)

        // 202 = accepted, 400 = logical rejection (signature_mismatch /
        // seq_no_replay_or_out_of_order) — both carry a decodable
        // {accepted, ...} body, so only a genuinely unexpected status throws.
        if http.statusCode == 202 || http.statusCode == 400 {
            return try decode(SecurityEventResponse.self, from: data)
        }
        throw ShellAPIError.httpError(status: http.statusCode, message: "Unexpected status: \(rawBody(data))")
    }

    // MARK: - Shared plumbing

    private func send<Body: Encodable>(path: String, body: Body) async throws -> (Data, HTTPURLResponse) {
        guard let baseURL = BackendConfig.baseURL else {
            throw ShellAPIError.missingConfiguration
        }
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ShellAPIError.invalidResponse
        }
        return (data, http)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw ShellAPIError.decodingFailed(error)
        }
    }

    private func rawBody(_ data: Data) -> String {
        String(data: data, encoding: .utf8) ?? "<non-utf8 body, \(data.count) bytes>"
    }
}
