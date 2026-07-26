import Foundation
import SwiftData

/// SwiftData access for the capture history. The only type in the app that touches
/// `ModelContext` — everything else reads the value snapshot published by `HistoryStore`.
@MainActor
struct HistoryService: HistoryRecording {
    let container: ModelContainer

    func record(_ text: String) {
        let context = container.mainContext
        context.insert(OCREntry(text: text))
        save(context, operation: "record")
        prune(in: context)
    }

    func clear() {
        let context = container.mainContext
        do {
            try context.delete(model: OCREntry.self)
        } catch {
            PerfLog.logger.error("history clear failed: \(String(describing: error), privacy: .public)")
        }
        save(context, operation: "clear")
    }

    /// The newest entries, as plain values. Bounded by `fetchLimit` so the menu never
    /// materialises more model objects than it displays.
    func recentItems(limit: Int) -> [HistoryItem] {
        var descriptor = FetchDescriptor<OCREntry>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = max(0, limit)
        do {
            return try container.mainContext.fetch(descriptor).map(HistoryItem.init)
        } catch {
            PerfLog.logger.error("history fetch failed: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    /// Deletes everything past the cap. `fetchOffset` makes SQLite skip the entries we
    /// keep, so this fetches only the rows about to be deleted rather than the whole table.
    private func prune(in context: ModelContext) {
        let cap = max(1, UserDefaults.standard.integer(forKey: AppSettings.historyMaxCountKey))
        var descriptor = FetchDescriptor<OCREntry>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchOffset = cap
        let excess: [OCREntry]
        do {
            excess = try context.fetch(descriptor)
        } catch {
            PerfLog.logger.error("history prune fetch failed: \(String(describing: error), privacy: .public)")
            return
        }
        guard !excess.isEmpty else { return }
        for entry in excess {
            context.delete(entry)
        }
        save(context, operation: "prune")
    }

    private func save(_ context: ModelContext, operation: String) {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            PerfLog.logger.error("history \(operation, privacy: .public) save failed: \(String(describing: error), privacy: .public)")
        }
    }
}
