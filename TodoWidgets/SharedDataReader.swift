import Foundation

/// Reads data from the shared App Group UserDefaults.
/// Used by widget extensions to access data written by the main app.
enum SharedDataReader {
    private static let defaults = UserDefaults(suiteName: "group.com.todoapp.aufgaben.ipad") ?? .standard
    private static let decoder  = JSONDecoder()

    // MARK: - Todos

    static func loadTodos() -> [Todo] {
        guard let data = defaults.data(forKey: "todoapp_todos_v1"),
              let todos = try? decoder.decode([Todo].self, from: data)
        else { return [] }
        return todos
    }

    // MARK: - Categories

    static func loadCategories() -> [Category] {
        guard let data       = defaults.data(forKey: "todoapp_categories_v1"),
              let categories = try? decoder.decode([Category].self, from: data)
        else { return Category.defaults }
        return categories.isEmpty ? Category.defaults : categories
    }

    // MARK: - Calendar Events

    static func loadCalendarEvents() -> [CalendarEvent] {
        guard let data   = defaults.data(forKey: "todoapp_calendar_events_v2"),
              let events = try? decoder.decode([CalendarEvent].self, from: data)
        else { return [] }
        return events
    }

    // MARK: - iCal URL

    static func icalURL() -> String {
        defaults.string(forKey: "todoapp_ical_url") ?? ""
    }
}
