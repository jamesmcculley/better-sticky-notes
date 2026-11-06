import UserNotifications

/// Fires a native notification when a note's item count grows between two directory reads --
/// catches a line added to a note file from outside notestack (hand-edited, or another tool
/// writing into ~/Documents/Notestack/), never notestack's own select-to-reorder, which doesn't
/// change any note's item count. Same bundle guard as AppDelegate's permission request:
/// silently does nothing under `swift run`, where there's no real .app bundle for
/// UNUserNotificationCenter to attach to.
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
