import Foundation

/// Tells whether the volume holding the home folder, and so `~/Library/Caches`, is nearly
/// full, so an OCR failure or a very slow OCR can be blamed on the disk instead of the app.
///
/// When free space runs low, macOS's `deleted` daemon purges `~/Library/Caches`, including
/// the Neural Engine model Vision compiled for this app. The next recognition then has to
/// recompile it (30–60 s), or fails with `e5rtError … 13` if the model was purged while
/// loaded. Purges were observed at 14 GB and 9.7 GB free, and had stopped at 24 GB.
@MainActor
struct DiskSpaceService: DiskSpaceChecking {
    static let nearlyFullBytes: Int64 = 20_000_000_000

    func isNearlyFull() -> Bool {
        // `volumeAvailableCapacityKey`, not `…ForImportantUsage`: the latter counts purgeable
        // space as available, and that space is exactly the caches being purged.
        let home = FileManager.default.homeDirectoryForCurrentUser
        guard let free = try? home.resourceValues(forKeys: [.volumeAvailableCapacityKey])
            .volumeAvailableCapacity else { return false }
        let nearlyFull = Int64(free) < Self.nearlyFullBytes
        if nearlyFull {
            PerfLog.logger.notice("disk nearly full: free=\(String(format: "%.1f", Double(free) / 1e9), privacy: .public)GB")
        }
        return nearlyFull
    }
}
