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
        coordinator = CaptureCoordinator(
            screenCapture: StubScreenCapture(capture),
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
