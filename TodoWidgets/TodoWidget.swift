import WidgetKit
import SwiftUI

struct TodoEntry: TimelineEntry {
    let date: Date
    let todos: [Todo]
    let categoryName: String
    let categories: [Category]
}

struct TodoTimelineProvider: AppIntentTimelineProvider {
    typealias Entry  = TodoEntry
    typealias Intent = CategoryFilterIntent

    func placeholder(in context: Context) -> TodoEntry {
        TodoEntry(date: .now, todos: [], categoryName: "Alle", categories: Category.defaults)
    }

    func snapshot(for configuration: CategoryFilterIntent, in context: Context) async -> TodoEntry {
        makeEntry(for: configuration)
    }

    func timeline(for configuration: CategoryFilterIntent, in context: Context) async -> Timeline<TodoEntry> {
        let entry = makeEntry(for: configuration)

        // Refresh at midnight or in 30 minutes
        let midnight = Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: 1, to: .now)!)
        let halfHour = Calendar.current.date(byAdding: .minute, value: 30, to: .now)!
        let nextRefresh = min(midnight, halfHour)

        return Timeline(entries: [entry], policy: .after(nextRefresh))
    }

    private func makeEntry(for config: CategoryFilterIntent) -> TodoEntry {
        let allTodos    = SharedDataReader.loadTodos()
        let categories  = SharedDataReader.loadCategories()
        let catName     = config.categoryName

        let openTodos = allTodos
            .filter { !$0.isCompleted }
            .filter { catName == "Alle" || $0.categoryName == catName }
            .sorted { t1, t2 in
                if let d1 = t1.dueDate, let d2 = t2.dueDate { return d1 < d2 }
                if t1.dueDate != nil { return true }
                if t2.dueDate != nil { return false }
                return t1.priority.sortOrder < t2.priority.sortOrder
            }

        return TodoEntry(date: .now, todos: openTodos, categoryName: catName, categories: categories)
    }
}

struct TodoWidget: Widget {
    let kind = "TodoWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: CategoryFilterIntent.self,
            provider: TodoTimelineProvider()
        ) { entry in
            TodoWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Aufgaben")
        .description("Zeigt deine offenen Aufgaben an.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
