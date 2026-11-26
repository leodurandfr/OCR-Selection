import Foundation
import Observation
import Sparkle

/// In-app updates through Sparkle.
///
/// The feed (`SUFeedURL`) and the EdDSA public key (`SUPublicEDKey`) live in
/// `OCRSelection/Info.plist`; `scripts/release.sh` signs each .dmg with the matching
/// private key (login keychain, account `ocr-selection`) and publishes `appcast.xml`
/// next to it. Sparkle downloads the .dmg, checks its signature and Developer ID, swaps
/// the app in place and relaunches it.
///
/// The Debug build never starts the updater: the feed serves the Release app, whose
/// bundle ID differs, and installing it over "OCR Selection Debug" would be wrong.
@MainActor
@Observable
final class UpdateService {
    static var isEnabled: Bool {
        #if DEBUG
        false
        #else
        true
        #endif
    }

    /// Mirrors `SPUUpdater.canCheckForUpdates` (false while a check is already running).
    private(set) var canCheckForUpdates = false

    var automaticallyChecksForUpdates: Bool {
        get { access(keyPath: \.automaticallyChecksForUpdates); return updater.automaticallyChecksForUpdates }
        set { withMutation(keyPath: \.automaticallyChecksForUpdates) { updater.automaticallyChecksForUpdates = newValue } }
    }

    var automaticallyDownloadsUpdates: Bool {
        get { access(keyPath: \.automaticallyDownloadsUpdates); return updater.automaticallyDownloadsUpdates }
        set { withMutation(keyPath: \.automaticallyDownloadsUpdates) { updater.automaticallyDownloadsUpdates = newValue } }
    }

    @ObservationIgnored private let userDriverDelegate = UserDriverDelegate()
    @ObservationIgnored private let controller: SPUStandardUpdaterController
    @ObservationIgnored private var canCheckObservation: NSKeyValueObservation?

    private var updater: SPUUpdater { controller.updater }

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: Self.isEnabled,
            updaterDelegate: nil,
            userDriverDelegate: userDriverDelegate
        )
        canCheckObservation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            let value = updater.canCheckForUpdates
            MainActor.assumeIsolated { self?.canCheckForUpdates = value }
        }
    }

    func checkForUpdates() {
        guard Self.isEnabled else { return }
        PerfLog.health.notice("update check requested by user")
        updater.checkForUpdates()
    }
}

/// A menu-bar app has no Dock icon, so a scheduled update window could open behind the
/// frontmost app. Gentle reminders let Sparkle show it without stealing focus.
private final class UserDriverDelegate: NSObject, SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }
}
