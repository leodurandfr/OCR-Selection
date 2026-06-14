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
        UserDefaults.standard.register(
            defaults: [AppSettings.historyMaxCountKey: AppSettings.historyMaxCountDefault]
        )
        let container: ModelContainer
        do {
            container = try ModelContainer(for: OCREntry.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
        self.container = container
        self.coordinator = CaptureCoordinator(
            screenCapture: ScreenCaptureService(),
            ocr: OCRService(),
            pasteboard: PasteboardService(),
            notifications: NotificationService(),
            history: HistoryService(container: container),
            permission: PermissionPresenter()
        )
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await notifications.requestAuthorization() }

        // Fire on key-DOWN so the capture starts the instant the chord is recognised,
        // rather than waiting for the user to release the keys.
        KeyboardShortcuts.onKeyDown(for: .captureRegion) { [coordinator] in
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
        let preview = entry.text.previewSnippet(maxLength: 40)
        let relative = entry.createdAt.formatted(.relative(presentation: .named))
        return "\(preview) — \(relative)"
    }
}
