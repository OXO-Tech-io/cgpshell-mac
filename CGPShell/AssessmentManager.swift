import AppKit
import Combine
import AutomaticAssessmentConfiguration

@MainActor
final class AssessmentManager: ObservableObject {
    @Published var isExamActive = false
    @Published var errorMessage = ""
    @Published var showExitModal = false

    // Set by handleSSOHandoff(_:) when the app is launched via opencgpshell://
    // from the exam portal's "Begin Assessment" button. Read once by
    // ContentView when constructing SecureWebView, to seed the tokens into the
    // WebView before the exam page loads.
    @Published var pendingSSOTokens: SSOTokens?

    // Violation Engine Tracking flags
    @Published var violationCount = 0
    @Published var showViolationWarning = false
    @Published var latestViolationType = ""

    private var activeSession: AEAssessmentSession?

    private let apiClient = ShellAPIClient()
    private let sessionContext = ExamSessionContext()

    // Populated by handleAssessmentStarted(...) when the webview bridge
    // receives the frontend's assessment_started postMessage:
    // {"event":"assessment_started","examId":"...","studentId":"...","sessionToken":"..."}
    private var examId: String = ""
    private var studentId: String = ""
    private var sessionToken: String = ""

    enum AuditAction: String {
        case examStarted = "EXAM_STARTED"
        case examExit = "EXAM_EXIT"
        case examCancelled = "EXAM_CANCELLED"
    }

    /// Call this with the real identifiers (from assessment_started) before startSecureExam().
    func configureSession(examId: String, studentId: String, sessionToken: String) {
        self.examId = examId
        self.studentId = studentId
        self.sessionToken = sessionToken
    }

    /// Entry point for the webview bridge's assessment_started postMessage
    /// (see SecureWebView.Coordinator). Fires the one-time POST /sessions +
    /// EXAM_STARTED audit log immediately, per spec. Ignores a repeat message
    /// for the same run — the backend only activates a session once, so a
    /// duplicate call would just come back 401 session_expired_or_already_active.
    func handleAssessmentStarted(examId: String, studentId: String, sessionToken: String) {
        guard self.sessionToken.isEmpty else {
            SessionLogger.log("handleAssessmentStarted: ignoring duplicate assessment_started (session already configured)")
            return
        }
        configureSession(examId: examId, studentId: studentId, sessionToken: sessionToken)
        Task {
            await registerSessionAndReportStart()
        }
    }

    /// Entry point for the cgpshell:// launch (see ContentView.onOpenURL).
    /// Stashes the SSO tokens for SecureWebView to seed, then jumps straight
    /// into the exam view — skipping the manual "Launch Secure Exam" landing
    /// screen, matching the ticket's "candidate doesn't need to relogin, the
    /// assessment will appear and they can start it" flow.
    func handleSSOHandoff(_ tokens: SSOTokens) {
        // access/refresh/id tokens are bearer credentials — never logged, held
        // only long enough to hand to SecureWebView for seeding.
        SessionLogger.log("SSO handoff received via opencgpshell:// (tokens redacted)")
        self.pendingSSOTokens = tokens
        startSecureExam()
    }

    func startSecureExam() {
        let isDevelopmentMode = true // TEMP: bypasses AEAssessmentSession (blocked by missing Apple entitlement). Revert to false before real exams.

        if isDevelopmentMode {
            self.isExamActive = true
        } else {
            let configuration = AEAssessmentConfiguration()
            let session = AEAssessmentSession(configuration: configuration)
            self.activeSession = session
            session.begin()
            self.isExamActive = true
        }
    }

    func stopSecureExam() {
        if let session = activeSession {
            session.end()
        }
        self.activeSession = nil
        self.isExamActive = false
    }

    // MARK: - Session lifecycle (POST /api/v1/shell/sessions)

    /// Called once, immediately after receiving assessment_started, per spec.
    private func registerSessionAndReportStart() async {
        guard !sessionToken.isEmpty else {
            SessionLogger.log("registerSessionAndReportStart skipped: no sessionToken configured yet")
            return
        }

        do {
            let response = try await apiClient.createSession(
                examId: examId,
                studentId: studentId,
                sessionToken: sessionToken
            )
            await sessionContext.begin(sessionToken: sessionToken, sessionSecret: response.sessionSecret)
            // session_secret itself is never logged — only non-sensitive metadata.
            SessionLogger.log("Session created: status=\(response.status) validUntil=\(response.validUntil)")

            async let auditLog: Void = sendAuditLog(action: .examStarted, description: "Student started the examination.")
            async let securityEvent: Void = reportSecurityEvent(eventType: "ASSESSMENT_STARTED", description: "Exam started from Webview message")
            _ = await (auditLog, securityEvent)
        } catch {
            SessionLogger.log("registerSessionAndReportStart FAILED: \(error.localizedDescription)")
            self.errorMessage = "Could not establish a secure exam session. Check connectivity and try again."
        }
    }

