import Foundation

struct CaptureCoordinator {
    var screenCapture = ScreenCaptureService()
    var ocr = OCRService()
    var pasteboard = PasteboardService()

    func run() async throws {
        let image = try await screenCapture.captureRegion()
        let text = try await ocr.recognizeText(in: image)
        pasteboard.copyText(text)
    }
}
