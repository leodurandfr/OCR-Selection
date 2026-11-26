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

    /// What `prewarm` recognises: a line of Latin text, then a line of Arabic. Vision runs
    /// one recognition model per script, compiled for the Neural Engine on first use: with
    /// the text detector and the orientation model, the Latin line compiles three. Captures
    /// were seen compiling a fourth, `cr_tr_model_arabic_v3` (13–16 s), as automatic
    /// language detection tried Arabic on some line, so the prewarm compiles it too.
    static func prewarmImages() -> [CGImage] {
        [
            render(lines: ["The quick brown fox jumps over the lazy dog"], width: 1400, height: 96),
            render(lines: ["مرحبا بكم في التعرف على النص"], width: 1400, height: 96, fontName: "GeezaPro")
        ].compactMap { $0 }
    }

    private static func render(lines: [String], width: Int, height: Int, fontName: String = "Helvetica") -> CGImage? {
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
        let font = CTFontCreateWithName(fontName as CFString, 40, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        ]
        for (index, text) in lines.enumerated() {
            let ctLine = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
            // Core Graphics counts y upwards: the first line is drawn at the top.
            context.textPosition = CGPoint(x: 24, y: CGFloat(height - 66 - 100 * index))
            CTLineDraw(ctLine, context)
        }
        return context.makeImage()
    }
}
