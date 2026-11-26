import AppKit
import KeyboardShortcuts
import SwiftData
import SwiftUI

@main
struct OCRSelectionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // No `.modelContainer` here: the menu reads `HistoryStore`'s value snapshot, so
        // SwiftData is never touched while SwiftUI re-evaluates the menu content.
        MenuBarExtra {
            MenuBarContent(coordinator: appDelegate.coordinator, history: appDelegate.history)
        } label: {
            MenuBarIcon(gate: appDelegate.coordinator.gate)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            PreferencesView(history: appDelegate.history)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let container: ModelContainer
    let history: HistoryStore
    let coordinator: CaptureCoordinator
    private let notifications = NotificationService()
    /// Prewarms Vision in the recognizer service and rebuilds its model after a purge.
    private let visionCache = VisionCacheMonitor(
        cacheRoot: VisionCacheMonitor.defaultCacheRoot(serviceName: RecognizerConnection.shared.serviceName),
        transport: RecognizerConnection.shared
    )

    override init() {
        UserDefaults.standard.register(
            defaults: [
                AppSettings.historyMaxCountKey: AppSettings.historyMaxCountDefault,
                AppSettings.preserveLineBreaksKey: AppSettings.preserveLineBreaksDefault
            ]
        )
        // A failure here used to be a `fatalError`. Losing the store is not worth taking the
        // app down with it: fall back to an in-memory container so captures keep working,
        // and leave a persisted log line explaining why history looks empty.
        var container: ModelContainer
        do {
            #if DEBUG
            container = try HistoryContainer.make(migratingLegacyStore: false)
            #else
            container = try HistoryContainer.make()
            #endif
        } catch {
            PerfLog.health.error("persistent history unavailable, falling back to memory: \(String(describing: error), privacy: .public)")
            container = try! ModelContainer(
                for: OCREntry.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        }
        self.container = container
        let history = HistoryStore(service: HistoryService(container: container))
        self.history = history
        self.coordinator = CaptureCoordinator(
            screenCapture: ScreenCaptureService(),
            ocr: OCRService(),
            pasteboard: PasteboardService(),
            notifications: NotificationService(),
            history: history,
            permission: PermissionPresenter(),
            diskSpace: DiskSpaceService(),
            modelCache: visionCache
        )
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        PerfLog.health.notice("launched version=\(version, privacy: .public) build=\(build, privacy: .public)")
        HealthMonitor.shared.start()
        PermissionPresenter.noteCurrentAccess()

        Task { await notifications.requestAuthorization() }
        visionCache.isRecognizing = { [gate = coordinator.gate] in gate.isRecognizing }
        visionCache.start()

        // Fire on key-DOWN so the capture starts the instant the chord is recognised,
        // rather than waiting for the user to release the keys.
        KeyboardShortcuts.onKeyDown(for: .captureRegion) { [coordinator] in
            Task { await coordinator.run() }
        }
    }
}

/// Its own view so only the icon, not the menu or the scene, is re-evaluated when OCR
/// starts or ends.
private struct MenuBarIcon: View {
    let gate: CaptureGate

    var body: some View {
        if gate.isRecognizing, let frames = PulsingMenuBarIcon.frames {
            PulsingMenuBarIcon(frames: frames)
        } else {
            Label("OCR Selection", systemImage: "text.viewfinder")
        }
    }
}

/// The menu-bar icon fading down and back up while OCR runs.
///
/// `MenuBarExtra` turns its label into a static status-item image, so `symbolEffect` and
/// SwiftUI animations never play there. The pulse is stepped by hand instead: the icon is
/// swapped through a fixed set of frames drawn at decreasing then increasing opacity. They
/// stay template images, so the menu bar still tints them for light, dark and tinted modes.
/// Costs about 6 % of one core while it runs, which is only during OCR.
private struct PulsingMenuBarIcon: View {
    private static let frameInterval: Duration = .milliseconds(80)
    /// One 1.44 s cycle: full → 35 % → full. `nil` if the symbol is missing, in which case
    /// the static icon stays up rather than an empty, zero-width status item.
    static let frames: [NSImage]? = {
        let count = 18
        guard let base = NSImage(systemSymbolName: "text.viewfinder", accessibilityDescription: nil) else {
            PerfLog.health.error("menu-bar pulse disabled: symbol text.viewfinder not found")
            return nil
        }
        return (0..<count).map { index in
            let opacity = 0.35 + 0.65 * (0.5 + 0.5 * cos(2 * .pi * Double(index) / Double(count)))
            let frame = NSImage(size: base.size, flipped: false) { rect in
                base.draw(in: rect, from: .zero, operation: .sourceOver, fraction: opacity)
                return true
            }
            frame.isTemplate = true
            return frame
        }
    }()

    let frames: [NSImage]
    @State private var frameIndex = 0

    var body: some View {
        Label {
            Text("OCR Selection")
        } icon: {
            Image(nsImage: frames[frameIndex])
        }
        .task {
            // Reduce Motion: hold the dimmest frame, a still "busy" icon, instead of pulsing.
            guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
                frameIndex = frames.count / 2
                return
            }
            while true {
                // Stop on cancellation instead of stepping once more on a view being removed.
                do { try await Task.sleep(for: Self.frameInterval) } catch { return }
                frameIndex = (frameIndex + 1) % frames.count
            }
        }
    }
}

private struct MenuBarContent: View {
    let coordinator: CaptureCoordinator
    let history: HistoryStore
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        // Counted, not free: a runaway count in the health heartbeat is the signature of
        // SwiftUI rebuilding this menu in a loop.
        let _ = HealthMonitor.shared.noteMenuRender()

        Button("Capture Area") {
            Task { await coordinator.run() }
        }

        if !history.items.isEmpty {
            Divider()
            Section("Recents") {
                ForEach(history.items) { item in
                    Button {
                        let text = item.text
                        Task { await coordinator.recopy(text) }
                    } label: {
                        Text(verbatim: Self.menuLabel(for: item))
                    }
                }
            }
        }

        Divider()

        // Not `SettingsLink`: it opened the window behind the frontmost app.
        Button("Preferences…") {
            Task { await SettingsWindowPresenter.show(using: openSettings) }
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

    /// Cached: `Date.formatted(.relative(…))` builds a formatter on every call, and this
    /// runs once per entry per body evaluation.
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .full
        return formatter
    }()

    private static func menuLabel(for item: HistoryItem) -> String {
        let preview = item.text.previewSnippet(maxLength: 40)
        let relative = relativeFormatter.localizedString(for: item.createdAt, relativeTo: Date())
        return "\(preview) — \(relative)"
    }
}
