import AppKit
import ImageIO

/// Native capture backend: drives Apple's interactive `screencapture -i` selection UI
/// (crosshair, space-to-move, window mode) and reads the region back from a temporary file.
///
/// The capture is written to a file rather than to the clipboard (`-c`). Going through the
/// clipboard meant snapshotting and restoring whatever the user had copied around every
/// capture — a deep copy of every representation of every pasteboard item, on the main
/// thread, so a large image sitting in the clipboard turned a capture into hundreds of MB
/// of copying. It also briefly put the screenshot on the clipboard, which clipboard
/// managers happily recorded. With a temp file the user's clipboard is never touched at
/// all until the recognised text is copied.
///
/// This shells out to `/usr/sbin/screencapture`, which is why App Sandbox is disabled —
/// the trade-off for keeping Apple's excellent native selection UI (Developer ID
/// distribution rather than the Mac App Store).
@MainActor
struct ScreenCaptureService: ScreenCapturing {
    func captureRegion() async throws -> CGImage {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "ocr-capture-\(UUID().uuidString).png", directoryHint: .notDirectory)
        defer { try? FileManager.default.removeItem(at: url) }

        let stderr = try await runScreenCapture(writingTo: url)

        // screencapture only creates the file once a region has actually been captured.
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe), !data.isEmpty else {
            if !CGPreflightScreenCaptureAccess() {
                throw CaptureError.permissionDenied
            }
            let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                throw CaptureError.userCancelled
            } else {
                throw CaptureError.captureFailed(ScreenCaptureCLIError(message: trimmed))
            }
        }

        // Decoded eagerly from the bytes so nothing keeps reading the file after the
        // `defer` above deletes it.
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(
                  source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
              ) else {
            throw CaptureError.captureFailed(nil)
        }
        return image
    }

    /// `screencapture -i` waits for the user indefinitely. Past this the process is killed
    /// so a forgotten selection (or a wedged process) can't hold the capture gate forever.
    nonisolated static let selectionTimeout: TimeInterval = 300

    // nonisolated so the blocking stderr read runs off the main actor.
    private nonisolated func runScreenCapture(writingTo url: URL) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", url.path]
        let errPipe = Pipe()
        process.standardError = errPipe

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { _ in continuation.resume() }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
                return
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Self.selectionTimeout) {
                guard process.isRunning else { return }
                PerfLog.logger.error("screencapture still running after \(Int(Self.selectionTimeout), privacy: .public)s, terminating it")
                process.terminate()
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5) {
                    if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                }
            }
        }

        let data = errPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

/// Carries `screencapture`'s stderr text into `CaptureError.captureFailed` for logging.
struct ScreenCaptureCLIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
