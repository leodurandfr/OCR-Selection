import Foundation
import SwiftData

/// Builds the SwiftData container that backs the capture history.
///
/// Two things this fixes over a bare `ModelContainer(for: OCREntry.self)`:
///
/// 1. **Location.** For a non-sandboxed app the default store URL is
///    `~/Library/Application Support/default.store` — the *shared* Application Support
///    root, not a folder the app owns. The store now lives in an app-scoped subfolder,
///    and a store found at the legacy path is migrated once and removed.
/// 2. **Autosave.** `mainContext.autosaveEnabled` defaults to `true`, which runs a
///    run-loop timer that saves on the main thread. Every write here is already an
///    explicit `save()`, so the timer only ever adds main-thread work — it was the
///    heaviest stack in a `cpu_resource` diagnostic report (100% of samples in
///    `__NSFireTimer → SwiftData → save:`), so it is switched off.
@MainActor
enum HistoryContainer {
    static let directoryName = "OCRSelection"
    static let storeName = "History.store"
    /// The pre-1.1 store location: Application Support root, default SwiftData name.
    static let legacyStoreName = "default.store"
    /// SQLite writes alongside the store; they move (and are cleaned up) with it.
    private static let sidecarSuffixes = ["-wal", "-shm"]

    /// - Parameter supportDirectory: Application Support root. Injectable so migration
    ///   can be tested against a temporary directory instead of the real one.
    static func make(in supportDirectory: URL? = nil) throws -> ModelContainer {
        let support = try supportDirectory ?? defaultSupportDirectory()
        let directory = support.appending(path: directoryName, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: storeName, directoryHint: .notDirectory)

        let rescued = FileManager.default.fileExists(atPath: url.path)
            ? []
            : takeLegacyEntries(from: support.appending(path: legacyStoreName, directoryHint: .notDirectory))

        let container = try ModelContainer(
            for: OCREntry.self,
            configurations: ModelConfiguration(url: url)
        )
        container.mainContext.autosaveEnabled = false

        if !rescued.isEmpty {
            let context = container.mainContext
            for entry in rescued {
                context.insert(OCREntry(id: entry.id, text: entry.text, createdAt: entry.createdAt))
            }
            try? context.save()
            PerfLog.health.notice("migrated \(rescued.count, privacy: .public) history entries from the legacy store")
        }
        return container
    }

    static func defaultSupportDirectory() throws -> URL {
        try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
    }

    /// Reads the entries out of a legacy store and deletes it.
    ///
    /// Opened with `allowsSave: false` so that a `default.store` belonging to some *other*
    /// non-sandboxed SwiftData app can't be migrated to our schema: a foreign store fails
    /// to open read-only against `OCREntry`, we return empty, and its files are left alone.
    private static func takeLegacyEntries(from url: URL) -> [(id: UUID, text: String, createdAt: Date)] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            let container = try ModelContainer(
                for: OCREntry.self,
                configurations: ModelConfiguration(url: url, allowsSave: false)
            )
            let entries = try container.mainContext
                .fetch(FetchDescriptor<OCREntry>())
                .map { (id: $0.id, text: $0.text, createdAt: $0.createdAt) }
            removeStoreFiles(at: url)
            return entries
        } catch {
            PerfLog.health.error("legacy store left in place, not readable as OCREntry: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    private static func removeStoreFiles(at url: URL) {
        for suffix in [""] + sidecarSuffixes {
            let file = URL(fileURLWithPath: url.path + suffix)
            try? FileManager.default.removeItem(at: file)
        }
    }
}
