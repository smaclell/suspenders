import Foundation
import UserNotifications

enum Notifier {
    /// UNUserNotificationCenter only works inside an app bundle (not `swift run`).
    static var available: Bool { Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app") }

    static func requestPermission() {
        guard available else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func send(title: String, body: String) {
        guard available else {
            NSLog("Suspenders: \(title) — \(body)")
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = nil // gentle: no sound
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    static let nudges: [(String, String)] = [
        ("It's getting late", "Whatever's on screen will keep. Tomorrow-you will thank you."),
        ("Time to start winding down", "Close one tab. Then another. Then the lid."),
        ("Still here?", "Rest is part of the work. Sign off when you reach a stopping point."),
        ("A gentle nudge", "The best thing you can do for tomorrow is go to bed tonight."),
        ("Be where your people are", "The laptop can wait until morning."),
    ]
}
