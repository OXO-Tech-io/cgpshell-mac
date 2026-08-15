import Foundation

/// Holds the current exam session's signing secret and monotonic seq_no
/// counter in memory only — never persisted, never logged, never sent back
/// to the backend. Actor isolation gives the counter thread-safe,
/// strictly-increasing increments across concurrent hook callbacks.
actor ExamSessionContext {
    private var sessionSecret: String?
    private var lastSeqNo: Int64 = -1

    func begin(sessionToken: String, sessionSecret: String) {
        self.sessionSecret = sessionSecret
        self.lastSeqNo = -1
    }

    func currentSecret() -> String? {
        sessionSecret
    }

    /// Returns the next seq_no to use, incrementing the internal counter first
    /// so it is always monotonic and never reused within this session.
    func nextSeqNo() -> Int64 {
        lastSeqNo += 1
        return lastSeqNo
    }
}
