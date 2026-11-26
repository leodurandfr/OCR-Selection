import Foundation

/// EXPERIMENT — drop this file and its one call in `AppDelegate` to undo it.
///
/// Moves the recognizer service's Vision cache out of `~/Library/Caches`, the folder
/// macOS's `deleted` purges when the disk is nearly full, by replacing
/// `~/Library/Caches/<service bundle ID>` with a symlink to
/// `~/Library/Application Support/<OCRSelection | OCRSelection Debug>/VisionCache`.
///
/// Verified: Vision follows the symlink (the compiled `.bundle`s land in the target, OCR
/// works, the next launch is warm). **Also verified, on 2026-11-26 at 7.7 GB free: it does
/// not protect the models.** The purge deleted the files in the target as well — e5rt marks
/// them purgeable, and APFS purges such files wherever they live. Candidate for removal.
///
/// Must run before the service first starts Vision, i.e. before any recognition.
@MainActor
enum VisionCacheRelocation {
    static func targetDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support", directoryHint: .isDirectory)
            .appending(path: HistoryContainer.directoryName, directoryHint: .isDirectory)
            .appending(path: "VisionCache", directoryHint: .isDirectory)
    }

    /// Makes `cacheRoot` a symlink to `target`, carrying over any models already compiled
    /// there. Idempotent; returns whether the symlink is in place.
    @discardableResult
    static func relocate(cacheRoot: URL, to target: URL? = nil) -> Bool {
        let target = target ?? targetDirectory()
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: target, withIntermediateDirectories: true)
            if let destination = try? fm.destinationOfSymbolicLink(atPath: cacheRoot.path) {
                if URL(fileURLWithPath: destination).standardizedFileURL == target.standardizedFileURL { return true }
                try fm.removeItem(at: cacheRoot)
            } else if fm.fileExists(atPath: cacheRoot.path) {
                // A real folder: keep what Vision compiled into it, so moving costs no recompile.
                for item in try fm.contentsOfDirectory(at: cacheRoot, includingPropertiesForKeys: nil) {
                    let moved = target.appending(path: item.lastPathComponent)
                    if fm.fileExists(atPath: moved.path) {
                        try fm.removeItem(at: item)
                    } else {
                        try fm.moveItem(at: item, to: moved)
                    }
                }
                try fm.removeItem(at: cacheRoot)
            }
            try fm.createDirectory(at: cacheRoot.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.createSymbolicLink(at: cacheRoot, withDestinationURL: target)
            PerfLog.health.notice("vision cache relocated to \(target.path, privacy: .public)")
            return true
        } catch {
            PerfLog.health.error("vision cache relocation failed: \(String(describing: error), privacy: .public)")
            return false
        }
    }
}
