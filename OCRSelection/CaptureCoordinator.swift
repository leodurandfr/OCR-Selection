import CoreGraphics
import Foundation
import Observation

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
    let diskSpace: any DiskSpaceChecking
    /// A warm model answers in well under a second; past this it had to be recompiled.
    var slowOCRMilliseconds: Double = 10_000
    /// A reference type so every copy of this struct (the shortcut handler and the menu
    /// each hold one) sees the same in-flight state.
    let gate = CaptureGate()

    func run() async {
        // Pressing the shortcut again while OCR is still working (a cold Vision model can
        // take ~30 s) used to start a second screencapture session, and each finished run
        // then overwrote the clipboard and added its own history entry. Drop re-entry.
        guard !gate.isBusy else {
            PerfLog.logger.notice("capture ignored: previous capture still in progress")
            notifications.notifyBusy()
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
            let isFirstOCR = !gate.hasRecognized
            let ocrStart = clock.now
            let text = try await recognize(image)
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
            // On a nearly full disk the recompile keeps coming back as macOS purges the model.
            // Not on the process's first OCR: that one compiles the model anyway after any
            // install or rebuild, and blaming the disk for it would be a false alarm.
            if ocrMs > slowOCRMilliseconds, !isFirstOCR, diskSpace.isNearlyFull() {
                await notifications.notifyDiskNearlyFull(recognitionFailed: false)
            }
        } catch CaptureError.userCancelled {
            // Silence volontaire : l'utilisateur a appuyé sur Échap.
            PerfLog.logger.notice("capture cancelled by user")
        } catch CaptureError.permissionDenied {
            PerfLog.logger.error("capture denied: screen recording permission missing")
            await permission.presentScreenRecordingDenied()
        } catch OCRError.noTextFound {
            await notifications.notifyNoText()
        } catch OCRError.visionFailed(let underlying) {
            // In practice this is `e5rtError … 13`: macOS purged Vision's compiled model
            // from ~/Library/Caches (it does so when the disk is nearly full) while it was
            // loaded, and every recognition fails until the process restarts. Retrying in
            // process, even pinned to the CPU, fails the same way — hence the relaunch hint.
            PerfLog.logger.error("OCR failed: \(String(describing: underlying), privacy: .public)")
            if diskSpace.isNearlyFull() {
                await notifications.notifyDiskNearlyFull(recognitionFailed: true)
            } else {
                await notifications.notifyOCRFailed()
            }
        } catch {
            PerfLog.logger.error("capture failed: \(String(describing: error), privacy: .public)")
            await notifications.notifyFailure()
        }
    }

    /// The menu-bar pulse covers OCR only: not the selection, where the user is the
    /// one working, nor the permission alert, where the app is waiting on them.
    private func recognize(_ image: CGImage) async throws -> String {
        gate.isRecognizing = true
        defer {
            gate.isRecognizing = false
            gate.hasRecognized = true
        }
        return try await ocr.recognizeText(in: image)
    }

    func recopy(_ text: String) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        pasteboard.copyText(text)
        await notifications.notifySuccess(preview: text)
    }
}

/// Tracks whether a capture is in progress; see `CaptureCoordinator.run()`.
@MainActor
@Observable
final class CaptureGate {
    @ObservationIgnored var isBusy = false
    /// Drives the menu-bar icon: a cold Vision model keeps OCR busy for 30–40 s, which
    /// otherwise looked like the app had stopped responding.
    var isRecognizing = false
    /// Whether this process has run OCR before (see the slow-OCR disk warning).
    @ObservationIgnored var hasRecognized = false
}
