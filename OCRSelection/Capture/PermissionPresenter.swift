import AppKit

/// Presents the "Screen Recording permission required" alert and deep-links to System
/// Settings. Extracted from `CaptureCoordinator` so orchestration no longer depends on
/// AppKit presentation and the permission-denied branch can be asserted in tests.
@MainActor
struct PermissionPresenter: PermissionPresenting {
    func presentScreenRecordingDenied() async {
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
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
