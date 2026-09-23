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
