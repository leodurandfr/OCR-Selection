import SwiftUI

@main
struct OCRSelectionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let coordinator = CaptureCoordinator()

    var body: some Scene {
        MenuBarExtra("OCR Selection", systemImage: "text.viewfinder") {
            Button("Capture Area") {
                Task { await coordinator.run() }
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
    private let notifications = NotificationService()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await notifications.requestAuthorization() }
    }
}
