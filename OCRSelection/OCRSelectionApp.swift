import SwiftUI

@main
struct OCRSelectionApp: App {
    var body: some Scene {
        MenuBarExtra("OCR Selection", systemImage: "text.viewfinder") {
            Button("Capturer une zone") {
                // Implémenté en Phase 4 (CaptureCoordinator)
            }
            .disabled(true)

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

private struct PreferencesView: View {
    var body: some View {
        Text("Préférences")
            .font(.title3)
            .frame(width: 480, height: 260)
    }
}
