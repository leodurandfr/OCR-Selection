import AppKit

@MainActor
struct PasteboardService: Pasteboarding {
    func copyText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
