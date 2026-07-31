import Foundation

// MARK: - POST /api/v1/shell/sessions

struct CreateSessionRequest: Encodable {
    let examId: String
    let studentId: String
    let sessionToken: String
}

struct CreateSessionResponse: Decodable {
    let status: String
    let sessionSecret: String
    let validUntil: String

    enum CodingKeys: String, CodingKey {
        case status
        case sessionSecret = "session_secret"
        case validUntil = "valid_until"
    }
}

// MARK: - POST /api/v1/shell/audit-logs

struct AuditLogRequest: Encodable {
    let sessionToken: String
    let action: String
    let description: String
    let signature: String
}

struct AuditLogResponse: Decodable {
    let accepted: Bool
    let status: String?
    let score: Double?
    let scoreUnchanged: Bool?

    enum CodingKeys: String, CodingKey {
        case accepted, status, score
        case scoreUnchanged = "score_unchanged"
    }
}

// MARK: - POST /api/v1/shell/security-events

struct SecurityEventRequest: Encodable {
    let sessionToken: String
    let eventType: String
    let description: String
    let seqNo: Int64
    let occurredAt: String
    let signature: String

    enum CodingKeys: String, CodingKey {
        case sessionToken, eventType, description, signature
        case seqNo = "seq_no"
        case occurredAt = "occurred_at"
    }
}

struct SecurityEventResponse: Decodable {
    let accepted: Bool
    let seqNo: Int64?
    let reason: String?

    enum CodingKeys: String, CodingKey {
        case accepted, reason
        case seqNo = "seq_no"
    }
}

// MARK: - Error envelopes

/// /sessions error shape: { "error": "session_not_found" }
struct ShellErrorEnvelope: Decodable {
    let error: String
}

/// /audit-logs (and other FastAPI-default) error shape: { "detail": "..." }
struct FastAPIErrorEnvelope: Decodable {
    let detail: String
}
