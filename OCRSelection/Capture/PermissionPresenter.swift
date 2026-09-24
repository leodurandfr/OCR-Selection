import AppKit

/// Presents the "Screen Recording permission required" alert and deep-links to System
/// Settings. Extracted from `CaptureCoordinator` so orchestration no longer depends on
/// AppKit presentation and the permission-denied branch can be asserted in tests.
@MainActor
struct PermissionPresenter: PermissionPresenting {
    private static let systemPromptSeenKey = "screenRecordingSystemPromptSeen"

    /// Access granted means macOS already has an answer on record and will not prompt again,
    /// so a later revocation must get this alert on the very first denied capture.
    static func noteCurrentAccess() {
        if CGPreflightScreenCaptureAccess() {
            UserDefaults.standard.set(true, forKey: systemPromptSeenKey)
        }
    }

    func presentScreenRecordingDenied() async {
        // The first time, `screencapture` itself asks TCC, and macOS shows its own prompt on
        // our behalf; this alert on top of it was a second dialog saying the same thing. Once
        // macOS has recorded an answer it never prompts again, and only this alert is left.
        // (Someone who denied access without ever granting it gets the alert one capture late.)
        guard UserDefaults.standard.bool(forKey: Self.systemPromptSeenKey) else {
            UserDefaults.standard.set(true, forKey: Self.systemPromptSeenKey)
            PerfLog.logger.notice("screen recording denied: leaving the first prompt to macOS")
            return
        }
        let alert = NSAlert()
        alert.messageText = String(localized: "Screen Recording permission required")
        alert.informativeText = String(
            localized: "OCR Selection needs the Screen Recording permission to capture your screen. Open System Settings to grant it."
        )
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "Open System Settings"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        // Only a request (not a preflight) adds the app to the Screen Recording list. Without
        // it, once the entry is gone (new Mac, `tccutil reset`) there is nothing to switch on.
        CGRequestScreenCaptureAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
