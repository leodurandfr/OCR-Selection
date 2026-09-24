import Foundation

/// Single source of truth for user-facing settings keys, defaults and bounds.
/// Referenced by the default registration, `@AppStorage`, the History slider
/// and `HistoryService` pruning so they cannot drift apart.
enum AppSettings {
    static let historyMaxCountKey = "historyMaxCount"
    static let historyMaxCountDefault = 30
    static let historyMaxCountRange = 10...50
    static let historyMaxCountStep = 5

    /// Copy every visual line as its own line instead of rejoining wrapped text.
    static let preserveLineBreaksKey = "preserveLineBreaks"
    static let preserveLineBreaksDefault = false
}

extension String {
    /// A single-line, trimmed, ellipsis-truncated preview of (potentially multi-line)
    /// text — shared by the menu-bar recents and the success notification so their
    /// cleaning rules stay in sync.
    func previewSnippet(maxLength: Int) -> String {
        let cleaned = replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count > maxLength else { return cleaned }
        return String(cleaned.prefix(maxLength)) + "…"
    }
}
