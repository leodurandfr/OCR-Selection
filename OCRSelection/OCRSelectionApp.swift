import SwiftUI

@main
struct OCRSelectionApp: App {
    var body: some Scene {
        MenuBarExtra("OCR Selection", systemImage: "text.viewfinder") {
            Text("OCR Selection")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 8)
            Divider()
            Button("Quitter") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
