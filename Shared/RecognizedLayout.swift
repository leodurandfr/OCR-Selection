import CoreGraphics
import Foundation

/// What Vision's text recognition found: one fragment per run of text on a visual line.
/// Vision splits a line where a wide gap separates two runs, so a table row comes as one
/// fragment per cell and side-by-side text columns as one fragment per column. Kept free of
/// Vision types so tests can build layouts by hand, and Codable because it is what the
/// recognizer XPC service sends back to the app. Frames are in image pixels with the
/// origin at the top-left (y grows downwards), so the geometry reads like the screen.
///
/// Compiled into both the app and the `OCRSelectionRecognizer` service (`Shared/`).
struct RecognizedLayout: Equatable, Codable, Sendable {
    struct Fragment: Equatable, Codable, Sendable {
        var text: String
        var frame: CGRect
    }

    /// In any order: reading order is rebuilt from the frames.
    var fragments: [Fragment]
}
