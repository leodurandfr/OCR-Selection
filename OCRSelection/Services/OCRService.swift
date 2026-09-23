import CoreGraphics
import CoreML
import Foundation
import Vision

enum OCRError: Error {
    case noTextFound
    case visionFailed(Error)
}

@MainActor
struct OCRService: TextRecognizing {
    /// One Vision pass over an image; `cpuOnly` pins every compute stage to the CPU.
    typealias Pass = (CGImage, _ cpuOnly: Bool) async throws -> String

    private let pass: Pass
    /// A reference type so every copy of this struct shares the device decision.
    private let device = ComputeDevicePreference()

    init() {
        self.init(pass: Self.visionPass)
    }

    /// Injects the Vision pass so tests can simulate a Neural Engine failure.
    init(pass: @escaping Pass) {
        self.pass = pass
    }

    func recognizeText(in image: CGImage) async throws -> String {
        if device.cpuOnly {
            return try await pass(image, true)
        }
        do {
            return try await pass(image, false)
        } catch OCRError.visionFailed(let underlying) {
            // On macOS 27.0 Vision intermittently fails to load its recogniser on the
            // Neural Engine (`e5rtError … precompiled_compute_operation … 13`) in a
            // long-running process, and keeps failing until relaunch. Failing takes a few
            // ms, so retry the same image with every stage pinned to the CPU rather than
            // telling the user the text couldn't be read.
            PerfLog.logger.error("OCR failed on default device, retrying on CPU: \(String(describing: underlying), privacy: .public)")
            do {
                let text = try await pass(image, true)
                stayOnCPU()
                return text
            } catch OCRError.noTextFound {
                stayOnCPU()
                throw OCRError.noTextFound
            }
            // Any other CPU failure is rethrown without switching: when both devices fail,
            // the image rather than the Neural Engine is the likely culprit.
        }
    }

    /// The CPU worked where the default device failed, so the fault is the device, and
    /// it is sticky: skip the doomed default attempt for the rest of this process.
    private func stayOnCPU() {
        device.cpuOnly = true
        PerfLog.logger.notice("OCR recovered on CPU, staying on CPU until relaunch")
    }

    nonisolated static func visionPass(_ image: CGImage, cpuOnly: Bool) async throws -> String {
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
                if cpuOnly {
                    Self.pinToCPU(request)
                }

                let handler = VNImageRequestHandler(cgImage: image, options: [:])
                do {
                    try handler.perform([request])
                } catch {
                    resume(.failure(OCRError.visionFailed(error)))
                }
            }
        }
    }

    /// Logs when a stage can't be pinned, so a failed "CPU" retry that actually ran on the
    /// default device isn't mistaken for the CPU path being broken.
    nonisolated private static func pinToCPU(_ request: VNRequest) {
        let stages: [VNComputeStage: [MLComputeDevice]]
        do {
            stages = try request.supportedComputeStageDevices
        } catch {
            PerfLog.logger.error("OCR could not list compute devices, CPU retry runs unpinned: \(String(describing: error), privacy: .public)")
            return
        }
        for (stage, devices) in stages {
            let cpu = devices.first { device in
                if case .cpu = device { return true }
                return false
            }
            if let cpu {
                request.setComputeDevice(cpu, for: stage)
            } else {
                PerfLog.logger.error("OCR stage \(stage.rawValue, privacy: .public) has no CPU device, left on default")
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

/// Whether Vision has been moved off its default device for the rest of this process.
@MainActor
final class ComputeDevicePreference {
    var cpuOnly = false
}
