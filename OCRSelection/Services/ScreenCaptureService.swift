import AppKit

/// Native capture backend: drives Apple's interactive `screencapture -i -c` selection UI
/// (crosshair, space-to-move, window mode), reads the captured image back off the
/// pasteboard, and restores the user's previous clipboard so a later OCR failure can't
/// destroy what they had copied.
///
/// This shells out to `/usr/sbin/screencapture`, which is why App Sandbox is disabled —
/// the trade-off for keeping Apple's excellent native selection UI (Developer ID
/// distribution rather than the Mac App Store).
@MainActor
struct ScreenCaptureService: ScreenCapturing {
    func captureRegion() async throws -> CGImage {
        let pasteboard = NSPasteboard.general
        // Snapshot the user's clipboard before `screencapture -c` overwrites it with the
        // captured image, so we can put it back and never destroy what they had copied.
        let savedItems = snapshot(of: pasteboard)
        let initialChangeCount = pasteboard.changeCount

        let stderr = try await runScreenCapture()

        guard pasteboard.changeCount != initialChangeCount else {
            // screencapture wrote nothing → the clipboard is untouched, nothing to restore.
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

        // The image is now on the general pasteboard. Whatever happens next (decode
        // failure, OCR failure, empty text), restore the user's original clipboard.
        defer { restore(savedItems, to: pasteboard) }

        guard let data = pasteboard.data(forType: .tiff) ?? pasteboard.data(forType: .png) else {
            throw CaptureError.captureFailed(nil)
        }
        guard let image = NSImage(data: data),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw CaptureError.captureFailed(nil)
        }
        return cgImage
    }

    // nonisolated so the blocking stderr read runs off the main actor.
    private nonisolated func runScreenCapture() async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-c"]
        let errPipe = Pipe()
        process.standardError = errPipe

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { _ in continuation.resume() }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }

        let data = errPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Deep-copies the pasteboard's current items so they survive a later `clearContents()`.
    private func snapshot(of pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        guard let items = pasteboard.pasteboardItems else { return [] }
        return items.map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }
    }

    /// Restores a previously captured snapshot, replacing the screenshot image that
    /// `screencapture -c` left behind. An empty snapshot clears the pasteboard, which
    /// correctly reproduces the "clipboard was empty" starting state.
    private func restore(_ items: [NSPasteboardItem], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        pasteboard.writeObjects(items)
    }
}

/// Carries `screencapture`'s stderr text into `CaptureError.captureFailed` for logging.
struct ScreenCaptureCLIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
