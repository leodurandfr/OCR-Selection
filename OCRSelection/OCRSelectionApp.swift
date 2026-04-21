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

            Button("Debug : tester la capture") {
                Task { await runCaptureDebug() }
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

    private func runCaptureDebug() async {
        let service = ScreenCaptureService()
        do {
            let image = try await service.captureRegion()
            await MainActor.run {
                showDebugAlert(
                    title: "Capture réussie",
                    message: "Dimensions : \(image.width) × \(image.height) px"
                )
            }
        } catch CaptureError.userCancelled {
            await MainActor.run {
                showDebugAlert(title: "Capture annulée", message: "L'utilisateur a appuyé sur Échap.")
            }
        } catch CaptureError.screenCaptureFailed(let details) {
            await MainActor.run {
                showDebugAlert(
                    title: "Échec de la capture",
                    message: "screencapture a échoué. Vérifier la permission Enregistrement d'écran.\n\nDétails :\n\(details)"
                )
            }
        } catch {
            await MainActor.run {
                showDebugAlert(title: "Erreur", message: String(describing: error))
            }
        }
    }

    @MainActor
    private func showDebugAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.runModal()
    }
}

private struct PreferencesView: View {
    var body: some View {
        Text("Préférences")
            .font(.title3)
            .frame(width: 480, height: 260)
    }
}
