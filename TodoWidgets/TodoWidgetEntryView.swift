import SwiftUI
import WidgetKit

struct TodoWidgetEntryView: View {
    let entry: TodoEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                switch family {
                case .systemSmall:  smallView
                case .systemMedium: mediumView
                case .systemLarge:  largeView
                default:            mediumView
                }
            }
            .widgetURL(URL(string: "todoapp://aufgaben"))

            Link(destination: URL(string: "todoapp://aufgaben/neu")!) {
                ZStack {
                    Circle()
                        .fill(.blue)
                        .frame(width: 28, height: 28)
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
    }

    // MARK: - Small

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "checklist")
                    .font(.caption)
                    .foregroundStyle(.blue)
                Text(entry.categoryName)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Text("\(entry.todos.count)")
                .font(.system(size: 36, weight: .bold, design: .rounded))
            Text("offene Aufgaben")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            if let first = entry.todos.first {
                HStack(spacing: 4) {
                    Circle()
                        .fill(first.priority.color)
                        .frame(width: 6, height: 6)
                    Text(first.title)
                        .font(.caption2)
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: - Medium

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if entry.todos.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(entry.todos.prefix(4)) { todo in
                        todoRow(todo)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Large

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if entry.todos.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(entry.todos.prefix(9)) { todo in
                        todoRow(todo)
                    }
                    if entry.todos.count > 9 {
                        Text("+ \(entry.todos.count - 9) weitere")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Components

    private var header: some View {
        HStack {
            Image(systemName: "checklist")
                .font(.caption)
                .foregroundStyle(.blue)
            Text(entry.categoryName)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(entry.todos.count)")
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(.blue)
        }
    }

    private var emptyState: some View {
        HStack {
            Spacer()
            VStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                Text("Alles erledigt!")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func todoRow(_ todo: Todo) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(todo.priority.color)
                .frame(width: 6, height: 6)

            Text(todo.title)
                .font(.caption)
                .lineLimit(1)

            Spacer(minLength: 0)

            if let due = todo.dueDate {
                Text(dueDateString(due))
                    .font(.system(size: 9))
                    .foregroundStyle(todo.isOverdue ? .red : .secondary)
            }
        }
    }

    private func dueDateString(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Heute" }
        if Calendar.current.isDateInTomorrow(date) { return "Morgen" }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "de_DE")
        fmt.dateFormat = "dd.MM."
        return fmt.string(from: date)
    }
}
