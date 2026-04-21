import AppKit
import Testing
@testable import OCRSelection

@MainActor
struct PasteboardServiceTests {
    @Test func copiesTextRoundtrip() {
        let service = PasteboardService()
        let text = "OCR Selection roundtrip \(UUID().uuidString)"
        service.copyText(text)
        let copied = NSPasteboard.general.string(forType: .string)
        #expect(copied == text)
    }

    @Test func replacesPreviousContents() {
        let service = PasteboardService()
        service.copyText("first")
        service.copyText("second")
        let copied = NSPasteboard.general.string(forType: .string)
        #expect(copied == "second")
    }
}
