import Foundation
import SwiftData
import Testing
@testable import OCRSelection

@MainActor
struct HistoryStoreTests {
    @Test func recordPublishesNewestFirst() throws {
        defer { UserDefaults.standard.removeObject(forKey: "historyMaxCount") }
        UserDefaults.standard.set(30, forKey: "historyMaxCount")
        let store = HistoryStore(service: HistoryService(container: try makeContainer()))

        store.record("first")
        store.record("second")

        #expect(store.items.map(\.text) == ["second", "first"])
    }

    @Test func publishedItemsAreCappedToTheMenuLimit() throws {
        defer { UserDefaults.standard.removeObject(forKey: "historyMaxCount") }
        UserDefaults.standard.set(50, forKey: "historyMaxCount")
        let store = HistoryStore(service: HistoryService(container: try makeContainer()))

        for i in 0..<(HistoryStore.menuLimit + 5) {
            store.record("entry \(i)")
        }

        #expect(store.items.count == HistoryStore.menuLimit)
        #expect(store.items.first?.text == "entry \(HistoryStore.menuLimit + 4)")
    }

    @Test func clearEmptiesPublishedItems() throws {
        defer { UserDefaults.standard.removeObject(forKey: "historyMaxCount") }
        UserDefaults.standard.set(30, forKey: "historyMaxCount")
        let store = HistoryStore(service: HistoryService(container: try makeContainer()))
        store.record("something")

        store.clear()

        #expect(store.items.isEmpty)
    }

    private func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: OCREntry.self, configurations: configuration)
    }
}
