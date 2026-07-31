import Foundation
import CryptoKit

/// Produces the HMAC-SHA256 signatures the backend verifies on audit-log and
/// security-event calls. session_secret is the HMAC key and must never be
/// transmitted — only the resulting signature is sent.
enum EventSigner {
    /// Audit-log signature: canonical string is sessionToken ALONE (no seq_no).
    static func signAuditLog(sessionToken: String, sessionSecret: String) -> String {
        sign(canonical: sessionToken, secret: sessionSecret)
    }

    /// Security-event signature: canonical string is "sessionToken|seqNo".
    static func signSecurityEvent(sessionToken: String, seqNo: Int64, sessionSecret: String) -> String {
        sign(canonical: "\(sessionToken)|\(seqNo)", secret: sessionSecret)
    }

    private static func sign(canonical: String, secret: String) -> String {
        let key = SymmetricKey(data: Data(secret.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: Data(canonical.utf8), using: key)
        return Data(mac).base64EncodedString()
    }
}
