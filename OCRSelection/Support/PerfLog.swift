import Darwin
import Foundation
import os

/// Performance and health instrumentation.
///
/// Two audiences:
/// - **Instruments** — `signposter` intervals show up in the os_signpost track.
/// - **After the fact** — everything worth diagnosing a slowdown or a runaway process
///   is emitted at `.notice` level or above, because `.info`/`.debug` live only in the
///   in-memory ring buffer and are gone by the time a bug is reported. `.notice` is
///   persisted to disk, so the previous day can be replayed with:
///
///   ```
///   log show --last 1d --predicate 'subsystem BEGINSWITH "com.leodurand.ocr-selection"' --style compact
///   ```
///
/// The Debug build logs under its own bundle ID (`com.leodurand.ocr-selection.debug`), so
/// the two apps can be told apart when both are running; `BEGINSWITH` shows both.
///
/// Nothing recognised by OCR is ever logged — only lengths and durations.
enum PerfLog {
    #if DEBUG
    static let subsystem = "com.leodurand.ocr-selection.debug"
    #else
    static let subsystem = "com.leodurand.ocr-selection"
    #endif
    static let signposter = OSSignposter(subsystem: subsystem, category: "capture")
    /// Per-capture timings and failures.
    static let logger = Logger(subsystem: subsystem, category: "perf")
    /// Periodic process vitals (see `HealthMonitor`).
    static let health = Logger(subsystem: subsystem, category: "health")

    /// Converts a `Duration` to fractional milliseconds for logging.
    static func milliseconds(_ duration: Duration) -> Double {
        let c = duration.components
        return Double(c.seconds) * 1_000 + Double(c.attoseconds) / 1_000_000_000_000_000
    }

    /// Memory footprint in MB — the same `phys_footprint` figure Activity Monitor and
    /// the `footprint` CLI report, and the one macOS uses when deciding to kill a process.
    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return -1 }
        return Double(info.phys_footprint) / 1_048_576
    }
}

/// Heartbeat that turns an intermittent "the app got slow / got killed" report into evidence.
///
/// Every `interval` it writes one persisted line with the process footprint, how many times
/// the menu-bar content was rebuilt since the last tick, and how late the timer actually fired.
/// Three things then become readable straight from the log:
/// - **a memory climb** → a leak, visible as a rising `mem=`;
/// - **a render storm** → SwiftUI re-evaluating the menu in a loop, visible as a large `menuRenders=`;
/// - **a main-thread stall** → the app frozen, visible as a `lag=` spike or a gap between heartbeats.
@MainActor
final class HealthMonitor {
    static let shared = HealthMonitor()

    private var timer: Timer?
    private var expectedFireDate: Date?
    private var interval: TimeInterval = 60
    private var menuRenders = 0
    private var rendersAtLastTick = 0
    private var captures = 0
    private let started = Date()

    private init() {}

    /// Called from the menu-bar content's `body`. Cheap on purpose: this is the counter
    /// that tells us whether SwiftUI is rebuilding the menu thousands of times a minute.
    func noteMenuRender() {
        menuRenders += 1
    }

    func noteCapture() {
        captures += 1
    }

    func start(interval: TimeInterval = 60) {
        self.interval = interval
        timer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            Task { @MainActor in HealthMonitor.shared.tick() }
        }
        // A generous tolerance keeps the heartbeat from waking the CPU on its own schedule;
        // `lag` below is measured against the expected date, not the tolerated one.
        timer.tolerance = interval / 4
        expectedFireDate = Date().addingTimeInterval(interval)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
    }

    private func tick() {
        let now = Date()
        let lag = expectedFireDate.map { now.timeIntervalSince($0) } ?? 0
        expectedFireDate = now.addingTimeInterval(interval)
        let renders = menuRenders - rendersAtLastTick
        rendersAtLastTick = menuRenders

        PerfLog.health.notice(
            """
            heartbeat mem=\(String(format: "%.1f", PerfLog.footprintMB()), privacy: .public)MB \
            uptime=\(Int(now.timeIntervalSince(self.started)), privacy: .public)s \
            menuRenders=+\(renders, privacy: .public)/\(self.menuRenders, privacy: .public) \
            captures=\(self.captures, privacy: .public) \
            lag=\(String(format: "%.1f", max(0, lag)), privacy: .public)s
            """
        )
    }
}
