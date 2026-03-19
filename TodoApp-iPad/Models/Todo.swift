import Foundation

struct Todo: Identifiable, Codable {
    var id: UUID = UUID()
    var title: String
    var notes: String = ""
    var priority: Priority = .medium
    var categoryName: String = "Allgemein"
    var dueDate: Date? = nil
    var reminderDate: Date? = nil
    var isCompleted: Bool = false
    var createdAt: Date = Date()
    var completedAt: Date? = nil

    var isOverdue: Bool {
        guard let due = dueDate, !isCompleted else { return false }
        return due < Date()
    }

    var isDueToday: Bool {
        guard let due = dueDate, !isCompleted else { return false }
        return Calendar.current.isDateInToday(due)
    }
}
