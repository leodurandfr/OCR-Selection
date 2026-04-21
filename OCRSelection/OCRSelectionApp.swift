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

            Button("Debug : tester la capture + OCR") {
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
        let capture = ScreenCaptureService()
        let ocr = OCRService()
        do {
            let image = try await capture.captureRegion()
            let text = try await ocr.recognizeText(in: image)
            await MainActor.run {
                showDebugAlert(
                    title: "OCR réussi",
                    message: "Image : \(image.width) × \(image.height) px\n\nTexte :\n\(text)"
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
        } catch OCRError.noTextFound {
            await MainActor.run {
                showDebugAlert(title: "Aucun texte détecté", message: "Vision n'a trouvé aucun texte dans la zone capturée.")
            }
        } catch OCRError.visionFailed(let underlying) {
            await MainActor.run {
                showDebugAlert(title: "Échec OCR", message: String(describing: underlying))
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
