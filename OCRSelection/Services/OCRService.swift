import CoreGraphics
import Foundation

enum OCRError: Error {
    case noTextFound
    case visionFailed(Error)
}

/// Recognises text through the `OCRSelectionRecognizer` XPC service (Vision runs there,
/// see its `main.swift`) and assembles the layout it returns into clipboard text.
///
/// A failed recognition is retried once, transparently, on a fresh service process: when
/// macOS purges Vision's compiled model the process that had it loaded fails until it
/// exits, and a new one recompiles the model and works. Only if that second attempt fails
/// too does the user hear about it.
@MainActor
struct OCRService: TextRecognizing {
    let transport: any RecognitionTransport
    /// Per attempt. Generous: a cold model compile takes 30–60 s on its own.
    var timeout: Duration = .seconds(90)

    init(transport: (any RecognitionTransport)? = nil, timeout: Duration = .seconds(90)) {
        self.transport = transport ?? RecognizerConnection.shared
        self.timeout = timeout
    }

    func recognizeText(in image: CGImage) async throws -> String {
        guard let payload = await Self.payload(for: image) else {
            throw OCRError.visionFailed(RecognitionTransportError.malformed("image could not be converted"))
        }
        let layout = try await layout(for: payload)
        let text = await Self.assemble(
            layout,
            preserveLineBreaks: UserDefaults.standard.bool(forKey: AppSettings.preserveLineBreaksKey)
        )
        guard !text.isEmpty else { throw OCRError.noTextFound }
        return text
    }

    private func layout(for payload: ImagePayload) async throws -> RecognizedLayout {
        do {
            return try await transport.recognize(payload, timeout: timeout)
        } catch let error as RecognitionTransportError where error.isRetryable {
            PerfLog.logger.notice("OCR attempt failed: \(error.description, privacy: .public); retrying on a fresh recognizer")
            await transport.restartIfFailed(reason: "retry after \(error.description)")
            do {
                let layout = try await transport.recognize(payload, timeout: timeout)
                PerfLog.logger.notice("OCR recovered on a fresh recognizer")
                return layout
            } catch {
                // Leave a fresh process behind for the next capture rather than the one
                // that just failed.
                await transport.restartIfFailed(reason: "retry failed")
                throw OCRError.visionFailed(error)
            }
        } catch {
            // A timeout means the service is stuck: kill it so the next capture starts
            // clean, but don't make the user wait another full timeout now.
            await transport.restartIfFailed(reason: "\(error)")
            throw OCRError.visionFailed(error)
        }
    }

    /// nonisolated so flattening a large capture stays off the main actor.
    private nonisolated static func payload(for image: CGImage) async -> ImagePayload? {
        ImagePayload(image)
    }

    /// nonisolated so the geometry work on a large capture stays off the main actor.
    private nonisolated static func assemble(_ layout: RecognizedLayout, preserveLineBreaks: Bool) async -> String {
        TextAssembler.text(from: layout, preserveLineBreaks: preserveLineBreaks)
    }
}
