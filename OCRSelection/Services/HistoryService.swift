import Foundation
import SwiftData

@MainActor
struct HistoryService: HistoryRecording {
    let container: ModelContainer

    func record(_ text: String) {
        let context = container.mainContext
        context.insert(OCREntry(text: text))
        prune(in: context)
        do {
            try context.save()
        } catch {
            NSLog("OCR Selection history save failed: %@", String(describing: error))
        }
    }

    func clear() {
        let context = container.mainContext
        do {
            try context.delete(model: OCREntry.self)
            try context.save()
        } catch {
            NSLog("OCR Selection history clear failed: %@", String(describing: error))
        }
    }

    private func prune(in context: ModelContext) {
        let cap = max(1, UserDefaults.standard.integer(forKey: AppSettings.historyMaxCountKey))
        let descriptor = FetchDescriptor<OCREntry>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let entries: [OCREntry]
        do {
            entries = try context.fetch(descriptor)
        } catch {
            NSLog("OCR Selection history prune fetch failed: %@", String(describing: error))
            return
        }
        guard entries.count > cap else { return }
        for entry in entries.dropFirst(cap) {
            context.delete(entry)
        }
    }
}
