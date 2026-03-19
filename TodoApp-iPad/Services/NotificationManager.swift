import Foundation
import UserNotifications

final class NotificationManager {
    static let shared = NotificationManager()

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .badge, .sound]
        ) { _, _ in }
    }

    /// Schedules a local notification for the given todo at the specified date.
    func schedule(for todo: Todo, at date: Date) {
        guard date > Date() else { return }

        let content      = UNMutableNotificationContent()
        content.title    = "Erinnerung"
        content.body     = todo.title
        content.sound    = .default
        content.badge    = 1

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: date
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: todo.id.uuidString, content: content, trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// Cancels the pending notification for the given todo ID.
    func cancel(id: UUID) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [id.uuidString])
    }

    /// Cancels all pending notifications.
    func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}
