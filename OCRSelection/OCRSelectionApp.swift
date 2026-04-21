import SwiftUI

@main
struct OCRSelectionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let coordinator = CaptureCoordinator()

    var body: some Scene {
        MenuBarExtra("OCR Selection", systemImage: "text.viewfinder") {
            Button("Capturer une zone") {
                Task { await coordinator.run() }
            }

            Divider()

            SettingsLink {
                Text("Préférences…")
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            Button("Quitter OCR Selection") {
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

private struct PreferencesView: View {
    var body: some View {
        Text("Préférences")
            .font(.title3)
            .frame(width: 480, height: 260)
    }
}
