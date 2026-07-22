import SwiftUI
import WebKit

struct ContentView: View {
    @StateObject private var manager = AssessmentManager()
    
    @State private var inputPassword = ""
    @State private var inputReason = ""
    @State private var modalErrorMessage = ""

    let examPortalURL = URL(string: "https://cgp-assessment-frontend-app-297614602590.us-central1.run.app/")!

    var body: some View {
        ZStack {
            if !manager.isExamActive {
                // Landing Screen Interface
                VStack(spacing: 25) {
                    Text("Secure Exam Browser")
                        .font(.largeTitle)
                        .bold()
                    
                    Text("Your Mac will lock down completely once the exam begins.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.gray)
                        .padding(.horizontal)

                    VStack(spacing: 12) {
                        Button(action: {
                            manager.startSecureExam()
                        }) {
                            Text("Launch Secure Exam")
                                .font(.headline)
                                .padding()
                                .frame(width: 250)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: {
                            NSApp.terminate(self)
                        }) {
                            Text("Exit Browser")
                                .font(.headline)
                                .padding()
                                .frame(width: 250)
                                .background(Color.gray.opacity(0.2))
                                .foregroundColor(.primary)
                                .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
            } else {
                // Exam Layout Layer
                ZStack(alignment: .topTrailing) {
                    SecureWebView(url: examPortalURL, onShortcutDetected: { shortcutName in
                        // Intercept event routed directly into the security engine
                        manager.registerShortcutViolation(keysPressed: shortcutName)
                    })
                    .edgesIgnoringSafeArea(.all)

                    Button(action: {
                        manager.showExitModal = true
                    }) {
                        Text("🔒 Quit Exam")
                            .font(.caption)
                            .bold()
                            .padding(8)
                            .background(Color.red.opacity(0.8))
                            .foregroundColor(.white)
                            .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                    .padding(16)
                }
            }
            
            // 3. SECURITY VIOLATION ON-SCREEN WARNING BOX OVERLAY
            if manager.showViolationWarning {
                Color.black.opacity(0.75) // Blocks student view of exam questions completely
                    .edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.red)
                    
                    Text("Security Violation Logged!")
                        .font(.title)
                        .bold()
                        .foregroundColor(.red)
                    
                    Text("Attempted shortcut action detected: \(manager.latestViolationType)")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text("This event has been classified as a security protocol infraction and pushed straight to the Bot Assessment backend supervisor database.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.gray)
                        .padding(.horizontal)
                    
                    Text("Strike Count: \(manager.violationCount) / 3\nReaching 3 strikes results in automated expulsion.")
                        .font(.subheadline)
                        .bold()
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                    
                    Button("Acknowledge & Resume Test") {
                        manager.showViolationWarning = false // Returns to exam content sheet
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .padding(.bottom)
                }
                .frame(width: 500, height: 380)
                .background(Color(NSColor.windowBackgroundColor))
                .cornerRadius(16)
                .shadow(radius: 30)
            }
            
            // SUPERVISOR EXIT POP-UP OVERLAY
            if manager.showExitModal {
                Color.black.opacity(0.5)
                    .edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 16) {
                    Text("Supervisor Authorization Required")
                        .font(.headline)
                        .foregroundColor(.red)
                    
                    Text("An early exit will void this exam session. Please provide credentials and a valid exit justification.")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                    
                    TextEditor(text: $inputReason)
                        .frame(height: 80)
                        .border(Color.gray.opacity(0.2))
                        .padding(.horizontal)
                        .overlay(
                            Group {
                                if inputReason.isEmpty {
                                    Text("Type clear reason for terminating exam early...")
                                        .foregroundColor(.gray.opacity(0.5))
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 8)
                                        .allowsHitTesting(false)
                                }
                            }, alignment: .topLeading
                        )
                    
                    if !modalErrorMessage.isEmpty {
                        Text(modalErrorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                            .bold()
                    }
                    
                    HStack(spacing: 20) {
                        Button("Resume Exam") {
                            manager.showExitModal = false
                            inputReason = ""
                            modalErrorMessage = ""
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Confirm & Terminate") {
                            if inputReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                modalErrorMessage = "You must provide a descriptive exit reason."
                            } else {
                                let success = manager.authorizeEarlyExit(reason: inputReason)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                    .padding(.bottom)
                }
                .frame(width: 450)
                .background(Color(NSColor.windowBackgroundColor))
                .cornerRadius(12)
                .shadow(radius: 20)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("SystemSwitchAttempted"))) { _ in
            if manager.isExamActive {
                manager.registerShortcutViolation(keysPressed: "Global System Key (Fn+Q / Workspace Switch)")
            }
        }
        .frame(minWidth: 800, minHeight: 600)
    }
}
