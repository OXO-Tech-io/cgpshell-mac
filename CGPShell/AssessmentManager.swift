import AppKit
import Combine
import AutomaticAssessmentConfiguration

class AssessmentManager: ObservableObject {
    @Published var isExamActive = false
    @Published var errorMessage = ""
    @Published var showExitModal = false // Controls the supervisor pop-up visibility
    
    // Violation Engine Tracking flags
    @Published var violationCount = 0
    @Published var showViolationWarning = false
    @Published var latestViolationType = ""
    
    private var activeSession: AEAssessmentSession?
    
    
    func startSecureExam() {
        let isDevelopmentMode = false
        
        if isDevelopmentMode {
            self.isExamActive = true
        } else {
            let configuration = AEAssessmentConfiguration()
            let session = AEAssessmentSession(configuration: configuration)
            self.activeSession = session // Safe assignment
            session.begin()
            self.isExamActive = true
        }
    }
    
    func stopSecureExam() {
        if let session = activeSession as? AEAssessmentSession {
            session.end()
        }
        self.activeSession = nil
        self.isExamActive = false
    }
    
    func registerShortcutViolation(keysPressed: String) {
        self.violationCount += 1
        self.latestViolationType = keysPressed
        
        // Report the event data immediately to your backend
        reportCheatingToBotAPI(infraction: "User pressed unauthorized shortcut: \(keysPressed)")
        
        if violationCount >= 3 {
            // Three strikes closes the application forcefully
            NSApp.terminate(self)
        } else {
            DispatchQueue.main.async {
                self.showViolationWarning = true
            }
        }
    }
    
    func authorizeEarlyExit(reason: String) -> Bool {
                
        submitExitLogToBackend(reason: reason)
        
        if let session = activeSession {
            session.end()
        }
        
        self.activeSession = nil
        self.isExamActive = false
        self.showExitModal = false
        
        NSApp.terminate(self)
        return true
    }
    
    private func reportCheatingToBotAPI(infraction: String) {
        guard let url = URL(string: "https://run.app") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let infractionData: [String: Any] = [
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "status": "SECURITY_VIOLATION",
            "log_description": infraction,
            "current_strike_count": self.violationCount
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: infractionData)
        URLSession.shared.dataTask(with: request).resume()
    }
    
    private func submitExitLogToBackend(reason: String) {
        guard let url = URL(string: "https://run.app") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let logPayload: [String: Any] = [
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "exit_reason": reason,
            "browser_agent": "SecureExamBrowser-MacOS-Native-1.0"
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: logPayload)
        URLSession.shared.dataTask(with: request).resume()
    }
}
