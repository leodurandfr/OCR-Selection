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
        } catch OCRError.noTextFound {
            await notifications.notifyNoText()
        } catch {
            NSLog("OCR Selection capture failed: %@", String(describing: error))
            await notifications.notifyFailure()
        }
    }

    func recopy(_ text: String) async {
        pasteboard.copyText(text)
        await notifications.notifySuccess(preview: text)
    }
}
