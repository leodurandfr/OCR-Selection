import Foundation
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
            body: String(localized: "The capture succeeded but text recognition failed.")
        )
    }

    func notifyFailure() async {
        await deliver(title: String(localized: "Capture failed"), body: "")
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
