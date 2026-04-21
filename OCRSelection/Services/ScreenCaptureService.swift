import AppKit
import Foundation

enum CaptureError: Error {
    case userCancelled
    case clipboardEmpty
    case decodingFailed
    case screenCaptureFailed(String)
}

struct ScreenCaptureService {
    func captureRegion() async throws -> CGImage {
        let pasteboard = NSPasteboard.general
        let initialChangeCount = pasteboard.changeCount

        let stderr = try await runScreenCapture()

        guard pasteboard.changeCount != initialChangeCount else {
            let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                throw CaptureError.userCancelled
            } else {
                throw CaptureError.screenCaptureFailed(trimmed)
            }
        }

        guard let data = pasteboard.data(forType: .tiff) ?? pasteboard.data(forType: .png) else {
            throw CaptureError.clipboardEmpty
        }

        guard let image = NSImage(data: data),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw CaptureError.decodingFailed
        }

        return cgImage
    }

    private func runScreenCapture() async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-c"]
        let errPipe = Pipe()
        process.standardError = errPipe

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { _ in
                continuation.resume()
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }

        let data = errPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
