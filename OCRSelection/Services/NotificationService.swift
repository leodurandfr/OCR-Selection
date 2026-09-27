import AppKit
import UserNotifications

@MainActor
struct NotificationService: Notifying {
    private var center: UNUserNotificationCenter { .current() }

    func requestAuthorization() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    func notifySuccess(preview text: String) async {
        await deliver(title: String(localized: "Text copied"), body: Self.preview(of: text))
    }

    func notifyNoText() async {
        await deliver(title: String(localized: "No text detected"), body: "")
    }

    func notifyOCRFailed() async {
        await deliver(
            title: String(localized: "Unable to read text"),
            body: String(localized: "The capture succeeded but text recognition failed. Quit and relaunch OCR Selection.")
        )
    }

    func notifyDiskNearlyFull(recognitionFailed: Bool) async {
        let body = recognitionFailed
            ? String(localized: "Text recognition failed because macOS deleted the app's files to free up space. Free up disk space, then quit and relaunch OCR Selection.")
            : String(localized: "Text recognition was slow because the disk is almost full. Free up disk space to speed it up.")
        await deliver(title: String(localized: "Disk almost full"), body: body)
    }

    func notifyFailure() async {
        await deliver(title: String(localized: "Capture failed"), body: "")
    }

    /// A beep rather than a banner: it answers the key press immediately, and a
    /// notification would pile up behind the one the running capture is about to post.
    func notifyBusy() {
        NSSound.beep()
    }

    private func deliver(title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }

    private static func preview(of text: String) -> String {
        text.previewSnippet(maxLength: 50)
    }
}
