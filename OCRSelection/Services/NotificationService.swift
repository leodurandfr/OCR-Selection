import Foundation
import UserNotifications

struct NotificationService {
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
        let cleaned = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count > 50 else { return cleaned }
        let cutoff = cleaned.index(cleaned.startIndex, offsetBy: 50)
        return cleaned[..<cutoff] + "…"
    }
}
