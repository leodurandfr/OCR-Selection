import CoreGraphics
import Foundation
import Vision

enum OCRError: Error {
    case noTextFound
    case visionFailed(Error)
}

@MainActor
struct OCRService: TextRecognizing {
    func recognizeText(in image: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                // Resume exactly once. Vision can both invoke the completion handler with
                // an error AND have `perform` throw for the same failure; resuming twice
                // crashes in debug and is undefined behaviour in release. The handler and
                // the `perform` call run on this one serial block, so a plain flag is safe.
                var didResume = false
                func resume(_ result: Result<String, Error>) {
                    guard !didResume else { return }
                    didResume = true
                    continuation.resume(with: result)
                }

                let request = VNRecognizeTextRequest { request, error in
                    if let error {
                        resume(.failure(OCRError.visionFailed(error)))
                        return
                    }
                    let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                    let text = Self.assembleText(from: observations)
                    resume(text.isEmpty ? .failure(OCRError.noTextFound) : .success(text))
                }
                request.recognitionLevel = .accurate
                request.automaticallyDetectsLanguage = true
                request.usesLanguageCorrection = true

                let handler = VNImageRequestHandler(cgImage: image, options: [:])
                do {
                    try handler.perform([request])
                } catch {
                    resume(.failure(OCRError.visionFailed(error)))
                }
            }
        }
    }

    /// Joins recognised observations into reading order. Vision uses normalised
    /// coordinates with the origin at bottom-left, so a higher `midY` is higher on
    /// screen. Observations are grouped into visual lines (top to bottom) using a
    /// vertical band, then ordered left to right within each line — which keeps
    /// same-line fragments and side-by-side columns from being interleaved or reversed.
    nonisolated static func assembleText(from observations: [VNRecognizedTextObservation]) -> String {
        let topToBottom = observations.sorted { $0.boundingBox.midY > $1.boundingBox.midY }
        var lines: [[VNRecognizedTextObservation]] = []
        for observation in topToBottom {
            if let reference = lines.last?.first {
                let band = min(observation.boundingBox.height, reference.boundingBox.height) * 0.5
                if abs(observation.boundingBox.midY - reference.boundingBox.midY) <= band {
                    lines[lines.count - 1].append(observation)
                    continue
                }
            }
            lines.append([observation])
        }
        return lines
            .map { line in
                line
                    .sorted { $0.boundingBox.minX < $1.boundingBox.minX }
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: " ")
            }
            .joined(separator: "\n")
    }
}
