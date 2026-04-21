import AppKit
import Foundation

struct CaptureCoordinator {
    var screenCapture = ScreenCaptureService()
    var ocr = OCRService()
    var pasteboard = PasteboardService()
    var notifications = NotificationService()
    let history: HistoryService

    func run() async {
        do {
            let image = try await screenCapture.captureRegion()
            let text = try await ocr.recognizeText(in: image)
            pasteboard.copyText(text)
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                await history.record(text)
            }
            await notifications.notifySuccess(preview: text)
        } catch CaptureError.userCancelled {
            // Silence volontaire : l'utilisateur a appuyé sur Échap.
        } catch CaptureError.screenRecordingPermissionDenied {
            await Self.presentScreenRecordingAlert()
        } catch OCRError.noTextFound {
            await notifications.notifyNoText()
        } catch OCRError.visionFailed(let underlying) {
            NSLog("OCR Selection OCR failed: %@", String(describing: underlying))
            await notifications.notifyOCRFailed()
        } catch {
            NSLog("OCR Selection capture failed: %@", String(describing: error))
            await notifications.notifyFailure()
        }
    }

    func recopy(_ text: String) async {
        pasteboard.copyText(text)
        await notifications.notifySuccess(preview: text)
    }

    @MainActor
    private static func presentScreenRecordingAlert() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Screen Recording permission required")
        alert.informativeText = String(
            localized: "OCR Selection needs the Screen Recording permission to capture your screen. Open System Settings to grant it."
        )
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "Open System Settings"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
