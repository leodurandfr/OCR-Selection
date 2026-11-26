import CoreGraphics
import CoreText
import Foundation
import Vision

/// The Vision side of OCR, run inside the recognizer service so that a broken Vision
/// (its compiled model purged from under it) dies with the service process instead of
/// sticking to the app until it is relaunched.
enum TextRecognition {
    /// Plain text recognition, not `RecognizeDocumentsRequest`. The document request also
    /// reports paragraphs, lists and tables, but on the same clean image it intermittently
    /// returned only some of the lines, or none, depending on how Vision scheduled it
    /// (reproduced by pinning its compute device: 1108 characters by default, 461 on the
    /// Neural Engine, 132 on the GPU or CPU). Text recognition read every line on every
    /// device, so the structure is rebuilt from the line geometry in the app's `TextAssembler`.
    static func recognize(_ image: CGImage) async throws -> RecognizedLayout {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = true
        request.usesLanguageCorrection = true
        let observations = try await request.perform(on: image)
        let size = CGSize(width: image.width, height: image.height)
        return RecognizedLayout(fragments: observations.compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            return .init(text: text, frame: observation.boundingBox.toImageCoordinates(size, origin: .upperLeft))
        })
    }

    /// A small line of text for `prewarm`: recognising it with the same request as a
    /// capture makes Vision load (or recompile) the models a capture will need.
    static func prewarmImage() -> CGImage? {
        let width = 480, height = 96
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let font = CTFontCreateWithName("Helvetica" as CFString, 40, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "Warm up 2026", attributes: attributes))
        context.textPosition = CGPoint(x: 24, y: 30)
        CTLineDraw(line, context)
        return context.makeImage()
    }
}
