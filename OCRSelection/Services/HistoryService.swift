import Foundation
import SwiftData

@MainActor
struct HistoryService {
    let container: ModelContainer

    func record(_ text: String) {
        let context = container.mainContext
        context.insert(OCREntry(text: text))
        prune(in: context)
        try? context.save()
    }

    func clear() {
        let context = container.mainContext
        try? context.delete(model: OCREntry.self)
        try? context.save()
    }

    private func prune(in context: ModelContext) {
        let cap = max(1, UserDefaults.standard.integer(forKey: "historyMaxCount"))
        let descriptor = FetchDescriptor<OCREntry>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        guard let entries = try? context.fetch(descriptor), entries.count > cap else { return }
        for entry in entries.dropFirst(cap) {
            context.delete(entry)
        }
    }
}
