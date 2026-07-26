import Foundation
import SwiftData
import Testing
@testable import OCRSelection

@MainActor
struct HistoryContainerTests {
    @Test func storeLivesInAnAppScopedSubfolder() throws {
        let support = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: support) }

        _ = try HistoryContainer.make(in: support)

        let expected = support
            .appending(path: HistoryContainer.directoryName)
            .appending(path: HistoryContainer.storeName)
        #expect(FileManager.default.fileExists(atPath: expected.path))
        // Never at the Application Support root, which is shared with every other app.
        #expect(!FileManager.default.fileExists(atPath: support.appending(path: "default.store").path))
    }

    @Test func autosaveIsDisabled() throws {
        let support = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: support) }

        let container = try HistoryContainer.make(in: support)

        #expect(container.mainContext.autosaveEnabled == false)
    }

    @Test func legacyStoreIsMigratedThenRemoved() throws {
        let support = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: support) }
        let legacy = support.appending(path: HistoryContainer.legacyStoreName)
        try seedLegacyStore(at: legacy, texts: ["older", "newer"])

        let container = try HistoryContainer.make(in: support)

        let entries = try container.mainContext.fetch(FetchDescriptor<OCREntry>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        ))
        #expect(entries.map(\.text) == ["newer", "older"])
        #expect(!FileManager.default.fileExists(atPath: legacy.path))
    }

    @Test func migrationRunsOnlyOnce() throws {
        let support = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: support) }
        try seedLegacyStore(at: support.appending(path: HistoryContainer.legacyStoreName), texts: ["kept"])

        _ = try HistoryContainer.make(in: support)
        let second = try HistoryContainer.make(in: support)

        let entries = try second.mainContext.fetch(FetchDescriptor<OCREntry>())
        #expect(entries.map(\.text) == ["kept"])
    }

    private func seedLegacyStore(at url: URL, texts: [String]) throws {
        let container = try ModelContainer(
            for: OCREntry.self,
            configurations: ModelConfiguration(url: url)
        )
        let context = container.mainContext
        for (index, text) in texts.enumerated() {
            context.insert(OCREntry(text: text, createdAt: Date(timeIntervalSince1970: Double(index))))
        }
        try context.save()
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "history-container-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
