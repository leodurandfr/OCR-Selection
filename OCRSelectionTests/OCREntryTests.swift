import Foundation
import Testing
@testable import OCRSelection

struct OCREntryTests {
    @Test func defaultsToFreshIdentifierAndTimestamp() {
        let before = Date()
        let entry = OCREntry(text: "hello")
        let after = Date()

        #expect(entry.text == "hello")
        #expect(entry.createdAt >= before)
        #expect(entry.createdAt <= after)
    }

    @Test func retainsExplicitValues() {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1_000_000)
        let entry = OCREntry(id: id, text: "hi", createdAt: date)

        #expect(entry.id == id)
        #expect(entry.text == "hi")
        #expect(entry.createdAt == date)
    }

    @Test func sortsByDateDescending() {
        let old = OCREntry(text: "old", createdAt: Date(timeIntervalSince1970: 0))
        let middle = OCREntry(text: "middle", createdAt: Date(timeIntervalSince1970: 100))
        let new = OCREntry(text: "new", createdAt: Date(timeIntervalSince1970: 200))

        let sorted = [middle, old, new].sorted { $0.createdAt > $1.createdAt }

        #expect(sorted.map(\.text) == ["new", "middle", "old"])
    }
}
