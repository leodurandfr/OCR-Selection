import Foundation
import SwiftData
import Testing
@testable import OCRSelection

@MainActor
struct HistoryServiceTests {
    @Test func recordInsertsEntry() throws {
        defer { UserDefaults.standard.removeObject(forKey: "historyMaxCount") }
        UserDefaults.standard.set(30, forKey: "historyMaxCount")
        let container = try makeContainer()
        let service = HistoryService(container: container)

        service.record("hello")

        let entries = try container.mainContext.fetch(FetchDescriptor<OCREntry>())
        #expect(entries.count == 1)
        #expect(entries.first?.text == "hello")
    }

    @Test func pruningEnforcesMaxCount() throws {
        defer { UserDefaults.standard.removeObject(forKey: "historyMaxCount") }
        UserDefaults.standard.set(3, forKey: "historyMaxCount")
        let container = try makeContainer()
        let context = container.mainContext
        for i in 0..<5 {
            context.insert(OCREntry(
                text: "old \(i)",
                createdAt: Date(timeIntervalSince1970: Double(i))
            ))
        }
        try context.save()

        HistoryService(container: container).record("newest")

        let entries = try context.fetch(FetchDescriptor<OCREntry>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        ))
        #expect(entries.count == 3)
        #expect(entries.first?.text == "newest")
        #expect(entries.contains { $0.text == "old 4" })
        #expect(entries.contains { $0.text == "old 3" })
        #expect(!entries.contains { $0.text == "old 0" })
    }

    @Test func clearRemovesAllEntries() throws {
        defer { UserDefaults.standard.removeObject(forKey: "historyMaxCount") }
        UserDefaults.standard.set(30, forKey: "historyMaxCount")
        let container = try makeContainer()
        let service = HistoryService(container: container)
        service.record("one")
        service.record("two")

        service.clear()

        let entries = try container.mainContext.fetch(FetchDescriptor<OCREntry>())
        #expect(entries.isEmpty)
    }

    @Test func recentItemsAreNewestFirstAndBounded() throws {
        defer { UserDefaults.standard.removeObject(forKey: "historyMaxCount") }
        UserDefaults.standard.set(30, forKey: "historyMaxCount")
        let container = try makeContainer()
        let context = container.mainContext
        for i in 0..<6 {
            context.insert(OCREntry(text: "entry \(i)", createdAt: Date(timeIntervalSince1970: Double(i))))
        }
        try context.save()

        let items = HistoryService(container: container).recentItems(limit: 3)

        #expect(items.map(\.text) == ["entry 5", "entry 4", "entry 3"])
    }

    private func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: OCREntry.self, configurations: configuration)
    }
}
