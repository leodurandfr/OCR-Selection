import Foundation
import os

/// Lightweight performance instrumentation for the capture pipeline.
///
/// Emits OS signpost intervals (visible in Instruments → os_signpost) and
/// human-readable durations to the unified log (Console.app, subsystem
/// `com.leodurand.ocr-selection`, category `perf`). Used to validate where the
/// time actually goes — and, after the ScreenCaptureKit migration, to measure the
/// real "time to crosshair" (shortcut → overlay visible), which cannot be observed
/// while the external `screencapture` binary owns the selection UI.
enum PerfLog {
    static let subsystem = "com.leodurand.ocr-selection"
    static let signposter = OSSignposter(subsystem: subsystem, category: "capture")
    static let logger = Logger(subsystem: subsystem, category: "perf")

    /// Converts a `Duration` to fractional milliseconds for logging.
    static func milliseconds(_ duration: Duration) -> Double {
        let c = duration.components
        return Double(c.seconds) * 1_000 + Double(c.attoseconds) / 1_000_000_000_000_000
    }
}
