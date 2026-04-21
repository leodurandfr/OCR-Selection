import AppKit
import KeyboardShortcuts
import SwiftData
import SwiftUI

@main
struct OCRSelectionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("OCR Selection", systemImage: "text.viewfinder") {
            MenuBarContent(coordinator: appDelegate.coordinator)
                .modelContainer(appDelegate.container)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            PreferencesView()
                .modelContainer(appDelegate.container)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let container: ModelContainer
    let coordinator: CaptureCoordinator
    private let notifications = NotificationService()

    override init() {
        UserDefaults.standard.register(defaults: ["historyMaxCount": 30])
        let container: ModelContainer
        do {
            container = try ModelContainer(for: OCREntry.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
        self.container = container
        self.coordinator = CaptureCoordinator(
            history: HistoryService(container: container)
        )
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await notifications.requestAuthorization() }

        KeyboardShortcuts.onKeyUp(for: .captureRegion) { [coordinator] in
            Task { await coordinator.run() }
        }
    }
}

private struct MenuBarContent: View {
    @Query(sort: \OCREntry.createdAt, order: .reverse) private var entries: [OCREntry]

    let coordinator: CaptureCoordinator

    var body: some View {
        Button("Capture Area") {
            Task { await coordinator.run() }
        }

        if !entries.isEmpty {
            Divider()
            Section("Recents") {
                ForEach(Array(entries.prefix(10))) { entry in
                    Button {
                        let text = entry.text
                        Task { await coordinator.recopy(text) }
                    } label: {
                        Text(verbatim: Self.menuLabel(for: entry))
                    }
                }
            }
        }

        Divider()

        SettingsLink {
            Text("Preferences…")
        }
        .keyboardShortcut(",", modifiers: .command)

        Button("About OCR Selection") {
            NSApplication.shared.activate(ignoringOtherApps: true)
            NSApplication.shared.orderFrontStandardAboutPanel(nil)
        }

        Divider()

        Button("Quit OCR Selection") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private static func menuLabel(for entry: OCREntry) -> String {
        let cleaned = entry.text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let truncated: String = cleaned.count > 40
            ? String(cleaned.prefix(40)) + "…"
            : cleaned
        let relative = entry.createdAt.formatted(.relative(presentation: .named))
        return "\(truncated) — \(relative)"
    }
}
