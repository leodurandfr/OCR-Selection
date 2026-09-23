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
    /// A reference type so every copy of this struct (the shortcut handler and the menu
    /// each hold one) sees the same in-flight state.
    let gate = CaptureGate()

    func run() async {
        // Pressing the shortcut again while OCR is still working (a cold Vision model can
        // take ~30 s) used to start a second screencapture session, and each finished run
        // then overwrote the clipboard and added its own history entry. Drop re-entry.
        guard !gate.isBusy else {
            PerfLog.logger.notice("capture ignored: previous capture still in progress")
            return
        }
        gate.isBusy = true
        defer { gate.isBusy = false }

        // On the native CLI path this spans OCR + paste + history: the selection happens
        // inside the external screencapture process, which has already exited by here.
        let signpost = PerfLog.signposter.beginInterval("pipeline")
        defer { PerfLog.signposter.endInterval("pipeline", signpost) }
        HealthMonitor.shared.noteCapture()
        let clock = ContinuousClock()
        let start = clock.now
        do {
            let image = try await screenCapture.captureRegion()
            let captureMs = PerfLog.milliseconds(clock.now - start)
            let ocrStart = clock.now
            let text = try await ocr.recognizeText(in: image)
            let ocrMs = PerfLog.milliseconds(clock.now - ocrStart)

            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            // Notice level, so this survives in the unified log and a slow capture can be
            // diagnosed after the fact. Sizes and durations only — never the recognised text.
            PerfLog.logger.notice(
                """
                capture ok pixels=\(image.width, privacy: .public)x\(image.height, privacy: .public) \
                chars=\(trimmed.count, privacy: .public) \
                selection=\(String(format: "%.0f", captureMs), privacy: .public)ms \
                ocr=\(String(format: "%.0f", ocrMs), privacy: .public)ms \
                mem=\(String(format: "%.1f", PerfLog.footprintMB()), privacy: .public)MB
                """
            )
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
            PerfLog.logger.notice("capture cancelled by user")
        } catch CaptureError.permissionDenied {
            PerfLog.logger.error("capture denied: screen recording permission missing")
            await permission.presentScreenRecordingDenied()
        } catch OCRError.noTextFound {
            await notifications.notifyNoText()
        } catch OCRError.visionFailed(let underlying) {
            PerfLog.logger.error("OCR failed: \(String(describing: underlying), privacy: .public)")
            await notifications.notifyOCRFailed()
        } catch {
            PerfLog.logger.error("capture failed: \(String(describing: error), privacy: .public)")
            await notifications.notifyFailure()
        }
    }

    func recopy(_ text: String) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        pasteboard.copyText(text)
        await notifications.notifySuccess(preview: text)
    }
}

/// Tracks whether a capture is in progress; see `CaptureCoordinator.run()`.
@MainActor
final class CaptureGate {
    var isBusy = false
}
