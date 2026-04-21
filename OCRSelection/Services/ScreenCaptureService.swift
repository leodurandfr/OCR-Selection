import AppKit
import Foundation

enum CaptureError: Error {
    case userCancelled
    case clipboardEmpty
    case decodingFailed
}

struct ScreenCaptureService {
    func captureRegion() async throws -> CGImage {
        let pasteboard = NSPasteboard.general
        let initialChangeCount = pasteboard.changeCount

        try await runScreenCapture()

        guard pasteboard.changeCount != initialChangeCount else {
            throw CaptureError.userCancelled
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

    private func runScreenCapture() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-i", "-c"]
            process.terminationHandler = { _ in
                continuation.resume()
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
