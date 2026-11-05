import UserNotifications

enum Notifier {
    static func noteGrew(_ note: Note, from oldCount: Int) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = note.title
        content.body = note.items.first?.title ?? "A new item arrived"
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
