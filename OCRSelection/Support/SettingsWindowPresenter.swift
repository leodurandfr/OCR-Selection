import AppKit
import SwiftUI

/// Brings the SwiftUI `Settings` window to the front.
///
/// `SettingsLink` and `openSettings()` alone open the window *behind* the frontmost app:
/// this is an `LSUIElement` app, macOS won't make an app without a Dock icon frontmost,
/// and since macOS 14 `activate(ignoringOtherApps:)` is only a request the system may
/// decline. So the app is promoted to `.regular` (Dock icon shown) while Settings is
/// open, and demoted back to `.accessory` when the window closes.
@MainActor
enum SettingsWindowPresenter {
    /// Identifier SwiftUI gives the window backing the `Settings` scene.
    private static let windowIdentifier = "com_apple_SwiftUI_Settings_window"
    private static var closeObserver: NSObjectProtocol?

    static func show(using openSettings: OpenSettingsAction) async {
        observeClose()
        NSApp.setActivationPolicy(.regular)
        // The policy change lands asynchronously; activating in the same turn is ignored.
        try? await Task.sleep(for: .milliseconds(100))
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
        // The first time, the window is only created on a later run-loop pass.
        try? await Task.sleep(for: .milliseconds(200))
        guard let window = NSApp.windows.first(where: isSettingsWindow) else {
            PerfLog.health.error("settings window not found after openSettings")
            return
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private static func isSettingsWindow(_ window: NSWindow) -> Bool {
        window.identifier?.rawValue == windowIdentifier
    }

    private static func observeClose() {
        guard closeObserver == nil else { return }
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main
        ) { notification in
            MainActor.assumeIsolated {
                guard let window = notification.object as? NSWindow,
                      isSettingsWindow(window) else { return }
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}
