import KeyboardShortcuts
import SwiftUI

@main
struct OCRSelectionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("OCR Selection", systemImage: "text.viewfinder") {
            Button("Capture Area") {
                Task { await appDelegate.coordinator.run() }
            }

            Divider()

            SettingsLink {
                Text("Preferences…")
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            Button("Quit OCR Selection") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            PreferencesView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator = CaptureCoordinator()
    private let notifications = NotificationService()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await notifications.requestAuthorization() }

        KeyboardShortcuts.onKeyUp(for: .captureRegion) { [coordinator] in
            Task { await coordinator.run() }
        }
    }
}
