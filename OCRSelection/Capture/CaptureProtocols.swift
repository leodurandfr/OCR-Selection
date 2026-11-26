import CoreGraphics

/// Seams that let `CaptureCoordinator` be driven with stubs in tests, and let the
/// capture backend be swapped (CLI → ScreenCaptureKit) without touching orchestration.
///
/// Everything is `@MainActor`: the capture overlay, pasteboard, notifications and
/// SwiftData context are all main-thread bound, so isolating the whole pipeline to the
/// main actor keeps the concurrency model trivial and `Sendable`-clean under Swift 6.

@MainActor protocol ScreenCapturing {
    /// Presents the selection UI and returns the captured region as pixels.
    func captureRegion() async throws -> CGImage
}

@MainActor protocol TextRecognizing {
    func recognizeText(in image: CGImage) async throws -> String
}

@MainActor protocol Pasteboarding {
    func copyText(_ text: String)
}

@MainActor protocol Notifying {
    func notifySuccess(preview text: String) async
    func notifyNoText() async
    func notifyOCRFailed() async
    /// OCR failed or was very slow while the disk was nearly full (see `DiskSpaceService`).
    func notifyDiskNearlyFull(recognitionFailed: Bool) async
    func notifyFailure() async
    /// A capture request arrived while one was still running and was dropped.
    func notifyBusy()
}

@MainActor protocol DiskSpaceChecking {
    func isNearlyFull() -> Bool
}

/// What the recognizer's Vision cache holds (see `VisionCacheMonitor`), so a slow OCR that
/// compiled a model Vision had never needed (another language) is not blamed on the disk.
@MainActor protocol VisionModelCaching {
    /// The most finished models seen since the last purge.
    var knownModelCount: Int { get }
    func currentModelCount() -> Int
}

@MainActor protocol HistoryRecording {
    func record(_ text: String)
}

@MainActor protocol PermissionPresenting {
    func presentScreenRecordingDenied() async
}
