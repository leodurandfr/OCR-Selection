import SwiftUI

@main
struct OCRSelectionApp: App {
    private let coordinator = CaptureCoordinator()

    var body: some Scene {
        MenuBarExtra("OCR Selection", systemImage: "text.viewfinder") {
            Button("Capturer une zone") {
                Task { await runCapture() }
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

    private func runCapture() async {
        do {
            try await coordinator.run()
        } catch CaptureError.userCancelled {
            // Silence attendu quand l'utilisateur appuie sur Échap.
        } catch {
            // Les retours utilisateur (succès + erreurs) sont câblés en Phase 5 via UNUserNotificationCenter.
            NSLog("OCR Selection capture failed: %@", String(describing: error))
        }
    }
}

private struct PreferencesView: View {
    var body: some View {
        Text("Préférences")
            .font(.title3)
            .frame(width: 480, height: 260)
    }
}
