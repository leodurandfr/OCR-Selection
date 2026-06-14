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
    func notifyFailure() async
}

@MainActor protocol HistoryRecording {
    func record(_ text: String)
}

@MainActor protocol PermissionPresenting {
    func presentScreenRecordingDenied() async
}
