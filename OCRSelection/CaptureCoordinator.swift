import Foundation

/// Orchestrates the capture pipeline and maps typed errors to user-facing outcomes.
/// Backend-agnostic: it depends only on the capture/OCR/pasteboard/notification/history
/// seams, so the ScreenCaptureKit backend swaps in without changing this code, and the
/// branches below can be exercised with stubs in tests.
@MainActor
struct CaptureCoordinator {
    let screenCapture: any ScreenCapturing
    let ocr: any TextRecognizing
    let pasteboard: any Pasteboarding
    let notifications: any Notifying
    let history: any HistoryRecording
    let permission: any PermissionPresenting

    func run() async {
        // On the native CLI path this spans OCR + paste + history: the selection happens
        // inside the external screencapture process, which has already exited by here.
        let signpost = PerfLog.signposter.beginInterval("pipeline")
        defer { PerfLog.signposter.endInterval("pipeline", signpost) }
        let clock = ContinuousClock()
        do {
            let image = try await screenCapture.captureRegion()
            let ocrStart = clock.now
            let text = try await ocr.recognizeText(in: image)
            let ocrMs = String(format: "%.1f", PerfLog.milliseconds(clock.now - ocrStart))
            PerfLog.logger.info("OCR completed in \(ocrMs, privacy: .public) ms")

            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                // Vision can return whitespace-only results; treat them as "no text"
                // instead of copying a blank string and claiming success.
                await notifications.notifyNoText()
                return
            }
            // Use the trimmed text so stray leading/trailing whitespace from OCR never
            // lands on the clipboard or in history.
            pasteboard.copyText(trimmed)
            history.record(trimmed)
            await notifications.notifySuccess(preview: trimmed)
        } catch CaptureError.userCancelled {
            // Silence volontaire : l'utilisateur a appuyé sur Échap.
        } catch CaptureError.permissionDenied {
            await permission.presentScreenRecordingDenied()
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
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        pasteboard.copyText(text)
        await notifications.notifySuccess(preview: text)
    }
}
