import AppKit
import CoreGraphics
import CoreText
import Testing
@testable import OCRSelection

@MainActor
struct OCRServiceTests {
    @Test func recognizesKnownText() async throws {
        let image = try renderFixture(text: "Hello World")
        let service = OCRService()
        let result = try await service.recognizeText(in: image)
        #expect(result.contains("Hello"))
        #expect(result.contains("World"))
    }

    @Test func rejoinsTextWrappedByItsColumn() async throws {
        defer { UserDefaults.standard.removeObject(forKey: AppSettings.preserveLineBreaksKey) }
        UserDefaults.standard.set(false, forKey: AppSettings.preserveLineBreaksKey)
        let image = try renderWrappedParagraph(
            "The quick brown fox jumps over the lazy dog while the cat watches quietly from the kitchen window."
        )
        let result = try await OCRService().recognizeText(in: image)
        #expect(!result.contains("\n"))
        #expect(result.contains("lazy dog"))
        #expect(result.contains("kitchen window"))
    }
}

/// Lays `text` out in a column narrow enough to wrap it over several lines.
private func renderWrappedParagraph(_ text: String) throws -> CGImage {
    let size = CGSize(width: 700, height: 360)
    guard let context = CGContext(
        data: nil,
        width: Int(size.width),
        height: Int(size.height),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw FixtureError.contextCreationFailed
    }
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(origin: .zero, size: size))
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 32),
        .foregroundColor: NSColor.black
    ]
    let framesetter = CTFramesetterCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    let path = CGPath(rect: CGRect(x: 30, y: 30, width: size.width - 60, height: size.height - 60), transform: nil)
    CTFrameDraw(CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil), context)
    guard let image = context.makeImage() else { throw FixtureError.renderFailed }
    return image
}

private func renderFixture(text: String) throws -> CGImage {
    let size = CGSize(width: 800, height: 200)
    guard let context = CGContext(
        data: nil,
        width: Int(size.width),
        height: Int(size.height),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw FixtureError.contextCreationFailed
    }
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(origin: .zero, size: size))
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 80, weight: .bold),
        .foregroundColor: NSColor.black
    ]
    let attributed = NSAttributedString(string: text, attributes: attributes)
    let line = CTLineCreateWithAttributedString(attributed)
    context.textPosition = CGPoint(x: 40, y: 60)
    CTLineDraw(line, context)
    guard let image = context.makeImage() else { throw FixtureError.renderFailed }
    return image
}

private enum FixtureError: Error {
    case contextCreationFailed
    case renderFailed
}
