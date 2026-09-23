import CoreGraphics
import Testing
@testable import OCRSelection

@MainActor
struct CaptureCoordinatorTests {
    @Test func successCopiesRecordsAndNotifies() async {
        let env = Env(capture: .success(dummyImage()), ocr: .success("hello world"))
        await env.coordinator.run()
        #expect(env.pasteboard.copied == ["hello world"])
        #expect(env.history.recorded == ["hello world"])
        #expect(env.notifications.events == [.success("hello world")])
        #expect(env.permission.presentedCount == 0)
    }

    @Test func whitespaceOnlyResultNotifiesNoTextWithoutCopying() async {
        let env = Env(capture: .success(dummyImage()), ocr: .success("   \n  "))
        await env.coordinator.run()
        #expect(env.pasteboard.copied.isEmpty)
        #expect(env.history.recorded.isEmpty)
        #expect(env.notifications.events == [.noText])
    }

    @Test func userCancelledIsSilent() async {
        let env = Env(capture: .failure(CaptureError.userCancelled), ocr: .success("unused"))
        await env.coordinator.run()
        #expect(env.pasteboard.copied.isEmpty)
        #expect(env.notifications.events.isEmpty)
        #expect(env.permission.presentedCount == 0)
    }

    @Test func permissionDeniedPresentsAlertOnly() async {
        let env = Env(capture: .failure(CaptureError.permissionDenied), ocr: .success("unused"))
        await env.coordinator.run()
        #expect(env.permission.presentedCount == 1)
        #expect(env.notifications.events.isEmpty)
        #expect(env.pasteboard.copied.isEmpty)
    }

    @Test func noTextFoundNotifiesNoText() async {
        let env = Env(capture: .success(dummyImage()), ocr: .failure(OCRError.noTextFound))
        await env.coordinator.run()
        #expect(env.notifications.events == [.noText])
        #expect(env.pasteboard.copied.isEmpty)
    }

    @Test func visionFailureNotifiesOCRFailed() async {
        struct Boom: Error {}
        let env = Env(capture: .success(dummyImage()), ocr: .failure(OCRError.visionFailed(Boom())))
        await env.coordinator.run()
        #expect(env.notifications.events == [.ocrFailed])
    }

    @Test func runWhileCaptureInProgressIsIgnored() async {
        let capture = SuspendedScreenCapture()
        let env = Env(screenCapture: capture, ocr: .success("hello"))
        let first = Task { await env.coordinator.run() }
        while !capture.isWaiting { await Task.yield() }

        await env.coordinator.run()
        capture.finish(with: dummyImage())
        await first.value

        #expect(capture.callCount == 1)
        #expect(env.pasteboard.copied == ["hello"])
        #expect(env.history.recorded == ["hello"])

        // The gate reopens once the first capture has finished.
        let next = Task { await env.coordinator.run() }
        while !capture.isWaiting { await Task.yield() }
        capture.finish(with: dummyImage())
        await next.value
        #expect(capture.callCount == 2)
        #expect(env.pasteboard.copied == ["hello", "hello"])
        #expect(env.history.recorded == ["hello", "hello"])
    }

    @Test func genericCaptureFailureNotifiesFailure() async {
        let env = Env(capture: .failure(CaptureError.captureFailed(nil)), ocr: .success("unused"))
        await env.coordinator.run()
        #expect(env.notifications.events == [.failure])
    }
}

// MARK: - Test harness

@MainActor
private struct Env {
    let pasteboard = SpyPasteboard()
    let notifications = SpyNotifications()
    let history = SpyHistory()
    let permission = SpyPermission()
    let coordinator: CaptureCoordinator

    init(capture: Result<CGImage, Error>, ocr: Result<String, Error>) {
        self.init(screenCapture: StubScreenCapture(capture), ocr: ocr)
    }

    init(screenCapture: any ScreenCapturing, ocr: Result<String, Error>) {
        coordinator = CaptureCoordinator(
            screenCapture: screenCapture,
            ocr: StubRecognizer(ocr),
            pasteboard: pasteboard,
            notifications: notifications,
            history: history,
            permission: permission
        )
    }
}

@MainActor private final class StubScreenCapture: ScreenCapturing {
    private let result: Result<CGImage, Error>
    init(_ result: Result<CGImage, Error>) { self.result = result }
    func captureRegion() async throws -> CGImage { try result.get() }
}

/// Holds `captureRegion()` open until the test calls `finish(with:)`, standing in for a
/// user who is still selecting a region (or a slow OCR) when the shortcut fires again.
@MainActor private final class SuspendedScreenCapture: ScreenCapturing {
    private(set) var callCount = 0
    private var continuation: CheckedContinuation<CGImage, Error>?
    var isWaiting: Bool { continuation != nil }

    func captureRegion() async throws -> CGImage {
        callCount += 1
        // Re-entry means the coordinator's gate is broken. Fail fast: overwriting the
        // pending continuation would leak it and hang the test instead.
        guard continuation == nil else {
            Issue.record("captureRegion() re-entered while a capture was pending")
            throw CaptureError.captureFailed(nil)
        }
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func finish(with image: CGImage) {
        continuation?.resume(returning: image)
        continuation = nil
    }
}

@MainActor private final class StubRecognizer: TextRecognizing {
    private let result: Result<String, Error>
    init(_ result: Result<String, Error>) { self.result = result }
    func recognizeText(in image: CGImage) async throws -> String { try result.get() }
}

@MainActor private final class SpyPasteboard: Pasteboarding {
    var copied: [String] = []
    func copyText(_ text: String) { copied.append(text) }
}

@MainActor private final class SpyNotifications: Notifying {
    enum Event: Equatable { case success(String), noText, ocrFailed, failure }
    var events: [Event] = []
    func notifySuccess(preview text: String) async { events.append(.success(text)) }
    func notifyNoText() async { events.append(.noText) }
    func notifyOCRFailed() async { events.append(.ocrFailed) }
    func notifyFailure() async { events.append(.failure) }
}

@MainActor private final class SpyHistory: HistoryRecording {
    var recorded: [String] = []
    func record(_ text: String) { recorded.append(text) }
}

@MainActor private final class SpyPermission: PermissionPresenting {
    var presentedCount = 0
    func presentScreenRecordingDenied() async { presentedCount += 1 }
}

private func dummyImage() -> CGImage {
    let context = CGContext(
        data: nil,
        width: 1,
        height: 1,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceGray(),
        bitmapInfo: CGImageAlphaInfo.none.rawValue
    )!
    return context.makeImage()!
}
