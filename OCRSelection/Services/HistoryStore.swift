import Foundation

/// One history entry, detached from SwiftData.
///
/// The menu renders these instead of `OCREntry` model objects on purpose: a
/// `MenuBarExtra(.menu)` body is re-evaluated far more often than the menu is opened,
/// and a `@Query` there means a SwiftData fetch — plus faulting of managed objects —
/// on every one of those evaluations.
struct HistoryItem: Identifiable, Hashable, Sendable {
    let id: UUID
    let text: String
    let createdAt: Date
}

extension HistoryItem {
    init(_ entry: OCREntry) {
        self.init(id: entry.id, text: entry.text, createdAt: entry.createdAt)
    }
}

/// Observable snapshot of the newest history entries, refreshed only when the history
/// actually changes (a capture, or a clear from Preferences). This is what the menu reads.
@MainActor
@Observable
final class HistoryStore: HistoryRecording {
    /// How many entries the menu shows — also the fetch limit, so nothing more is loaded.
    static let menuLimit = 10

    private(set) var items: [HistoryItem] = []
    @ObservationIgnored private let service: HistoryService

    init(service: HistoryService) {
        self.service = service
        refresh()
    }

    func record(_ text: String) {
        service.record(text)
        refresh()
    }

    func clear() {
        service.clear()
        refresh()
    }

    func refresh() {
        items = service.recentItems(limit: Self.menuLimit)
    }
}
