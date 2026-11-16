import CoreGraphics
import Foundation
import Vision

enum OCRError: Error {
    case noTextFound
    case visionFailed(Error)
}

@MainActor
struct OCRService: TextRecognizing {
    /// Plain text recognition, not `RecognizeDocumentsRequest`. The document request also
    /// reports paragraphs, lists and tables, but on the same clean image it intermittently
    /// returned only some of the lines, or none, depending on how Vision scheduled it
    /// (reproduced by pinning its compute device: 1108 characters by default, 461 on the
    /// Neural Engine, 132 on the GPU or CPU). Text recognition read every line on every
    /// device, so the structure is rebuilt from the line geometry in `TextAssembler`.
    func recognizeText(in image: CGImage) async throws -> String {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = true
        request.usesLanguageCorrection = true

        let observations: [RecognizedTextObservation]
        do {
            // Vision's `perform` is nonisolated: the recognition runs off the main actor.
            observations = try await request.perform(on: image)
        } catch {
            throw OCRError.visionFailed(error)
        }

        let text = await Self.assemble(
            observations,
            imageSize: CGSize(width: image.width, height: image.height),
            preserveLineBreaks: UserDefaults.standard.bool(forKey: AppSettings.preserveLineBreaksKey)
        )
        guard !text.isEmpty else { throw OCRError.noTextFound }
        return text
    }

    /// nonisolated so the geometry work on a large capture stays off the main actor.
    private nonisolated static func assemble(
        _ observations: [RecognizedTextObservation], imageSize: CGSize, preserveLineBreaks: Bool
    ) async -> String {
        TextAssembler.text(from: RecognizedLayout(observations, imageSize: imageSize), preserveLineBreaks: preserveLineBreaks)
    }
}

extension RecognizedLayout {
    init(_ observations: [RecognizedTextObservation], imageSize: CGSize) {
        fragments = observations.compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            return Fragment(text: text, frame: observation.boundingBox.toImageCoordinates(imageSize, origin: .upperLeft))
        }
    }
}
