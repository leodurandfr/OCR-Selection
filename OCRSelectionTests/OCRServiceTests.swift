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

    /// The real XPC path: a restart must hand the next request to a new process, since a
    /// reconnect alone would land in the old one and keep a broken Vision.
    @Test func restartGivesTheNextRequestAFreshServiceProcess() async throws {
        let connection = RecognizerConnection.shared
        let payload = try #require(ImagePayload(try renderFixture(text: "Fresh")))
        _ = try await connection.recognize(payload, timeout: .seconds(120))
        let before = try #require(connection.servicePid)
        #expect(before > 0)
        await connection.restart(reason: "test")
        #expect(kill(before, 0) != 0)
        let layout = try await connection.recognize(payload, timeout: .seconds(120))
        #expect(layout.fragments.map(\.text).joined().contains("Fresh"))
        let after = try #require(connection.servicePid)
        #expect(after > 0)
        #expect(after != before)
    }

    /// Recognition is limited to Latin-script languages, with the app's three first.
    @Test(arguments: ["Café déjà été", "Año señal niño"])
    func readsFrenchAndSpanishAccents(text: String) async throws {
        let result = try await OCRService().recognizeText(in: try renderFixture(text: text))
        #expect(result == text)
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

    @Test func readsABorderlessTableRowByRow() async throws {
        defer { UserDefaults.standard.removeObject(forKey: AppSettings.preserveLineBreaksKey) }
        UserDefaults.standard.set(false, forKey: AppSettings.preserveLineBreaksKey)
        let rows = [["Region", "Q1", "Q2"], ["North America", "1,204", "1,388"], ["Europe", "987", "1,020"]]
        let image = try renderGrid(rows, columnX: [20, 400, 600])
        let result = try await OCRService().recognizeText(in: image)
        // The layout is under test, not the reading of each value: three rows of three cells.
        let cells = result.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.split(separator: "\t", omittingEmptySubsequences: false) }
        #expect(cells.map(\.count) == [3, 3, 3])
        #expect(cells.first?.first == "Region")
        #expect(cells.map { $0.first ?? "" } == ["Region", "North America", "Europe"])
    }
}

/// Draws each row's values at the given column positions, 50 px apart, without borders.
private func renderGrid(_ rows: [[String]], columnX: [CGFloat]) throws -> CGImage {
    let size = CGSize(width: 900, height: 60 + 50 * CGFloat(rows.count))
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
        .font: NSFont.systemFont(ofSize: 26),
        .foregroundColor: NSColor.black
    ]
    for (rowIndex, values) in rows.enumerated() {
        for (value, x) in zip(values, columnX) {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: value, attributes: attributes))
            // Core Graphics counts y upwards: the first row is drawn at the top.
            context.textPosition = CGPoint(x: x, y: size.height - 46 - 50 * CGFloat(rowIndex))
            CTLineDraw(line, context)
        }
    }
    guard let image = context.makeImage() else { throw FixtureError.renderFailed }
    return image
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