    // MARK: - Audit logs (POST /api/v1/shell/audit-logs) — EXAM_STARTED / EXAM_EXIT / EXAM_CANCELLED

    private func sendAuditLog(action: AuditAction, description: String) async {
        guard let secret = await sessionContext.currentSecret() else {
            SessionLogger.log("sendAuditLog(\(action.rawValue)) skipped: no active session secret")
            return
        }

        // Audit-log signature is over sessionToken ALONE — do not reuse the
        // security-event signer (which includes seq_no) here.
        let signature = EventSigner.signAuditLog(sessionToken: sessionToken, sessionSecret: secret)
        let body = AuditLogRequest(
            sessionToken: sessionToken,
            action: action.rawValue,
            description: description,
            signature: signature
        )

        do {
            let response = try await apiClient.sendAuditLog(body)
            SessionLogger.log(
                "Audit log \(action.rawValue) accepted=\(response.accepted) status=\(response.status ?? "-") "
                + "score=\(response.score.map { String($0) } ?? "-") scoreUnchanged=\(response.scoreUnchanged.map { String($0) } ?? "-")"
            )
        } catch {
            SessionLogger.log("Audit log \(action.rawValue) FAILED: \(error.localizedDescription)")
        }
    }

    // MARK: - Security events (POST /api/v1/shell/security-events) — continuous telemetry

    /// keysPressed/description stays human-readable for the on-screen violation
    /// warning; eventType is the machine-readable category sent to the backend
    /// (e.g. "ALT_TAB", "SHORTCUT_BLOCKED", "COPY_PASTE_BLOCKED").
    func registerShortcutViolation(keysPressed: String, eventType: String = "SHORTCUT_BLOCKED") {
        self.violationCount += 1
        self.latestViolationType = keysPressed

        Task {
            await reportSecurityEvent(
                eventType: eventType,
                description: "User pressed unauthorized shortcut: \(keysPressed)"
            )
        }

        if violationCount >= 3 {
            // Three strikes closes the application forcefully.
            NSApp.terminate(self)
        } else {
            self.showViolationWarning = true
        }
    }

    private func reportSecurityEvent(eventType: String, description: String) async {
        guard let secret = await sessionContext.currentSecret() else {
            SessionLogger.log("reportSecurityEvent(\(eventType)) skipped: no active session secret")
            return
        }

        let seqNo = await sessionContext.nextSeqNo()
        let signature = EventSigner.signSecurityEvent(sessionToken: sessionToken, seqNo: seqNo, sessionSecret: secret)
        let occurredAt = Self.iso8601WithMilliseconds.string(from: Date())

        let body = SecurityEventRequest(
            sessionToken: sessionToken,
            eventType: eventType,
            description: description,
            seqNo: seqNo,
            occurredAt: occurredAt,
            signature: signature
        )

        do {
            let response = try await apiClient.sendSecurityEvent(body)
            if !response.accepted {
                // signature_mismatch -> check secret/canonical-string encoding.
                // seq_no_replay_or_out_of_order -> counter got out of sync (shouldn't
                // happen given the actor serializes access, but log loudly if it does).
                SessionLogger.log("Security event seq=\(seqNo) REJECTED: \(response.reason ?? "unknown")")
            }
        } catch {
            SessionLogger.log("Security event seq=\(seqNo) FAILED to send: \(error.localizedDescription)")
        }
    }

    // MARK: - Early exit

    func authorizeEarlyExit(reason: String) -> Bool {
        Task {
            // Supervisor-authorized manual early exit maps to EXAM_CANCELLED
            // (confirmed against the working Windows shell's observed traffic).
            await sendAuditLog(action: .examCancelled, description: reason)

            if let session = activeSession {
                session.end()
            }
            self.activeSession = nil
            self.isExamActive = false
            self.showExitModal = false

            // Give the in-flight audit-log POST a moment to leave the process
            // before we terminate — fire-and-forget from a Task can otherwise
            // get cancelled by NSApp.terminate before the request completes.
            try? await Task.sleep(nanoseconds: 500_000_000)
            NSApp.terminate(self)
        }
        return true
    }

    // occurred_at in the doc's example includes milliseconds ("...10:12:04.812Z");
    // the default ISO8601DateFormatter omits fractional seconds, so configure it explicitly.
    private static let iso8601WithMilliseconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
