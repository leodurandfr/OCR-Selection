import CoreGraphics
import Foundation
import Vision

enum OCRError: Error {
    case noTextFound
    case visionFailed(Error)
}

struct OCRService {
    func recognizeText(in image: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest { request, error in
                    if let error {
                        continuation.resume(throwing: OCRError.visionFailed(error))
                        return
                    }
                    let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                    let sorted = observations.sorted { $0.boundingBox.midY > $1.boundingBox.midY }
                    let text = sorted
                        .compactMap { $0.topCandidates(1).first?.string }
                        .joined(separator: "\n")
                    if text.isEmpty {
                        continuation.resume(throwing: OCRError.noTextFound)
                    } else {
                        continuation.resume(returning: text)
                    }
                }
                request.recognitionLevel = .accurate
                request.automaticallyDetectsLanguage = true
                request.usesLanguageCorrection = true

                let handler = VNImageRequestHandler(cgImage: image, options: [:])
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: OCRError.visionFailed(error))
                }
            }
        }
    }
}
